"""label2k 최종 후보 모델 — 전체 라벨 데이터로 재학습 + TFLite 변환.

Train: niten19 4000 + pilot 421(3x) + label2k 1869 전체(3x) + user 57(3x)
       — 검증(label2k_train.py gate)은 끝났으므로 hold-out 없이 전량 투입.
Verify: Keras vs TFLite argmax 일치 (label2k 1869).
주의:  flutter/assets 배포는 하지 않는다 — out/label2k/ 에 보관만.

Run:
  tools/.venv/bin/python tools/face_shape_ml/label2k_export.py
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")

import numpy as np
import pandas as pd
import tensorflow as tf
from sklearn.preprocessing import StandardScaler

sys.path.insert(0, str(Path(__file__).resolve().parent))
from extract_landmarks import CLASSES, FEATURE_NAMES  # noqa: E402
from train_28feat_eastasian import build_mlp  # noqa: E402

OUT = Path(__file__).resolve().parent / "out"
PILOT = OUT / "pilot"
L2K = OUT / "label2k"
SEED = 42
DUP = 3


def main() -> None:
    tf.keras.utils.set_random_seed(SEED)

    data = np.load(OUT / "landmarks.npz")
    is_train = data["is_train"].astype(bool)
    Xn = data["ratios"].astype(np.float32)[is_train]
    yn = data["labels"].astype(np.int32)[is_train]

    df_p = pd.read_csv(PILOT / "features.csv")
    Xp = df_p[FEATURE_NAMES].to_numpy(np.float32)
    yp = df_p.class_idx.to_numpy(np.int32)

    df_2 = pd.read_csv(L2K / "features.csv")
    X2 = df_2[FEATURE_NAMES].to_numpy(np.float32)
    y2 = df_2.class_idx.to_numpy(np.int32)

    df_u = pd.read_csv(OUT / "user_features.csv")
    Xu = df_u[FEATURE_NAMES].to_numpy(np.float32)
    yu = df_u["class_idx"].to_numpy(np.int32)

    X = np.concatenate([Xn] + [Xp] * DUP + [X2] * DUP + [Xu] * DUP)
    y = np.concatenate([yn] + [yp] * DUP + [y2] * DUP + [yu] * DUP)
    print(f"train total {len(y)} (niten {len(yn)}, pilot {len(yp)}x{DUP}, "
          f"l2k {len(y2)}x{DUP}, user {len(yu)}x{DUP})")

    scaler = StandardScaler().fit(X)
    mu = scaler.mean_.astype(np.float32)
    sd = scaler.scale_.astype(np.float32)

    unique, counts = np.unique(y, return_counts=True)
    cw = {int(c): float(y.size / (len(unique) * n))
          for c, n in zip(unique, counts)}

    model = build_mlp()
    model.compile(optimizer=tf.keras.optimizers.Adam(1e-3),
                  loss="sparse_categorical_crossentropy", metrics=["accuracy"])
    z = ((X - mu) / sd).astype(np.float32)
    model.fit(z, y, epochs=100, batch_size=64, class_weight=cw, verbose=0)
    print(f"train acc: {model.evaluate(z, y, verbose=0)[1]:.3f}")

    print("[convert] TFLite float32")
    conv = tf.lite.TFLiteConverter.from_keras_model(model)
    conv.optimizations = []
    tfl = conv.convert()
    (L2K / "face_shape_ratios.tflite").write_bytes(tfl)
    print(f"  size: {len(tfl) / 1024:.1f} KB")

    print("[verify] Keras vs TFLite argmax (l2k 1869)")
    z2 = ((X2 - mu) / sd).astype(np.float32)
    keras_pred = np.argmax(model.predict(z2, verbose=0), axis=1)
    interp = tf.lite.Interpreter(model_content=tfl)
    in_d = interp.get_input_details()[0]
    out_d = interp.get_output_details()[0]
    interp.resize_tensor_input(in_d["index"], z2.shape)
    interp.allocate_tensors()
    interp.set_tensor(in_d["index"], z2)
    interp.invoke()
    tfl_pred = np.argmax(interp.get_tensor(out_d["index"]), axis=1)
    agree = int(np.sum(keras_pred == tfl_pred))
    print(f"  agreement: {agree}/{len(z2)}")
    assert agree == len(z2), "TFLite 변환 drift"

    model.save(L2K / "mlp_2k_final.keras")
    scaler_json = json.dumps({
        "feature_names": FEATURE_NAMES,
        "mu": mu.tolist(), "sd": sd.tolist()}, indent=2)
    (L2K / "scaler.json").write_text(scaler_json)
    print(f"saved: {L2K / 'mlp_2k_final.keras'} + face_shape_ratios.tflite + scaler.json")

    dist = {CLASSES[i]: int(n)
            for i, n in enumerate(np.bincount(keras_pred, minlength=5))}
    print(f"l2k 1869 예측 분포: {dist}")


if __name__ == "__main__":
    main()
