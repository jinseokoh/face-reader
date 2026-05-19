"""새 TFLite + scaler 가 Flutter assets 에 배포됐다. 이제 Flutter 의
applyPosterior() 가 적용하는 _priorRatio 의 4가지 조합을 시뮬레이션해서
어느 prior 가 East Asian deploy 에서 최선인지 측정.

설정:
  P0 = 현재 Flutter [0.4, 0.6, 2.5, 1.0, 0.5]  ← 기존 (이중 보정 위험)
  P1 = uniform [1, 1, 1, 1, 1]                  ← prior 제거 (raw 모델만)
  P2 = 약한 [0.7, 0.8, 1.3, 1.0, 0.8]           ← 미세 보정
  P3 = 새 모델에 맞춘 deploy 분포 prior          ← user 57 분포로 계산
"""
from __future__ import annotations

import os
os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")

import json
import sys
from pathlib import Path
import numpy as np
import pandas as pd
import tensorflow as tf
from sklearn.model_selection import StratifiedKFold

sys.path.insert(0, str(Path(__file__).resolve().parent))
from extract_landmarks import FEATURE_NAMES, CLASSES  # type: ignore

OUT = Path(__file__).resolve().parent / "out"
TFLITE = "/Users/chuck/Code/face/flutter/assets/ml/face_shape_ratios.tflite"
SCALER = "/Users/chuck/Code/face/flutter/assets/ml/scaler.json"
USER = OUT / "user_features.csv"


def evaluate(probs, y, prior, name):
    adj = probs * np.array(prior)
    adj = adj / adj.sum(axis=1, keepdims=True)
    pred = np.argmax(adj, axis=1)
    acc = float(np.mean(pred == y))
    print(f"\n{name}  prior={prior}")
    print(f"  top-1: {sum(pred==y)}/{len(y)} = {acc:.1%}")
    from sklearn.metrics import confusion_matrix
    cm = confusion_matrix(y, pred, labels=list(range(5)))
    hdr = "true\\pred"
    print(f"  {hdr:10s}" + "".join(f"{c[:6]:>7s}" for c in CLASSES))
    for i, c in enumerate(CLASSES):
        print(f"  {c:10s}" + "".join(f"{cm[i][j]:>7d}" for j in range(5)))
    return acc, pred


def main():
    df = pd.read_csv(USER)
    sc = json.loads(Path(SCALER).read_text())
    mu = np.array(sc["mu"], dtype=np.float32)
    sd = np.array(sc["sd"], dtype=np.float32)
    X = df[FEATURE_NAMES].to_numpy(dtype=np.float32)
    y = df["class_idx"].to_numpy(dtype=np.int32)
    Xz = (X - mu) / sd

    interp = tf.lite.Interpreter(model_path=TFLITE)
    in_idx = interp.get_input_details()[0]["index"]
    out_idx = interp.get_output_details()[0]["index"]
    interp.resize_tensor_input(in_idx, [Xz.shape[0], Xz.shape[1]])
    interp.allocate_tensors()
    interp.set_tensor(in_idx, Xz)
    interp.invoke()
    probs = interp.get_tensor(out_idx)

    print(f"loaded {len(y)} samples; class dist: {dict(zip(CLASSES, np.bincount(y, minlength=5)))}")

    priors = {
        "P0 (current Flutter)": [0.4, 0.6, 2.5, 1.0, 0.5],
        "P1 (uniform)":         [1.0, 1.0, 1.0, 1.0, 1.0],
        "P2 (weak)":            [0.7, 0.8, 1.3, 1.0, 0.8],
        # P3: user 57 class distribution / uniform (effectively cancels)
        "P3 (user-dist)":       (np.bincount(y, minlength=5) / len(y) * 5).tolist(),
    }
    results = {}
    for name, prior in priors.items():
        acc, pred = evaluate(probs, y, prior, name)
        results[name] = (acc, pred)

    print("\n" + "=" * 60)
    print("SUMMARY (train accuracy on 57 East Asian, single-model)")
    print("=" * 60)
    for name, (acc, _) in sorted(results.items(), key=lambda kv: -kv[1][0]):
        print(f"  {name:25s} → {acc:.1%}")


if __name__ == "__main__":
    main()
