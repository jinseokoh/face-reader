import logging
import sys

from pythonjsonlogger import jsonlogger

from app.utils.config import get_settings


def configure_logging() -> None:
    """Install a single JSON-formatted stdout handler on the root logger.

    Uvicorn's access/error loggers reuse the root handler once propagate=True,
    so the same JSON format covers framework + app logs.
    """
    settings = get_settings()
    level = getattr(logging, settings.log_level.upper(), logging.INFO)

    handler = logging.StreamHandler(sys.stdout)
    formatter = jsonlogger.JsonFormatter(
        fmt="%(asctime)s %(levelname)s %(name)s %(message)s",
        rename_fields={"asctime": "ts", "levelname": "level", "name": "logger"},
    )
    handler.setFormatter(formatter)

    root = logging.getLogger()
    root.handlers = [handler]
    root.setLevel(level)

    # Let uvicorn loggers bubble up to root so they format as JSON too.
    for name in ("uvicorn", "uvicorn.error", "uvicorn.access"):
        logger = logging.getLogger(name)
        logger.handlers = []
        logger.propagate = True
