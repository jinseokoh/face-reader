"""AAF 얼굴마다 468 랜드마크를 앱 저장 형식(등방 좌표: x, y×h/w)으로 뽑는다.
extract_aaf.py 와 같은 pose 필터(yaw/pitch ≤ 18°)라 같은 11,800장이 나온다.

출력 (out/):
  aaf_landmarks.f32       float32 N×936 (행 = 얼굴, [x0,y0,x1,y1,…]) — Dart 가 바로 읽는다
  aaf_landmarks_meta.csv  stem,gender,age (행 순서 = f32 행 순서)
용도: Procrustes 닮은 정도 보정(procrustes_calibration_test) · 데모 seed 인물 좌표.
실행: tools/.venv/bin/python tools/face_shape_ml/extract_aaf_landmarks.py
"""
import re
import time
import cv2
import numpy as np
import mediapipe as mp
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision as mp_vision

from extract_aaf import IMG_DIR, OUT, YAW_MAX, PITCH_MAX, FNAME_RE, gender_of, yaw_pitch_from_matrix
from extract_landmarks import MODEL_PATH


def main():
    files = sorted(IMG_DIR.glob("*.jpg"))
    opts = mp_vision.FaceLandmarkerOptions(
        base_options=mp_python.BaseOptions(model_asset_path=MODEL_PATH),
        num_faces=1,
        output_facial_transformation_matrixes=True,
    )
    det = mp_vision.FaceLandmarker.create_from_options(opts)
    rows, meta = [], []
    t0 = time.time()
    for i, f in enumerate(files):
        g = gender_of(f.stem)
        if g is None:
            continue
        age = int(FNAME_RE.match(f.stem).group(2))
        img = cv2.imread(str(f))
        if img is None:
            continue
        h, w = img.shape[:2]
        res = det.detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=cv2.cvtColor(img, cv2.COLOR_BGR2RGB)))
        if not res.face_landmarks:
            continue
        if res.facial_transformation_matrixes:
            yaw, pitch = yaw_pitch_from_matrix(np.array(res.facial_transformation_matrixes[0]).reshape(4, 4))
            if abs(yaw) > YAW_MAX or abs(pitch) > PITCH_MAX:
                continue
        lm = res.face_landmarks[0][:468]  # tasks API 는 478(홍채 10) — 앱은 468
        aspect = h / w
        row = np.array([[p.x, p.y * aspect] for p in lm], dtype=np.float32).reshape(-1)
        row = np.round(row, 4)
        rows.append(row)
        meta.append(f"{f.stem},{g},{age}")
        if (i + 1) % 1000 == 0:
            print(f"  ...{i+1}/{len(files)} ok={len(rows)} ({time.time()-t0:.0f}s)", flush=True)
    arr = np.stack(rows).astype(np.float32)
    arr.tofile(OUT / "aaf_landmarks.f32")
    (OUT / "aaf_landmarks_meta.csv").write_text("stem,gender,age\n" + "\n".join(meta) + "\n")
    print(f"done: {arr.shape} → out/aaf_landmarks.f32 ({time.time()-t0:.0f}s)")


if __name__ == "__main__":
    main()
