"""Predict face shape for unlabeled photos + move into label folders.

Stage 1 (wide vs rest): rule-based threshold on `faceTaperRatio` — learned
from the training-sample clean gap between wide-min and non-wide-max.
Stage 2 (long vs standard): LDA on [faceAspectRatio, gonialAngle, upperFaceRatio].

Run:
    /Users/chuck/Code/face/tools/.venv/bin/python classify_unlabeled.py [--move]
"""
from __future__ import annotations

import argparse
import shutil
import unicodedata
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.discriminant_analysis import LinearDiscriminantAnalysis

from calibrate_face_shape import (
    collect,
    compute_metrics,
    extract_landmarks,
)

STAGE1_FEAT = "faceTaperRatio"
STAGE2_FEATS = ["faceAspectRatio", "gonialAngle", "upperFaceRatio"]


def fit_hierarchical(df: pd.DataFrame):
    # Stage 1: threshold = midpoint(wide min, non-wide max) of STAGE1_FEAT
    wmin = df[df.label == "wide"][STAGE1_FEAT].min()
    nmax = df[df.label != "wide"][STAGE1_FEAT].max()
    t1 = (wmin + nmax) / 2

    # Stage 2: binary LDA long vs standard on z-scored features
    d2 = df[df.label.isin(["long", "standard"])]
    X2 = d2[STAGE2_FEATS].values.astype(float)
    m2 = X2.mean(0)
    s2 = X2.std(0, ddof=1).clip(min=1e-9)
    X2s = (X2 - m2) / s2
    y2 = (d2.label == "long").astype(int).values
    c2 = LinearDiscriminantAnalysis()
    c2.fit(X2s, y2)

    return (t1, wmin, nmax), (c2, m2, s2)


def predict(feat_row: dict, stage1, stage2) -> tuple[str, float, float]:
    t1, _, _ = stage1
    c2, m2, s2 = stage2

    s1_val = feat_row[STAGE1_FEAT]
    margin1 = s1_val - t1  # positive → wide
    if margin1 > 0:
        return "wide", margin1, float("nan")

    x2 = np.array([feat_row[f] for f in STAGE2_FEATS])
    x2s = (x2 - m2) / s2
    s2_score = float(c2.decision_function([x2s])[0])
    return ("long" if s2_score > 0 else "standard"), margin1, s2_score


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", default="/Users/chuck/Desktop/test/data")
    ap.add_argument("--move", action="store_true", help="실제로 파일 이동")
    args = ap.parse_args()

    data_dir = Path(args.data)

    print("=== 학습 데이터 수집 ===")
    df = collect(data_dir)
    if df.empty:
        print("[error] no labeled samples")
        return

    print(f"\n=== 분류기 학습 (n={len(df)}) ===")
    stage1, stage2 = fit_hierarchical(df)
    t1, wmin, nmax = stage1
    print(f"stage1 rule: {STAGE1_FEAT} > {t1:.4f}  → wide")
    print(f"  (wide min={wmin:.3f}, non-wide max={nmax:.3f}, gap={wmin-nmax:+.3f})")

    # Unlabeled images: loose files directly under data/ (not in subfolders)
    loose = []
    for f in sorted(data_dir.iterdir()):
        if not f.is_file():
            continue
        nname = unicodedata.normalize("NFC", f.name)
        if "측면" in nname:
            continue
        if f.suffix.lower() not in (".jpg", ".jpeg", ".png", ".webp"):
            continue
        loose.append(f)

    if not loose:
        print("\n[info] no unlabeled images in", data_dir)
        return

    print(f"\n=== 분류 대상 {len(loose)}장 ===")
    results = []
    for f in loose:
        lm, w, h = extract_landmarks(str(f))
        if lm is None:
            print(f"  [no face] {f.name}")
            continue
        feat = compute_metrics(lm, w, h)
        pred, m1, s2 = predict(feat, stage1, stage2)
        results.append((f, pred, m1, s2, feat))
        s2_str = f"{s2:+.2f}" if not np.isnan(s2) else "--"
        print(
            f"  {f.name:30s}  aspect={feat['faceAspectRatio']:.3f}  "
            f"taper={feat['faceTaperRatio']:.3f}  "
            f"taper−t1={m1:+.3f}  stage2={s2_str}  → {pred}"
        )

    if not args.move:
        print("\n(dry-run) 이동하려면 --move 추가")
        return

    print("\n=== 이동 ===")
    for f, pred, *_ in results:
        dst = data_dir / pred / f.name
        dst.parent.mkdir(exist_ok=True)
        shutil.move(str(f), str(dst))
        print(f"  {f.name}  →  {pred}/")


if __name__ == "__main__":
    main()
