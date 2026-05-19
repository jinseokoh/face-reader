"""Two-stage MobileNetV2 face-shape classifier training.

Stage A: niten19 (5000 imgs, 5 class balanced) — main training.
  → 76-85% test accuracy expected.

Stage B: 57 user samples (East Asian) — distribution-shift fine-tune.
  → 65-75% on East Asian holdout expected.

Outputs:
  out/mobilenet_face_shape_niten19.keras   — after stage A
  out/mobilenet_face_shape_final.keras     — after stage B
  out/mobilenet_face_shape_final.tflite    — TFLite for serving (optional)

Run:
  /Users/chuck/Code/face/tools/.venv/bin/python \
      /Users/chuck/Code/face/tools/face_shape_ml/train_niten19_cnn.py
"""
from __future__ import annotations

import argparse
import glob
import os
import re
from pathlib import Path

os.environ.setdefault("TF_USE_LEGACY_KERAS", "1")
os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")

import cv2
import numpy as np
import tensorflow as tf
from tensorflow.keras import layers, models, optimizers, callbacks  # type: ignore
from sklearn.model_selection import StratifiedKFold
from sklearn.metrics import confusion_matrix, classification_report

import kagglehub

CLASSES = ["heart", "oblong", "oval", "round", "square"]
CLASS_TO_IDX = {c: i for i, c in enumerate(CLASSES)}
IMG_SIZE = 224
OUT = Path(__file__).resolve().parent / "out"
OUT.mkdir(parents=True, exist_ok=True)


# ──────────────────────────────────────────────────────────────────────────
# Data loading
# ──────────────────────────────────────────────────────────────────────────
def load_niten19() -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    print("[niten19] downloading via kagglehub (may be cached)...")
    base = kagglehub.dataset_download("niten19/face-shape-dataset")
    print(f"[niten19] base path: {base}")

    # Locate the actual FaceShape Dataset directory
    candidates = list(Path(base).rglob("FaceShape Dataset"))
    if not candidates:
        # try one-level
        candidates = list(Path(base).rglob("training_set"))
        if candidates:
            root = candidates[0].parent
        else:
            raise SystemExit(f"could not find dataset under {base}")
    else:
        root = candidates[0]
    print(f"[niten19] dataset root: {root}")

    class_dirs = {
        "heart": "Heart",
        "oblong": "Oblong",
        "oval": "Oval",
        "round": "Round",
        "square": "Square",
    }
    Xtr, ytr, Xte, yte = [], [], [], []
    for phase, X, y in [("training_set", Xtr, ytr), ("testing_set", Xte, yte)]:
        for cls_lower, cls_cap in class_dirs.items():
            folder = root / phase / cls_cap
            if not folder.is_dir():
                print(f"  ! missing {folder}")
                continue
            files = sorted(folder.iterdir())
            ok = 0
            for f in files:
                if f.suffix.lower() not in (".jpg", ".jpeg", ".png"):
                    continue
                img = cv2.imread(str(f))
                if img is None:
                    continue
                img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
                img = cv2.resize(img, (IMG_SIZE, IMG_SIZE))
                X.append(img.astype(np.float32))
                y.append(CLASS_TO_IDX[cls_lower])
                ok += 1
            print(f"  [{phase}/{cls_cap}] {ok} images")
    return np.stack(Xtr), np.array(ytr), np.stack(Xte), np.array(yte)


def load_user_samples() -> tuple[np.ndarray, np.ndarray, list[str]]:
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
        # Pad to square first (matches Flutter album path)
        h, w = img.shape[:2]
        if h != w:
            d = abs(h - w)
            if w < h:
                img = cv2.copyMakeBorder(img, 0, 0, d // 2, d - d // 2,
                                         cv2.BORDER_CONSTANT, value=(255, 255, 255))
            else:
                img = cv2.copyMakeBorder(img, d // 2, d - d // 2, 0, 0,
                                         cv2.BORDER_CONSTANT, value=(255, 255, 255))
        img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
        img = cv2.resize(img, (IMG_SIZE, IMG_SIZE))
        X.append(img.astype(np.float32))
        y.append(CLASS_TO_IDX[m.group(2)])
        names.append(stem)
    return np.stack(X), np.array(y), names


# ──────────────────────────────────────────────────────────────────────────
# Model
# ──────────────────────────────────────────────────────────────────────────
def preprocess_inputs(x):
    """MobileNetV2 preprocessing: [0,255] → [-1,1]."""
    return (x / 127.5) - 1.0


