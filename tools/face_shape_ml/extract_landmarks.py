"""Extract MediaPipe face-mesh landmarks + 18 Flutter-parity metrics from the
niten19 Kaggle face-shape dataset. Saves per-sample NPZ and aggregate CSV.

Flutter parity: formulas mirror `flutter/lib/domain/services/face_metrics.dart`
and the aspectRatio correction in `face_analysis.dart`
(`aspect_corr = aspect_raw * (imgH/imgW) * 1.05`).

Output:
  out/landmarks.npz   — landmarks[N,468,3] float32, labels[N] int, ratios[N,18] float32
  out/features.csv    — human-readable per-sample features
  out/meta.json       — {classes, feature_names, stats}

Run:
  .venv/bin/python face_shape_ml/extract_landmarks.py
"""
from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path

import cv2
import numpy as np
import pandas as pd
import mediapipe as mp
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision as mp_vision

TOOLS = Path(__file__).resolve().parent.parent
DATASET = TOOLS / "datasets/kaggle_cache/datasets/niten19/face-shape-dataset/versions/2/FaceShape Dataset"
MODEL_PATH = str(TOOLS / "face_landmarker.task")
OUT = Path(__file__).resolve().parent / "out"
OUT.mkdir(parents=True, exist_ok=True)

CLASSES = ("Heart", "Oblong", "Oval", "Round", "Square")

# Mirror face_metrics.dart::LandmarkIndex
FOREHEAD_TOP = 10
CHIN = 152
R_FACE_EDGE, L_FACE_EDGE = 234, 454
R_GONION, L_GONION = 172, 397
R_EAR, L_EAR = 132, 361
R_JAW_LOWER, L_JAW_LOWER = 150, 379
R_CHIN_SIDE, L_CHIN_SIDE = 148, 377
R_TEMPLE, L_TEMPLE = 54, 284          # Phase 1: 天庭
R_CHEEKBONE, L_CHEEKBONE = 116, 345   # Phase 1: 顴骨
NASION, NOSE_TIP, SUBNASALE = 168, 1, 94
R_ALA, L_ALA = 98, 327
R_ENDO, L_ENDO = 133, 362
R_EXO, L_EXO = 33, 263
R_EYE_TOP, L_EYE_TOP = 159, 386
R_EYE_BOT, L_EYE_BOT = 145, 374        # Phase 1: eyeAspect
R_BROW_UP = (46, 53, 52)
R_BROW_LO = (70, 63, 105)
L_BROW_UP = (276, 283, 282)
L_BROW_LO = (300, 293, 334)
R_BROW_LO3, L_BROW_LO3 = 105, 334
R_BROW_OUTER, R_BROW_INNER = 46, 55    # Phase 1: tail / head
L_BROW_OUTER, L_BROW_INNER = 276, 285
R_BROW_MID, L_BROW_MID = 52, 282        # upper-arc midpoint for curvature
R_CHEILION, L_CHEILION = 61, 291
UPPER_LIP_TOP, LOWER_LIP_BOT = 0, 17
UPPER_LIP_INNER, LOWER_LIP_INNER = 13, 14

LM10_CORRECTION = 1.05  # face_analysis.dart::kLandmark10Correction

FEATURE_NAMES = [
    # ─── Original 18 (nasalHeightRatio formula changed 2026-04-17: nose bridge) ───
    "faceAspectRatio",    # includes (imgH/imgW)*1.05 correction (Flutter parity)
    "faceTaperRatio",
    "lowerFaceFullness",
    "upperFaceRatio",
    "midFaceRatio",
    "lowerFaceRatio",
    "gonialAngle",
    "intercanthalRatio",
    "eyeFissureRatio",
    "eyeCanthalTilt",
    "eyebrowThickness",
    "browEyeDistance",
    "nasalWidthRatio",    # ala / icd
    "nasalHeightRatio",   # NOW dist(nasion, noseTip) / faceHeight (bug fix)
    "mouthWidthRatio",
    "mouthCornerAngle",   # bug-fixed: midLipX used as x-ref
    "lipFullnessRatio",
    "philtrumLength",
    # ─── Phase 1 — 관상학 additions (2026-04-17) ───
    "eyebrowLength",        # 兄弟宮 (눈 길이 대비)
    "eyebrowTiltDirection", # 劍眉/八字眉 (부호 보존)
    "eyebrowCurvature",     # 直眉/彎眉
    "browSpacing",          # 印堂
    "eyeAspect",            # 鳳眼/圓眼 (세로/가로)
    "upperVsLowerLipRatio", # 윗/아랫 입술
    "chinAngle",            # 方/尖 頤
    "foreheadWidth",        # 天庭
    "cheekboneWidth",       # 顴骨
    "noseBridgeRatio",      # 콧대 bridge / nasion-subnasale
]


