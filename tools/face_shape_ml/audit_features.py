"""Rigorous audit: which of the 18 Flutter metrics actually help face-shape
classification? Uses the 5000-sample niten19 Kaggle dataset as ground truth.

Four independent tests per feature:
  1. ANOVA F-score            — linear between-class discriminability
  2. Mutual Information       — non-linear dependence on label
  3. Permutation Importance   — drop in test accuracy when feature is shuffled
  4. Leave-one-out re-train   — accuracy drop when feature is excluded entirely
Plus:
  5. Pairwise correlation matrix → flags redundant features
  6. Final ranking with keep/drop recommendation

Output: out/feature_audit.md (human-readable) + out/feature_audit.json.

Run:
  .venv/bin/python face_shape_ml/audit_features.py
"""
from __future__ import annotations

import json
import os
from pathlib import Path

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")

import numpy as np
import pandas as pd
from scipy import stats
from sklearn.feature_selection import mutual_info_classif
from sklearn.inspection import permutation_importance
from sklearn.neural_network import MLPClassifier
from sklearn.preprocessing import StandardScaler

OUT = Path(__file__).resolve().parent / "out"

FEATURE_NAMES = [
    "faceAspectRatio", "faceTaperRatio", "lowerFaceFullness",
    "upperFaceRatio", "midFaceRatio", "lowerFaceRatio", "gonialAngle",
    "intercanthalRatio", "eyeFissureRatio", "eyeCanthalTilt",
    "eyebrowThickness", "browEyeDistance",
    "nasalWidthRatio", "nasalHeightRatio",
    "mouthWidthRatio", "mouthCornerAngle", "lipFullnessRatio", "philtrumLength",
    # Phase 1 additions (2026-04-17)
    "eyebrowLength", "eyebrowTiltDirection", "eyebrowCurvature", "browSpacing",
    "eyeAspect", "upperVsLowerLipRatio", "chinAngle",
    "foreheadWidth", "cheekboneWidth", "noseBridgeRatio",
]
CLASSES = ("Heart", "Oblong", "Oval", "Round", "Square")


def load():
    npz = np.load(OUT / "landmarks.npz")
    return npz["ratios"].astype(np.float32), npz["labels"], npz["is_train"]


def train_mlp(X_tr, y_tr, X_te, y_te) -> float:
    clf = MLPClassifier(
        hidden_layer_sizes=(64, 32),
        activation="relu", solver="adam",
        max_iter=200, random_state=42, early_stopping=True,
        validation_fraction=0.1, n_iter_no_change=15, verbose=False,
    )
    clf.fit(X_tr, y_tr)
    return float(clf.score(X_te, y_te)), clf