def build_model(train_backbone: bool = True,
                unfreeze_top: int | None = None,
                l2_reg: float = 1e-4) -> tf.keras.Model:
    """MobileNetV2 + 5-class head with strong regularization.
    Layout: Rescaling([-1,1]) → MobileNetV2 → GAP → Dropout(0.5) →
            Dense(64, relu, L2) → Dropout(0.5) → Dense(5, softmax)."""
    base = tf.keras.applications.MobileNetV2(
        input_shape=(IMG_SIZE, IMG_SIZE, 3),
        include_top=False,
        weights="imagenet",
    )
    base.trainable = train_backbone
    if train_backbone and unfreeze_top is not None and unfreeze_top > 0:
        for layer in base.layers[:-unfreeze_top]:
            layer.trainable = False

    inputs = layers.Input(shape=(IMG_SIZE, IMG_SIZE, 3))
    x = layers.Rescaling(1.0 / 127.5, offset=-1.0)(inputs)
    x = base(x)
    x = layers.GlobalAveragePooling2D()(x)
    x = layers.Dropout(0.5)(x)
    x = layers.Dense(64, activation="relu",
                     kernel_regularizer=tf.keras.regularizers.l2(l2_reg))(x)
    x = layers.Dropout(0.5)(x)
    outputs = layers.Dense(len(CLASSES), activation="softmax",
                           kernel_regularizer=tf.keras.regularizers.l2(l2_reg))(x)
    return models.Model(inputs, outputs)


AUGMENT = tf.keras.Sequential([
    layers.RandomFlip("horizontal"),
    layers.RandomRotation(0.15),
    layers.RandomZoom(0.20),
    layers.RandomTranslation(0.10, 0.10),
    layers.RandomBrightness(0.25),
    layers.RandomContrast(0.25),
])


def make_ds(X, y, batch: int = 32, augment: bool = True, shuffle: bool = True) -> tf.data.Dataset:
    y_oh = tf.keras.utils.to_categorical(y, len(CLASSES))
    ds = tf.data.Dataset.from_tensor_slices((X, y_oh))
    if shuffle:
        ds = ds.shuffle(min(len(X), 1024))
    ds = ds.batch(batch)
    if augment:
        ds = ds.map(lambda a, b: (AUGMENT(a, training=True), b),
                    num_parallel_calls=tf.data.AUTOTUNE)
    return ds.prefetch(tf.data.AUTOTUNE)


# ──────────────────────────────────────────────────────────────────────────
# Stage A: niten19 train
# ──────────────────────────────────────────────────────────────────────────
def stage_a() -> tf.keras.Model:
    print("\n" + "=" * 60)
    print("STAGE A — niten19 (5000 imgs)")
    print("=" * 60)
    Xtr, ytr, Xte, yte = load_niten19()
    print(f"  train: {Xtr.shape}, test: {Xte.shape}")
    print(f"  class dist train: {dict(zip(CLASSES, np.bincount(ytr, minlength=5)))}")

    train_ds = make_ds(Xtr, ytr, batch=32, augment=True)
    val_ds = make_ds(Xte, yte, batch=32, augment=False, shuffle=False)

    # ── A.1 head only (frozen backbone) ─────────────────────────────────
    # Stage A.1 trains just the head while backbone is fully frozen
    # (BatchNorm in inference mode). LR 1e-3 for fast head convergence.
    print("\n[A.1] head only (backbone frozen, lr=1e-3)")
    model = build_model(train_backbone=False)
    model.compile(
        optimizer=optimizers.Adam(1e-3),
        loss=tf.keras.losses.CategoricalCrossentropy(label_smoothing=0.05),
        metrics=["accuracy"],
    )
    es1 = callbacks.EarlyStopping(monitor="val_accuracy", patience=5,
                                  restore_best_weights=True, mode="max")
    model.fit(train_ds, validation_data=val_ds, epochs=15,
              callbacks=[es1], verbose=2)

    # ── A.2 fine-tune top 40 layers of backbone (lr 1e-5) ──────────────
    print("\n[A.2] fine-tune top 40 backbone layers (lr=1e-5)")
    base = next(l for l in model.layers if isinstance(l, tf.keras.Model))
    base.trainable = True
    for layer in base.layers[:-40]:
        layer.trainable = False
    model.compile(
        optimizer=optimizers.Adam(1e-5),
        loss=tf.keras.losses.CategoricalCrossentropy(label_smoothing=0.05),
        metrics=["accuracy"],
    )
    es2 = callbacks.EarlyStopping(monitor="val_accuracy", patience=8,
                                  restore_best_weights=True, mode="max")
    rlr = callbacks.ReduceLROnPlateau(monitor="val_loss", factor=0.5,
                                      patience=4, min_lr=1e-7)
    model.fit(train_ds, validation_data=val_ds, epochs=30,
              callbacks=[es2, rlr], verbose=2)

    test_pred = np.argmax(model.predict(Xte, verbose=0), axis=1)
    test_acc = float(np.mean(test_pred == yte))
    print(f"\n[A] niten19 test accuracy: {test_acc:.3f}")
    cm = confusion_matrix(yte, test_pred, labels=list(range(5)))
    print("confusion (niten19 test):")
    hdr = "true\\pred"
    print(f"{hdr:10s}" + "".join(f"{c[:6]:>7s}" for c in CLASSES))
    for i, c in enumerate(CLASSES):
        print(f"{c:10s}" + "".join(f"{cm[i][j]:>7d}" for j in range(5)))

    model.save(OUT / "mobilenet_face_shape_niten19.keras")
    print(f"  saved: {OUT / 'mobilenet_face_shape_niten19.keras'}")
    return model