def _d(lm, a, b):
    return float(np.hypot(lm[a, 0] - lm[b, 0], lm[a, 1] - lm[b, 1]))


def _ang(lm, a, v, b):
    ax, ay = lm[a, 0] - lm[v, 0], lm[a, 1] - lm[v, 1]
    bx, by = lm[b, 0] - lm[v, 0], lm[b, 1] - lm[v, 1]
    return float(np.degrees(np.arctan2(abs(ax * by - ay * bx), ax * bx + ay * by)))


def compute_ratios(lm: np.ndarray, img_w: int, img_h: int) -> np.ndarray:
    fh = _d(lm, FOREHEAD_TOP, CHIN)
    fw = _d(lm, R_FACE_EDGE, L_FACE_EDGE)
    jaw = _d(lm, R_GONION, L_GONION)
    jaw_lo = _d(lm, R_JAW_LOWER, L_JAW_LOWER)
    chin_s = _d(lm, R_CHIN_SIDE, L_CHIN_SIDE)
    icd = _d(lm, R_ENDO, L_ENDO)

    aspect_raw = fh / fw if fw > 0 else 0.0
    aspect_corr = aspect_raw * (img_h / img_w) * LM10_CORRECTION

    taper = jaw / fw if fw > 0 else 0.0
    fullness = (jaw + jaw_lo + chin_s) / (3.0 * fw) if fw > 0 else 0.0

    upper = _d(lm, FOREHEAD_TOP, NASION) / fh if fh > 0 else 0.0
    mid = _d(lm, NASION, SUBNASALE) / fh if fh > 0 else 0.0
    lower = _d(lm, SUBNASALE, CHIN) / fh if fh > 0 else 0.0

    gonial = (_ang(lm, R_EAR, R_GONION, CHIN) + _ang(lm, L_EAR, L_GONION, CHIN)) / 2.0

    inter = icd / fw if fw > 0 else 0.0
    eye_r_w = _d(lm, R_EXO, R_ENDO)
    eye_l_w = _d(lm, L_EXO, L_ENDO)
    fissure = (eye_r_w + eye_l_w) / 2.0 / fw if fw > 0 else 0.0

    rx = lm[R_EXO, 0] - lm[R_ENDO, 0]
    ry = -(lm[R_EXO, 1] - lm[R_ENDO, 1])
    lx = lm[L_EXO, 0] - lm[L_ENDO, 0]
    ly = -(lm[L_EXO, 1] - lm[L_ENDO, 1])
    tilt_r = np.degrees(np.arctan2(ry, abs(rx)))
    tilt_l = np.degrees(np.arctan2(ly, abs(lx)))
    canthal_tilt = (tilt_r + tilt_l) / 2.0

    brow_r = sum(_d(lm, u, l) for u, l in zip(R_BROW_UP, R_BROW_LO)) / 3.0
    brow_l = sum(_d(lm, u, l) for u, l in zip(L_BROW_UP, L_BROW_LO)) / 3.0
    brow_thick = (brow_r + brow_l) / 2.0 / fh if fh > 0 else 0.0

    brow_eye = (_d(lm, R_BROW_LO3, R_EYE_TOP) + _d(lm, L_BROW_LO3, L_EYE_TOP)) / 2.0 / fh if fh > 0 else 0.0

    ala_w = _d(lm, R_ALA, L_ALA)
    nasal_w = ala_w / icd if icd > 0 else 0.0
    # nasalHeightRatio bug fix: NASION → NOSE_TIP (was NASION → SUBNASALE; duplicated midFaceRatio)
    nasal_h = _d(lm, NASION, NOSE_TIP) / fh if fh > 0 else 0.0

    mouth_w = _d(lm, R_CHEILION, L_CHEILION) / fw if fw > 0 else 0.0

    # mouthCornerAngle bug fix: use midLipX (not midLipY) as x-reference
    mid_lip_x = (lm[UPPER_LIP_INNER, 0] + lm[LOWER_LIP_INNER, 0]) / 2.0
    mid_lip_y = (lm[UPPER_LIP_INNER, 1] + lm[LOWER_LIP_INNER, 1]) / 2.0
    rcx = lm[R_CHEILION, 0] - mid_lip_x
    rcy = -(lm[R_CHEILION, 1] - mid_lip_y)
    lcx = lm[L_CHEILION, 0] - mid_lip_x
    lcy = -(lm[L_CHEILION, 1] - mid_lip_y)
    mca_r = np.degrees(np.arctan2(rcy, abs(rcx)))
    mca_l = np.degrees(np.arctan2(lcy, abs(lcx)))
    mouth_corner = (mca_r + mca_l) / 2.0

    lip_full = _d(lm, UPPER_LIP_TOP, LOWER_LIP_BOT) / fh if fh > 0 else 0.0
    philtrum = _d(lm, SUBNASALE, UPPER_LIP_TOP) / fh if fh > 0 else 0.0

    # ─── Phase 1 attributes (2026-04-17) ───
    # eyebrowLength: brow length / eye length
    brow_len_r = _d(lm, R_BROW_OUTER, R_BROW_INNER)
    brow_len_l = _d(lm, L_BROW_OUTER, L_BROW_INNER)
    eye_avg_w = (eye_r_w + eye_l_w) / 2.0
    brow_length = ((brow_len_r + brow_len_l) / 2.0 / eye_avg_w) if eye_avg_w > 0 else 0.0

    # eyebrowTiltDirection: (inner.y - outer.y) / faceHeight. + if outer higher
    r_tilt_dir = lm[R_BROW_INNER, 1] - lm[R_BROW_OUTER, 1]
    l_tilt_dir = lm[L_BROW_INNER, 1] - lm[L_BROW_OUTER, 1]
    brow_tilt_dir = ((r_tilt_dir + l_tilt_dir) / 2.0 / fh) if fh > 0 else 0.0

    # eyebrowCurvature: chord(y of inner/outer midpoint) - middle.y, normalized
    def _curve(inner, middle, outer):
        y_line = (lm[inner, 1] + lm[outer, 1]) / 2.0
        return y_line - lm[middle, 1]
    r_curve = _curve(R_BROW_INNER, R_BROW_MID, R_BROW_OUTER)
    l_curve = _curve(L_BROW_INNER, L_BROW_MID, L_BROW_OUTER)
    brow_curvature = ((r_curve + l_curve) / 2.0 / fh) if fh > 0 else 0.0

    # browSpacing: 印堂
    brow_spacing = _d(lm, R_BROW_INNER, L_BROW_INNER) / fw if fw > 0 else 0.0

    # eyeAspect: eye height / width
    eye_asp_r = _d(lm, R_EYE_TOP, R_EYE_BOT) / eye_r_w if eye_r_w > 0 else 0.0
    eye_asp_l = _d(lm, L_EYE_TOP, L_EYE_BOT) / eye_l_w if eye_l_w > 0 else 0.0
    eye_aspect = (eye_asp_r + eye_asp_l) / 2.0

    # upperVsLowerLipRatio
    upper_lip_thick = _d(lm, UPPER_LIP_TOP, UPPER_LIP_INNER)
    lower_lip_thick = _d(lm, LOWER_LIP_INNER, LOWER_LIP_BOT)
    up_lo_lip = (upper_lip_thick / lower_lip_thick) if lower_lip_thick > 0 else 0.0

    # chinAngle: at chin (152), between rightChinSide (148) and leftChinSide (377)
    chin_angle = _ang(lm, R_CHIN_SIDE, CHIN, L_CHIN_SIDE)

    # foreheadWidth: 天庭 (temple-to-temple) / faceWidth
    forehead_w = _d(lm, R_TEMPLE, L_TEMPLE) / fw if fw > 0 else 0.0

    # cheekboneWidth: 顴骨
    cheek_w = _d(lm, R_CHEEKBONE, L_CHEEKBONE) / fw if fw > 0 else 0.0

    # noseBridgeRatio: bridge(nasion→noseTip) / full(nasion→subnasale)
    full_n = _d(lm, NASION, SUBNASALE)
    nose_bridge_ratio = (_d(lm, NASION, NOSE_TIP) / full_n) if full_n > 0 else 0.0

    return np.array([
        aspect_corr, taper, fullness,
        upper, mid, lower, gonial,
        inter, fissure, canthal_tilt,
        brow_thick, brow_eye,
        nasal_w, nasal_h,
        mouth_w, mouth_corner, lip_full, philtrum,
        # Phase 1
        brow_length, brow_tilt_dir, brow_curvature, brow_spacing,
        eye_aspect, up_lo_lip, chin_angle,
        forehead_w, cheek_w, nose_bridge_ratio,
    ], dtype=np.float32)


