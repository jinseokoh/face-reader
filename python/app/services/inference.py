"""DeepFace wrapper — age / gender / race only, CPU-tuned.

DeepFace.analyze is blocking (numpy + tensorflow). We call it via
asyncio.to_thread so a slow inference doesn't park the event loop. Model
weights download on first call; the startup warm-up forces that to happen
before the first real request lands.
"""
from __future__ import annotations

import asyncio
import logging
from typing import Any

import numpy as np
from deepface import DeepFace

from app.utils.config import get_settings

logger = logging.getLogger(__name__)

_ACTIONS = ["age", "gender", "race"]


class NoFaceError(Exception):
    """DeepFace failed to detect a face in the supplied image."""


def _analyze_blocking(image_path: str, detector_backend: str) -> dict[str, Any]:
    """Synchronous DeepFace call. Lives off the event loop."""
    try:
        results = DeepFace.analyze(
            img_path=image_path,
            actions=_ACTIONS,
            detector_backend=detector_backend,
            enforce_detection=True,
            silent=True,
        )
    except ValueError as exc:
        # DeepFace raises ValueError("Face could not be detected.") on miss.
        if "could not be detected" in str(exc).lower() or "face" in str(exc).lower():
            raise NoFaceError(str(exc)) from exc
        raise

    if not results:
        raise NoFaceError("DeepFace returned an empty result")

    # DeepFace ≥ 0.0.79 always returns a list; older versions returned a dict.
    first = results[0] if isinstance(results, list) else results
    return first


async def analyze_image(image_path: str) -> dict[str, Any]:
    """Run DeepFace.analyze off the event loop and shape the output.

    Returns a dict with keys: age (int), gender (str), race (str).
    Raises NoFaceError if no face is detected.
    """
    settings = get_settings()
    result = await asyncio.to_thread(
        _analyze_blocking, image_path, settings.detector_backend
    )

    age_raw = result.get("age")
    gender = result.get("dominant_gender") or result.get("gender")
    race = result.get("dominant_race") or result.get("race")

    if age_raw is None or gender is None or race is None:
        raise NoFaceError("DeepFace result missing required fields")

    # gender may be a dict of confidences in old payloads — pick argmax.
    if isinstance(gender, dict):
        gender = max(gender, key=gender.get)
    if isinstance(race, dict):
        race = max(race, key=race.get)

    return {
        "age": int(round(float(age_raw))),
        "gender": str(gender),
        "race": str(race),
    }


async def warm_up() -> None:
    """Force model weight download + first-call JIT before serving traffic.

    Uses a synthetic 224×224 image so we never hit the wire; enforce_detection
    is False so failure to detect a face on the blank image isn't fatal.
    """
    settings = get_settings()
    logger.info("warming up DeepFace models (backend=%s)", settings.detector_backend)

    def _warm() -> None:
        try:
            blank = (np.random.rand(224, 224, 3) * 255).astype("uint8")
            DeepFace.analyze(
                img_path=blank,
                actions=_ACTIONS,
                detector_backend=settings.detector_backend,
                enforce_detection=False,
                silent=True,
            )
        except Exception as exc:  # pragma: no cover — best effort
            logger.warning("warm-up call raised: %s", exc)

    await asyncio.to_thread(_warm)
    logger.info("DeepFace warm-up complete")
