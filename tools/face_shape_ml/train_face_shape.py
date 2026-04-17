"""Train two face-shape classifiers on landmarks extracted from niten19 dataset:
  (A) ratios-only MLP  (18 features)    — matches Flutter's existing metric path
  (B) landmarks MLP    (468×2 = 936)    — raw-ish geometry, normalized per-face

Both export to Keras + TFLite (FP16). Validation uses the dataset's held-out
testing_set (1001 images).

Run (after extract_landmarks.py has produced out/landmarks.npz):
  .venv/bin/python face_shape_ml/train_face_shape.py
"""
from __future__ import annotations

import json
import os
from pathlib import Path

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")

import numpy as np
import tensorflow as tf
from tensorflow import keras
from sklearn.metrics import confusion_matrix, classification_report

OUT = Path(__file__).resolve().parent / "out"
CLASSES = ("Heart", "Oblong", "Oval", "Round", "Square")

# Landmark normalization constants — mirror Flutter-side pre-processing if we
# later ship the landmarks-MLP. Center = face bounding-box midpoint, scale =
# face width (234↔454). Flutter equivalent: compute the same two quantities
# before feeding to the TFLite model.
R_FACE_EDGE, L_FACE_EDGE = 234, 454
FOREHEAD_TOP, CHIN = 10, 152


def load_data():
    npz = np.load(OUT / "landmarks.npz")
    return npz["landmarks"], npz["ratios"], npz["labels"], npz["is_train"]


def normalize_landmarks(lm: np.ndarray) -> np.ndarray:
    """lm: [N,468,3] → [N, 468*2] scale/translation-invariant."""
    r_edge = lm[:, R_FACE_EDGE, :2]
    l_edge = lm[:, L_FACE_EDGE, :2]
    forehead = lm[:, FOREHEAD_TOP, :2]
    chin = lm[:, CHIN, :2]

    center_x = (r_edge[:, 0] + l_edge[:, 0]) / 2.0
    center_y = (forehead[:, 1] + chin[:, 1]) / 2.0
    scale = np.linalg.norm(r_edge - l_edge, axis=1, keepdims=True)  # [N,1]
    scale = np.clip(scale, 1e-6, None)

    xy = lm[:, :, :2].copy()
    xy[:, :, 0] -= center_x[:, None]
    xy[:, :, 1] -= center_y[:, None]
    xy /= scale[:, :, None]
    return xy.reshape(xy.shape[0], -1).astype(np.float32)


def build_ratio_mlp(n_in: int, n_out: int) -> keras.Model:
    m = keras.Sequential([
        keras.layers.Input(shape=(n_in,), name="ratios"),
        keras.layers.BatchNormalization(),
        keras.layers.Dense(64, activation="relu"),
        keras.layers.Dropout(0.3),
        keras.layers.Dense(32, activation="relu"),
        keras.layers.Dropout(0.2),
        keras.layers.Dense(n_out, activation="softmax"),
    ])
    m.compile(optimizer=keras.optimizers.Adam(1e-3),
              loss="sparse_categorical_crossentropy",
              metrics=["accuracy"])
    return m


def build_landmark_mlp(n_in: int, n_out: int) -> keras.Model:
    m = keras.Sequential([
        keras.layers.Input(shape=(n_in,), name="landmarks"),
        keras.layers.Dense(256, activation="relu"),
        keras.layers.Dropout(0.4),
        keras.layers.Dense(128, activation="relu"),
        keras.layers.Dropout(0.3),
        keras.layers.Dense(64, activation="relu"),
        keras.layers.Dropout(0.2),
        keras.layers.Dense(n_out, activation="softmax"),
    ])
    m.compile(optimizer=keras.optimizers.Adam(5e-4),
              loss="sparse_categorical_crossentropy",
              metrics=["accuracy"])
    return m


def train_and_eval(model: keras.Model, X_tr, y_tr, X_te, y_te, tag: str):
    cb = [
        keras.callbacks.EarlyStopping(
            monitor="val_accuracy", patience=12, restore_best_weights=True),
        keras.callbacks.ReduceLROnPlateau(
            monitor="val_loss", factor=0.5, patience=5, min_lr=1e-5),
    ]
    hist = model.fit(
        X_tr, y_tr,
        validation_data=(X_te, y_te),
        epochs=100, batch_size=64, verbose=2, callbacks=cb,
    )
    loss, acc = model.evaluate(X_te, y_te, verbose=0)
    pred = model.predict(X_te, verbose=0).argmax(axis=1)
    cm = confusion_matrix(y_te, pred, labels=list(range(len(CLASSES))))
    rep = classification_report(
        y_te, pred, target_names=CLASSES, digits=3, zero_division=0)
    print(f"\n══════ {tag} ══════")
    print(f"test acc = {acc:.4f}  loss = {loss:.4f}")
    print("confusion matrix (rows=true, cols=pred):")
    header = "          " + "  ".join(f"{c:>7s}" for c in CLASSES)
    print(header)
    for i, c in enumerate(CLASSES):
        row = f"  {c:8s}" + "  ".join(f"{cm[i,j]:>7d}" for j in range(len(CLASSES)))
        print(row)
    print(rep)
    return acc, hist


