"""Face shape calibration: MediaPipe face mesh → metrics → LDA weights.

Reads labeled photos from `data/{wide,long,standard}/*` (skip files with "측면"),
computes the same metrics as `face_metrics.dart`, runs ANOVA + LDA, and
prints suggested weights + thresholds for `_faceShape()`.

Run:
    /Users/chuck/Code/face/tools/.venv/bin/python calibrate_face_shape.py
"""
from __future__ import annotations

import argparse
import os
import unicodedata
from pathlib import Path

import cv2
import numpy as np
import pandas as pd
import mediapipe as mp
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision as mp_vision
from scipy import stats
from sklearn.discriminant_analysis import LinearDiscriminantAnalysis
from sklearn.model_selection import LeaveOneOut

_MODEL_PATH = str(Path(__file__).parent / "face_landmarker.task")
_DETECTOR = None


def _get_detector():
    global _DETECTOR
    if _DETECTOR is None:
        _DETECTOR = mp_vision.FaceLandmarker.create_from_options(
            mp_vision.FaceLandmarkerOptions(
                base_options=mp_python.BaseOptions(model_asset_path=_MODEL_PATH),
                running_mode=mp_vision.RunningMode.IMAGE,
                num_faces=1,
            )
        )
    return _DETECTOR

# ─── Landmark indices (port of face_metrics.dart::LandmarkIndex) ───
FOREHEAD_TOP = 10
CHIN = 152
R_FACE_EDGE, L_FACE_EDGE = 234, 454
R_GONION, L_GONION = 172, 397
R_EAR, L_EAR = 132, 361
R_JAW_LOWER, L_JAW_LOWER = 150, 379
R_CHIN_SIDE, L_CHIN_SIDE = 148, 377
NASION, NOSE_TIP, SUBNASALE = 168, 1, 94
R_ENDO, L_ENDO = 133, 362

LM10_CORR = 1.05  # face_analysis.dart::kLandmark10Correction


def _d(lm, a, b) -> float:
    return float(np.hypot(lm[a, 0] - lm[b, 0], lm[a, 1] - lm[b, 1]))


def _ang(lm, a, v, b) -> float:
    ax, ay = lm[a, 0] - lm[v, 0], lm[a, 1] - lm[v, 1]
    bx, by = lm[b, 0] - lm[v, 0], lm[b, 1] - lm[v, 1]
    return float(np.degrees(np.arctan2(abs(ax * by - ay * bx), ax * bx + ay * by)))


def compute_metrics(lm: np.ndarray, img_w: int, img_h: int) -> dict:
    fh = _d(lm, FOREHEAD_TOP, CHIN)
    fw = _d(lm, R_FACE_EDGE, L_FACE_EDGE)
    jaw = _d(lm, R_GONION, L_GONION)
    jaw_lo = _d(lm, R_JAW_LOWER, L_JAW_LOWER)
    chin_s = _d(lm, R_CHIN_SIDE, L_CHIN_SIDE)
    icd = _d(lm, R_ENDO, L_ENDO)

    aspect_raw = fh / fw
    aspect_corr = aspect_raw * (img_h / img_w) * LM10_CORR

    upper = _d(lm, FOREHEAD_TOP, NASION) / fh
    mid = _d(lm, NASION, SUBNASALE) / fh
    lower = _d(lm, SUBNASALE, CHIN) / fh

    gonial = (_ang(lm, R_EAR, R_GONION, CHIN) + _ang(lm, L_EAR, L_GONION, CHIN)) / 2.0

    return {
        "faceH_raw": fh,
        "faceW_raw": fw,
        "jawW_raw": jaw,
        "jawLowerW_raw": jaw_lo,
        "chinSideW_raw": chin_s,
        "icd_raw": icd,
        "faceAspectRatio_raw": aspect_raw,
        "faceAspectRatio": aspect_corr,
        "faceTaperRatio": jaw / fw,
        "upperFaceRatio": upper,
        "midFaceRatio": mid,
        "lowerFaceRatio": lower,
        "lowerFaceFullness": (jaw + jaw_lo + chin_s) / (3.0 * fw),
        "fullnessMin": min(jaw, jaw_lo, chin_s) / fw,
        "fullnessSlope": (jaw - chin_s) / fw,
        "taperJawLower": jaw_lo / fw,
        "taperChinSide": chin_s / fw,
        "widthSignature": fw / (fw + jaw),
        "verticalBalance": upper - lower,
        "gonialAngle": gonial,
    }


