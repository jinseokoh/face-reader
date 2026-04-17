"""Device-side recalibration: Flutter 앱에서 수집한 CSV → LDA → weights.

Python MediaPipe 없이 앱이 이미 계산한 metric raw값만 사용.
calibrate_face_shape.py와 동일한 분석 파이프라인.

Run:
    /Users/chuck/Code/face/tools/.venv/bin/python calibrate_device.py
"""
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import pandas as pd
from scipy import stats
from sklearn.discriminant_analysis import LinearDiscriminantAnalysis
from sklearn.model_selection import LeaveOneOut


def analyze(df: pd.DataFrame) -> None:
    non_metric = {"label", "alias", "timestamp", "gender", "ethnicity", "ageGroup", "source"}
    metric_cols = [c for c in df.columns if c not in non_metric]
    y = df["label"].values

    print(f"총 {len(df)}건: " + ", ".join(
        f"{lab}={n}" for lab, n in df.label.value_counts().items()
    ))

    # ─── Per-class means ───
    print("\n══════════ Per-class mean ± std ══════════")
    for c in metric_cols:
        row = f"  {c:22s}"
        for lab in ("wide", "standard", "long"):
            v = df[df.label == lab][c]
            if len(v):
                row += f"  {lab}: {v.mean():+.4f}±{v.std():.4f}"
        print(row)

    # ─── ANOVA F ───
    print("\n══════════ ANOVA F ══════════")
    f_rows = []
    for m in metric_cols:
        groups = [df[df.label == lab][m].values for lab in ("wide", "long", "standard")]
        groups = [g for g in groups if len(g) >= 2]
        if len(groups) < 2:
            continue
        F, p = stats.f_oneway(*groups)
        f_rows.append((m, F, p))
    f_rows.sort(key=lambda x: (0 if np.isnan(x[1]) else x[1]), reverse=True)
    for m, F, p in f_rows[:12]:
        print(f"  {m:22s}  F={F:7.2f}  p={p:.4f}")

    # ─── Cohen's d (wide vs long) ───
    print("\n══════════ Cohen's d (wide vs long) ══════════")
    d_rows = []
    for m in metric_cols:
        w = df[df.label == "wide"][m].values
        l = df[df.label == "long"][m].values
        if len(w) < 2 or len(l) < 2:
            continue
        sp = np.sqrt(
            ((len(w) - 1) * w.var(ddof=1) + (len(l) - 1) * l.var(ddof=1))
            / (len(w) + len(l) - 2)
        )
        if sp == 0:
            continue
        d = (w.mean() - l.mean()) / sp
        d_rows.append((m, d))
    d_rows.sort(key=lambda x: abs(x[1]), reverse=True)
    for m, d in d_rows[:12]:
        print(f"  {m:22s}  d={d:+.2f}")

    # ─── Stage 1: wide detection (threshold rule on best single feature) ───
    print("\n══════════ Stage 1: Wide detection ══════════")
    # Try faceTaperRatio and lowerFaceFullness as candidates
    for feat in ["faceTaperRatio", "lowerFaceFullness"]:
        wmin = df[df.label == "wide"][feat].min()
        wmax = df[df.label == "wide"][feat].max()
        nmin = df[df.label != "wide"][feat].min()
        nmax = df[df.label != "wide"][feat].max()
        gap = wmin - nmax
        t = (wmin + nmax) / 2
        overlap = wmin < nmax
        print(f"  {feat}: wide=[{wmin:.4f},{wmax:.4f}]  rest=[{nmin:.4f},{nmax:.4f}]  "
              f"gap={gap:+.4f}  threshold={t:.4f}  {'OVERLAP!' if overlap else 'clean'}")

    # Pick best stage1 feature: faceTaperRatio or lowerFaceFullness (whichever has bigger gap)
    s1_candidates = {}
    for feat in ["faceTaperRatio", "lowerFaceFullness"]:
        wmin = df[df.label == "wide"][feat].min()
        nmax = df[df.label != "wide"][feat].max()
        s1_candidates[feat] = (wmin - nmax, (wmin + nmax) / 2, wmin, nmax)

    best_s1 = max(s1_candidates.items(), key=lambda x: x[1][0])
    s1_feat = best_s1[0]
    s1_gap, s1_threshold, s1_wmin, s1_nmax = best_s1[1]
    print(f"\n  → Best stage1: {s1_feat} > {s1_threshold:.4f} (gap={s1_gap:+.4f})")

    # ─── Stage 2: long vs standard (LDA on non-wide) ───
    print("\n══════════ Stage 2: Long vs Standard ══════════")
    stage2_feats = ["faceAspectRatio", "gonialAngle", "upperFaceRatio"]

    d2 = df[df.label.isin(["long", "standard"])]
    X2 = d2[stage2_feats].values.astype(float)
    m2 = X2.mean(0)
    s2 = X2.std(0, ddof=1).clip(min=1e-9)
    X2s = (X2 - m2) / s2
    y2 = (d2.label == "long").astype(int).values
    lda2 = LinearDiscriminantAnalysis()
    lda2.fit(X2s, y2)

    print("LDA coefficients (z-scored):")
    for f_, w in zip(stage2_feats, lda2.coef_[0]):
        print(f"  {f_:22s}  {w:+.3f}")
    print(f"  intercept: {lda2.intercept_[0]:+.3f}")

    # Unstandardize to raw-value form
    coef_raw = lda2.coef_[0] / s2
    int_raw = float(lda2.intercept_[0] - np.sum(lda2.coef_[0] * m2 / s2))

    print("\nRaw-value formula (Dart-ready):")
    print("  stage2 =")
    for f_, w in zip(stage2_feats, coef_raw):
        print(f"    {w:+.4f} * {f_}")
    print(f"    + ({int_raw:+.4f})")
    print("  isLong = stage2 > 0")

    # Verify on training data
    raw_scores = d2[stage2_feats].values @ coef_raw + int_raw
    for lab in ("long", "standard"):
        v = raw_scores[d2.label.values == lab]
        if len(v):
            print(f"  {lab}: mean={v.mean():+.3f} std={v.std():.3f} "
                  f"range=[{v.min():+.3f},{v.max():+.3f}]")

    # ─── Hierarchical LOOCV ───
    print("\n══════════ Hierarchical LOOCV ══════════")
    loo = LeaveOneOut()
    correct = 0
    labels = sorted(set(y))
    conf = {a: {b: 0 for b in labels} for a in labels}
    wrong = []

    for tr, te in loo.split(df):
        df_tr = df.iloc[tr]
        df_te = df.iloc[te]

        # Stage 1 refit
        wmin_f = df_tr[df_tr.label == "wide"][s1_feat].min()
        nmax_f = df_tr[df_tr.label != "wide"][s1_feat].max()
        t1_f = (wmin_f + nmax_f) / 2

        test_val = df_te[s1_feat].values[0]
        if test_val > t1_f:
            pred = "wide"
        else:
            # Stage 2 refit
            d2_tr = df_tr[df_tr.label.isin(["long", "standard"])]
            X2_tr = d2_tr[stage2_feats].values.astype(float)
            m2_f = X2_tr.mean(0)
            s2_f = X2_tr.std(0, ddof=1).clip(min=1e-9)
            X2s_f = (X2_tr - m2_f) / s2_f
            y2_f = (d2_tr.label == "long").astype(int).values
            clf2 = LinearDiscriminantAnalysis()
            clf2.fit(X2s_f, y2_f)
            x_te = (df_te[stage2_feats].values[0] - m2_f) / s2_f
            pred = "long" if clf2.predict([x_te])[0] == 1 else "standard"

        true = df_te.label.values[0]
        conf[true][pred] += 1
        if pred == true:
            correct += 1
        else:
            wrong.append((df_te.index[0], true, pred,
                          df_te[s1_feat].values[0],
                          df_te["faceAspectRatio"].values[0]))

    n = len(df)
    print(f"Accuracy: {correct}/{n} = {correct / n * 100:.1f}%")
    header = "  " + " " * 10 + "  ".join(f"{l:>10s}" for l in labels)
    print(header)
    for t in labels:
        print("  " + t.ljust(10) + "  ".join(f"{conf[t][p]:>10d}" for p in labels))
    if wrong:
        print(f"\nmisclassified ({len(wrong)}):")
        for idx, tru, pre, s1v, asp in wrong:
            print(f"  row={idx}  true={tru:10s}  pred={pre:10s}  "
                  f"{s1_feat}={s1v:.4f}  aspect={asp:.4f}")

    # ─── Final formula summary ───
    print("\n══════════ FINAL DART FORMULA ══════════")
    print(f"// Stage 1: isWide = {s1_feat} > {s1_threshold:.4f}")
    print(f"//   (wide min={s1_wmin:.4f}, non-wide max={s1_nmax:.4f}, gap={s1_gap:+.4f})")
    print("// Stage 2 (if not wide):")
    print("//   stage2 =")
    for f_, w in zip(stage2_feats, coef_raw):
        print(f"//     {w:+.4f} * {f_}")
    print(f"//     + ({int_raw:+.4f})")
    print("//   isLong = stage2 > 0")
    print("//   else → standard")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", default="/Users/chuck/Code/face/tools/device_data/face_calib_device.csv")
    args = ap.parse_args()

    df = pd.read_csv(args.csv)
    print(f"[csv] loaded {len(df)} rows from {args.csv}")
    analyze(df)


if __name__ == "__main__":
    main()
