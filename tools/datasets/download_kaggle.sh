#!/usr/bin/env bash
# Downloads the niten19/face-shape-dataset Kaggle dataset into the local
# kagglehub cache, matching the path that
# tools/face_shape_ml/extract_landmarks.py and train_cnn.py expect:
#   tools/datasets/kaggle_cache/datasets/niten19/face-shape-dataset/versions/2/FaceShape Dataset
#
# Prerequisites:
#   1. Kaggle API token at ~/.kaggle/kaggle.json (https://www.kaggle.com/settings → Create New API Token)
#   2. pip install kagglehub
#
# Usage:
#   bash tools/datasets/download_kaggle.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export KAGGLEHUB_CACHE="$SCRIPT_DIR/kaggle_cache"
mkdir -p "$KAGGLEHUB_CACHE"

python - <<'PY'
import kagglehub
path = kagglehub.dataset_download("niten19/face-shape-dataset")
print(f"Dataset downloaded to: {path}")
PY
