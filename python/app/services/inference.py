"""나이·성별·인종 추론 — MiVOLO v2 (나이·성별) + DeepFace race 헤드 (인종). CPU.

왜 둘인가 (tools/face_shape_ml/README.md ③, 2026-09-20 AAF 1,972장 측정):
  DeepFace 나이는 동아시아 성인에서 MAE 9.8세, 50대 이상을 18~33세 젊게 본다.
  MiVOLO v2 는 MAE 6.1세, 성별 99%. 인종은 MiVOLO 가 안 주므로 DeepFace 의
  race 헤드만 남긴다 (앱이 기준 분포표를 고르는 데 쓴다).

입력 두 가지:
  * face_crop=True  — 앱/웹이 랜드마크 박스를 넓혀 잘라 보낸 정사각 얼굴 크롭.
                      검출을 건너뛴다 (DeepFace detector "skip", MiVOLO 는 그대로).
  * face_crop=False — 전체 사진(옛 앱의 image_url 경로). DeepFace opencv 검출로
                      얼굴 박스를 얻고, 박스를 CROP_MARGIN 만큼 넓힌 정사각 크롭을
                      MiVOLO 에 넣는다.

두 모델은 독립이라 스레드 둘로 동시에 돈다 (asyncio.gather). 둘 다 blocking
(numpy + torch / tensorflow) 이라 이벤트 루프 밖에서 실행한다.

응답 정규화 — Flutter SSOT enum name:
  gender:    MiVOLO "male"/"female" 그대로
  ethnicity: DeepFace 6-class → eastAsian | caucasian | african |
             southeastAsian | hispanic | middleEastern
"""
from __future__ import annotations

import asyncio
import logging
from typing import Any

import cv2
import numpy as np

from app.utils.config import get_settings

logger = logging.getLogger(__name__)

# DeepFace 는 인종만. age/gender 헤드는 로드하지 않는다 (메모리·시간 절약).
_DEEPFACE_ACTIONS = ["race"]

# DeepFace race → Flutter Ethnicity enum name.
# DeepFace 의 "asian" 학습 데이터는 한·중·일이 다수라 eastAsian 으로 매핑.
# "indian" 은 남아시아권 → 앱의 southeastAsian 라벨에 통폐합 (앱 enum 의
# 원 결정과 일치).
_ETHNICITY_MAP: dict[str, str] = {
    "asian": "eastAsian",
    "white": "caucasian",
    "black": "african",
    "indian": "southeastAsian",
    "middle eastern": "middleEastern",
    "latino hispanic": "hispanic",
}

# MiVOLO 입력 한 변 (모델 카드 규격).
MIVOLO_INPUT_PX = 384

# 응답 `ageModel` — 어느 식이 낸 나이인지 카드에 남긴다 (APPLE.md §58 과 같은 원칙).
AGE_MODEL = "mivolo_v2"


class NoFaceError(Exception):
    """얼굴 미검출 (또는 모델 결과 누락)."""


# ── MiVOLO ────────────────────────────────────────────────────────────────

_mivolo: dict[str, Any] = {}


def _load_mivolo() -> dict[str, Any]:
    """HF 원격 코드로 MiVOLO v2 를 한 번만 올린다. 프로세스당 1개."""
    if _mivolo:
        return _mivolo
    import torch
    from transformers import AutoConfig, AutoImageProcessor, AutoModelForImageClassification

    s = get_settings()
    kw = {"trust_remote_code": True, "revision": s.mivolo_revision}
    config = AutoConfig.from_pretrained(s.mivolo_model_id, **kw)
    model = AutoModelForImageClassification.from_pretrained(
        s.mivolo_model_id, torch_dtype=torch.float32, **kw
    ).eval()
    proc = AutoImageProcessor.from_pretrained(s.mivolo_model_id, **kw)
    _mivolo.update(
        model=model,
        proc=proc,
        gender_id2label=config.gender_id2label,
        # 몸 크롭 없음 — processor 가 [None] 을 빈 텐서로 만든다 (모델 카드 README).
        empty_body=proc(images=[None])["pixel_values"],
    )
    logger.info("MiVOLO loaded", extra={"model": s.mivolo_model_id, "revision": s.mivolo_revision})
    return _mivolo


def _mivolo_predict(face_bgr: np.ndarray) -> tuple[int, str]:
    """정사각 얼굴 크롭(BGR) → (나이 정수, 'male'|'female')."""
    import torch

    m = _load_mivolo()
    if face_bgr.shape[0] != MIVOLO_INPUT_PX or face_bgr.shape[1] != MIVOLO_INPUT_PX:
        face_bgr = cv2.resize(face_bgr, (MIVOLO_INPUT_PX, MIVOLO_INPUT_PX), interpolation=cv2.INTER_AREA)
    faces = m["proc"](images=[face_bgr])["pixel_values"]
    with torch.no_grad():
        out = m["model"](faces_input=faces, body_input=m["empty_body"])
    age = int(round(float(out.age_output[0].item())))
    gender = str(m["gender_id2label"][int(out.gender_class_idx[0].item())]).lower()
    if gender not in ("male", "female"):
        raise NoFaceError(f"MiVOLO unexpected gender label: {gender}")
    return age, gender