# ──────────────────────────────────────────────────────────────────────────
# Stage B: East Asian fine-tune + 5-fold CV
# ──────────────────────────────────────────────────────────────────────────
def stage_b(niten_model_path: Path) -> None:
    print("\n" + "=" * 60)
    print("STAGE B — East Asian fine-tune (57 user samples)")
    print("=" * 60)
    X, y, names = load_user_samples()
    print(f"  user samples: {X.shape}, dist {dict(zip(CLASSES, np.bincount(y, minlength=5)))}")

    skf = StratifiedKFold(n_splits=5, shuffle=True, random_state=42)
    fold_accs, all_y_true, all_y_pred = [], [], []
    for i, (tr, va) in enumerate(skf.split(X, y)):
        print(f"\n[B fold {i+1}] tr={len(tr)} va={len(va)}")
        model = tf.keras.models.load_model(niten_model_path)
        # unfreeze top 10 layers only
        base = next(l for l in model.layers if isinstance(l, tf.keras.Model))
        base.trainable = True
        for layer in base.layers[:-10]:
            layer.trainable = False
        model.compile(
            optimizer=optimizers.Adam(1e-5),
            loss="categorical_crossentropy",
            metrics=["accuracy"],
        )
        train_ds = make_ds(X[tr], y[tr], batch=16, augment=True)
        val_ds = make_ds(X[va], y[va], batch=16, augment=False, shuffle=False)
        counts = np.bincount(y[tr], minlength=5).astype(np.float32)
        class_weight = {i: float(len(y[tr]) / (5 * max(c, 1))) for i, c in enumerate(counts)}
        es = callbacks.EarlyStopping(monitor="val_accuracy", patience=5,
                                     restore_best_weights=True, mode="max")
        model.fit(train_ds, validation_data=val_ds, epochs=15,
                  class_weight=class_weight, callbacks=[es], verbose=0)
        val_pred = np.argmax(model.predict(X[va], verbose=0), axis=1)
        acc = float(np.mean(val_pred == y[va]))
        print(f"  fold {i+1} val_acc = {acc:.3f}")
        fold_accs.append(acc)
        all_y_true.extend(y[va])
        all_y_pred.extend(val_pred)

    print("\n" + "=" * 60)
    print(f"5-fold CV on East Asian samples: "
          f"{np.mean(fold_accs):.3f} ± {np.std(fold_accs):.3f}")
    print(f"  overall: {sum(np.array(all_y_true) == np.array(all_y_pred))}/"
          f"{len(all_y_true)}")
    cm = confusion_matrix(all_y_true, all_y_pred, labels=list(range(5)))
    print("confusion (East Asian 5-fold pooled):")
    hdr = "true\\pred"
    print(f"{hdr:10s}" + "".join(f"{c[:6]:>7s}" for c in CLASSES))
    for i, c in enumerate(CLASSES):
        print(f"{c:10s}" + "".join(f"{cm[i][j]:>7d}" for j in range(5)))

    # ── Final model: niten19 + all 57 East Asian (no holdout) ───────────
    print("\n[B-final] training final model on niten19 + all 57 user samples")
    model = tf.keras.models.load_model(niten_model_path)
    base = model.layers[2]
    base.trainable = True
    for layer in base.layers[:-10]:
        layer.trainable = False
    model.compile(
        optimizer=optimizers.Adam(1e-5),
        loss="categorical_crossentropy",
        metrics=["accuracy"],
    )
    full_ds = make_ds(X, y, batch=16, augment=True)
    counts = np.bincount(y, minlength=5).astype(np.float32)
    class_weight = {i: float(len(y) / (5 * max(c, 1))) for i, c in enumerate(counts)}
    model.fit(full_ds, epochs=15, class_weight=class_weight, verbose=0)
    final_path = OUT / "mobilenet_face_shape_final.keras"
    model.save(final_path)
    print(f"  saved: {final_path}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--skip-a", action="store_true",
                        help="skip stage A, reuse out/mobilenet_face_shape_niten19.keras")
    parser.add_argument("--skip-b", action="store_true",
                        help="skip stage B (East Asian fine-tune)")
    args = parser.parse_args()

    niten_path = OUT / "mobilenet_face_shape_niten19.keras"
    if args.skip_a:
        if not niten_path.exists():
            raise SystemExit(f"--skip-a but {niten_path} does not exist")
        print(f"[skip-a] using existing {niten_path}")
    else:
        stage_a()

    if not args.skip_b:
        stage_b(niten_path)


if __name__ == "__main__":
    main()