def export_tflite(model: keras.Model, out_path: Path, tag: str):
    conv = tf.lite.TFLiteConverter.from_keras_model(model)
    conv.optimizations = [tf.lite.Optimize.DEFAULT]
    conv.target_spec.supported_types = [tf.float16]
    tfl = conv.convert()
    out_path.write_bytes(tfl)
    print(f"  [tflite-fp16] {tag}: {out_path}  {len(tfl)/1024:.1f} KB")

    # Also full-fp32 as a safety fallback
    fp32_path = out_path.with_suffix(".fp32.tflite")
    conv2 = tf.lite.TFLiteConverter.from_keras_model(model)
    tfl2 = conv2.convert()
    fp32_path.write_bytes(tfl2)
    print(f"  [tflite-fp32] {tag}: {fp32_path}  {len(tfl2)/1024:.1f} KB")


def validate_tflite_parity(model: keras.Model, tflite_path: Path, X_te, y_te, tag: str):
    """Sanity: Keras vs TFLite on the test set."""
    interp = tf.lite.Interpreter(model_path=str(tflite_path))
    interp.allocate_tensors()
    in_det = interp.get_input_details()[0]
    out_det = interp.get_output_details()[0]
    preds = []
    for x in X_te.astype(np.float32):
        interp.set_tensor(in_det["index"], x[None, :])
        interp.invoke()
        preds.append(interp.get_tensor(out_det["index"])[0].argmax())
    preds = np.array(preds)
    keras_pred = model.predict(X_te, verbose=0).argmax(axis=1)
    agreement = float((preds == keras_pred).mean())
    acc_tfl = float((preds == y_te).mean())
    print(f"  [{tag}] tflite vs keras agreement={agreement:.4f}  tflite-acc={acc_tfl:.4f}")
    return agreement


def main():
    lm, ratios, labels, is_train = load_data()
    print(f"[load] N={len(labels)}  train={is_train.sum()}  test={(~is_train).sum()}")

    # ─── Model A: ratios ───
    Xa_tr, ya_tr = ratios[is_train], labels[is_train]
    Xa_te, ya_te = ratios[~is_train], labels[~is_train]
    mu = Xa_tr.mean(0)
    sd = Xa_tr.std(0) + 1e-9
    np.save(OUT / "ratios_mu.npy", mu)
    np.save(OUT / "ratios_sd.npy", sd)
    Xa_tr = ((Xa_tr - mu) / sd).astype(np.float32)
    Xa_te = ((Xa_te - mu) / sd).astype(np.float32)
    m_a = build_ratio_mlp(Xa_tr.shape[1], len(CLASSES))
    acc_a, _ = train_and_eval(m_a, Xa_tr, ya_tr, Xa_te, ya_te, "A: ratios MLP (18d)")
    m_a.save(OUT / "face_shape_ratios.keras")
    export_tflite(m_a, OUT / "face_shape_ratios.tflite", "ratios")
    validate_tflite_parity(m_a, OUT / "face_shape_ratios.tflite", Xa_te, ya_te, "ratios")

    # ─── Model B: landmarks ───
    xy = normalize_landmarks(lm)
    Xb_tr, yb_tr = xy[is_train], labels[is_train]
    Xb_te, yb_te = xy[~is_train], labels[~is_train]
    m_b = build_landmark_mlp(Xb_tr.shape[1], len(CLASSES))
    acc_b, _ = train_and_eval(m_b, Xb_tr, yb_tr, Xb_te, yb_te, "B: landmarks MLP (936d)")
    m_b.save(OUT / "face_shape_landmarks.keras")
    export_tflite(m_b, OUT / "face_shape_landmarks.tflite", "landmarks")
    validate_tflite_parity(m_b, OUT / "face_shape_landmarks.tflite", Xb_te, yb_te, "landmarks")

    # ─── Summary ───
    print("\n" + "═" * 60)
    print(f"Model A (ratios, 18d):      test acc = {acc_a:.4f}")
    print(f"Model B (landmarks, 936d):  test acc = {acc_b:.4f}")
    winner = "A" if acc_a >= acc_b else "B"
    print(f"→ Winner: {winner}")

    summary = {
        "model_a_ratios": {"test_acc": float(acc_a),
                           "tflite": "face_shape_ratios.tflite",
                           "mu": "ratios_mu.npy", "sd": "ratios_sd.npy"},
        "model_b_landmarks": {"test_acc": float(acc_b),
                              "tflite": "face_shape_landmarks.tflite"},
        "winner": winner,
        "classes": list(CLASSES),
    }
    (OUT / "train_summary.json").write_text(json.dumps(summary, indent=2))
    print(f"  → {OUT/'train_summary.json'}")


if __name__ == "__main__":
    main()