def extract_landmarks(path: str):
    img = cv2.imread(path)
    if img is None:
        return None, None, None
    h, w = img.shape[:2]
    rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
    mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
    result = _get_detector().detect(mp_image)
    if not result.face_landmarks:
        return None, w, h
    lm = np.array(
        [(p.x, p.y, p.z) for p in result.face_landmarks[0]],
        dtype=np.float64,
    )
    return lm, w, h


def collect(data_dir: Path) -> pd.DataFrame:
    rows = []
    for label in ("wide", "long", "standard"):
        folder = data_dir / label
        if not folder.is_dir():
            print(f"[skip] {folder} missing")
            continue
        for f in sorted(folder.iterdir()):
            if not f.is_file():
                continue
            # macOS may return NFD-decomposed Korean filenames → normalize to NFC.
            nname = unicodedata.normalize("NFC", f.name)
            if "측면" in nname:
                print(f"[skip lateral] {label}/{nname}")
                continue
            if f.suffix.lower() not in (".jpg", ".jpeg", ".png", ".webp"):
                continue
            lm, w, h = extract_landmarks(str(f))
            if lm is None:
                print(f"[no face] {label}/{f.name}")
                continue
            m = compute_metrics(lm, w, h)
            m.update({"label": label, "subject": f.stem, "imgW": w, "imgH": h})
            rows.append(m)
            print(
                f"[ok] {label}/{f.name:30s}  "
                f"aspect={m['faceAspectRatio']:.3f}  "
                f"taper={m['faceTaperRatio']:.3f}  "
                f"fullnessMin={m['fullnessMin']:.3f}  "
                f"slope={m['fullnessSlope']:.3f}"
            )
    return pd.DataFrame(rows)


