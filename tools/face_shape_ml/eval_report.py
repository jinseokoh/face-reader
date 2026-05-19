"""Evaluate the niten19-trained CNN on all /tmp/{gender}-{type}-{n}.{ext}
samples and produce a human-readable report.

For each photo:
  - top-1 prediction + confidence
  - top-2 prediction (인접 후보)
  - full 5-class softmax probabilities
  - match status (top-1 == expected, top-2 contains expected, neither)

Aggregate:
  - top-1 accuracy
  - top-2 accuracy (in top-2 considered correct)
  - per-class confusion matrix
  - per-class precision/recall

Run:
  /Users/chuck/Code/face/tools/.venv/bin/python \
      /Users/chuck/Code/face/tools/face_shape_ml/eval_report.py
"""
from __future__ import annotations

import os
os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")

import glob
import re
from pathlib import Path
import cv2
import numpy as np
import tensorflow as tf
from sklearn.metrics import confusion_matrix

CLASSES = ["Heart", "Oblong", "Oval", "Round", "Square"]
CLASS_LOWER = [c.lower() for c in CLASSES]
IDX = {c: i for i, c in enumerate(CLASS_LOWER)}
IMG_SIZE = 224
OUT = Path(__file__).resolve().parent / "out"
MODEL_PATH = OUT / "simple_mobilenet.keras"


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


def main():
    pat = re.compile(r"^(male|female)-(heart|oblong|oval|round|square)-\d+$")
    files = sorted(
        glob.glob("/tmp/male-*.png") + glob.glob("/tmp/male-*.jpg") + glob.glob("/tmp/male-*.jpeg")
        + glob.glob("/tmp/female-*.png") + glob.glob("/tmp/female-*.jpg") + glob.glob("/tmp/female-*.jpeg")
    )

    print(f"[load] {len(files)} files")
    print(f"[model] {MODEL_PATH}")
    model = tf.keras.models.load_model(MODEL_PATH)

    rows = []
    Xs, ys, names, genders = [], [], [], []
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
        Xs.append(img.astype(np.float32))
        ys.append(IDX[m.group(2)])
        names.append(stem)
        genders.append(m.group(1))

    X = np.stack(Xs)
    y = np.array(ys)
    probs = model.predict(X, verbose=0)
    top1 = np.argmax(probs, axis=1)
    top2 = np.argsort(probs, axis=1)[:, -2]  # 2nd highest

    print()
    print("=" * 80)
    print("PER-PHOTO DIAGNOSIS")
    print("=" * 80)
    hdr = f"{'file':22s} {'expected':9s}  {'top1':16s}  {'top2':16s}  match"
    print(hdr)
    print("-" * 80)
    for i, name in enumerate(names):
        exp = y[i]
        t1 = top1[i]
        t2 = top2[i]
        ps = probs[i]
        t1_str = f"{CLASSES[t1]:7s} ({ps[t1]*100:4.1f}%)"
        t2_str = f"{CLASSES[t2]:7s} ({ps[t2]*100:4.1f}%)"
        if t1 == exp:
            match = "✓ top1"
        elif t2 == exp:
            match = "~ top2"
        else:
            match = "✗ miss"
        print(f"{name:22s} {CLASSES[exp]:9s}  {t1_str:16s}  {t2_str:16s}  {match}")

    # Aggregate metrics
    n = len(y)
    top1_correct = int(np.sum(top1 == y))
    top2_correct = int(np.sum((top1 == y) | (top2 == y)))
    print()
    print("=" * 60)
    print(f"Top-1 accuracy:  {top1_correct}/{n} = {top1_correct/n:.1%}")
    print(f"Top-2 accuracy:  {top2_correct}/{n} = {top2_correct/n:.1%}  (정답이 1·2위 안)")

    # Confusion matrix
    print()
    print("Confusion matrix (top-1):")
    cm = confusion_matrix(y, top1, labels=list(range(5)))
    hdr_label = "true\\pred"
    print(f"{hdr_label:10s}" + "".join(f"{c[:6]:>7s}" for c in CLASSES) + "  total recall")
    for i, c in enumerate(CLASSES):
        row = "".join(f"{cm[i][j]:>7d}" for j in range(5))
        total = cm[i].sum()
        recall = cm[i][i] / max(total, 1)
        print(f"{c:10s}{row}   {total:5d}  {recall:.1%}")
    # column-wise precision
    print(f"{'precision':10s}", end="")
    for j in range(5):
        col = cm[:, j].sum()
        prec = cm[j][j] / max(col, 1)
        print(f"{prec:>7.1%}", end="")
    print()

    # Gender split
    print()
    print("Gender split:")
    for g in ("male", "female"):
        mask = np.array([gg == g for gg in genders])
        gn = mask.sum()
        gc1 = int(np.sum(top1[mask] == y[mask]))
        gc2 = int(np.sum((top1[mask] == y[mask]) | (top2[mask] == y[mask])))
        print(f"  {g}: top-1 {gc1}/{gn} ({gc1/gn:.1%}) | top-2 {gc2}/{gn} ({gc2/gn:.1%})")


if __name__ == "__main__":
    main()
