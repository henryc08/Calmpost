"""Settings from vision/.env (git-ignored). See .env.example."""

import os
from dataclasses import dataclass
from pathlib import Path

from dotenv import load_dotenv

HERE = Path(__file__).resolve().parent
# override: vision/.env beats stale keys left in the shell environment.
load_dotenv(HERE / ".env", override=True)


def _source(raw: str) -> int | str:
    """'0' -> webcam index 0; anything else is a file path or stream URL."""
    return int(raw) if raw.isdigit() else raw


@dataclass(frozen=True)
class Settings:
    camera_source: int | str = _source(os.environ.get("CAMERA_SOURCE", "0"))
    bin_id: str = os.environ.get("BIN_ID", "bin-001")
    backend_url: str = os.environ.get("BACKEND_URL", "http://localhost:8090").rstrip("/")
    api_key: str = os.environ.get("APP_API_KEY", "")
    gemini_api_key: str = os.environ.get("GEMINI_API_KEY", "")
    gemini_vision_model: str = os.environ.get("GEMINI_VISION_MODEL", "gemini-2.5-flash")
    preview_port: int = int(os.environ.get("PREVIEW_PORT", "8081"))
    roi_path: Path = HERE / "roi.json"
    catalog_path: Path = HERE / "catalog.json"
    thumbs_dir: Path = HERE / "thumbs"


settings = Settings()
