"""Run the FaceShape classifier pipeline on ONE user photo.

추측 그만하고 사진의 실제 raw softmax + key z-score 를 측정한다. Flutter 의
FaceMetrics.computeAll() + scaler.json + face_shape_ratios.tflite 의 numerical
parity를 보장.

Run:
  /Users/chuck/Code/face/tools/.venv/bin/python \
      /Users/chuck/Code/face/tools/face_shape_ml/probe_photo.py \
      "/Users/chuck/Desktop/스크린샷 2026-05-18 오전 11.33.58.png"
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import cv2
import numpy as np

# Import compute_ratios + FEATURE_NAMES from extract_landmarks (Flutter parity).
sys.path.insert(0, str(Path(__file__).resolve().parent))
from extract_landmarks import (  # type: ignore  # noqa: E402
    FEATURE_NAMES,
    compute_ratios,
)

import mediapipe as mp  # noqa: E402
from mediapipe.tasks import python as mp_python  # noqa: E402
from mediapipe.tasks.python import vision as mp_vision  # noqa: E402
import tensorflow as tf  # noqa: E402

TOOLS = Path(__file__).resolve().parent.parent
LANDMARKER = str(TOOLS / "face_landmarker.task")
SCALER_JSON = TOOLS.parent / "flutter/assets/ml/scaler.json"
TFLITE = TOOLS.parent / "flutter/assets/ml/face_shape_ratios.tflite"

CLASSES = ("Heart", "Oblong", "Oval", "Round", "Square")


def main(img_path: str) -> None:
    img = cv2.imread(img_path)
    if img is None:
        raise SystemExit(f"image read failed: {img_path}")
    h, w = img.shape[:2]
    rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)

    # 1) MediaPipe landmarks ─────────────────────────────────────────────
    opts = mp_vision.FaceLandmarkerOptions(
        base_options=mp_python.BaseOptions(model_asset_path=LANDMARKER),
        running_mode=mp_vision.RunningMode.IMAGE,
        num_faces=1,
    )
    det = mp_vision.FaceLandmarker.create_from_options(opts)
    result = det.detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb))
    if not result.face_landmarks:
        raise SystemExit("no face detected")
    lm = np.array(
        [(p.x, p.y, p.z) for p in result.face_landmarks[0]],
        dtype=np.float32,
    )
    print(f"[mediapipe] landmarks={lm.shape} img={w}x{h}")

    # 2) 28 features (Flutter parity) ────────────────────────────────────
    ratios = compute_ratios(lm, w, h)
    if not np.all(np.isfinite(ratios)):
        raise SystemExit("non-finite ratios")

    # 3) Standardize with scaler.json ────────────────────────────────────
    scaler = json.loads(SCALER_JSON.read_text())
    mu = np.array(scaler["mu"], dtype=np.float32)
    sd = np.array(scaler["sd"], dtype=np.float32)
    z = (ratios - mu) / sd

    # 4) TFLite inference ────────────────────────────────────────────────
    interp = tf.lite.Interpreter(model_path=str(TFLITE))
    interp.allocate_tensors()
    in_det = interp.get_input_details()[0]
    out_det = interp.get_output_details()[0]
    interp.set_tensor(in_det["index"], z.reshape(1, -1).astype(np.float32))
    interp.invoke()
    raw = interp.get_tensor(out_det["index"])[0].astype(np.float64)

    # 5) Pretty-print ────────────────────────────────────────────────────
    print()
    print("=" * 72)
    print(f"PHOTO: {Path(img_path).name}")
    print("=" * 72)

    print("\n── raw 28 features ──")
    for name, raw_val, z_val in zip(FEATURE_NAMES, ratios, z):
        marker = "  ⚠" if abs(z_val) >= 1.5 else "   "
        print(f"  {marker} {name:24s} raw={raw_val:8.4f}  z={z_val:+6.2f}")

    print(f"\n── raw softmax [{', '.join(CLASSES)}] ──")
    for i, c in enumerate(CLASSES):
        print(f"     {c:7s} = {raw[i]:.4f}")
    argmax_raw = int(np.argmax(raw))
    print(f"     argmax = {CLASSES[argmax_raw]} ({raw[argmax_raw]:.4f})")

    # 6) Apply East Asian female prior (current Dart code) ──────────────
    # _priorRatio = [heart 0.4, oblong 0.6, oval 2.5, round 1.0, square 0.5]
    prior_ratio = np.array([0.4, 0.6, 2.5, 1.0, 0.5])
    post = raw * prior_ratio
    post = post / post.sum()
    argmax_post = int(np.argmax(post))
    print(f"\n── posterior (current Dart code: ratio={list(prior_ratio)}) ──")
    for i, c in enumerate(CLASSES):
        print(f"     {c:7s} = {post[i]:.4f}")
    print(f"     argmax = {CLASSES[argmax_post]} ({post[argmax_post]:.4f})")

    # 7) Print code-paste-ready line for unit test ──────────────────────
    print("\n── unit test paste ──")
    raw_str = ", ".join(f"{v:.6f}" for v in raw)
    print(f"  raw = [{raw_str}]")
    print(f"  aspectZ = {z[0]:.4f}  taperZ = {z[1]:.4f}  midFaceZ = {z[4]:.4f}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit("usage: probe_photo.py <image_path>")
    main(sys.argv[1])
