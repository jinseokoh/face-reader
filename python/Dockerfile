FROM python:3.10-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    # DeepFace caches downloaded weights here. Pre-create it so we can warm
    # the image at build time without polluting /root.
    DEEPFACE_HOME=/app/.deepface \
    # tensorflow-cpu noise reduction.
    TF_CPP_MIN_LOG_LEVEL=2

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

RUN mkdir -p "$DEEPFACE_HOME"

EXPOSE 8000

# Single-worker is intentional: each worker would hold its own copy of the
# TF model in memory. Scale by container count, not by uvicorn --workers.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
