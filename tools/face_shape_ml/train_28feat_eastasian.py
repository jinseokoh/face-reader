"""Train 28-feature MLP face-shape classifier — 3 strategies compared.

Inputs:
  out/landmarks.npz    — niten19 28-feat (extract_landmarks.py)
  out/user_features.csv — 57 East Asian 28-feat (extract_user_features.py)

Strategies:
  A. niten19 only (baseline, equivalent to current Flutter on-device model)
  B. niten19 + user 57 mixed (full retrain on combined data)
  C. niten19 first → user 57 fine-tune (transfer learning)

Evaluation:
  5-fold stratified CV on the 57 user samples for each strategy.
  Final saved model trained on ALL data (niten19 + user 57).

Output:
  out/mlp_eastasian_<strategy>.keras  — best MLP per strategy
  out/mlp_eastasian_scaler.json       — new StandardScaler stats
  out/mlp_eastasian_final.keras       — final winner
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")

import numpy as np
import pandas as pd
import tensorflow as tf
from tensorflow.keras import layers, models, optimizers, callbacks  # type: ignore
from sklearn.model_selection import StratifiedKFold
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import confusion_matrix

sys.path.insert(0, str(Path(__file__).resolve().parent))
from extract_landmarks import FEATURE_NAMES, CLASSES  # type: ignore

OUT = Path(__file__).resolve().parent / "out"
NITEN_NPZ = OUT / "landmarks.npz"
USER_CSV = OUT / "user_features.csv"
N_CLASSES = len(CLASSES)
SEED = 42


# ──────────────────────────────────────────────────────────────────────────
# Data loading
# ──────────────────────────────────────────────────────────────────────────
def load_niten19():
    data = np.load(NITEN_NPZ)
    X = data["ratios"].astype(np.float32)      # (N, 28)
    y = data["labels"].astype(np.int32)         # (N,)
    is_train = data["is_train"].astype(bool)
    # Use only the training_set portion (4000 imgs) — testing_set quality varies.
    return X[is_train], y[is_train], X[~is_train], y[~is_train]


def load_user():
    df = pd.read_csv(USER_CSV)
    X = df[FEATURE_NAMES].to_numpy(dtype=np.float32)
    y = df["class_idx"].to_numpy(dtype=np.int32)
    return X, y, df


# ──────────────────────────────────────────────────────────────────────────
# Model
# ──────────────────────────────────────────────────────────────────────────
def build_mlp(input_dim: int = 28, l2_reg: float = 1e-4) -> tf.keras.Model:
    """Keras MLP equivalent to the current TFLite 28-feat classifier.
    Architecture chosen for TFLite conversion compatibility."""
    inputs = layers.Input(shape=(input_dim,))
    x = layers.Dense(64, activation="relu",
                     kernel_regularizer=tf.keras.regularizers.l2(l2_reg))(inputs)
    x = layers.Dropout(0.3)(x)
    x = layers.Dense(32, activation="relu",
                     kernel_regularizer=tf.keras.regularizers.l2(l2_reg))(x)
    x = layers.Dropout(0.2)(x)
    outputs = layers.Dense(N_CLASSES, activation="softmax")(x)
    return models.Model(inputs, outputs)


def fit_model(Xtr, ytr, Xv=None, yv=None, epochs=100, lr=1e-3,
              class_weight=None, verbose=0):
    tf.keras.utils.set_random_seed(SEED)
    model = build_mlp(Xtr.shape[1])
    model.compile(
        optimizer=optimizers.Adam(lr),
        loss=tf.keras.losses.SparseCategoricalCrossentropy(),
        metrics=["accuracy"],
    )
    cb = []
    if Xv is not None:
        cb.append(callbacks.EarlyStopping(monitor="val_accuracy",
                                          patience=20, mode="max",
                                          restore_best_weights=True))
    model.fit(Xtr, ytr,
              validation_data=(Xv, yv) if Xv is not None else None,
              epochs=epochs, batch_size=64,
              callbacks=cb, class_weight=class_weight, verbose=verbose)
    return model


# ──────────────────────────────────────────────────────────────────────────
# Strategies — each returns per-fold val accuracy on user 57
# ──────────────────────────────────────────────────────────────────────────
def cv_strategy_a(niten_X, niten_y, user_X, user_y, scaler):
    """A. Train on niten19 only, evaluate on user 5-fold splits (predict only)."""
    print("\n[A] niten19 only — train on 4000, evaluate on user 57 splits")
    Xtr_n = scaler.transform(niten_X)
    Xtr_u = scaler.transform(user_X)
    model = fit_model(Xtr_n, niten_y, epochs=80)
    # Sanity: niten19 holdout check
    print(f"   niten19 train accuracy = {model.evaluate(Xtr_n, niten_y, verbose=0)[1]:.3f}")
    # Evaluate per-fold on user (no fine-tune, single model)
    skf = StratifiedKFold(n_splits=5, shuffle=True, random_state=SEED)
    accs, allp, ally = [], [], []
    for tr, va in skf.split(user_X, user_y):
        # Strategy A: ignore tr (no fine-tune) — same model predicts va
        pred = np.argmax(model.predict(Xtr_u[va], verbose=0), axis=1)
        acc = float(np.mean(pred == user_y[va]))
        accs.append(acc)
        allp.extend(pred)
        ally.extend(user_y[va])
    print(f"   fold accs: {[f'{a:.3f}' for a in accs]}")
    print(f"   user 5-fold mean = {np.mean(accs):.3f}, pooled = {sum(np.array(ally)==np.array(allp))}/57")
    return model, np.mean(accs), allp, ally


def cv_strategy_b(niten_X, niten_y, user_X, user_y, scaler):
    """B. niten19 + user TRAIN mixed (full retrain each fold)."""
    print("\n[B] niten19 + user_train mixed retrain")
    Xtr_n = scaler.transform(niten_X)
    Xtr_u = scaler.transform(user_X)
    skf = StratifiedKFold(n_splits=5, shuffle=True, random_state=SEED)
    accs, allp, ally = [], [], []
    for i, (tr, va) in enumerate(skf.split(user_X, user_y)):
        # Heavy upweight user data so 57 doesn't drown in 4000
        Xcat = np.concatenate([Xtr_n, Xtr_u[tr]])
        ycat = np.concatenate([niten_y, user_y[tr]])
        # sample_weight: 1 for niten, 10x for user (to bias the model)
        weight_map = {ci: 1.0 for ci in range(N_CLASSES)}
        # class_weight to handle user class imbalance
        unique, counts = np.unique(ycat, return_counts=True)
        total = counts.sum()
        cw = {int(c): float(total / (len(unique) * n)) for c, n in zip(unique, counts)}
        model = fit_model(Xcat, ycat, epochs=80, class_weight=cw)
        pred = np.argmax(model.predict(Xtr_u[va], verbose=0), axis=1)
        acc = float(np.mean(pred == user_y[va]))
        accs.append(acc)
        allp.extend(pred)
        ally.extend(user_y[va])
        print(f"   fold {i+1}: tr={len(tr)} va={len(va)} acc={acc:.3f}")
    print(f"   user 5-fold mean = {np.mean(accs):.3f}, pooled = {sum(np.array(ally)==np.array(allp))}/57")
    # Final model on ALL data
    Xfinal = np.concatenate([Xtr_n, Xtr_u])
    yfinal = np.concatenate([niten_y, user_y])
    unique, counts = np.unique(yfinal, return_counts=True)
    cw = {int(c): float(yfinal.size / (len(unique) * n)) for c, n in zip(unique, counts)}
    final = fit_model(Xfinal, yfinal, epochs=100, class_weight=cw)
    return final, np.mean(accs), allp, ally


def cv_strategy_c(niten_X, niten_y, user_X, user_y, scaler):
    """C. Pre-train on niten19, then fine-tune on user fold tr."""
    print("\n[C] niten19 pre-train → user fine-tune (transfer)")
    Xtr_n = scaler.transform(niten_X)
    Xtr_u = scaler.transform(user_X)
    # Pre-train once
    print("   pre-training on niten19 4000...")
    pretrain = fit_model(Xtr_n, niten_y, epochs=80)
    pretrain.save(OUT / "_mlp_pretrain.keras")

    skf = StratifiedKFold(n_splits=5, shuffle=True, random_state=SEED)
    accs, allp, ally = [], [], []
    for i, (tr, va) in enumerate(skf.split(user_X, user_y)):
        model = tf.keras.models.load_model(OUT / "_mlp_pretrain.keras")
        # Fine-tune: low LR, fewer epochs
        model.compile(
            optimizer=optimizers.Adam(1e-4),
            loss=tf.keras.losses.SparseCategoricalCrossentropy(),
            metrics=["accuracy"],
        )
        unique, counts = np.unique(user_y[tr], return_counts=True)
        cw = {int(c): float(len(tr) / (len(unique) * n)) for c, n in zip(unique, counts)}
        model.fit(Xtr_u[tr], user_y[tr], epochs=40, batch_size=16,
                  class_weight=cw, verbose=0)
        pred = np.argmax(model.predict(Xtr_u[va], verbose=0), axis=1)
        acc = float(np.mean(pred == user_y[va]))
        accs.append(acc)
        allp.extend(pred)
        ally.extend(user_y[va])
        print(f"   fold {i+1}: tr={len(tr)} va={len(va)} acc={acc:.3f}")
    print(f"   user 5-fold mean = {np.mean(accs):.3f}, pooled = {sum(np.array(ally)==np.array(allp))}/57")
    # Final: pretrain + fine-tune on ALL user
    final = tf.keras.models.load_model(OUT / "_mlp_pretrain.keras")
    final.compile(optimizer=optimizers.Adam(1e-4),
                  loss=tf.keras.losses.SparseCategoricalCrossentropy(),
                  metrics=["accuracy"])
    unique, counts = np.unique(user_y, return_counts=True)
    cw = {int(c): float(user_y.size / (len(unique) * n)) for c, n in zip(unique, counts)}
    final.fit(Xtr_u, user_y, epochs=60, batch_size=16, class_weight=cw, verbose=0)
    return final, np.mean(accs), allp, ally


# ──────────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────────
def main():
    print(f"[load] niten19 npz: {NITEN_NPZ}")
    Xn_tr, yn_tr, Xn_te, yn_te = load_niten19()
    print(f"   train: {Xn_tr.shape}, test: {Xn_te.shape}")
    print(f"   class dist (train): {dict(zip(CLASSES, np.bincount(yn_tr, minlength=5)))}")

    print(f"\n[load] user csv: {USER_CSV}")
    Xu, yu, df_user = load_user()
    print(f"   user: {Xu.shape}")
    print(f"   class dist: {dict(zip(CLASSES, np.bincount(yu, minlength=5)))}")

    # Fit scaler on niten19 train + ALL user (matches deployment dist)
    Xcombined = np.concatenate([Xn_tr, Xu])
    scaler = StandardScaler().fit(Xcombined)

    results = {}
    a_model, a_acc, a_pred, a_true = cv_strategy_a(Xn_tr, yn_tr, Xu, yu, scaler)
    b_model, b_acc, b_pred, b_true = cv_strategy_b(Xn_tr, yn_tr, Xu, yu, scaler)
    c_model, c_acc, c_pred, c_true = cv_strategy_c(Xn_tr, yn_tr, Xu, yu, scaler)
    results["A"] = (a_acc, a_pred, a_true, a_model)
    results["B"] = (b_acc, b_pred, b_true, b_model)
    results["C"] = (c_acc, c_pred, c_true, c_model)

    # Confusion matrices
    print("\n" + "=" * 60)
    print("STRATEGY COMPARISON — pooled confusion on user 57")
    print("=" * 60)
    for k, (acc, pred, true, _) in results.items():
        print(f"\n--- Strategy {k}: 5-fold mean = {acc:.3f} ({sum(np.array(true)==np.array(pred))}/57) ---")
        cm = confusion_matrix(true, pred, labels=list(range(5)))
        hdr = "true\\pred"
        print(f"{hdr:10s}" + "".join(f"{c[:6]:>7s}" for c in CLASSES))
        for i, c in enumerate(CLASSES):
            print(f"{c:10s}" + "".join(f"{cm[i][j]:>7d}" for j in range(5)))

    best = max(results.items(), key=lambda kv: kv[1][0])
    print(f"\n[BEST] Strategy {best[0]}: {best[1][0]:.3f}")

    # Save winner + scaler
    final_path = OUT / f"mlp_eastasian_final.keras"
    best[1][3].save(final_path)
    scaler_dict = {
        "feature_names": FEATURE_NAMES,
        "mu": scaler.mean_.tolist(),
        "sd": scaler.scale_.tolist(),
    }
    (OUT / "mlp_eastasian_scaler.json").write_text(json.dumps(scaler_dict, indent=2))
    print(f"saved: {final_path}")
    print(f"saved: {OUT / 'mlp_eastasian_scaler.json'}")


if __name__ == "__main__":
    main()
