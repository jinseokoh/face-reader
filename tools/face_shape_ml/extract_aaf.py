"""Recalibrate face_reference_data.dart from the All-Age-Faces (AAF) dataset.

Reuses `extract_landmarks.compute_ratios` (verified Flutter parity with
face_metrics.dart: normalized [0,1] coords, faceAspectRatio gets
(imgH/imgW)*1.05 correction, everything else raw-normalized).

For each AAF "original images" photo:
  - MediaPipe FaceLandmarker → 468 normalized landmarks
  - near-frontal filter via facial transformation matrix (|yaw|,|pitch| < thresh)
  - compute the 26 referenceData metrics
Then aggregate per-gender mean/std and emit a drop-in `referenceData` block.

Gender from filename %05dA%02d.jpg: person_id < 7381 → female, else male.

Run:
  .venv/bin/python extract_aaf.py --limit 80      # quick smoke test
  .venv/bin/python extract_aaf.py                 # full run
"""
from __future__ import annotations

import argparse
import json
import math
import re
import time
from pathlib import Path

import cv2
import numpy as np
import mediapipe as mp
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision as mp_vision

from extract_landmarks import compute_ratios, FEATURE_NAMES, MODEL_PATH

HERE = Path(__file__).resolve().parent
IMG_DIR = HERE / "datasets/AAF/All-Age-Faces Dataset/original images"
OUT = HERE / "out"
OUT.mkdir(parents=True, exist_ok=True)

# referenceData 미사용(분류기 전용) 2개 제외.
SKIP = {"eyebrowLength", "noseBridgeRatio"}
REF_METRICS = [m for m in FEATURE_NAMES if m not in SKIP]

FNAME_RE = re.compile(r"^(\d{5})A(\d{2})", re.I)

YAW_MAX = 18.0    # degrees
PITCH_MAX = 18.0


def gender_of(stem: str) -> str | None:
    m = FNAME_RE.match(stem)
    if not m:
        return None
    pid = int(m.group(1))
    return "female" if pid <= 7380 else "male"


def yaw_pitch_from_matrix(mat: np.ndarray) -> tuple[float, float]:
    """Extract yaw,pitch (deg) from 4x4 facial transformation matrix (rotation part)."""
    r = mat[:3, :3]
    # yaw about Y, pitch about X (Tait-Bryan, MediaPipe convention approx)
    yaw = math.degrees(math.atan2(-r[2, 0], math.hypot(r[2, 1], r[2, 2])))
    pitch = math.degrees(math.atan2(r[2, 1], r[2, 2]))
    return yaw, pitch


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0, help="0 = all")
    ap.add_argument("--no-pose-filter", action="store_true")
    args = ap.parse_args()

    if not IMG_DIR.is_dir():
        raise SystemExit(f"AAF images not found: {IMG_DIR}")

    opts = mp_vision.FaceLandmarkerOptions(
        base_options=mp_python.BaseOptions(model_asset_path=MODEL_PATH),
        running_mode=mp_vision.RunningMode.IMAGE,
        num_faces=1,
        output_facial_transformation_matrixes=True,
    )
    det = mp_vision.FaceLandmarker.create_from_options(opts)

    files = sorted(IMG_DIR.glob("*.jpg"))
    if args.limit:
        # stride sample across the whole id range (covers both genders + ages)
        step = max(1, len(files) // args.limit)
        files = files[::step][: args.limit]

    # per gender: list of ratio-vectors
    bucket = {"male": [], "female": []}
    n_seen = n_ok = n_noface = n_pose = n_nan = n_nogender = 0
    t0 = time.time()

    for i, f in enumerate(files):
        n_seen += 1
        g = gender_of(f.stem)
        if g is None:
            n_nogender += 1
            continue
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
        bucket[g].append(ratios)
        n_ok += 1
        if (i + 1) % 500 == 0:
            print(f"  ...{i+1}/{len(files)} ok={n_ok} ({time.time()-t0:.0f}s)", flush=True)

    print(f"\n[scan] seen={n_seen} ok={n_ok} noface={n_noface} "
          f"pose_reject={n_pose} nan={n_nan} nogender={n_nogender} "
          f"({time.time()-t0:.0f}s)")
    print(f"  male={len(bucket['male'])} female={len(bucket['female'])}")

    # aggregate
    idx = {name: i for i, name in enumerate(FEATURE_NAMES)}
    result = {}
    for g in ("male", "female"):
        arr = np.stack(bucket[g]) if bucket[g] else np.empty((0, len(FEATURE_NAMES)))
        stats = {}
        for m in REF_METRICS:
            col = arr[:, idx[m]]
            stats[m] = {
                "mean": float(np.mean(col)),
                "sd": float(np.std(col)),       # population std (ddof=0)
                "n": int(col.size),
            }
        result[g] = stats

    (OUT / "aaf_reference.json").write_text(json.dumps(result, indent=2))
    print(f"  → {OUT/'aaf_reference.json'}")

    # per-face raw CSV (for Dart end-to-end validation through the real engine)
    with open(OUT / "aaf_per_face.csv", "w") as fh:
        fh.write("gender," + ",".join(REF_METRICS) + "\n")
        for g in ("male", "female"):
            for vec in bucket[g]:
                vals = [f"{vec[idx[m]]:.6f}" for m in REF_METRICS]
                fh.write(g + "," + ",".join(vals) + "\n")
    print(f"  → {OUT/'aaf_per_face.csv'}")

    # Dart drop-in block (eastAsian cell — applied to all ethnicities as pooled baseline)
    def fmt(g):
        lines = [f"    Gender.{g}: {{"]
        for m in REF_METRICS:
            s = result[g][m]
            # angles/ratios: keep 3-4 sig digits
            mean = s["mean"]
            sd = s["sd"]
            md = f"{mean:.4g}"
            sdd = f"{sd:.4g}"
            lines.append(f"      '{m}': MetricReference({md}, {sdd}),")
        lines.append("    },")
        return "\n".join(lines)

    dart = ("  // AAF-recalibrated (pooled East Asian, N male=%d female=%d) %s\n"
            "  Ethnicity.eastAsian: {\n%s\n%s\n  },\n") % (
        len(bucket["male"]), len(bucket["female"]),
        time.strftime("%Y-%m-%d"),
        fmt("male"), fmt("female"),
    )
    (OUT / "aaf_referenceData.dart.txt").write_text(dart)
    print(f"  → {OUT/'aaf_referenceData.dart.txt'}")
    print("\n=== female means (sanity) ===")
    for m in REF_METRICS:
        s = result["female"][m]
        print(f"  {m:24s} mean={s['mean']:.4f} sd={s['sd']:.4f}")


if __name__ == "__main__":
    main()
