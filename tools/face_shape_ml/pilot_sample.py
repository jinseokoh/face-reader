"""AAF 500장 파일럿 표본 추출 — 성별 균형 + MediaPipe 검출 성공분만.

Output:
  out/pilot/sample.csv       — file,gender (500 rows, seed 42)
  out/pilot/images/{file}    — 라벨링용 사본 (원본 그대로)

Run:
  tools/.venv/bin/python tools/face_shape_ml/pilot_sample.py
"""
from __future__ import annotations

import csv
import random
import shutil
import sys
from pathlib import Path

import cv2
import mediapipe as mp
import numpy as np
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision as mp_vision

sys.path.insert(0, str(Path(__file__).resolve().parent))
from extract_aaf import gender_of  # noqa: E402
from extract_landmarks import MODEL_PATH  # noqa: E402

TOOLS = Path(__file__).resolve().parent
AAF = TOOLS / "datasets/AAF/All-Age-Faces Dataset/original images"
OUT = TOOLS / "out/pilot"
N_PER_GENDER = 250
SEED = 42


def main() -> None:
    (OUT / "images").mkdir(parents=True, exist_ok=True)
    detector = mp_vision.FaceLandmarker.create_from_options(
        mp_vision.FaceLandmarkerOptions(
            base_options=mp_python.BaseOptions(model_asset_path=str(MODEL_PATH)),
            num_faces=1,
        )
    )

    by_gender: dict[str, list[Path]] = {"male": [], "female": []}
    for f in sorted(AAF.glob("*.jpg")):
        g = gender_of(f.stem)
        if g:
            by_gender[g].append(f)

    rng = random.Random(SEED)
    rows = []
    for g, files in by_gender.items():
        rng.shuffle(files)
        picked = 0
        for f in files:
            if picked >= N_PER_GENDER:
                break
            img = cv2.imread(str(f))
            if img is None:
                continue
            rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
            res = detector.detect(
                mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb))
            if not res.face_landmarks:
                continue
            shutil.copy(f, OUT / "images" / f.name)
            rows.append((f.name, g))
            picked += 1
        print(f"{g}: {picked}", flush=True)

    rng.shuffle(rows)  # 라벨링 순서도 성별 섞기
    with (OUT / "sample.csv").open("w", newline="") as fp:
        w = csv.writer(fp)
        w.writerow(["file", "gender"])
        w.writerows(rows)
    print(f"total {len(rows)} → {OUT / 'sample.csv'}")


if __name__ == "__main__":
    main()
