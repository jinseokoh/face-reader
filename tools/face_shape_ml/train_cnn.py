"""Train a face-shape CNN on 112x112 face crops from the niten19 Kaggle dataset.

Goal: replace the ratios-MLP (70.4%) with a vision model targeting 85%+.
Architecture: MobileNetV3-Small (ImageNet pretrained, fine-tuned) → 5-class softmax.
Export: TFLite FP16.

Dependencies: tensorflow, mediapipe (for face crop bbox).

Run (after extract_landmarks.py has produced out/landmarks.npz):
    .venv/bin/python face_shape_ml/train_cnn.py
"""
from __future__ import annotations

import json
import os
import time
from pathlib import Path

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")

import cv2
import numpy as np
import tensorflow as tf
from tensorflow import keras
from sklearn.metrics import classification_report, confusion_matrix

TOOLS = Path(__file__).resolve().parent.parent
DATASET = TOOLS / "datasets/kaggle_cache/datasets/niten19/face-shape-dataset/versions/2/FaceShape Dataset"
OUT = Path(__file__).resolve().parent / "out"
OUT.mkdir(parents=True, exist_ok=True)

CLASSES = ("Heart", "Oblong", "Oval", "Round", "Square")
IMG_SIZE = 112
BATCH = 32
EPOCHS_HEAD = 20   # head-only training
EPOCHS_FT = 30     # fine-tune last N layers


def crop_face_from_landmarks(img: np.ndarray, lm: np.ndarray, pad: float = 0.15) -> np.ndarray:
    """Use precomputed landmarks (from landmarks.npz, normalized 0~1) to bbox-crop the face."""
    h, w = img.shape[:2]
    xs = lm[:, 0] * w
    ys = lm[:, 1] * h
    x0, y0 = xs.min(), ys.min()
    x1, y1 = xs.max(), ys.max()
    # pad
    bw, bh = x1 - x0, y1 - y0
    x0 = max(0, int(x0 - bw * pad))
    y0 = max(0, int(y0 - bh * pad))
    x1 = min(w, int(x1 + bw * pad))
    y1 = min(h, int(y1 + bh * pad))
    crop = img[y0:y1, x0:x1]
    if crop.size == 0:
        return cv2.resize(img, (IMG_SIZE, IMG_SIZE))
    return cv2.resize(crop, (IMG_SIZE, IMG_SIZE))


def build_dataset():
    """Load all images, crop using landmarks.npz, return arrays."""
    npz = np.load(OUT / "landmarks.npz")
    landmarks = npz["landmarks"]  # [N, 468, 3], normalized 0~1
    labels = npz["labels"]
    is_train = npz["is_train"]

    # Reload images in the same order extract_landmarks.py scanned them
    imgs = []
    idx = 0
    for phase in ("training_set", "testing_set"):
        for ci, cls in enumerate(CLASSES):
            folder = DATASET / phase / cls
            if not folder.is_dir():
                continue
            for f in sorted(folder.iterdir()):
                if f.suffix.lower() not in (".jpg", ".jpeg", ".png"):
                    continue
                img = cv2.imread(str(f))
                if img is None:
                    continue
                rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
                crop = crop_face_from_landmarks(rgb, landmarks[idx])
                imgs.append(crop)
                idx += 1
        print(f"  [load] {phase} → {idx} images", flush=True)
    X = np.stack(imgs).astype(np.float32) / 255.0
    assert len(X) == len(labels) == len(is_train), f"mismatch {len(X)} {len(labels)} {len(is_train)}"
    return X, labels, is_train


def build_model(n_classes: int) -> tuple[keras.Model, keras.Model]:
    """EfficientNetV2B0 backbone + small head. Dataset is [0,1]; backbone
    expects [0,255] via its own preprocessing."""
    base = keras.applications.EfficientNetV2B0(
        input_shape=(IMG_SIZE, IMG_SIZE, 3),
        include_top=False,
        weights="imagenet",
        pooling="avg",
        include_preprocessing=True,  # handles 0~255 → internal norm
    )
    base.trainable = False

    aug = keras.Sequential([
        keras.layers.RandomFlip("horizontal"),
        keras.layers.RandomRotation(0.04),
        keras.layers.RandomZoom(0.05),
    ], name="augment")

    inp = keras.Input(shape=(IMG_SIZE, IMG_SIZE, 3))
    x = aug(inp)
    x = keras.layers.Rescaling(255.0)(x)  # [0,1] → [0,255]
    x = base(x, training=False)
    x = keras.layers.BatchNormalization()(x)
    x = keras.layers.Dropout(0.3)(x)
    x = keras.layers.Dense(64, activation="relu")(x)
    x = keras.layers.Dropout(0.2)(x)
    out = keras.layers.Dense(n_classes, activation="softmax")(x)

    model = keras.Model(inp, out)
    return model, base