def run(phase: str, detector) -> list[dict]:
    rows = []
    for ci, cls in enumerate(CLASSES):
        folder = DATASET / phase / cls
        files = sorted(folder.iterdir()) if folder.is_dir() else []
        t0 = time.time()
        ok = 0
        fail = 0
        for f in files:
            if f.suffix.lower() not in (".jpg", ".jpeg", ".png"):
                continue
            img = cv2.imread(str(f))
            if img is None:
                fail += 1
                continue
            h, w = img.shape[:2]
            rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
            result = detector.detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb))
            if not result.face_landmarks:
                fail += 1
                continue
            lm = np.array(
                [(p.x, p.y, p.z) for p in result.face_landmarks[0]],
                dtype=np.float32,
            )
            ratios = compute_ratios(lm, w, h)
            if not np.all(np.isfinite(ratios)):
                fail += 1
                continue
            rows.append({
                "phase": phase,
                "class": cls,
                "class_idx": ci,
                "file": f.name,
                "img_w": w,
                "img_h": h,
                "landmarks": lm,  # [468,3]
                "ratios": ratios,
            })
            ok += 1
        dt = time.time() - t0
        print(f"[{phase}/{cls}] ok={ok} fail={fail} ({dt:.1f}s)", flush=True)
    return rows


def main():
    opts = mp_vision.FaceLandmarkerOptions(
        base_options=mp_python.BaseOptions(model_asset_path=MODEL_PATH),
        running_mode=mp_vision.RunningMode.IMAGE,
        num_faces=1,
    )
    det = mp_vision.FaceLandmarker.create_from_options(opts)

    train = run("training_set", det)
    test = run("testing_set", det)
    all_rows = train + test

    N = len(all_rows)
    landmarks = np.stack([r["landmarks"] for r in all_rows])
    ratios = np.stack([r["ratios"] for r in all_rows])
    labels = np.array([r["class_idx"] for r in all_rows], dtype=np.int32)
    phase_mask = np.array([r["phase"] == "training_set" for r in all_rows], dtype=bool)

    np.savez(
        OUT / "landmarks.npz",
        landmarks=landmarks,
        ratios=ratios,
        labels=labels,
        is_train=phase_mask,
    )

    # Human-readable CSV (drop landmarks)
    df = pd.DataFrame({
        "phase": [r["phase"] for r in all_rows],
        "class": [r["class"] for r in all_rows],
        "class_idx": [r["class_idx"] for r in all_rows],
        "file": [r["file"] for r in all_rows],
        "img_w": [r["img_w"] for r in all_rows],
        "img_h": [r["img_h"] for r in all_rows],
    })
    for i, name in enumerate(FEATURE_NAMES):
        df[name] = ratios[:, i]
    df.to_csv(OUT / "features.csv", index=False)

    meta = {
        "classes": list(CLASSES),
        "feature_names": FEATURE_NAMES,
        "n_train": int(phase_mask.sum()),
        "n_test": int((~phase_mask).sum()),
        "n_total": int(N),
        "landmark_correction": {
            "lm10": LM10_CORRECTION,
            "aspect_corr": "(imgH/imgW)",
        },
    }
    (OUT / "meta.json").write_text(json.dumps(meta, indent=2))
    print(f"\n[done] train={meta['n_train']} test={meta['n_test']} total={meta['n_total']}")
    print(f"  → {OUT/'landmarks.npz'}")
    print(f"  → {OUT/'features.csv'}")
    print(f"  → {OUT/'meta.json'}")


if __name__ == "__main__":
    main()
