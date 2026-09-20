"""DeepFace 나이 추정을 AAF 실제 나이와 대조한다 — "AI 가 본 나이" 기능의 근거 측정.

python/app/services/inference.py 와 같은 설정(deepface 0.0.93, detector opencv,
enforce_detection=True)으로 AAF "original images" 를 돌린다. 실제 나이는 파일명
%05dA%02d.jpg 의 A 뒤 두 자리, 성별은 person_id ≤ 7380 → female (extract_aaf.py 와 동일).

산출 out/aaf_deepface_age.csv: file,gender,true_age,pred_age,pred_gender,detected
요약(MAE·편향·±5세 적중률, 성별·연령대별)은 --summary 로 CSV 에서 다시 계산한다.

  $VENV eval_deepface_age.py --per-stratum 120     # 연령대×성별 층화 샘플 (~2,000장)
  $VENV eval_deepface_age.py --all                 # 13,322장 전부
  $VENV eval_deepface_age.py --summary             # 요약만
"""
from __future__ import annotations

import argparse
import csv
import os
import random
import re
import sys
import time
from pathlib import Path

os.environ.setdefault("TF_USE_LEGACY_KERAS", "1")
os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "3")

HERE = Path(__file__).resolve().parent
IMG_DIR = HERE / "datasets/AAF/All-Age-Faces Dataset/original images"
OUT = HERE / "out/aaf_deepface_age.csv"
FNAME_RE = re.compile(r"^(\d{5})A(\d{2})", re.I)
DETECTOR = "opencv"  # python/app/utils/config.py detector_backend 기본값


def parse(stem: str) -> tuple[str, int] | None:
    m = FNAME_RE.match(stem)
    if not m:
        return None
    pid, age = int(m[1]), int(m[2])
    return ("female" if pid <= 7380 else "male"), age


def pick(per_stratum: int | None, seed: int) -> list[Path]:
    files = sorted(IMG_DIR.glob("*.jpg"))
    if per_stratum is None:
        return files
    strata: dict[tuple[str, int], list[Path]] = {}
    for f in files:
        p = parse(f.stem)
        if p is None:
            continue
        strata.setdefault((p[0], p[1] // 10 * 10), []).append(f)
    rng = random.Random(seed)
    out: list[Path] = []
    for key in sorted(strata):
        group = strata[key]
        rng.shuffle(group)
        out.extend(group[:per_stratum])
    return sorted(out)


def run(files: list[Path]) -> None:
    from deepface import DeepFace  # 느린 import — 실행 시에만

    done: set[str] = set()
    if OUT.exists():
        with OUT.open() as fh:
            done = {r["file"] for r in csv.DictReader(fh)}
    todo = [f for f in files if f.name not in done]
    print(f"[eval] {len(files)} selected, {len(done)} already done, {len(todo)} to run", flush=True)
    new = not OUT.exists()
    t0 = time.time()
    with OUT.open("a", newline="") as fh:
        w = csv.writer(fh)
        if new:
            w.writerow(["file", "gender", "true_age", "pred_age", "pred_gender", "detected"])
        for i, f in enumerate(todo, 1):
            gender, true_age = parse(f.stem)  # type: ignore[misc]
            pred_age, pred_gender, detected = "", "", 0
            try:
                res = DeepFace.analyze(
                    img_path=str(f),
                    actions=["age", "gender"],
                    detector_backend=DETECTOR,
                    enforce_detection=True,
                    silent=True,
                )
                first = res[0] if isinstance(res, list) else res
                pred_age = int(round(float(first["age"])))
                g = first.get("dominant_gender") or first.get("gender")
                if isinstance(g, dict):
                    g = max(g, key=g.get)
                pred_gender = {"Man": "male", "Woman": "female"}.get(str(g), str(g))
                detected = 1
            except ValueError:
                pass  # 얼굴 미검출 — 앱에서도 분석 실패로 빠지는 경우
            w.writerow([f.name, gender, true_age, pred_age, pred_gender, detected])
            if i % 50 == 0 or i == len(todo):
                fh.flush()
                el = time.time() - t0
                print(f"[eval] {i}/{len(todo)}  {el/i:.2f}s/img  eta {(len(todo)-i)*el/i/60:.1f}min", flush=True)


def summary() -> None:
    import pandas as pd

    df = pd.read_csv(OUT)
    n = len(df)
    det = df[df.detected == 1].copy()
    print(f"rows {n}  detected {len(det)} ({len(det)/n*100:.1f}%)")
    det["err"] = det.pred_age - det.true_age
    det["abs"] = det.err.abs()
    det["decade"] = det.true_age // 10 * 10

    def block(d: pd.DataFrame) -> str:
        return (
            f"n={len(d):5d}  MAE={d['abs'].mean():5.2f}  bias={d.err.mean():+6.2f}  "
            f"±5={((d['abs']<=5).mean()*100):5.1f}%  ±10={((d['abs']<=10).mean()*100):5.1f}%  "
            f"decade-hit={((det_decade(d)).mean()*100):5.1f}%"
        )

    def det_decade(d: pd.DataFrame) -> pd.Series:
        return (d.pred_age // 10) == (d.true_age // 10)

    print("\n전체         ", block(det))
    for g, d in det.groupby("gender"):
        print(f"{g:12s} ", block(d))
    print("\n연령대별 (실제 나이 기준)")
    for dec, d in det.groupby("decade"):
        print(f"  {dec:2d}대  ", block(d))
    print("\n성별 정확도:", f"{(det.pred_gender == det.gender).mean()*100:.1f}%")
    print("\n예측 나이 분포 (실제 → 예측 중앙값)")
    for dec, d in det.groupby("decade"):
        print(f"  {dec:2d}대 → 예측 중앙값 {d.pred_age.median():4.0f}  (p10 {d.pred_age.quantile(.1):3.0f} · p90 {d.pred_age.quantile(.9):3.0f})")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--per-stratum", type=int, default=None, help="연령대×성별 층마다 N장")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--limit", type=int, default=None, help="스모크 — 앞 N장만")
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--summary", action="store_true")
    a = ap.parse_args()
    if a.summary:
        summary()
        return
    if not IMG_DIR.exists():
        sys.exit(f"AAF not found: {IMG_DIR}")
    files = pick(None if a.all else (a.per_stratum or 120), a.seed)
    if a.limit:
        files = files[: a.limit]
    run(files)
    summary()


if __name__ == "__main__":
    main()