# ── DeepFace (race + 검출) ─────────────────────────────────────────────────


def _deepface_race(img_bgr: np.ndarray, detect: bool) -> tuple[str, dict[str, int] | None]:
    """인종 라벨과 (검출했을 때) 얼굴 박스 {x,y,w,h}. detect=False 면 입력을 얼굴로 본다."""
    from deepface import DeepFace

    s = get_settings()
    try:
        results = DeepFace.analyze(
            img_path=img_bgr,
            actions=_DEEPFACE_ACTIONS,
            detector_backend=s.detector_backend if detect else "skip",
            enforce_detection=detect,
            silent=True,
        )
    except ValueError as exc:
        # DeepFace raises ValueError("Face could not be detected.") on miss.
        if "face" in str(exc).lower():
            raise NoFaceError(str(exc)) from exc
        raise
    if not results:
        raise NoFaceError("DeepFace returned an empty result")
    # 여러 얼굴이면 가장 큰 박스.
    first = max(results, key=lambda r: r.get("region", {}).get("w", 0) * r.get("region", {}).get("h", 0))
    race = first.get("dominant_race") or first.get("race")
    if isinstance(race, dict):
        race = max(race, key=race.get)
    if race is None:
        raise NoFaceError("DeepFace result missing race")
    region = first.get("region") if detect else None
    if detect and (not region or region.get("w", 0) <= 0):
        raise NoFaceError("DeepFace returned no face region")
    return _ETHNICITY_MAP.get(str(race).strip().lower(), str(race).strip().lower()), region


# ── 크롭 ──────────────────────────────────────────────────────────────────


def square_crop(img: np.ndarray, box: tuple[int, int, int, int], margin: float, size: int = MIVOLO_INPUT_PX) -> np.ndarray:
    """박스(x1,y1,x2,y2)를 사방 margin 배 넓힌 뒤 긴 변 기준 정사각으로 잘라 size 로 줄인다.
    사진 밖은 검정 패딩. tools/face_shape_ml/eval_mivolo_crop_margin.py 와 같은 식."""
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


def decode_image(data: bytes) -> np.ndarray:
    """JPEG/PNG/WebP bytes → BGR ndarray. 디코드 실패는 NoFaceError (얼굴 이전에 이미지가 아님)."""
    arr = np.frombuffer(data, dtype=np.uint8)
    img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if img is None or img.size == 0:
        raise NoFaceError("image could not be decoded")
    return img


# ── 진입점 ────────────────────────────────────────────────────────────────


async def analyze_image(img_bgr: np.ndarray, *, face_crop: bool) -> dict[str, Any]:
    """나이·성별(MiVOLO)·인종(DeepFace) — 이벤트 루프 밖에서 두 모델을 동시에.

    face_crop=True 면 img 가 이미 얼굴 크롭이라 검출을 건너뛴다.
    Returns {age:int, gender:str, ethnicity:str, ageModel:str}. 얼굴 없으면 NoFaceError.
    """
    s = get_settings()
    if face_crop:
        race_task = asyncio.to_thread(_deepface_race, img_bgr, False)
        age_task = asyncio.to_thread(_mivolo_predict, img_bgr)
        (ethnicity, _), (age, gender) = await asyncio.gather(race_task, age_task)
    else:
        # 전체 사진: 검출이 먼저다 — MiVOLO 크롭이 박스에 의존한다.
        ethnicity, region = await asyncio.to_thread(_deepface_race, img_bgr, True)
        assert region is not None
        box = (region["x"], region["y"], region["x"] + region["w"], region["y"] + region["h"])
        crop = square_crop(img_bgr, box, s.crop_margin)
        age, gender = await asyncio.to_thread(_mivolo_predict, crop)
    return {"age": age, "gender": gender, "ethnicity": ethnicity, "ageModel": AGE_MODEL}


async def warm_up() -> None:
    """가중치 다운로드 + 첫 호출 JIT 를 트래픽 전에 끝낸다. 실패해도 기동은 막지 않는다."""
    settings = get_settings()
    logger.info("warming up models (detector=%s)", settings.detector_backend)

    def _warm() -> None:
        blank = (np.random.rand(MIVOLO_INPUT_PX, MIVOLO_INPUT_PX, 3) * 255).astype("uint8")
        try:
            _deepface_race(blank, False)
        except Exception as exc:  # pragma: no cover — best effort
            logger.warning("DeepFace warm-up raised: %s", exc)
        try:
            _mivolo_predict(blank)
        except Exception as exc:  # pragma: no cover
            logger.warning("MiVOLO warm-up raised: %s", exc)

    await asyncio.to_thread(_warm)
    logger.info("warm-up complete")
