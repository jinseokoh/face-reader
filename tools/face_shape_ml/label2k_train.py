"""label2k 재학습 — Opus 라벨 1869장 feature 추출 → 70/30 분리 → 혼합 재학습.

Split:  label2k stratified 70/30 → l2k-train(~1308) / l2k-eval(~561)
Train:  niten19 4000 + pilot 421(3x) + l2k-train(3x) + user57(3x), class weight
Gate:   l2k-eval 에서 [현행 배포 / 파일럿 / 신규] 3-way 비교 (전부 미학습 데이터)
참고:   pilot 421(내 라벨), user 57 에서도 3-way 비교

Output:
  out/label2k/features.csv
  out/label2k/mlp_2k.keras + mlp_2k_scaler.json
  out/label2k/train_report.json

Run:
  tools/.venv/bin/python tools/face_shape_ml/label2k_train.py
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
L2K = OUT / "label2k"
SEED = 42
DUP = 3
CLASS_IDX = {c: i for i, c in enumerate(CLASSES)}


def extract_features() -> pd.DataFrame:
    cache = L2K / "features.csv"
    if cache.exists():
        return pd.read_csv(cache)
    detector = mp_vision.FaceLandmarker.create_from_options(
        mp_vision.FaceLandmarkerOptions(
            base_options=mp_python.BaseOptions(model_asset_path=MODEL_PATH),
            num_faces=1,
        )
    )
    labels = pd.read_csv(L2K / "labels.csv")
    labels = labels[labels.label != "SKIP"]
    rows = []
    for i, (_, r) in enumerate(labels.iterrows()):
        img = cv2.imread(str(L2K / "images" / r.file))
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
        if (i + 1) % 200 == 0:
            print(f"  features {i + 1}/{len(labels)}", flush=True)
    df = pd.DataFrame(rows)
    df.to_csv(cache, index=False)
    return df


def evaluate(name, model, X, y, mu, sd, verbose=True):
    z = ((X - mu) / sd).astype(np.float32)
    pred = np.argmax(model.predict(z, verbose=0), axis=1)
    acc = float(np.mean(pred == y))
    if verbose:
        cm = confusion_matrix(y, pred, labels=list(range(5)))
        print(f"\n[{name}] acc = {acc:.4f} ({int((pred == y).sum())}/{len(y)})")
        hdr = "true\\pred"
        print(f"{hdr:10s}" + "".join(f"{c[:6]:>7s}" for c in CLASSES))
        for i, c in enumerate(CLASSES):
            print(f"{c:10s}" + "".join(f"{cm[i][j]:>7d}" for j in range(5)))
    else:
        print(f"[{name}] acc = {acc:.4f} ({int((pred == y).sum())}/{len(y)})")
    return acc


def main() -> None:
    tf.keras.utils.set_random_seed(SEED)
    df = extract_features()
    print(f"label2k features: {len(df)}")
    print(df.label.value_counts().to_dict())

    X2 = df[FEATURE_NAMES].to_numpy(np.float32)
    y2 = df.class_idx.to_numpy(np.int32)
    tr_idx, ev_idx = train_test_split(
        np.arange(len(df)), test_size=0.3, stratify=y2, random_state=SEED)

    data = np.load(OUT / "landmarks.npz")
    is_train = data["is_train"].astype(bool)
    Xn = data["ratios"].astype(np.float32)[is_train]
    yn = data["labels"].astype(np.int32)[is_train]

    df_p = pd.read_csv(PILOT / "features.csv")
    Xp = df_p[FEATURE_NAMES].to_numpy(np.float32)
    yp = df_p.class_idx.to_numpy(np.int32)

    df_u = pd.read_csv(OUT / "user_features.csv")
    Xu = df_u[FEATURE_NAMES].to_numpy(np.float32)
    yu = df_u["class_idx"].to_numpy(np.int32)

    Xcat = np.concatenate([Xn] + [Xp] * DUP + [X2[tr_idx]] * DUP + [Xu] * DUP)
    ycat = np.concatenate([yn] + [yp] * DUP + [y2[tr_idx]] * DUP + [yu] * DUP)
    print(f"\ntrain total {len(ycat)} (niten {len(yn)}, pilot {len(yp)}x{DUP}, "
          f"l2k-train {len(tr_idx)}x{DUP}, user {len(yu)}x{DUP})")

    scaler = StandardScaler().fit(Xcat)
    mu_n = scaler.mean_.astype(np.float32)
    sd_n = scaler.scale_.astype(np.float32)

    unique, counts = np.unique(ycat, return_counts=True)
    cw = {int(c): float(ycat.size / (len(unique) * n))
          for c, n in zip(unique, counts)}

    model = build_mlp()
    model.compile(optimizer=tf.keras.optimizers.Adam(1e-3),
                  loss="sparse_categorical_crossentropy", metrics=["accuracy"])
    z = ((Xcat - mu_n) / sd_n).astype(np.float32)
    model.fit(z, ycat, epochs=100, batch_size=64, class_weight=cw, verbose=0)
    print(f"train acc: {model.evaluate(z, ycat, verbose=0)[1]:.3f}")

    cur = tf.keras.models.load_model(OUT / "mlp_eastasian_final.keras")
    sc = json.loads((OUT / "mlp_eastasian_scaler.json").read_text())
    mu_c = np.array(sc["mu"], dtype=np.float32)
    sd_c = np.array(sc["sd"], dtype=np.float32)

    pil = tf.keras.models.load_model(PILOT / "mlp_pilot.keras")
    sp = json.loads((PILOT / "mlp_pilot_scaler.json").read_text())
    mu_p = np.array(sp["mu"], dtype=np.float32)
    sd_p = np.array(sp["sd"], dtype=np.float32)

    print("\n════════ GATE: l2k-eval (3모델 전부 미학습 데이터) ════════")
    acc_cur = evaluate("현행 · l2k-eval", cur, X2[ev_idx], y2[ev_idx], mu_c, sd_c)
    acc_pil = evaluate("파일럿 · l2k-eval", pil, X2[ev_idx], y2[ev_idx], mu_p, sd_p)
    acc_new = evaluate("신규2k · l2k-eval", model, X2[ev_idx], y2[ev_idx], mu_n, sd_n)

    print("\n════════ 참고: pilot 421 (내 라벨, 신규는 학습 포함) ════════")
    evaluate("현행 · pilot421", cur, Xp, yp, mu_c, sd_c, verbose=False)
    evaluate("파일럿 · pilot421", pil, Xp, yp, mu_p, sd_p, verbose=False)
    evaluate("신규2k · pilot421", model, Xp, yp, mu_n, sd_n, verbose=False)

    print("\n════════ 참고: user 57 ════════")
    evaluate("현행 · user57", cur, Xu, yu, mu_c, sd_c, verbose=False)
    evaluate("파일럿 · user57", pil, Xu, yu, mu_p, sd_p, verbose=False)
    evaluate("신규2k · user57", model, Xu, yu, mu_n, sd_n, verbose=False)

    gate = acc_new > acc_cur
    print(f"\n{'✓ GATE PASS' if gate else '✗ GATE FAIL'}: "
          f"l2k-eval 신규 {acc_new:.3f} vs 현행 {acc_cur:.3f} "
          f"(파일럿 {acc_pil:.3f})")

    model.save(L2K / "mlp_2k.keras")
    (L2K / "mlp_2k_scaler.json").write_text(json.dumps({
        "feature_names": FEATURE_NAMES,
        "mu": mu_n.tolist(), "sd": sd_n.tolist()}, indent=2))
    (L2K / "train_report.json").write_text(json.dumps({
        "n_l2k": len(df), "n_train": len(tr_idx), "n_eval": len(ev_idx),
        "l2k_eval": {"current": acc_cur, "pilot": acc_pil, "new": acc_new},
        "gate_pass": gate}, indent=2))
    print(f"saved: {L2K / 'mlp_2k.keras'}")


if __name__ == "__main__":
    main()
