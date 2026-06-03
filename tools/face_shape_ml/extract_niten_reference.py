"""Derive a non-East-Asian `referenceData` baseline from the niten19 Kaggle
FaceShape dataset — measured through the SAME pipeline as extract_aaf.py.

Why: eastAsian frontal reference is AAF-empirical (measured in our 2D MediaPipe
proxy frame). The 5 other ethnicities still carried clinical-anthropometry
estimates whose measurement frame differs from production input (e.g. clinical
gonialAngle ~120° vs our pipeline's ~140° → systematic +z bias). This script
re-measures niten19 IN OUR FRAME and emits a pooled "rest-of-world" baseline so
EA and non-EA references finally live in one commensurable frame.

Caveats (intentional, documented):
  * niten19 has NO ethnicity labels (mixed-race) → ONE pooled baseline applied
    to all 5 non-EA ethnicities, not per-ethnicity calibration.
  * niten19 has NO gender labels → gender-pooled (male == female block).
  * niten19 is balanced by face SHAPE (equal oval/round/square/heart/oblong),
    not population-representative → shape-metric SD slightly inflated, means
    flattened. Conservative for saturation; fine as a fallback.
  * Frontal 26 metric only. Lateral 8 metric (nasofrontal/E-line/dorsal etc.)
    are NOT measurable from frontal photos → lateral clinical estimates stay.

Run:
  .venv/bin/python extract_niten_reference.py --limit 80   # smoke
  .venv/bin/python extract_niten_reference.py              # full (~5000 imgs)
"""
from __future__ import annotations

import argparse
import json
import math
import time
from pathlib import Path

import cv2
import numpy as np
import mediapipe as mp
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision as mp_vision

from extract_landmarks import compute_ratios, FEATURE_NAMES, MODEL_PATH, DATASET, CLASSES

HERE = Path(__file__).resolve().parent
OUT = HERE / "out"
OUT.mkdir(parents=True, exist_ok=True)

# referenceData 미사용(분류기 전용) 2개 제외 — extract_aaf.py 와 동일.
SKIP = {"eyebrowLength", "noseBridgeRatio"}
REF_METRICS = [m for m in FEATURE_NAMES if m not in SKIP]

# 5 non-EA ethnicities that share the pooled niten19 baseline.
NON_EA_ETHNICITIES = [
    "caucasian",
    "african",
    "southeastAsian",
    "hispanic",
    "middleEastern",
]

YAW_MAX = 18.0    # degrees — same near-frontal gate as extract_aaf.py
PITCH_MAX = 18.0


def yaw_pitch_from_matrix(mat: np.ndarray) -> tuple[float, float]:
    """yaw,pitch (deg) from 4x4 facial transformation matrix. Mirrors extract_aaf."""
    r = mat[:3, :3]
    yaw = math.degrees(math.atan2(-r[2, 0], math.hypot(r[2, 1], r[2, 2])))
    pitch = math.degrees(math.atan2(r[2, 1], r[2, 2]))
    return yaw, pitch


