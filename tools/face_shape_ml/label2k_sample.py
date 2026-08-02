"""AAF 2000장 본 라벨링 표본 추출 — 성별 균형 + MediaPipe 검출 성공분만.

파일럿 500장(out/pilot/sample.csv)과 중복되지 않는 파일만 뽑는다.

Output:
  out/label2k/sample.csv       — file,gender (2000 rows, seed 202)
  out/label2k/images/{file}    — 라벨링용 사본 (원본 그대로)

Run:
  tools/.venv/bin/python tools/face_shape_ml/label2k_sample.py
"""
from __future__ import annotations

import csv
import random
import shutil
import sys
from pathlib import Path

import cv2
import mediapipe as mp
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision as mp_vision

sys.path.insert(0, str(Path(__file__).resolve().parent))
from extract_aaf import gender_of  # noqa: E402
from extract_landmarks import MODEL_PATH  # noqa: E402

TOOLS = Path(__file__).resolve().parent
AAF = TOOLS / "datasets/AAF/All-Age-Faces Dataset/original images"
PILOT_CSV = TOOLS / "out/pilot/sample.csv"
OUT = TOOLS / "out/label2k"
N_PER_GENDER = 1000
SEED = 202


def main() -> None:
    (OUT / "images").mkdir(parents=True, exist_ok=True)
    detector = mp_vision.FaceLandmarker.create_from_options(
        mp_vision.FaceLandmarkerOptions(
            base_options=mp_python.BaseOptions(model_asset_path=str(MODEL_PATH)),
            num_faces=1,
        )
    )

    with PILOT_CSV.open() as fp:
        pilot_files = {r["file"] for r in csv.DictReader(fp)}
    print(f"pilot exclusion: {len(pilot_files)} files")

    by_gender: dict[str, list[Path]] = {"male": [], "female": []}
    for f in sorted(AAF.glob("*.jpg")):
        if f.name in pilot_files:
            continue
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
            if picked % 200 == 0:
                print(f"{g}: {picked}", flush=True)
        print(f"{g}: {picked} done", flush=True)

    rng.shuffle(rows)
    with (OUT / "sample.csv").open("w", newline="") as fp:
        w = csv.writer(fp)
        w.writerow(["file", "gender"])
        w.writerows(rows)
    print(f"total {len(rows)} → {OUT / 'sample.csv'}")


if __name__ == "__main__":
    main()
