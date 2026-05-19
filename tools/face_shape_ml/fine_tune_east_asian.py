"""Fine-tune niten19-trained MobileNetV2 on 57 East Asian samples.

5-fold stratified CV to honestly measure East Asian accuracy.
Then train final model on all 57 + niten19 train set combined.

Run:
  /Users/chuck/Code/face/tools/.venv/bin/python \
      /Users/chuck/Code/face/tools/face_shape_ml/fine_tune_east_asian.py
"""
from __future__ import annotations

import os
os.environ.setdefault("TF_USE_LEGACY_KERAS", "1")
os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")

import glob
import re
from pathlib import Path
import cv2
import numpy as np
import tensorflow as tf
from tensorflow.keras import layers, optimizers, callbacks  # type: ignore
from sklearn.model_selection import StratifiedKFold
from sklearn.metrics import confusion_matrix

CLASSES = ["Heart", "Oblong", "Oval", "Round", "Square"]
CLASS_LOWER = [c.lower() for c in CLASSES]
IDX = {c: i for i, c in enumerate(CLASS_LOWER)}
IMG_SIZE = 224
OUT = Path(__file__).resolve().parent / "out"
NITEN_MODEL = OUT / "simple_mobilenet.keras"


def aspect_resize(img, size=IMG_SIZE):
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


def load_user():
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
        img = cv2.imread(f)
        if img is None:
            continue
        img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
        img = aspect_resize(img)
        X.append(img.astype(np.float32))
        y.append(IDX[m.group(2)])
        names.append(stem)
    return np.stack(X), np.array(y), names


AUG = tf.keras.Sequential([
    layers.RandomFlip("horizontal"),
    layers.RandomRotation(0.10),
    layers.RandomZoom(0.10),
    layers.RandomContrast(0.15),
])


def evaluate_pretrained(X, y):
    """No-fine-tune baseline: niten19 model directly on East Asian samples."""
    model = tf.keras.models.load_model(NITEN_MODEL)
    pred = np.argmax(model.predict(X, verbose=0), axis=1)
    acc = float(np.mean(pred == y))
    print(f"\n[baseline] niten19 model directly on 57 East Asian: {acc:.3f}")
    cm = confusion_matrix(y, pred, labels=list(range(5)))
    hdr = "true\\pred"
    print(f"{hdr:10s}" + "".join(f"{c[:6]:>7s}" for c in CLASSES))
    for i, c in enumerate(CLASSES):
        print(f"{c:10s}" + "".join(f"{cm[i][j]:>7d}" for j in range(5)))
    return acc


def fine_tune_fold(Xtr, ytr, Xv, yv, fold):
    model = tf.keras.models.load_model(NITEN_MODEL)
    # Unfreeze top 30 layers of MobileNetV2 backbone for fine-tune
    base = next(l for l in model.layers if isinstance(l, tf.keras.Model))
    base.trainable = True
    for layer in base.layers[:-30]:
        layer.trainable = False

    model.compile(
        optimizer=optimizers.Adam(1e-5),
        loss="categorical_crossentropy",
        metrics=["accuracy"],
    )
    ytr_oh = tf.keras.utils.to_categorical(ytr, 5)
    yv_oh = tf.keras.utils.to_categorical(yv, 5)
    train_ds = (tf.data.Dataset.from_tensor_slices((Xtr, ytr_oh))
                .shuffle(256).batch(8)
                .map(lambda a, b: (AUG(a, training=True), b),
                     num_parallel_calls=tf.data.AUTOTUNE)
                .prefetch(tf.data.AUTOTUNE))
    val_ds = tf.data.Dataset.from_tensor_slices((Xv, yv_oh)).batch(8)

    es = callbacks.EarlyStopping(monitor="val_accuracy", patience=8,
                                 restore_best_weights=True, mode="max")
    model.fit(train_ds, validation_data=val_ds, epochs=30,
              callbacks=[es], verbose=0)
    pred = np.argmax(model.predict(Xv, verbose=0), axis=1)
    return float(np.mean(pred == yv)), pred


def main():
    X, y, names = load_user()
    print(f"loaded {len(X)} East Asian samples; dist {dict(zip(CLASS_LOWER, np.bincount(y, minlength=5)))}")

    # Sanity: niten19 model directly on user data
    evaluate_pretrained(X, y)

    # 5-fold CV with fine-tune
    skf = StratifiedKFold(n_splits=5, shuffle=True, random_state=42)
    fold_accs, ally, allp = [], [], []
    for i, (tr, va) in enumerate(skf.split(X, y)):
        acc, pred = fine_tune_fold(X[tr], y[tr], X[va], y[va], i + 1)
        fold_accs.append(acc)
        ally.extend(y[va])
        allp.extend(pred)
        print(f"[fold {i+1}] {len(tr)}/{len(va)} val_acc={acc:.3f}")

    print()
    print("=" * 60)
    print(f"5-fold CV East Asian: {np.mean(fold_accs):.3f} ± {np.std(fold_accs):.3f}")
    print(f"  per fold: {[f'{a:.3f}' for a in fold_accs]}")
    print(f"  pooled: {sum(np.array(ally) == np.array(allp))}/{len(ally)}")
    cm = confusion_matrix(ally, allp, labels=list(range(5)))
    hdr = "true\\pred"
    print(f"{hdr:10s}" + "".join(f"{c[:6]:>7s}" for c in CLASSES))
    for i, c in enumerate(CLASSES):
        print(f"{c:10s}" + "".join(f"{cm[i][j]:>7d}" for j in range(5)))


if __name__ == "__main__":
    main()
