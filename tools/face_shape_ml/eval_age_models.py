"""나이 추정 모델 후보를 AAF 실제 나이로 잰다 — eval_deepface_age.py 와 같은 샘플·같은 지표.

샘플은 out/aaf_deepface_age.csv 의 file 열(층화 1,972장)을 그대로 쓴다. 모델마다
out/aaf_age_{model}.csv (file,gender,true_age,pred_age,pred_gender,detected) 를 남기고
--compare 가 모든 CSV 를 한 표로 놓는다.

  $VENV eval_age_models.py --model insightface   # buffalo_l genderage (원본 이미지에서 자체 검출)
  $VENV eval_age_models.py --model fairface      # nateraw/vit-age-classifier, 연령 구간 → 구간 중앙값
  $VENV eval_age_models.py --model mivolo        # iitolstykh/mivolo_v2, 얼굴 크롭 384
  $VENV eval_age_models.py --compare

fairface·mivolo 는 AAF "aglined faces"(정렬 크롭)를 입력한다. insightface 는 원본을
넣고 가장 큰 얼굴을 쓴다 (앱 파이프라인과 같은 조건 — 사진 한 장, 검출부터).
"""
from __future__ import annotations

import argparse
import csv
import re
import time
from pathlib import Path

import numpy as np
import pandas as pd
from PIL import Image

HERE = Path(__file__).resolve().parent
AAF = HERE / "datasets/AAF/All-Age-Faces Dataset"
ORIG = AAF / "original images"
ALIGNED = AAF / "aglined faces"
OUT = HERE / "out"
SAMPLE = OUT / "aaf_deepface_age.csv"
FNAME_RE = re.compile(r"^(\d{5})A(\d{2})", re.I)


def parse(stem: str) -> tuple[str, int]:
    m = FNAME_RE.match(stem)
    assert m, stem
    return ("female" if int(m[1]) <= 7380 else "male"), int(m[2])


def sample_files() -> list[str]:
    return list(pd.read_csv(SAMPLE).file)


# ── 모델별 predict(file) -> (pred_age, pred_gender) | None ──────────────────


def make_insightface():
    from insightface.app import FaceAnalysis

    app = FaceAnalysis(name="buffalo_l", allowed_modules=["detection", "genderage"],
                       providers=["CPUExecutionProvider"])
    app.prepare(ctx_id=0, det_size=(640, 640))

    def predict(f: str):
        import cv2

        img = cv2.imread(str(ORIG / f))
        faces = app.get(img)
        if not faces:
            return None
        face = max(faces, key=lambda x: (x.bbox[2] - x.bbox[0]) * (x.bbox[3] - x.bbox[1]))
        return int(round(float(face.age))), ("male" if int(face.gender) == 1 else "female")

    return predict


# FairFace 9구간 → 대표 나이 (구간 중앙, 70+ 는 75).
_FAIRFACE_MID = {
    "0-2": 1, "3-9": 6, "10-19": 15, "20-29": 25, "30-39": 35,
    "40-49": 45, "50-59": 55, "60-69": 65, "more than 70": 75, "70+": 75,
}


def make_fairface():
    import torch
    from transformers import ViTForImageClassification, ViTImageProcessor

    name = "nateraw/vit-age-classifier"
    proc = ViTImageProcessor.from_pretrained(name)
    model = ViTForImageClassification.from_pretrained(name).eval()
    labels = model.config.id2label

    def predict(f: str):
        img = Image.open(ALIGNED / f).convert("RGB")
        with torch.no_grad():
            logits = model(**proc(img, return_tensors="pt")).logits
        lab = labels[int(logits.argmax(-1))]
        mid = _FAIRFACE_MID.get(lab)
        if mid is None:
            return None
        return mid, ""  # 성별 없음

    return predict