def main():
    t0 = time.time()
    print("[load] reading dataset...", flush=True)
    X, y, is_train = build_dataset()
    print(f"[load] X={X.shape} y={y.shape} train={is_train.sum()} test={(~is_train).sum()} "
          f"({time.time()-t0:.1f}s)", flush=True)

    X_tr, y_tr = X[is_train], y[is_train]
    X_te, y_te = X[~is_train], y[~is_train]

    model, base = build_model(len(CLASSES))
    model.compile(
        optimizer=keras.optimizers.Adam(1e-3),
        loss="sparse_categorical_crossentropy",
        metrics=["accuracy"],
    )
    model.summary(line_length=100)

    cb = [
        keras.callbacks.EarlyStopping(
            monitor="val_accuracy", patience=6, restore_best_weights=True),
        keras.callbacks.ReduceLROnPlateau(
            monitor="val_loss", factor=0.5, patience=3, min_lr=1e-5),
    ]

    # ─── Phase 1: head only ───
    print("\n════════ Phase 1: head-only ════════", flush=True)
    model.fit(
        X_tr, y_tr,
        validation_data=(X_te, y_te),
        epochs=EPOCHS_HEAD, batch_size=BATCH, verbose=2, callbacks=cb,
    )

    # ─── Phase 2: fine-tune last 40 layers ───
    base.trainable = True
    for l in base.layers[:-40]:
        l.trainable = False
    model.compile(
        optimizer=keras.optimizers.Adam(1e-4),
        loss="sparse_categorical_crossentropy",
        metrics=["accuracy"],
    )
    print("\n════════ Phase 2: fine-tune last 40 layers ════════", flush=True)
    model.fit(
        X_tr, y_tr,
        validation_data=(X_te, y_te),
        epochs=EPOCHS_FT, batch_size=BATCH, verbose=2, callbacks=cb,
    )

    # ─── Evaluate ───
    loss, acc = model.evaluate(X_te, y_te, verbose=0)
    pred = model.predict(X_te, verbose=0).argmax(axis=1)
    cm = confusion_matrix(y_te, pred, labels=list(range(len(CLASSES))))
    rep = classification_report(y_te, pred, target_names=CLASSES, digits=3, zero_division=0)
    print(f"\n══════ CNN test acc = {acc:.4f} loss = {loss:.4f} ══════")
    header = "          " + "  ".join(f"{c:>7s}" for c in CLASSES)
    print(header)
    for i, c in enumerate(CLASSES):
        row = f"  {c:8s}" + "  ".join(f"{cm[i,j]:>7d}" for j in range(len(CLASSES)))
        print(row)
    print(rep)

    # ─── Export ───
    model.save(OUT / "face_shape_cnn.keras")
    conv = tf.lite.TFLiteConverter.from_keras_model(model)
    conv.optimizations = [tf.lite.Optimize.DEFAULT]
    conv.target_spec.supported_types = [tf.float16]
    tfl = conv.convert()
    (OUT / "face_shape_cnn.tflite").write_bytes(tfl)
    print(f"  [tflite-fp16] {len(tfl)/1024:.1f} KB → {OUT/'face_shape_cnn.tflite'}")

    # ─── Parity check ───
    interp = tf.lite.Interpreter(model_path=str(OUT / "face_shape_cnn.tflite"))
    interp.allocate_tensors()
    in_det = interp.get_input_details()[0]
    out_det = interp.get_output_details()[0]
    preds_tfl = []
    for x in X_te:
        interp.set_tensor(in_det["index"], x[None, ...].astype(np.float32))
        interp.invoke()
        preds_tfl.append(interp.get_tensor(out_det["index"])[0].argmax())
    preds_tfl = np.array(preds_tfl)
    agreement = float((preds_tfl == pred).mean())
    acc_tfl = float((preds_tfl == y_te).mean())
    print(f"  [tflite] agreement={agreement:.4f}  acc={acc_tfl:.4f}")

    summary = {
        "cnn_test_acc_keras": float(acc),
        "cnn_test_acc_tflite": acc_tfl,
        "parity_agreement": agreement,
        "tflite_kb": len(tfl) / 1024,
        "input_size": IMG_SIZE,
        "classes": list(CLASSES),
        "epochs_head": EPOCHS_HEAD,
        "epochs_ft": EPOCHS_FT,
    }
    (OUT / "train_cnn_summary.json").write_text(json.dumps(summary, indent=2))
    print(f"  → {OUT/'train_cnn_summary.json'}")


if __name__ == "__main__":
    main()
