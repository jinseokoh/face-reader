"""AAF 남/여 정면 사진 1장씩의 468 랜드마크를 앱 저장 형식(등방 좌표, 소수 4자리)으로 뽑는다.
출력: out/demo_landmarks.json {"male": [[x,y]×468], "female": [...]}
용도: 웹 데모 카드(supabase.ts demoRow) · Dart/TS 테스트 픽스처. 실행:
  tools/.venv/bin/python tools/face_shape_ml/dump_demo_landmarks.py
"""
import json
import cv2
import mediapipe as mp
import numpy as np
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision as mp_vision

from extract_aaf import IMG_DIR, OUT, YAW_MAX, PITCH_MAX, FNAME_RE, gender_of, yaw_pitch_from_matrix
from extract_landmarks import MODEL_PATH


def main():
    opts = mp_vision.FaceLandmarkerOptions(
        base_options=mp_python.BaseOptions(model_asset_path=MODEL_PATH),
        num_faces=1,
        output_facial_transformation_matrixes=True,
    )
    det = mp_vision.FaceLandmarker.create_from_options(opts)
    out = {}
    for f in sorted(IMG_DIR.glob("*.jpg")):
        g = gender_of(f.stem)
        if g is None or g in out:
            continue
        age = int(FNAME_RE.match(f.stem).group(2))
        if not 25 <= age <= 35:  # 성인 얼굴만 — 데모 카드·픽스처
            continue
        img = cv2.imread(str(f))
        if img is None:
            continue
        h, w = img.shape[:2]
        res = det.detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=cv2.cvtColor(img, cv2.COLOR_BGR2RGB)))
        if not res.face_landmarks or not res.facial_transformation_matrixes:
            continue
        yaw, pitch = yaw_pitch_from_matrix(np.array(res.facial_transformation_matrixes[0]).reshape(4, 4))
        if abs(yaw) > YAW_MAX / 3 or abs(pitch) > PITCH_MAX / 3:  # 아주 정면만
            continue
        aspect = h / w
        out[g] = [[round(p.x, 4), round(p.y * aspect, 4)] for p in res.face_landmarks[0][:468]]  # tasks API 는 478(홍채 10 포함) — 앱은 468
        print(f"{g}: {f.name} age={age} {w}x{h} yaw={yaw:.1f} pitch={pitch:.1f}")
        if len(out) == 2:
            break
    (OUT / "demo_landmarks.json").write_text(json.dumps(out))


if __name__ == "__main__":
    main()
