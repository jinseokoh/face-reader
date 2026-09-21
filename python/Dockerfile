FROM python:3.10-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    # DeepFace caches downloaded weights here. Pre-create it so we can warm
    # the image at build time without polluting /root.
    DEEPFACE_HOME=/app/.deepface \
    # MiVOLO 가중치·원격 코드(HF hub) 캐시 — DeepFace 와 같은 볼륨 아래.
    HF_HOME=/app/.deepface/hf \
    # HF 원격 코드 modeling_mivolo.py 가 `mivolo.model.…` 을 import 한다 (vendor/NOTICE.md).
    PYTHONPATH=/app/vendor \
    # tensorflow-cpu noise reduction (suppress info + warning + error stubs).
    TF_CPP_MIN_LOG_LEVEL=3 \
    # TF 2.16+ moved to Keras 3. DeepFace/retinaface still need Keras 2 API.
    # This env tells TF to alias tf.keras → tf_keras (installed via pip).
    TF_USE_LEGACY_KERAS=1

# OpenCV headless still needs the dynamic linker to see libGL etc.
# These are the minimum apt deps for opencv-python-headless + DeepFace on
# Debian slim.
RUN apt-get update && apt-get install -y --no-install-recommends \
        libglib2.0-0 \
        libsm6 \
        libxext6 \
        libxrender1 \
        libgomp1 \
        libgl1 \
        ca-certificates \
        curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt ./
RUN pip install --upgrade pip && pip install -r requirements.txt

COPY app ./app
COPY vendor ./vendor

# HF 캐시를 볼륨(/app/.deepface) 밖으로 옮긴다 — 위 ENV 의 HF_HOME 을 덮어쓴다.
# 빌드 때 받아 이미지에 굽고(아래 RUN) 실행 시엔 오프라인이다. 볼륨 아래 두면
# 마운트가 구운 파일을 가리고, 실행 시점 다운로드는 집 회선에서 끊겨 기동이
# 반쪽이 된 적이 있다 (2026-09-21). 이 ENV 가 pip RUN 뒤에 있는 이유는
# 위 ENV 블록을 바꾸면 pip 레이어 캐시(30분)가 통째로 깨지기 때문이다.
ENV HF_HOME=/app/.hf \
    HF_HUB_OFFLINE=1

# MiVOLO v2 가중치·원격 코드를 이미지에 굽는다 (약 120MB). 리비전은
# app/utils/config.py 의 mivolo_revision 과 같아야 한다. 실행 시엔 HF_HUB_OFFLINE=1
# 이라 네트워크를 안 본다 — 없으면 기동이 아니라 빌드가 실패한다.
RUN HF_HUB_OFFLINE=0 python -c "\
from huggingface_hub import snapshot_download; \
snapshot_download('iitolstykh/mivolo_v2', revision='53393526c220e34cdd7b722b36d22b6f9e5f4241')"

RUN mkdir -p "$DEEPFACE_HOME"

EXPOSE 8000

# Single-worker is intentional: each worker would hold its own copy of the
# TF model in memory. Scale by container count, not by uvicorn --workers.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