def iter_images():
    """All niten19 jpgs across training_set + testing_set × 5 shape folders."""
    for split in ("training_set", "testing_set"):
        for cls in CLASSES:
            d = DATASET / split / cls
            if not d.is_dir():
                continue
            for f in sorted(d.glob("*.jpg")):
                yield f


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0, help="0 = all")
    ap.add_argument("--no-pose-filter", action="store_true")
    args = ap.parse_args()

    if not DATASET.is_dir():
        raise SystemExit(f"niten19 dataset not found: {DATASET}")

    opts = mp_vision.FaceLandmarkerOptions(
        base_options=mp_python.BaseOptions(model_asset_path=MODEL_PATH),
        running_mode=mp_vision.RunningMode.IMAGE,
        num_faces=1,
        output_facial_transformation_matrixes=True,
    )
    det = mp_vision.FaceLandmarker.create_from_options(opts)

    files = list(iter_images())
    if args.limit:
        step = max(1, len(files) // args.limit)
        files = files[::step][: args.limit]

    bucket: list[np.ndarray] = []
    n_seen = n_ok = n_noface = n_pose = n_nan = 0
    t0 = time.time()

    for i, f in enumerate(files):
        n_seen += 1
        img = cv2.imread(str(f))
        if img is None:
            n_noface += 1
            continue
        h, w = img.shape[:2]
        rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
        res = det.detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb))
        if not res.face_landmarks:
            n_noface += 1
            continue
        if not args.no_pose_filter and res.facial_transformation_matrixes:
            mat = np.array(res.facial_transformation_matrixes[0]).reshape(4, 4)
            yaw, pitch = yaw_pitch_from_matrix(mat)
            if abs(yaw) > YAW_MAX or abs(pitch) > PITCH_MAX:
                n_pose += 1
                continue
        lm = np.array([(p.x, p.y, p.z) for p in res.face_landmarks[0]], dtype=np.float32)
        ratios = compute_ratios(lm, w, h)
        if not np.all(np.isfinite(ratios)):
            n_nan += 1
            continue
        bucket.append(ratios)
        n_ok += 1
        if (i + 1) % 500 == 0:
            print(f"  ...{i+1}/{len(files)} ok={n_ok} ({time.time()-t0:.0f}s)", flush=True)

    print(f"\n[scan] seen={n_seen} ok={n_ok} noface={n_noface} "
          f"pose_reject={n_pose} nan={n_nan} ({time.time()-t0:.0f}s)")

    if not bucket:
        raise SystemExit("no usable faces — aborting (check dataset / pose filter)")

    idx = {name: i for i, name in enumerate(FEATURE_NAMES)}
    arr = np.stack(bucket)
    stats = {}
    for m in REF_METRICS:
        col = arr[:, idx[m]]
        stats[m] = {
            "mean": float(np.mean(col)),
            "sd": float(np.std(col)),    # population std (ddof=0), matches AAF
            "n": int(col.size),
        }

    (OUT / "niten_reference.json").write_text(json.dumps(stats, indent=2))
    print(f"  → {OUT/'niten_reference.json'}")

    with open(OUT / "niten_per_face.csv", "w") as fh:
        fh.write(",".join(REF_METRICS) + "\n")
        for vec in bucket:
            fh.write(",".join(f"{vec[idx[m]]:.6f}" for m in REF_METRICS) + "\n")
    print(f"  → {OUT/'niten_per_face.csv'}")

    # Dart drop-in — 5 non-EA ethnicities, gender-pooled (male == female).
    n = len(bucket)
    stamp = time.strftime("%Y-%m-%d")

    def fmt_gender(g: str) -> str:
        lines = [f"    Gender.{g}: {{"]
        for m in REF_METRICS:
            s = stats[m]
            lines.append(f"      '{m}': MetricReference({s['mean']:.4g}, {s['sd']:.4g}),")
        lines.append("    },")
        return "\n".join(lines)

    male = fmt_gender("male")
    female = fmt_gender("female")
    head = (
        "    // ─── niten19 pooled non-EA baseline (%s, N=%d) ───\n"
        "    // Kaggle FaceShape dataset, measured through the SAME pipeline as\n"
        "    // extract_aaf.py (MediaPipe 468 → compute_ratios, near-frontal\n"
        "    // yaw/pitch<18°). No ethnicity/gender labels → ONE pooled baseline,\n"
        "    // gender-pooled (male == female). Shape-balanced sampling → SD\n"
        "    // slightly inflated. Source: tools/face_shape_ml/extract_niten_reference.py."
    ) % (stamp, n)

    blocks = []
    for eth in NON_EA_ETHNICITIES:
        blocks.append(
            f"  Ethnicity.{eth}: {{\n{head}\n{male}\n{female}\n  }},"
        )
    dart = "\n".join(blocks) + "\n"
    (OUT / "niten_referenceData.dart.txt").write_text(dart)
    print(f"  → {OUT/'niten_referenceData.dart.txt'}")

    print(f"\n=== pooled means (sanity, N={n}) ===")
    for m in REF_METRICS:
        s = stats[m]
        print(f"  {m:24s} mean={s['mean']:.4f} sd={s['sd']:.4f}")


if __name__ == "__main__":
    main()
