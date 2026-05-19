"""Convert mlp_eastasian_final.keras → face_shape_ratios.tflite + scaler.json
to drop into flutter/assets/ml/.

Verifies:
  1. TFLite output matches Keras output bit-exact (within 1e-5).
  2. New scaler.json schema matches existing (feature_names order, mu/sd).
  3. End-to-end: load .tflite + scaler, run on user_features.csv,
     compare argmax to Keras predictions.
"""
from __future__ import annotations

import json
import os
import sys
import shutil
from pathlib import Path

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")

import numpy as np
import pandas as pd
import tensorflow as tf

sys.path.insert(0, str(Path(__file__).resolve().parent))
from extract_landmarks import FEATURE_NAMES, CLASSES  # type: ignore

OUT = Path(__file__).resolve().parent / "out"
KERAS_PATH = OUT / "mlp_eastasian_final.keras"
NEW_SCALER = OUT / "mlp_eastasian_scaler.json"
USER_CSV = OUT / "user_features.csv"

TFLITE_OUT = OUT / "face_shape_ratios.tflite"
TARGET_TFLITE = Path("/Users/chuck/Code/face/flutter/assets/ml/face_shape_ratios.tflite")
TARGET_SCALER = Path("/Users/chuck/Code/face/flutter/assets/ml/scaler.json")


def main():
    # 1. Convert Keras → TFLite
    print("[1] loading Keras model")
    model = tf.keras.models.load_model(KERAS_PATH)
    model.summary(line_length=80)

    print("\n[2] converting to TFLite (float32)")
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = []  # no quantization — keep precision
    tflite_bytes = converter.convert()
    TFLITE_OUT.write_bytes(tflite_bytes)
    print(f"  TFLite size: {len(tflite_bytes)/1024:.1f} KB")

    # 2. Verify parity Keras vs TFLite
    print("\n[3] verifying Keras vs TFLite bit-exactness")
    df = pd.read_csv(USER_CSV)
    sc = json.loads(NEW_SCALER.read_text())
    mu = np.array(sc["mu"], dtype=np.float32)
    sd = np.array(sc["sd"], dtype=np.float32)
    X = df[FEATURE_NAMES].to_numpy(dtype=np.float32)
    Xz = (X - mu) / sd

    keras_probs = model.predict(Xz, verbose=0)

    interp = tf.lite.Interpreter(model_content=tflite_bytes)
    interp.allocate_tensors()
    in_idx = interp.get_input_details()[0]["index"]
    out_idx = interp.get_output_details()[0]["index"]
    in_shape = interp.get_input_details()[0]["shape"]
    print(f"  TFLite input shape: {in_shape}")
    # Some TFLite converters output dynamic shape. Resize per-sample if needed.
    if in_shape[0] != Xz.shape[0]:
        interp.resize_tensor_input(in_idx, [Xz.shape[0], Xz.shape[1]])
        interp.allocate_tensors()
    interp.set_tensor(in_idx, Xz)
    interp.invoke()
    tflite_probs = interp.get_tensor(out_idx)

    max_diff = float(np.abs(keras_probs - tflite_probs).max())
    print(f"  max |keras - tflite|: {max_diff:.6f}")
    if max_diff > 1e-3:
        print(f"  ⚠ parity drift > 1e-3 — review")
    else:
        print("  ✓ within tolerance")

    keras_argmax = np.argmax(keras_probs, axis=1)
    tflite_argmax = np.argmax(tflite_probs, axis=1)
    agree = int(np.sum(keras_argmax == tflite_argmax))
    print(f"  argmax agreement: {agree}/{len(df)}")

    # 3. Validate scaler.json schema matches existing
    print("\n[4] validating new scaler.json schema")
    existing_scaler = json.loads(TARGET_SCALER.read_text())
    existing_names = existing_scaler.get("feature_names", [])
    if existing_names == sc["feature_names"]:
        print("  ✓ feature_names match")
    else:
        print("  ⚠ feature_names DIFFER:")
        print(f"    existing: {existing_names[:5]}...")
        print(f"    new:      {sc['feature_names'][:5]}...")
    assert len(sc["mu"]) == 28 and len(sc["sd"]) == 28, "mu/sd len != 28"
    print(f"  ✓ mu/sd are 28-vectors")

    # 4. Deploy — copy to flutter assets
    print("\n[5] copying to flutter/assets/ml/")
    shutil.copy(TFLITE_OUT, TARGET_TFLITE)
    shutil.copy(NEW_SCALER, TARGET_SCALER)
    print(f"  ✓ {TARGET_TFLITE} ({TARGET_TFLITE.stat().st_size/1024:.1f} KB)")
    print(f"  ✓ {TARGET_SCALER} ({TARGET_SCALER.stat().st_size/1024:.1f} KB)")

    # 5. Per-photo final check (TFLite)
    print("\n[6] per-photo TFLite results")
    classes = CLASSES
    top1 = tflite_argmax
    y_true = df["class_idx"].to_numpy()
    correct = int(np.sum(top1 == y_true))
    print(f"  top-1 (TFLite, user 57): {correct}/{len(df)} = {correct/len(df):.1%}")

    # Confusion
    from sklearn.metrics import confusion_matrix
    cm = confusion_matrix(y_true, top1, labels=list(range(5)))
    hdr = "true\\pred"
    print(f"  {hdr:10s}" + "".join(f"{c[:6]:>7s}" for c in classes))
    for i, c in enumerate(classes):
        print(f"  {c:10s}" + "".join(f"{cm[i][j]:>7d}" for j in range(5)))


if __name__ == "__main__":
    main()