def analyze(df: pd.DataFrame, out_dir: Path) -> None:
    non_metric = {"label", "subject", "imgW", "imgH"}
    metric_cols = [c for c in df.columns if c not in non_metric]

    # ─── Per-class descriptive ───
    print("\n══════════ Per-class mean ± std ══════════")
    for c in metric_cols:
        row = "  {:22s}".format(c)
        for lab in ("wide", "standard", "long"):
            v = df[df.label == lab][c]
            if len(v):
                row += f"  {lab}: {v.mean():+.3f}±{v.std():.3f}"
            else:
                row += f"  {lab}: --"
        print(row)

    # ─── ANOVA F (3-class) ───
    print("\n══════════ ANOVA F (higher = stronger 3-class signal) ══════════")
    f_rows = []
    for m in metric_cols:
        groups = [df[df.label == lab][m].values for lab in ("wide", "long", "standard")]
        groups = [g for g in groups if len(g) >= 2]
        if len(groups) < 2:
            continue
        F, p = stats.f_oneway(*groups)
        f_rows.append((m, F, p))
    f_rows.sort(key=lambda x: (0 if np.isnan(x[1]) else x[1]), reverse=True)
    for m, F, p in f_rows:
        print(f"  {m:22s}  F={F:7.2f}  p={p:.4f}")

    # ─── Cohen's d (wide vs long, the primary axis) ───
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
    for m, d in d_rows:
        print(f"  {m:22s}  d={d:+.2f}")

    # ─── Pick top-k metrics (by 3-class F) for LDA ───
    # Drop raw distances (not scale-invariant) to avoid leaking image size.
    excluded = {"faceH_raw", "faceW_raw", "jawW_raw", "jawLowerW_raw",
                "chinSideW_raw", "icd_raw", "faceAspectRatio_raw", "imgW", "imgH"}
    candidates = [m for m, _, _ in f_rows if m not in excluded]
    TOP_K = min(5, len(candidates))
    top = candidates[:TOP_K]
    print(f"\n══════════ LDA on top-{TOP_K}: {top} ══════════")

    # Standardize each metric → coefficients directly comparable
    X = df[top].values.astype(float)
    means = X.mean(axis=0)
    sds = X.std(axis=0, ddof=1)
    Xs = (X - means) / np.where(sds == 0, 1, sds)
    y = df["label"].values

    lda3 = LinearDiscriminantAnalysis()
    lda3.fit(Xs, y)
    print("3-class LDA coefficients (on z-scored metrics):")
    print(f"  classes: {list(lda3.classes_)}")
    for i, c in enumerate(lda3.classes_):
        cstr = "  " + c.ljust(10)
        for m, w in zip(top, lda3.coef_[i]):
            cstr += f"  {m}={w:+.2f}"
        print(cstr)

    # ─── Binary LDA: wide vs long (primary axis for widthScore) ───
    mask = df.label.isin(["wide", "long"])
    Xb = Xs[mask.values]
    yb = (df.loc[mask, "label"] == "wide").astype(int).values
    ldab = LinearDiscriminantAnalysis()
    ldab.fit(Xb, yb)
    coef = ldab.coef_[0]  # + → wide
    intercept = ldab.intercept_[0]

    print("\n══════════ SUGGESTED _faceShape() FORMULA ══════════")
    print("Compute on z-scored metrics (z = (raw - refMean) / refSD):")
    print("  widthScore = " + "  ".join(
        f"{w:+.2f}*{m}_z" for m, w in zip(top, coef)
    ))

    # Project all samples onto this axis
    proj_all = Xs @ coef + intercept
    df["widthScore"] = proj_all
    print("\nwidthScore by class:")
    for lab in ("wide", "standard", "long"):
        v = df[df.label == lab]["widthScore"].values
        if len(v):
            print(f"  {lab:10s}  n={len(v)}  "
                  f"mean={v.mean():+.3f}  std={v.std():.3f}  "
                  f"min={v.min():+.3f}  max={v.max():+.3f}")

    w_mean = df[df.label == "wide"]["widthScore"].mean()
    s_mean = df[df.label == "standard"]["widthScore"].mean()
    l_mean = df[df.label == "long"]["widthScore"].mean()
    t_pos = (w_mean + s_mean) / 2 if not np.isnan(s_mean) else (w_mean + l_mean) / 2
    t_neg = (s_mean + l_mean) / 2 if not np.isnan(s_mean) else (w_mean + l_mean) / 2
    print(f"\nThresholds (midpoints of class means):")
    print(f"  widthScore > {t_pos:+.2f}  → wide")
    print(f"  widthScore < {t_neg:+.2f}  → long")
    print(f"  otherwise                 → standard")

    # ─── Hierarchical 2-stage classifier ───
    # Stage 1: wide vs non-wide (best signal: fullnessSlope / faceTaperRatio / widthSignature)
    # Stage 2: long vs standard   (best signal: faceAspectRatio)
    print("\n══════════ Hierarchical 2-stage classifier ══════════")

    # Stage 1: rule-based (faceTaperRatio 임계). 상관 높은 피처로 LDA 돌리면
    # 계수 부호 불안정 → 단순 임계값이 훨씬 robust.
    # threshold = (학습 wide 최소 + 학습 non-wide 최대) / 2
    stage1_feat = "faceTaperRatio"
    wide_min = df[df.label == "wide"][stage1_feat].min()
    nonwide_max = df[df.label != "wide"][stage1_feat].max()
    t1 = (wide_min + nonwide_max) / 2
    stage1_feats = [stage1_feat]  # for downstream print
    stage2_feats = ["faceAspectRatio", "gonialAngle", "upperFaceRatio"]
    print(f"stage 1 (wide vs rest): rule `faceTaperRatio > {t1:.3f}`")
    print(f"  (wide min={wide_min:.3f}, non-wide max={nonwide_max:.3f}, gap={wide_min-nonwide_max:+.3f})")
    print(f"stage 2 (long vs standard): {stage2_feats}")

    def _fit_stage1(df_):
        # Rule-based: recompute threshold per fold to keep LOOCV honest.
        wmin = df_[df_.label == "wide"][stage1_feat].min()
        nmax = df_[df_.label != "wide"][stage1_feat].max()
        t = (wmin + nmax) / 2 if (not np.isnan(wmin) and not np.isnan(nmax)) else 0.8
        return ("rule", t, stage1_feat), None, None

    def _fit_stage2(df_):
        d2 = df_[df_.label.isin(["long", "standard"])]
        X2 = d2[stage2_feats].values.astype(float)
        X2s = (X2 - X2.mean(0)) / X2.std(0, ddof=1).clip(min=1e-9)
        y2 = (d2.label == "long").astype(int).values
        clf = LinearDiscriminantAnalysis()
        clf.fit(X2s, y2)
        return clf, X2.mean(0), X2.std(0, ddof=1).clip(min=1e-9)

    c1, _, _ = _fit_stage1(df)  # ("rule", threshold, feature_name)
    c2, m2, s2 = _fit_stage2(df)

    _, t1_val, t1_feat = c1
    print(f"\nstage 1 rule: {t1_feat} > {t1_val:.4f}  → wide")
    print("stage 2 coefficients (long = +1, standard = 0; z-scored features):")
    for f_, w in zip(stage2_feats, c2.coef_[0]):
        print(f"  {f_:22s}  {w:+.3f}")
    print(f"  intercept: {c2.intercept_[0]:+.3f}")

    def _predict_stage1(row_feat_val, c1_tuple):
        _, thr, _ = c1_tuple
        return row_feat_val > thr

    # LOOCV on hierarchical classifier
    loo = LeaveOneOut()
    correct_h = 0
    labels = sorted(set(y))
    conf_h = {a: {b: 0 for b in labels} for a in labels}
    wrong_rows = []
    for tr, te in loo.split(df):
        df_tr = df.iloc[tr]
        df_te = df.iloc[te]
        c1_, _, _ = _fit_stage1(df_tr)
        c2_, m2_, s2_ = _fit_stage2(df_tr)
        s1_val = df_te[t1_feat].values[0]
        if _predict_stage1(s1_val, c1_):
            pred = "wide"
        else:
            xs2 = (df_te[stage2_feats].values[0] - m2_) / s2_
            pred = "long" if c2_.predict([xs2])[0] == 1 else "standard"
        true = df_te.label.values[0]
        conf_h[true][pred] += 1
        if pred == true:
            correct_h += 1
        else:
            wrong_rows.append((df_te.subject.values[0], true, pred))

    n = len(df)
    print(f"\n══════════ Hierarchical LOOCV: {correct_h}/{n} = {correct_h/n*100:.1f}% ══════════")
    header = "  " + " " * 10 + "  " + "  ".join(f"{l:>10s}" for l in labels)
    print(header)
    for t in labels:
        print("  " + t.ljust(10) + "  " + "  ".join(f"{conf_h[t][p]:>10d}" for p in labels))
    if wrong_rows:
        print("\nmisclassified subjects:")
        for sub, tru, pre in wrong_rows:
            print(f"  {sub:20s}  true={tru:10s}  pred={pre}")

    # ─── Also: flat 3-class LDA for comparison ───
    correct_f = 0
    conf_f = {a: {b: 0 for b in labels} for a in labels}
    for tr, te in loo.split(Xs):
        clf = LinearDiscriminantAnalysis()
        clf.fit(Xs[tr], y[tr])
        pred = clf.predict(Xs[te])[0]
        true = y[te][0]
        conf_f[true][pred] += 1
        if pred == true:
            correct_f += 1
    print(f"\n(flat 3-class LDA LOOCV for comparison: {correct_f}/{n} = {correct_f/n*100:.1f}%)")

    # ─── Print final proposed Dart formula ───
    # Unstandardize stage-2 LDA to raw-value form (no z-score needed in Dart).
    c2_coef_z = c2.coef_[0]
    c2_int_z = c2.intercept_[0]
    c2_coef_raw = c2_coef_z / s2
    c2_int_raw = float(c2_int_z - np.sum(c2_coef_z * m2 / s2))

    print("\n══════════ PROPOSED _faceShape() (Dart-ready, raw values) ══════════")
    print(f"// Stage 1: isWide = {t1_feat} > {t1_val:.4f}")
    print("// Stage 2: long vs standard (only if not wide)")
    print("//   stage2 =")
    for f_, w in zip(stage2_feats, c2_coef_raw):
        print(f"//     {w:+.4f} * {f_}")
    print(f"//   + ({c2_int_raw:+.4f})")
    print("//   isLong = stage2 > 0")
    print("// Verification — raw formula reproduces training predictions:")
    raw_scores = df[stage2_feats].values @ c2_coef_raw + c2_int_raw
    for i, lab in enumerate(df["label"].values):
        if lab in ("long", "standard"):
            pass  # trust; no print per sample
    # Summary by class
    dfc = df.copy()
    dfc["s2_raw"] = raw_scores
    for lab in ("long", "standard"):
        v = dfc[dfc.label == lab]["s2_raw"].values
        if len(v):
            print(f"//   {lab}: mean={v.mean():+.3f} std={v.std():.3f} range=[{v.min():+.3f},{v.max():+.3f}]")

    for f_, w in zip(stage2_feats, c2.coef_[0]):
        print(f"// {f_}_z × {w:+.2f}")
    print(f"// isLong = (stage2Score + ({c2.intercept_[0]:+.2f})) > 0")
    print("// else: standard")

    # ─── Save CSV ───
    df.to_csv(out_dir / "face_calib.csv", index=False)
    print(f"\n[csv] {len(df)} rows → {out_dir/'face_calib.csv'}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", default="/Users/chuck/Desktop/test/data")
    ap.add_argument("--out", default="/Users/chuck/Code/face/tools/out")
    args = ap.parse_args()

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    df = collect(Path(args.data))
    if df.empty:
        print("[error] no samples")
        return
    analyze(df, out_dir)


if __name__ == "__main__":
    main()
