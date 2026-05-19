"""Evaluate Strategy B MLP (niten19+user mixed) on all 57 user samples.
Uses the SAVED final model trained on niten19 + ALL user data, so this is
a *train accuracy* measurement, not generalization. (5-fold CV mean was 47.6%
for honest generalization.)
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

sys.path.insert(0, str(Path(__file__).resolve().parent))
from extract_landmarks import FEATURE_NAMES, CLASSES  # type: ignore

OUT = Path(__file__).resolve().parent / "out"
MODEL = OUT / "mlp_eastasian_final.keras"
SCALER = OUT / "mlp_eastasian_scaler.json"
USER = OUT / "user_features.csv"


def main():
    df = pd.read_csv(USER)
    X = df[FEATURE_NAMES].to_numpy(dtype=np.float32)
    y_true = df["class_idx"].to_numpy(dtype=np.int32)
    names = df["file"].tolist()
    genders = df["gender"].tolist()

    sc = json.loads(SCALER.read_text())
    mu = np.array(sc["mu"], dtype=np.float32)
    sd = np.array(sc["sd"], dtype=np.float32)
    Xz = (X - mu) / sd

    model = tf.keras.models.load_model(MODEL)
    probs = model.predict(Xz, verbose=0)
    top1 = np.argmax(probs, axis=1)
    top2 = np.argsort(probs, axis=1)[:, -2]

    print()
    print("=" * 80)
    print("PER-PHOTO DIAGNOSIS — Strategy B (niten19 + user mixed, final all-data)")
    print("=" * 80)
    hdr = f"{'file':22s} {'expected':9s}  {'top1':17s}  {'top2':17s}  match"
    print(hdr)
    print("-" * 80)
    correct1 = correct2 = 0
    for i, name in enumerate(names):
        e = y_true[i]
        t1 = top1[i]
        t2 = top2[i]
        ps = probs[i]
        t1_s = f"{CLASSES[t1]:7s} ({ps[t1]*100:4.1f}%)"
        t2_s = f"{CLASSES[t2]:7s} ({ps[t2]*100:4.1f}%)"
        if t1 == e:
            match = "✓ top1"; correct1 += 1; correct2 += 1
        elif t2 == e:
            match = "~ top2"; correct2 += 1
        else:
            match = "✗ miss"
        print(f"{name:22s} {CLASSES[e]:9s}  {t1_s:17s}  {t2_s:17s}  {match}")

    n = len(names)
    print()
    print("=" * 60)
    print(f"Top-1: {correct1}/{n} = {correct1/n:.1%}")
    print(f"Top-2: {correct2}/{n} = {correct2/n:.1%}")
    print(f"  ⚠ NOTE: this measures train accuracy (final model saw all 57).")
    print(f"  Honest 5-fold CV mean was 47.6% (= deployment expectation).")

    # Confusion
    from sklearn.metrics import confusion_matrix
    cm = confusion_matrix(y_true, top1, labels=list(range(5)))
    print()
    print("Confusion matrix (top-1, all-data final model):")
    hdr = "true\\pred"
    print(f"{hdr:10s}" + "".join(f"{c[:6]:>7s}" for c in CLASSES) + "  total recall")
    for i, c in enumerate(CLASSES):
        row = "".join(f"{cm[i][j]:>7d}" for j in range(5))
        total = cm[i].sum()
        recall = cm[i][i] / max(total, 1)
        print(f"{c:10s}{row}   {total:5d}  {recall:.1%}")


if __name__ == "__main__":
    main()
