"""Batch face-shape classification report.

Runs the full Flutter-parity pipeline (square-pad → MediaPipe → 28 features →
scaler → TFLite) on a directory of /tmp/{gender}-{type}-{n}.{ext} files and
emits an accuracy report under three regimes:
  (1) raw argmax — no post-process
  (2) female prior — current Dart `_priorRatio`
  (3) male prior — proposed (oval 1.5, oblong 1.1, round 0.75, square 1.0, heart 0.65)

Run:
  /Users/chuck/Code/face/tools/.venv/bin/python \
      /Users/chuck/Code/face/tools/face_shape_ml/batch_report.py
"""
from __future__ import annotations

import glob
import json
import re
import sys
from pathlib import Path

import cv2
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from extract_landmarks import compute_ratios, FEATURE_NAMES  # type: ignore

import mediapipe as mp
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision as mp_vision
import tensorflow as tf

TOOLS = Path(__file__).resolve().parent.parent
LANDMARKER = str(TOOLS / "face_landmarker.task")
SCALER = json.loads((TOOLS.parent / "flutter/assets/ml/scaler.json").read_text())
MU = np.array(SCALER["mu"], dtype=np.float32)
SD = np.array(SCALER["sd"], dtype=np.float32)
TFLITE = str(TOOLS.parent / "flutter/assets/ml/face_shape_ratios.tflite")

CLASSES = ("Heart", "Oblong", "Oval", "Round", "Square")
SHORT = {"Heart": "H", "Oblong": "Ob", "Oval": "Ov", "Round": "Ro", "Square": "Sq"}
LABEL = {"heart": 0, "oblong": 1, "oval": 2, "round": 3, "square": 4}

# Current Dart `_priorRatio` (East Asian female 30s deploy).
PRIOR_FEMALE = np.array([0.4, 0.6, 2.5, 1.0, 0.5])
# Proposed male prior — closer to uniform with slight oval/square bias.
# East Asian male adult anthropometry: oval ≈30%, oblong ≈22%, round ≈15%,
# square ≈20%, heart ≈13% → ratios vs uniform 0.20.
PRIOR_MALE = np.array([0.65, 1.1, 1.5, 0.75, 1.0])


def pad_to_square(img: np.ndarray) -> np.ndarray:
    h, w = img.shape[:2]
    if h == w:
        return img
    if w < h:
        delta = h - w
        left = delta // 2
        right = delta - left
        return cv2.copyMakeBorder(img, 0, 0, left, right, cv2.BORDER_CONSTANT, value=(255, 255, 255))
    delta = w - h
    top = delta // 2
    bot = delta - top
    return cv2.copyMakeBorder(img, top, bot, 0, 0, cv2.BORDER_CONSTANT, value=(255, 255, 255))


def softmax_with_prior(raw: np.ndarray, ratio: np.ndarray) -> np.ndarray:
    adj = raw * ratio
    return adj / adj.sum()


def main() -> None:
    opts = mp_vision.FaceLandmarkerOptions(
        base_options=mp_python.BaseOptions(model_asset_path=LANDMARKER),
        running_mode=mp_vision.RunningMode.IMAGE,
        num_faces=1,
    )
    det = mp_vision.FaceLandmarker.create_from_options(opts)
    interp = tf.lite.Interpreter(model_path=TFLITE)
    interp.allocate_tensors()
    in_idx = interp.get_input_details()[0]["index"]
    out_idx = interp.get_output_details()[0]["index"]

    pat = re.compile(r"^(male|female)-(heart|oblong|oval|round|square)-\d+$")
    files = sorted(
        glob.glob("/tmp/male-*-*.png")
        + glob.glob("/tmp/male-*-*.jpg")
        + glob.glob("/tmp/male-*-*.jpeg")
        + glob.glob("/tmp/female-*-*.png")
        + glob.glob("/tmp/female-*-*.jpg")
        + glob.glob("/tmp/female-*-*.jpeg")
    )

    rows = []
    for f in files:
        stem = Path(f).stem
        m = pat.match(stem)
        if not m:
            continue
        gender = m.group(1)
        expected = m.group(2)
        img = cv2.imread(f)
        if img is None:
            print(f"  ! read fail: {f}")
            continue
        sq = pad_to_square(img)
        h, w = sq.shape[:2]
        rgb = cv2.cvtColor(sq, cv2.COLOR_BGR2RGB)
        result = det.detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb))
        if not result.face_landmarks:
            print(f"  ! no face: {stem}")
            continue
        lm = np.array(
            [(p.x, p.y, p.z) for p in result.face_landmarks[0]],
            dtype=np.float32,
        )
        ratios = compute_ratios(lm, w, h)
        if not np.all(np.isfinite(ratios)):
            print(f"  ! non-finite: {stem}")
            continue
        z = (ratios - MU) / SD
        interp.set_tensor(in_idx, z.reshape(1, -1).astype(np.float32))
        interp.invoke()
        raw = interp.get_tensor(out_idx)[0].astype(np.float64)
        post_f = softmax_with_prior(raw, PRIOR_FEMALE)
        post_m = softmax_with_prior(raw, PRIOR_MALE)
        rows.append({
            "stem": stem,
            "gender": gender,
            "expected": expected,
            "aspectZ": float(z[0]),
            "raw": raw,
            "argmax_raw": CLASSES[int(np.argmax(raw))].lower(),
            "argmax_female": CLASSES[int(np.argmax(post_f))].lower(),
            "argmax_male": CLASSES[int(np.argmax(post_m))].lower(),
        })

    # ── Per-file table ────────────────────────────────────────────────
    print()
    print("=" * 110)
    print("PER-FILE CLASSIFICATION")
    print("=" * 110)
    hdr = f"{'file':22s} {'expected':8s} {'aspZ':>5s}  raw softmax [H,Ob,Ov,Ro,Sq]              raw=>     femP=>   maleP=>"
    print(hdr)
    print("-" * 110)
    for r in rows:
        raw_str = ",".join(f"{v:.2f}" for v in r["raw"])
        def mark(pred):
            return f"{pred:6s}" + ("✓" if pred == r["expected"] else "✗")
        print(f"{r['stem']:22s} {r['expected']:8s} {r['aspectZ']:+5.2f}  [{raw_str}]   "
              f"{mark(r['argmax_raw'])} {mark(r['argmax_female'])} {mark(r['argmax_male'])}")

    # ── Confusion matrix ──────────────────────────────────────────────
    def confusion(key: str) -> None:
        print()
        print(f"── Confusion ({key}) ──")
        labels = ["heart", "oblong", "oval", "round", "square"]
        mat = {e: {p: 0 for p in labels} for e in labels}
        for r in rows:
            mat[r["expected"]][r[key]] += 1
        hdr_label = "exp\\pred"
        print(f"{hdr_label:10s} " + " ".join(f"{p[:5]:>6s}" for p in labels) + "   support")
        for e in labels:
            support = sum(mat[e].values())
            row = " ".join(f"{mat[e][p]:>6d}" for p in labels)
            print(f"{e:10s} {row}   {support}")
        correct = sum(mat[e][e] for e in labels)
        total = sum(sum(v.values()) for v in mat.values())
        print(f"  → accuracy: {correct}/{total} = {correct/max(total,1):.1%}")

    confusion("argmax_raw")
    confusion("argmax_female")
    confusion("argmax_male")


if __name__ == "__main__":
    main()