def make_mivolo():
    import torch
    from transformers import AutoConfig, AutoImageProcessor, AutoModelForImageClassification

    name = "iitolstykh/mivolo_v2"
    config = AutoConfig.from_pretrained(name, trust_remote_code=True)
    model = AutoModelForImageClassification.from_pretrained(
        name, trust_remote_code=True, torch_dtype=torch.float32).eval()
    proc = AutoImageProcessor.from_pretrained(name, trust_remote_code=True)
    id2label = config.gender_id2label

    def predict(f: str):
        import cv2

        # README 대로 cv2(BGR) 배열. 몸 크롭 없음은 [None] — processor 가 빈 텐서로 만든다.
        img = cv2.imread(str(ALIGNED / f))
        faces = proc(images=[img])["pixel_values"]
        body = proc(images=[None])["pixel_values"]
        with torch.no_grad():
            out = model(faces_input=faces, body_input=body)
        age = float(out.age_output[0].item())
        g = str(id2label[int(out.gender_class_idx[0].item())]).lower()
        return int(round(age)), g

    return predict


MODELS = {"insightface": make_insightface, "fairface": make_fairface, "mivolo": make_mivolo}


def run(model: str, limit: int | None) -> Path:
    out = OUT / f"aaf_age_{model}.csv"
    predict = MODELS[model]()
    files = sample_files()
    if limit:
        files = files[:limit]
    done: set[str] = set()
    if out.exists():
        done = {r["file"] for r in csv.DictReader(out.open())}
    todo = [f for f in files if f not in done]
    print(f"[{model}] {len(files)} selected, {len(done)} done, {len(todo)} to run", flush=True)
    new = not out.exists()
    t0 = time.time()
    with out.open("a", newline="") as fh:
        w = csv.writer(fh)
        if new:
            w.writerow(["file", "gender", "true_age", "pred_age", "pred_gender", "detected"])
        for i, f in enumerate(todo, 1):
            gender, true_age = parse(Path(f).stem)
            try:
                r = predict(f)
            except Exception as e:  # 모델 내부 실패도 미검출로 기록
                print(f"[{model}] {f}: {e}", flush=True)
                r = None
            if r is None:
                w.writerow([f, gender, true_age, "", "", 0])
            else:
                w.writerow([f, gender, true_age, r[0], r[1], 1])
            if i % 100 == 0 or i == len(todo):
                fh.flush()
                el = time.time() - t0
                print(f"[{model}] {i}/{len(todo)}  {el/i:.2f}s/img  eta {(len(todo)-i)*el/i/60:.1f}min", flush=True)
    return out


def stats(path: Path) -> dict:
    df = pd.read_csv(path)
    det = df[df.detected == 1].copy()
    det["err"] = det.pred_age - det.true_age
    ad = det[(det.true_age >= 20) & (det.true_age < 60)]
    a = ad.err.abs()
    row = {
        "model": path.stem.replace("aaf_age_", "").replace("aaf_deepface_age", "deepface"),
        "detected%": len(det) / len(df) * 100,
        "adult n": len(ad),
        "MAE": a.mean(),
        "bias": ad.err.mean(),
        "±5%": (a <= 5).mean() * 100,
        "±10%": (a <= 10).mean() * 100,
        "decade%": ((ad.pred_age // 10) == (ad.true_age // 10)).mean() * 100,
        "gender%": (ad.pred_gender == ad.gender).mean() * 100 if ad.pred_gender.notna().any() else float("nan"),
    }
    for dec in range(20, 60, 10):
        d = det[(det.true_age >= dec) & (det.true_age < dec + 10)]
        row[f"{dec}대 bias"] = d.err.mean()
    for dec in (60, 70):
        d = det[(det.true_age >= dec) & (det.true_age < dec + 10)]
        row[f"{dec}대 bias"] = d.err.mean()
    return row


def compare() -> None:
    paths = [SAMPLE] + sorted(OUT.glob("aaf_age_*.csv"))
    rows = [stats(p) for p in paths if p.exists()]
    df = pd.DataFrame(rows).set_index("model")
    pd.set_option("display.width", 200)
    print("성인 20~59 기준 (bias 열은 실제 연령대별 평균 오차, 음수 = 젊게 봄)")
    print(df.round(1).to_string())


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", choices=sorted(MODELS))
    ap.add_argument("--limit", type=int)
    ap.add_argument("--compare", action="store_true")
    a = ap.parse_args()
    if a.model:
        p = run(a.model, a.limit)
        row = stats(p)
        print(row.pop("model"))
        print(pd.Series(row, dtype=float).round(2).to_string())
    if a.compare or not a.model:
        compare()


if __name__ == "__main__":
    main()
