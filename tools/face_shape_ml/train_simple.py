"""Simple baseline: MobileNetV2 fine-tuning that ACTUALLY learns.

Key fixes vs prior attempts:
  1) Aspect-preserving resize (pad to square first, then resize to 224×224)
  2) MobileNetV2 preprocess_input via API (not Lambda) — matches ImageNet weights
  3) Backbone trainable=True from epoch 1 (BatchNorm needs to update)
  4) Lower LR (3e-4) and longer warm-up
  5) Validate on held-out 1/3 of training_set (testing_set is unlabeled-quality
     according to community reports; skip until model works)

Run:
  /Users/chuck/Code/face/tools/.venv/bin/python \
      /Users/chuck/Code/face/tools/face_shape_ml/train_simple.py
"""
from __future__ import annotations

import os
os.environ.setdefault("TF_USE_LEGACY_KERAS", "1")
os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")

from pathlib import Path
import cv2
import numpy as np
import tensorflow as tf
from tensorflow.keras import layers, models, optimizers, callbacks  # type: ignore
from sklearn.metrics import confusion_matrix

import kagglehub

CLASSES = ["Heart", "Oblong", "Oval", "Round", "Square"]
IMG_SIZE = 224
OUT = Path(__file__).resolve().parent / "out"
OUT.mkdir(parents=True, exist_ok=True)


def aspect_resize(img: np.ndarray, size: int = IMG_SIZE) -> np.ndarray:
    """Pad to square (white), then resize to size×size."""
    h, w = img.shape[:2]
    if h != w:
        if w < h:
            d = h - w
            img = cv2.copyMakeBorder(img, 0, 0, d // 2, d - d // 2,
                                     cv2.BORDER_CONSTANT, value=(255, 255, 255))
        else:
            d = w - h
            img = cv2.copyMakeBorder(img, d // 2, d - d // 2, 0, 0,
                                     cv2.BORDER_CONSTANT, value=(255, 255, 255))
    return cv2.resize(img, (size, size), interpolation=cv2.INTER_AREA)


def load_niten19():
    base = kagglehub.dataset_download("niten19/face-shape-dataset")
    root = next(Path(base).rglob("FaceShape Dataset"))
    print(f"[load] {root}")
    X, y = [], []
    for ci, cls in enumerate(CLASSES):
        folder = root / "training_set" / cls
        for f in sorted(folder.iterdir()):
            if f.suffix.lower() not in (".jpg", ".jpeg", ".png"):
                continue
            img = cv2.imread(str(f))
            if img is None:
                continue
            img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
            img = aspect_resize(img)
            X.append(img.astype(np.float32))
            y.append(ci)
        print(f"  {cls}: {sum(1 for v in y if v == ci)}")
    X = np.stack(X)
    y = np.array(y)
    # Hold-out 15% as val (stratified)
    rng = np.random.default_rng(42)
    val_idx = []
    for c in range(5):
        cls_idx = np.where(y == c)[0]
        rng.shuffle(cls_idx)
        val_idx.extend(cls_idx[: max(1, int(len(cls_idx) * 0.15))].tolist())
    val_mask = np.zeros(len(y), bool)
    val_mask[val_idx] = True
    return X[~val_mask], y[~val_mask], X[val_mask], y[val_mask]


def build():
    base = tf.keras.applications.MobileNetV2(
        input_shape=(IMG_SIZE, IMG_SIZE, 3),
        include_top=False,
        weights="imagenet",
    )
    base.trainable = True  # BatchNorm must learn face statistics

    inputs = layers.Input(shape=(IMG_SIZE, IMG_SIZE, 3))
    x = tf.keras.applications.mobilenet_v2.preprocess_input(inputs)
    x = base(x)
    x = layers.GlobalAveragePooling2D()(x)
    x = layers.Dropout(0.4)(x)
    x = layers.Dense(5, activation="softmax",
                     kernel_regularizer=tf.keras.regularizers.l2(1e-4))(x)
    return models.Model(inputs, x)


AUG = tf.keras.Sequential([
    layers.RandomFlip("horizontal"),
    layers.RandomRotation(0.10),
    layers.RandomZoom(0.10),
    layers.RandomContrast(0.15),
])


def main():
    Xtr, ytr, Xv, yv = load_niten19()
    print(f"\ntrain {len(Xtr)} | val {len(Xv)}")
    print(f"val dist: {dict(zip(CLASSES, np.bincount(yv, minlength=5)))}")

    ytr_oh = tf.keras.utils.to_categorical(ytr, 5)
    yv_oh = tf.keras.utils.to_categorical(yv, 5)

    train_ds = (tf.data.Dataset.from_tensor_slices((Xtr, ytr_oh))
                .shuffle(2048).batch(32)
                .map(lambda a, b: (AUG(a, training=True), b),
                     num_parallel_calls=tf.data.AUTOTUNE)
                .prefetch(tf.data.AUTOTUNE))
    val_ds = tf.data.Dataset.from_tensor_slices((Xv, yv_oh)).batch(32).prefetch(tf.data.AUTOTUNE)

    model = build()
    model.compile(
        optimizer=optimizers.Adam(3e-4),
        loss="categorical_crossentropy",
        metrics=["accuracy"],
    )
    model.summary(line_length=100)

    es = callbacks.EarlyStopping(monitor="val_accuracy", patience=8,
                                 restore_best_weights=True, mode="max")
    rlr = callbacks.ReduceLROnPlateau(monitor="val_accuracy", factor=0.5,
                                      patience=4, mode="max", min_lr=1e-6)
    history = model.fit(train_ds, validation_data=val_ds, epochs=40,
                        callbacks=[es, rlr], verbose=2)

    val_pred = np.argmax(model.predict(Xv, verbose=0), axis=1)
    acc = float(np.mean(val_pred == yv))
    print(f"\n[FINAL] niten19 val accuracy: {acc:.3f}")
    cm = confusion_matrix(yv, val_pred, labels=list(range(5)))
    hdr = "true\\pred"
    print(f"{hdr:10s}" + "".join(f"{c[:6]:>7s}" for c in CLASSES))
    for i, c in enumerate(CLASSES):
        print(f"{c:10s}" + "".join(f"{cm[i][j]:>7d}" for j in range(5)))
    model.save(OUT / "simple_mobilenet.keras")
    print(f"saved: {OUT / 'simple_mobilenet.keras'}")


if __name__ == "__main__":
    main()