def main():
    X, y, is_train = load()
    X_tr, y_tr = X[is_train], y[is_train]
    X_te, y_te = X[~is_train], y[~is_train]

    sc = StandardScaler().fit(X_tr)
    X_tr_s = sc.transform(X_tr)
    X_te_s = sc.transform(X_te)

    # ── (1) ANOVA F per feature ──
    anova = []
    for i, n in enumerate(FEATURE_NAMES):
        groups = [X_tr[y_tr == k, i] for k in range(len(CLASSES))]
        F, p = stats.f_oneway(*groups)
        anova.append((n, float(F), float(p)))

    # ── (2) Mutual information per feature ──
    mi = mutual_info_classif(X_tr_s, y_tr, random_state=42)

    # ── (3) Permutation importance on the full 18d model ──
    base_acc, base_clf = train_mlp(X_tr_s, y_tr, X_te_s, y_te)
    perm = permutation_importance(
        base_clf, X_te_s, y_te, n_repeats=10, random_state=42, n_jobs=-1,
    )
    perm_means = perm.importances_mean  # [18] — avg accuracy drop when shuffled
    perm_stds = perm.importances_std

    # ── (4) Leave-one-feature-out re-train ──
    loo_acc = []
    for i in range(len(FEATURE_NAMES)):
        cols = [j for j in range(len(FEATURE_NAMES)) if j != i]
        acc, _ = train_mlp(X_tr_s[:, cols], y_tr, X_te_s[:, cols], y_te)
        loo_acc.append(acc)
        print(f"  LOO[{FEATURE_NAMES[i]:22s}]  acc_without={acc:.4f}  "
              f"Δ={base_acc-acc:+.4f}", flush=True)

    # ── (5) Pairwise correlation (Pearson) ──
    df_x = pd.DataFrame(X_tr, columns=FEATURE_NAMES)
    corr = df_x.corr(method="pearson").abs()
    redundant_pairs = []
    for i in range(len(FEATURE_NAMES)):
        for j in range(i + 1, len(FEATURE_NAMES)):
            r = corr.iloc[i, j]
            if r >= 0.8:
                redundant_pairs.append((FEATURE_NAMES[i], FEATURE_NAMES[j], float(r)))

    # ── Aggregate + rank ──
    rows = []
    for i, name in enumerate(FEATURE_NAMES):
        anova_f = anova[i][1]
        anova_p = anova[i][2]
        rows.append({
            "name": name,
            "anova_F": anova_f,
            "anova_p": anova_p,
            "mutual_info": float(mi[i]),
            "perm_drop": float(perm_means[i]),
            "perm_std": float(perm_stds[i]),
            "loo_acc_without": loo_acc[i],
            "loo_delta": float(base_acc - loo_acc[i]),
        })
    # normalize ranks
    df = pd.DataFrame(rows)
    for col in ("anova_F", "mutual_info", "perm_drop", "loo_delta"):
        df[f"rank_{col}"] = df[col].rank(ascending=False).astype(int)
    df["mean_rank"] = df[[c for c in df.columns if c.startswith("rank_")]].mean(axis=1)
    df = df.sort_values("mean_rank").reset_index(drop=True)

    # Classification recommendation
    def recommend(row):
        # Strong: high anova F, meaningful perm drop, and dropping hurts
        if row["anova_F"] > 10 and row["perm_drop"] > 0.005:
            return "KEEP (strong signal)"
        if row["anova_F"] > 5 and row["perm_drop"] > 0.002:
            return "KEEP (moderate signal)"
        if row["anova_F"] < 2 and row["perm_drop"] < 0.001:
            return "DROP (no signal for face shape)"
        return "WEAK (marginal, check redundancy)"

    df["verdict"] = df.apply(recommend, axis=1)

    # ── Write markdown report ──
    md = []
    md.append("# Feature Audit — Face Shape Classification\n")
    md.append(f"Dataset: niten19 Kaggle, N={len(X)}, train={len(X_tr)}, test={len(X_te)}\n")
    md.append(f"Baseline (all 18 features) test accuracy: **{base_acc:.4f}**\n\n")

    md.append("## Ranking (lower mean_rank = more important)\n")
    md.append("| Rank | Feature | ANOVA F | p-value | MI | Perm Δacc | LOO Δacc | Verdict |")
    md.append("|-----:|---------|--------:|--------:|---:|---------:|--------:|:--------|")
    for i, r in df.iterrows():
        p_str = f"{r['anova_p']:.2e}" if r['anova_p'] < 0.001 else f"{r['anova_p']:.3f}"
        md.append(f"| {i+1} | `{r['name']}` | {r['anova_F']:6.1f} | {p_str} | "
                  f"{r['mutual_info']:.3f} | {r['perm_drop']:+.4f} | "
                  f"{r['loo_delta']:+.4f} | {r['verdict']} |")

    md.append("\n## Strongly redundant pairs (|r| ≥ 0.80)\n")
    if redundant_pairs:
        md.append("| Feature A | Feature B | |correlation| |")
        md.append("|-----------|-----------|--------------:|")
        for a, b, r_val in sorted(redundant_pairs, key=lambda x: -x[2]):
            md.append(f"| `{a}` | `{b}` | {r_val:.3f} |")
        md.append("\n> Redundant pairs carry nearly identical information. Keep one, drop the other (or replace with a combined feature).")
    else:
        md.append("_(none above 0.80)_")

    # Classification-specific recommendation
    keep_strong = df[df["verdict"].str.startswith("KEEP (strong")]["name"].tolist()
    keep_mod = df[df["verdict"].str.startswith("KEEP (moderate")]["name"].tolist()
    drop = df[df["verdict"].str.startswith("DROP")]["name"].tolist()
    weak = df[df["verdict"].str.startswith("WEAK")]["name"].tolist()

    md.append("\n## Summary & Recommendation — for face-shape classifier\n")
    md.append(f"- **KEEP strong** ({len(keep_strong)}): " + ", ".join(f"`{n}`" for n in keep_strong))
    md.append(f"- **KEEP moderate** ({len(keep_mod)}): " + ", ".join(f"`{n}`" for n in keep_mod))
    md.append(f"- **WEAK** ({len(weak)}): " + ", ".join(f"`{n}`" for n in weak))
    md.append(f"- **DROP** ({len(drop)}): " + ", ".join(f"`{n}`" for n in drop))

    md.append("\n### IMPORTANT — scope caveat")
    md.append("This audit answers only: _is this metric useful for the 5-class face-shape label?_")
    md.append("Metrics flagged DROP here may still matter for:")
    md.append("- Other attribute scoring (`attribute_engine.dart` — 10 attribute rules)")
    md.append("- Ethnic/demographic analysis")
    md.append("- Nose/eye/mouth reports shown in the UI")
    md.append("\nDecision to remove a metric from the codebase requires checking its downstream users, not just this audit.")

    (OUT / "feature_audit.md").write_text("\n".join(md))

    # JSON for programmatic use
    summary = {
        "baseline_test_acc": base_acc,
        "ranking": df.to_dict("records"),
        "redundant_pairs": [{"a": a, "b": b, "r": r} for a, b, r in redundant_pairs],
        "keep_strong": keep_strong,
        "keep_moderate": keep_mod,
        "weak": weak,
        "drop": drop,
    }
    (OUT / "feature_audit.json").write_text(json.dumps(summary, indent=2))

    print("\n" + "=" * 60)
    print(f"baseline test acc = {base_acc:.4f}")
    print(f"KEEP strong:   {keep_strong}")
    print(f"KEEP moderate: {keep_mod}")
    print(f"WEAK:          {weak}")
    print(f"DROP:          {drop}")
    print(f"redundant:     {redundant_pairs}")
    print(f"\n→ {OUT/'feature_audit.md'}")
    print(f"→ {OUT/'feature_audit.json'}")


if __name__ == "__main__":
    main()
