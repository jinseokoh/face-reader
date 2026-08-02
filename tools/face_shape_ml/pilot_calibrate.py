"""파일럿 보정 체크 — labels.csv 의 내 라벨 vs 현행 MLP 예측 대조.

Run:
  tools/.venv/bin/python tools/face_shape_ml/pilot_calibrate.py
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")

import cv2
import mediapipe as mp
import numpy as np
import pandas as pd
import tensorflow as tf
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision as mp_vision

sys.path.insert(0, str(Path(__file__).resolve().parent))
from extract_landmarks import CLASSES, MODEL_PATH, compute_ratios  # noqa: E402

TOOLS = Path(__file__).resolve().parent
OUT = TOOLS / "out"
PILOT = OUT / "pilot"


def main() -> None:
    mlp = tf.keras.models.load_model(OUT / "mlp_eastasian_final.keras")
    sc = json.loads((OUT / "mlp_eastasian_scaler.json").read_text())
    mu = np.array(sc["mu"], dtype=np.float32)
    sd = np.array(sc["sd"], dtype=np.float32)
    detector = mp_vision.FaceLandmarker.create_from_options(
        mp_vision.FaceLandmarkerOptions(
            base_options=mp_python.BaseOptions(model_asset_path=MODEL_PATH),
            num_faces=1,
        )
    )

    df = pd.read_csv(PILOT / "labels.csv")
    agree = 0
    used = 0
    dist_mine: dict[str, int] = {}
    dist_mlp: dict[str, int] = {}
    print(f"{'file':16s}{'mine':8s}{'conf':6s}{'mlp':8s}{'mlp_p':6s}")
    for _, r in df.iterrows():
        img = cv2.imread(str(PILOT / "images" / r.file))
        rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
        res = detector.detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb))
        if not res.face_landmarks:
            print(f"{r.file:16s}{r.label:8s}{r.confidence:6s}{'—':8s}")
            continue
        lm = np.array([(p.x, p.y, p.z) for p in res.face_landmarks[0]],
                      dtype=np.float32)
        ratios = compute_ratios(lm, rgb.shape[1], rgb.shape[0])
        z = ((ratios - mu) / sd).astype(np.float32)[None]
        probs = mlp.predict(z, verbose=0)[0]
        pred = CLASSES[int(np.argmax(probs))]
        used += 1
        agree += int(pred == r.label)
        dist_mine[r.label] = dist_mine.get(r.label, 0) + 1
        dist_mlp[pred] = dist_mlp.get(pred, 0) + 1
        print(f"{r.file:16s}{r.label:8s}{r.confidence:6s}{pred:8s}"
              f"{float(probs.max()):.2f}")

    print(f"\nagreement: {agree}/{used}")
    print(f"my dist : {dict(sorted(dist_mine.items()))}")
    print(f"mlp dist: {dict(sorted(dist_mlp.items()))}")


if __name__ == "__main__":
    main()
