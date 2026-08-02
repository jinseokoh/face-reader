"""AAF 파일럿 재학습 — 라벨 421장 feature 추출 → train/eval 분리 → 혼합 재학습.

Split:  라벨분 stratified 70/30 → AAF-train(~295) / AAF-eval(~126)
Train:  niten19 4000 + AAF-train (class weight 보정)
Gate:   AAF-eval 에서 신규 vs 현행 배포 모델 비교 (둘 다 leakage 없음)
참고:   user 57 에서도 비교 (현행은 user 57 로 학습된 leakage 우위 있음)

Output:
  out/pilot/features.csv
  out/pilot/mlp_pilot.keras + scaler json
  out/pilot/train_report.json

Run:
  tools/.venv/bin/python tools/face_shape_ml/pilot_train.py
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
from sklearn.metrics import confusion_matrix
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler

sys.path.insert(0, str(Path(__file__).resolve().parent))
from extract_landmarks import (  # noqa: E402
    CLASSES, FEATURE_NAMES, MODEL_PATH, compute_ratios)
from train_28feat_eastasian import build_mlp  # noqa: E402

OUT = Path(__file__).resolve().parent / "out"
PILOT = OUT / "pilot"
SEED = 42
CLASS_IDX = {c: i for i, c in enumerate(CLASSES)}


def extract_features() -> pd.DataFrame:
    cache = PILOT / "features.csv"
    if cache.exists():
        return pd.read_csv(cache)
    detector = mp_vision.FaceLandmarker.create_from_options(
        mp_vision.FaceLandmarkerOptions(
            base_options=mp_python.BaseOptions(model_asset_path=MODEL_PATH),
            num_faces=1,
        )
    )
    labels = pd.read_csv(PILOT / "labels.csv")
    labels = labels[labels.label != "SKIP"]
    rows = []
    for _, r in labels.iterrows():
        img = cv2.imread(str(PILOT / "images" / r.file))
        if img is None:
            continue
        rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
        res = detector.detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb))
        if not res.face_landmarks:
            continue
        lm = np.array([(p.x, p.y, p.z) for p in res.face_landmarks[0]],
                      dtype=np.float32)
        ratios = compute_ratios(lm, rgb.shape[1], rgb.shape[0])
        if not np.all(np.isfinite(ratios)):
            continue
        rows.append({"file": r.file, "label": r.label,
                     "class_idx": CLASS_IDX[r.label], "confidence": r.confidence,
                     **dict(zip(FEATURE_NAMES, ratios.tolist()))})
    df = pd.DataFrame(rows)
    df.to_csv(cache, index=False)
    return df


def evaluate(name, model, X, y, mu, sd):
    z = ((X - mu) / sd).astype(np.float32)
    pred = np.argmax(model.predict(z, verbose=0), axis=1)
    acc = float(np.mean(pred == y))
    cm = confusion_matrix(y, pred, labels=list(range(5)))
    print(f"\n[{name}] acc = {acc:.4f} ({int((pred == y).sum())}/{len(y)})")
    hdr = "true\\pred"
    print(f"{hdr:10s}" + "".join(f"{c[:6]:>7s}" for c in CLASSES))
    for i, c in enumerate(CLASSES):
        print(f"{c:10s}" + "".join(f"{cm[i][j]:>7d}" for j in range(5)))
    return acc


def main() -> None:
    tf.keras.utils.set_random_seed(SEED)
    df = extract_features()
    print(f"pilot features: {len(df)}")
    print(df.label.value_counts().to_dict())

    Xp = df[FEATURE_NAMES].to_numpy(np.float32)
    yp = df.class_idx.to_numpy(np.int32)
    tr_idx, ev_idx = train_test_split(
        np.arange(len(df)), test_size=0.3, stratify=yp, random_state=SEED)

    data = np.load(OUT / "landmarks.npz")
    is_train = data["is_train"].astype(bool)
    Xn = data["ratios"].astype(np.float32)[is_train]
    yn = data["labels"].astype(np.int32)[is_train]

    df_u = pd.read_csv(OUT / "user_features.csv")
    Xu = df_u[FEATURE_NAMES].to_numpy(np.float32)
    yu = df_u["class_idx"].to_numpy(np.int32)

    # ── 신규 학습: niten19 + AAF-train, AAF 3x 가중(4000 vs ~295 희석 방지) ──
    AAF_DUP = 3
    Xcat = np.concatenate([Xn] + [Xp[tr_idx]] * AAF_DUP)
    ycat = np.concatenate([yn] + [yp[tr_idx]] * AAF_DUP)
    scaler = StandardScaler().fit(Xcat)
    mu_n, sd_n = scaler.mean_.astype(np.float32), scaler.scale_.astype(np.float32)

    unique, counts = np.unique(ycat, return_counts=True)
    cw = {int(c): float(ycat.size / (len(unique) * n))
          for c, n in zip(unique, counts)}

    model = build_mlp()
    model.compile(optimizer=tf.keras.optimizers.Adam(1e-3),
                  loss="sparse_categorical_crossentropy", metrics=["accuracy"])
    z = ((Xcat - mu_n) / sd_n).astype(np.float32)
    model.fit(z, ycat, epochs=100, batch_size=64, class_weight=cw, verbose=0)

    # ── 현행 배포 모델 로드 ──
    cur = tf.keras.models.load_model(OUT / "mlp_eastasian_final.keras")
    sc = json.loads((OUT / "mlp_eastasian_scaler.json").read_text())
    mu_c = np.array(sc["mu"], dtype=np.float32)
    sd_c = np.array(sc["sd"], dtype=np.float32)

    print("\n════════ GATE: AAF-eval (양쪽 다 미학습 데이터) ════════")
    acc_cur_aaf = evaluate("현행 · AAF-eval", cur, Xp[ev_idx], yp[ev_idx], mu_c, sd_c)
    acc_new_aaf = evaluate("신규 · AAF-eval", model, Xp[ev_idx], yp[ev_idx], mu_n, sd_n)

    print("\n════════ 참고: user 57 (현행은 학습 포함 leakage 우위) ════════")
    acc_cur_u = evaluate("현행 · user57", cur, Xu, yu, mu_c, sd_c)
    acc_new_u = evaluate("신규 · user57", model, Xu, yu, mu_n, sd_n)

    gate = acc_new_aaf > acc_cur_aaf
    print(f"\n{'✓ GATE PASS' if gate else '✗ GATE FAIL'}: "
          f"AAF-eval 신규 {acc_new_aaf:.3f} vs 현행 {acc_cur_aaf:.3f}")

    model.save(PILOT / "mlp_pilot.keras")
    (PILOT / "mlp_pilot_scaler.json").write_text(json.dumps({
        "feature_names": FEATURE_NAMES,
        "mu": mu_n.tolist(), "sd": sd_n.tolist()}, indent=2))
    (PILOT / "train_report.json").write_text(json.dumps({
        "n_pilot": len(df), "n_train": len(tr_idx), "n_eval": len(ev_idx),
        "aaf_eval": {"current": acc_cur_aaf, "new": acc_new_aaf},
        "user57": {"current": acc_cur_u, "new": acc_new_u},
        "gate_pass": gate}, indent=2))
    print(f"saved: {PILOT / 'mlp_pilot.keras'}")


if __name__ == "__main__":
    main()
