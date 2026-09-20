"""MiVOLO 입력 크롭의 여유 비율을 정한다 — 앱이 보낼 384px 얼굴 크롭 규격의 근거.

AAF 원본에서 InsightFace 로 얼굴 박스를 잡고, 박스를 사방 margin 만큼 넓힌 정사각
크롭(384×384)을 MiVOLO v2 에 넣어 실제 나이와의 오차를 margin 별로 비교한다.
샘플은 out/aaf_deepface_age.csv 의 성인(20~59) 행에서 앞 N장.

  PYTHONPATH=<MiVOLO clone> $VENV eval_mivolo_crop_margin.py --n 300 --margins 0 0.1 0.2 0.3 0.4
산출: out/aaf_mivolo_crop_margin.csv (file,true_age,margin,pred_age) + 요약 표.
"""
from __future__ import annotations

import argparse
import csv
import re
import time
from pathlib import Path

import cv2
import numpy as np
import pandas as pd

HERE = Path(__file__).resolve().parent
ORIG = HERE / "datasets/AAF/All-Age-Faces Dataset/original images"
OUT = HERE / "out/aaf_mivolo_crop_margin.csv"
SAMPLE = HERE / "out/aaf_deepface_age.csv"
FNAME_RE = re.compile(r"^(\d{5})A(\d{2})", re.I)


def square_crop(img: np.ndarray, box: np.ndarray, margin: float, size: int = 384) -> np.ndarray:
    """박스를 사방 margin 배 넓힌 뒤 긴 변 기준 정사각으로 맞춰 자른다. 밖은 검정 패딩."""
    x1, y1, x2, y2 = box
    w, h = x2 - x1, y2 - y1
    cx, cy = (x1 + x2) / 2, (y1 + y2) / 2
    side = max(w, h) * (1 + 2 * margin)
    sx1, sy1 = int(round(cx - side / 2)), int(round(cy - side / 2))
    sx2, sy2 = int(round(cx + side / 2)), int(round(cy + side / 2))
    H, W = img.shape[:2]
    pad = max(0, -sx1, -sy1, sx2 - W, sy2 - H)
    if pad:
        img = cv2.copyMakeBorder(img, pad, pad, pad, pad, cv2.BORDER_CONSTANT, value=(0, 0, 0))
        sx1, sy1, sx2, sy2 = sx1 + pad, sy1 + pad, sx2 + pad, sy2 + pad
    crop = img[sy1:sy2, sx1:sx2]
    return cv2.resize(crop, (size, size), interpolation=cv2.INTER_AREA)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=300)
    ap.add_argument("--margins", type=float, nargs="+", default=[0.0, 0.1, 0.2, 0.3, 0.4])
    a = ap.parse_args()

    import torch
    from insightface.app import FaceAnalysis
    from transformers import AutoConfig, AutoImageProcessor, AutoModelForImageClassification

    det = FaceAnalysis(name="buffalo_l", allowed_modules=["detection"], providers=["CPUExecutionProvider"])
    det.prepare(ctx_id=0, det_size=(640, 640))
    name = "iitolstykh/mivolo_v2"
    config = AutoConfig.from_pretrained(name, trust_remote_code=True)
    model = AutoModelForImageClassification.from_pretrained(name, trust_remote_code=True).eval()
    proc = AutoImageProcessor.from_pretrained(name, trust_remote_code=True)
    empty_body = proc(images=[None])["pixel_values"]

    df = pd.read_csv(SAMPLE)
    files = list(df[(df.true_age >= 20) & (df.true_age < 60)].file)[: a.n]
    t0 = time.time()
    rows = []
    for i, f in enumerate(files, 1):
        true_age = int(FNAME_RE.match(Path(f).stem)[2])
        img = cv2.imread(str(ORIG / f))
        faces = det.get(img)
        if not faces:
            continue
        box = max(faces, key=lambda x: (x.bbox[2] - x.bbox[0]) * (x.bbox[3] - x.bbox[1])).bbox
        for m in a.margins:
            crop = square_crop(img, box, m)
            with torch.no_grad():
                out = model(faces_input=proc(images=[crop])["pixel_values"], body_input=empty_body)
            rows.append((f, true_age, m, float(out.age_output[0].item())))
        if i % 25 == 0 or i == len(files):
            el = time.time() - t0
            print(f"[margin] {i}/{len(files)}  eta {(len(files)-i)*el/i/60:.1f}min", flush=True)

    with OUT.open("w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["file", "true_age", "margin", "pred_age"])
        w.writerows(rows)

    r = pd.DataFrame(rows, columns=["file", "true_age", "margin", "pred_age"])
    r["err"] = r.pred_age - r.true_age
    r["abs"] = r.err.abs()
    print("\n성인 20~59, margin 별 (박스 사방 여유 비율)")
    for m, d in r.groupby("margin"):
        print(f"  margin {m:.1f}  n={len(d):4d}  MAE={d['abs'].mean():5.2f}  bias={d.err.mean():+5.2f}  "
              f"±5={((d['abs']<=5).mean()*100):5.1f}%  ±10={((d['abs']<=10).mean()*100):5.1f}%")


if __name__ == "__main__":
    main()
