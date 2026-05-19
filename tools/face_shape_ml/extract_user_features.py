"""Extract 28 features from /tmp/{gender}-{type}-{n}.{ext} user samples.
Square-pad first (matches Flutter album path), then MediaPipe → 28 ratios.
Writes out/user_features.csv with same FEATURE_NAMES schema as niten19.

Run:
  /Users/chuck/Code/face/tools/.venv/bin/python \
      /Users/chuck/Code/face/tools/face_shape_ml/extract_user_features.py
"""
from __future__ import annotations

import sys
import glob
import re
import time
from pathlib import Path

import cv2
import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))
from extract_landmarks import compute_ratios, FEATURE_NAMES, CLASSES  # type: ignore

import mediapipe as mp
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision as mp_vision

TOOLS = Path(__file__).resolve().parent.parent
LANDMARKER = str(TOOLS / "face_landmarker.task")
OUT = Path(__file__).resolve().parent / "out"
OUT.mkdir(parents=True, exist_ok=True)


def pad_to_square(img):
    h, w = img.shape[:2]
    if h == w:
        return img
    if w < h:
        d = h - w
        return cv2.copyMakeBorder(img, 0, 0, d // 2, d - d // 2,
                                  cv2.BORDER_CONSTANT, value=(255, 255, 255))
    d = w - h
    return cv2.copyMakeBorder(img, d // 2, d - d // 2, 0, 0,
                              cv2.BORDER_CONSTANT, value=(255, 255, 255))


def main():
    opts = mp_vision.FaceLandmarkerOptions(
        base_options=mp_python.BaseOptions(model_asset_path=LANDMARKER),
        running_mode=mp_vision.RunningMode.IMAGE,
        num_faces=1,
    )
    det = mp_vision.FaceLandmarker.create_from_options(opts)

    pat = re.compile(r"^(male|female)-(heart|oblong|oval|round|square)-\d+$")
    files = sorted(
        glob.glob("/tmp/male-*.png") + glob.glob("/tmp/male-*.jpg") + glob.glob("/tmp/male-*.jpeg")
        + glob.glob("/tmp/female-*.png") + glob.glob("/tmp/female-*.jpg") + glob.glob("/tmp/female-*.jpeg")
    )

    rows = []
    t0 = time.time()
    for f in files:
        stem = Path(f).stem
        m = pat.match(stem)
        if not m:
            continue
        gender, label = m.group(1), m.group(2)
        img = cv2.imread(f)
        if img is None:
            print(f"  ! read fail: {stem}")
            continue
        img = pad_to_square(img)
        h, w = img.shape[:2]
        rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
        result = det.detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb))
        if not result.face_landmarks:
            print(f"  ! no face: {stem}")
            continue
        lm = np.array([(p.x, p.y, p.z) for p in result.face_landmarks[0]], dtype=np.float32)
        ratios = compute_ratios(lm, w, h)
        if not np.all(np.isfinite(ratios)):
            print(f"  ! non-finite: {stem}")
            continue
        row = {"file": stem, "gender": gender, "class": label.capitalize(),
               "class_idx": CLASSES.index(label.capitalize())}
        for name, v in zip(FEATURE_NAMES, ratios):
            row[name] = float(v)
        rows.append(row)
        print(f"  ok {stem} ({label})")

    df = pd.DataFrame(rows)
    out = OUT / "user_features.csv"
    df.to_csv(out, index=False)
    dt = time.time() - t0
    print(f"\n[done] {len(rows)}/{len(files)} ok in {dt:.1f}s → {out}")
    print(f"  class dist: {df['class'].value_counts().to_dict()}")
    print(f"  gender dist: {df['gender'].value_counts().to_dict()}")


if __name__ == "__main__":
    main()
