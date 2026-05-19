"""5-fold stratified CV training of MobileNetV2 face-shape classifier.

User dataset: /tmp/{gender}-{type}-{n}.{ext}, 57 labeled samples.

Pipeline:
  1) For each image: DeepFace.extract_faces (mtcnn) → 224×224 aligned RGB
  2) Stratified 5-fold split
  3) MobileNetV2(ImageNet pretrained, include_top=False) backbone, frozen
  4) Head: GAP → Dropout(0.3) → Dense(128, relu) → Dense(5, softmax)
  5) Heavy augmentation (rotation, brightness, h-flip, zoom)
  6) Train 30 epoch head, then unfreeze top 30 layers, fine-tune 20 epoch
  7) Report per-fold val accuracy + aggregate confusion

Run:
  /Users/chuck/Code/face/tools/.venv/bin/python \
      /Users/chuck/Code/face/tools/face_shape_ml/train_mobilenetv2.py
"""
from __future__ import annotations

import glob
import os
import re
import sys
from pathlib import Path

import numpy as np

os.environ.setdefault("TF_USE_LEGACY_KERAS", "1")
os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")

import cv2
import tensorflow as tf
from tensorflow.keras import layers, models, optimizers, callbacks  # type: ignore
from sklearn.model_selection import StratifiedKFold
from sklearn.metrics import confusion_matrix

CLASSES = ["heart", "oblong", "oval", "round", "square"]
CLASS_TO_IDX = {c: i for i, c in enumerate(CLASSES)}
IMG_SIZE = 224

# DeepFace face extraction
try:
    from deepface import DeepFace  # type: ignore
except ImportError:
    DeepFace = None


def extract_face(path: str) -> np.ndarray | None:
    """DeepFace.extract_faces → 224x224 RGB float [0,1]. Returns None on fail."""
    if DeepFace is None:
        # Fallback: just resize the raw image
        img = cv2.imread(path)
        if img is None:
            return None
        img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
        img = cv2.resize(img, (IMG_SIZE, IMG_SIZE))
        return (img / 255.0).astype(np.float32)
    try:
        faces = DeepFace.extract_faces(
            img_path=path,
            detector_backend="mtcnn",
            enforce_detection=True,
            align=True,
        )
        if not faces:
            return None
        face = faces[0]["face"]  # already RGB float [0,1]
        # DeepFace may give various sizes — force 224
        if face.shape[:2] != (IMG_SIZE, IMG_SIZE):
            face = cv2.resize(face, (IMG_SIZE, IMG_SIZE))
        return face.astype(np.float32)
    except Exception as e:
        print(f"  ! extract_faces failed for {Path(path).name}: {e}")
        return None


def load_dataset() -> tuple[np.ndarray, np.ndarray, list[str]]:
    pat = re.compile(r"^(male|female)-(heart|oblong|oval|round|square)-\d+$")
    files = sorted(
        glob.glob("/tmp/male-*.png") + glob.glob("/tmp/male-*.jpg") + glob.glob("/tmp/male-*.jpeg")
        + glob.glob("/tmp/female-*.png") + glob.glob("/tmp/female-*.jpg") + glob.glob("/tmp/female-*.jpeg")
    )
    X, y, names = [], [], []
    for f in files:
        stem = Path(f).stem
        m = pat.match(stem)
        if not m:
            continue
        face = extract_face(f)
        if face is None:
            print(f"  skip {stem} (no face)")
            continue
        X.append(face)
        y.append(CLASS_TO_IDX[m.group(2)])
        names.append(stem)
    return np.stack(X), np.array(y), names


def build_model(train_backbone: bool = False) -> tf.keras.Model:
    base = tf.keras.applications.MobileNetV2(
        input_shape=(IMG_SIZE, IMG_SIZE, 3),
        include_top=False,
        weights="imagenet",
    )
    base.trainable = train_backbone
    inputs = layers.Input(shape=(IMG_SIZE, IMG_SIZE, 3))
    x = layers.Lambda(tf.keras.applications.mobilenet_v2.preprocess_input)(inputs)
    x = base(x, training=False if not train_backbone else None)
    x = layers.GlobalAveragePooling2D()(x)
    x = layers.Dropout(0.3)(x)
    x = layers.Dense(128, activation="relu")(x)
    x = layers.Dropout(0.3)(x)
    outputs = layers.Dense(len(CLASSES), activation="softmax")(x)
    model = models.Model(inputs, outputs)
    return model


AUGMENT = tf.keras.Sequential([
    layers.RandomFlip("horizontal"),
    layers.RandomRotation(0.08),
    layers.RandomZoom(0.10),
    layers.RandomBrightness(0.15),
    layers.RandomContrast(0.15),
])


