"""AAF 얼굴마다 28 계측 + 좌우 대칭 5개를 한 CSV 로 뽑는다.

extract_aaf.py 와 같은 사진·같은 pose 필터(yaw/pitch ≤ 18°)를 쓰고, 대칭 공식은
shared/lib/domain/services/symmetry_metrics.dart 와 1:1 이어야 한다 (Dart parity
테스트가 이 CSV 의 첫 행을 검사한다 — symmetry_parity_test).

대칭(비대칭도) 정의:
  midline = nasion(168) → chin(152) 선. u = 단위 방향, n = 법선.
  점 P 의 (s, t) = ((P−nasion)·u, (P−nasion)·n) — 등방 좌표(y × aspect).
  좌우 쌍 (L, R): R 을 midline 에 대칭시킨 (s_R, −t_R) 과 L 의 거리 / faceWidth.
  영역 값 = 그 영역 쌍들의 평균. overall = 5 영역 평균. 0 이 완전 대칭.

출력: out/aaf_per_face_sym.csv — gender, <28 FEATURE_NAMES>, symEyes, symBrows,
      symNose, symMouth, symOutline, symOverall

실행: tools/.venv/bin/python tools/face_shape_ml/extract_aaf_symmetry.py [--limit N]
"""

import argparse
import math
import time

import cv2
import numpy as np
import mediapipe as mp
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision as mp_vision

from extract_aaf import IMG_DIR, OUT, YAW_MAX, PITCH_MAX, gender_of, yaw_pitch_from_matrix
from extract_landmarks import compute_ratios, FEATURE_NAMES, MODEL_PATH

# shared/.../symmetry_metrics.dart 와 동일 순서·동일 쌍.
PAIRS = {
    "symEyes": [(33, 263), (133, 362), (159, 386), (145, 374)],
    "symBrows": [(46, 276), (52, 282), (55, 285), (70, 300), (105, 334)],
    "symNose": [(98, 327), (48, 278)],
    "symMouth": [(61, 291), (78, 308), (40, 270), (84, 314)],
    "symOutline": [(234, 454), (132, 361), (172, 397), (150, 379), (148, 377), (54, 284), (116, 345)],
}
SYM_NAMES = list(PAIRS.keys()) + ["symOverall"]


def compute_symmetry(lm: np.ndarray, img_w: int, img_h: int) -> np.ndarray:
    """lm: [468,3] normalized. 반환 [6] = 5 영역 + overall (비대칭도, 0=완전 대칭)."""
    aspect = img_h / img_w
    pts = lm[:, :2].astype(np.float64).copy()
    pts[:, 1] *= aspect
    nasion = pts[168]
    chin = pts[152]
    u = chin - nasion
    norm = np.hypot(u[0], u[1])
    if norm == 0:
        return np.full(len(SYM_NAMES), np.nan)
    u = u / norm
    n = np.array([-u[1], u[0]])
    face_w = np.hypot(*(pts[454] - pts[234]))
    if face_w == 0:
        return np.full(len(SYM_NAMES), np.nan)

    def st(p):
        d = p - nasion
        return d @ u, d @ n

    out = []
    for name, pairs in PAIRS.items():
        acc = 0.0
        for a, b in pairs:
            sa, ta = st(pts[a])
            sb, tb = st(pts[b])
            acc += math.hypot(sa - sb, ta + tb) / face_w
        out.append(acc / len(pairs))
    out.append(float(np.mean(out)))
    return np.array(out, dtype=np.float64)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0)
    args = ap.parse_args()

    files = sorted(IMG_DIR.glob("*.jpg"))
    if args.limit:
        step = max(1, len(files) // args.limit)
        files = files[::step][: args.limit]

    opts = mp_vision.FaceLandmarkerOptions(
        base_options=mp_python.BaseOptions(model_asset_path=MODEL_PATH),
        num_faces=1,
        output_facial_transformation_matrixes=True,
    )
    det = mp_vision.FaceLandmarker.create_from_options(opts)

    rows = []
    n_ok = n_skip = 0
    t0 = time.time()
    for i, f in enumerate(files):
        g = gender_of(f.stem)
        if g is None:
            n_skip += 1
            continue
        img = cv2.imread(str(f))
        if img is None:
            n_skip += 1
            continue
        h, w = img.shape[:2]
        rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
        res = det.detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb))
        if not res.face_landmarks:
            n_skip += 1
            continue
        if res.facial_transformation_matrixes:
            mat = np.array(res.facial_transformation_matrixes[0]).reshape(4, 4)
            yaw, pitch = yaw_pitch_from_matrix(mat)
            if abs(yaw) > YAW_MAX or abs(pitch) > PITCH_MAX:
                n_skip += 1
                continue
        lm = np.array([(p.x, p.y, p.z) for p in res.face_landmarks[0]], dtype=np.float32)
        ratios = compute_ratios(lm, w, h)
        sym = compute_symmetry(lm, w, h)
        if not (np.all(np.isfinite(ratios)) and np.all(np.isfinite(sym))):
            n_skip += 1
            continue
        rows.append((g, ratios, sym))
        n_ok += 1
        if (i + 1) % 500 == 0:
            print(f"  ...{i+1}/{len(files)} ok={n_ok} ({time.time()-t0:.0f}s)", flush=True)

    out_path = OUT / "aaf_per_face_sym.csv"
    with open(out_path, "w") as fh:
        fh.write("gender," + ",".join(FEATURE_NAMES) + "," + ",".join(SYM_NAMES) + "\n")
        for g, ratios, sym in rows:
            fh.write(g + "," + ",".join(f"{v:.6f}" for v in ratios) + "," + ",".join(f"{v:.6f}" for v in sym) + "\n")
    print(f"[done] ok={n_ok} skip={n_skip} → {out_path} ({time.time()-t0:.0f}s)")


if __name__ == "__main__":
    main()