def train_fold(X_tr, y_tr, X_va, y_va, fold: int) -> dict:
    n_classes = len(CLASSES)
    y_tr_oh = tf.keras.utils.to_categorical(y_tr, n_classes)
    y_va_oh = tf.keras.utils.to_categorical(y_va, n_classes)

    # Class weights for imbalance
    counts = np.bincount(y_tr, minlength=n_classes).astype(np.float32)
    weights = (len(y_tr) / (n_classes * np.clip(counts, 1, None)))
    class_weight = {i: float(w) for i, w in enumerate(weights)}

    train_ds = tf.data.Dataset.from_tensor_slices((X_tr, y_tr_oh))
    train_ds = train_ds.shuffle(256).batch(16)
    train_ds = train_ds.map(lambda x, y: (AUGMENT(x, training=True), y),
                            num_parallel_calls=tf.data.AUTOTUNE)
    train_ds = train_ds.prefetch(tf.data.AUTOTUNE)

    val_ds = tf.data.Dataset.from_tensor_slices((X_va, y_va_oh)).batch(16)

    # Stage 1: frozen backbone, train head
    model = build_model(train_backbone=False)
    model.compile(
        optimizer=optimizers.Adam(1e-3),
        loss="categorical_crossentropy",
        metrics=["accuracy"],
    )
    es = callbacks.EarlyStopping(monitor="val_accuracy", patience=8,
                                 restore_best_weights=True, mode="max")
    print(f"\n[fold {fold}] Stage 1: head training (frozen backbone)")
    model.fit(train_ds, validation_data=val_ds, epochs=30,
              class_weight=class_weight, callbacks=[es], verbose=0)

    # Stage 2: unfreeze top 30 layers
    print(f"[fold {fold}] Stage 2: fine-tune top 30 layers")
    base = model.layers[2]  # The MobileNetV2 submodel
    base.trainable = True
    for layer in base.layers[:-30]:
        layer.trainable = False
    model.compile(
        optimizer=optimizers.Adam(1e-5),
        loss="categorical_crossentropy",
        metrics=["accuracy"],
    )
    es2 = callbacks.EarlyStopping(monitor="val_accuracy", patience=6,
                                  restore_best_weights=True, mode="max")
    history = model.fit(train_ds, validation_data=val_ds, epochs=20,
                        class_weight=class_weight, callbacks=[es2], verbose=0)

    val_pred = np.argmax(model.predict(X_va, verbose=0), axis=1)
    val_acc = float(np.mean(val_pred == y_va))
    return {"fold": fold, "val_acc": val_acc, "y_true": y_va, "y_pred": val_pred,
            "history": history.history}


def main() -> None:
    print("[load] extracting faces...")
    X, y, names = load_dataset()
    print(f"  loaded {len(X)} samples ({X.dtype}, range {X.min():.2f}-{X.max():.2f})")
    print(f"  class distribution: {dict(zip(CLASSES, np.bincount(y, minlength=5)))}")

    skf = StratifiedKFold(n_splits=5, shuffle=True, random_state=42)
    fold_accs, all_y_true, all_y_pred = [], [], []
    for i, (tr, va) in enumerate(skf.split(X, y)):
        res = train_fold(X[tr], y[tr], X[va], y[va], i + 1)
        fold_accs.append(res["val_acc"])
        all_y_true.extend(res["y_true"])
        all_y_pred.extend(res["y_pred"])
        print(f"[fold {res['fold']}] val_acc = {res['val_acc']:.3f}")

    print()
    print("=" * 60)
    print(f"5-fold CV accuracy: {np.mean(fold_accs):.3f} ± {np.std(fold_accs):.3f}")
    print(f"  per-fold: {[f'{a:.3f}' for a in fold_accs]}")
    print(f"  overall:  {np.mean(np.array(all_y_true) == np.array(all_y_pred)):.3f} "
          f"({sum(np.array(all_y_true) == np.array(all_y_pred))}/{len(all_y_true)})")
    print()
    print("Confusion matrix (rows=true, cols=pred):")
    cm = confusion_matrix(all_y_true, all_y_pred, labels=list(range(5)))
    hdr_label = "true\\pred"
    print(f"{hdr_label:10s}" + "".join(f"{c[:6]:>7s}" for c in CLASSES) + "   support")
    for i, c in enumerate(CLASSES):
        row = "".join(f"{cm[i][j]:>7d}" for j in range(5))
        print(f"{c:10s}{row}   {cm[i].sum()}")


if __name__ == "__main__":
    main()
