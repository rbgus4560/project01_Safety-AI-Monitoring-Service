# 프로젝트 여러 곳에서 함께 사용하는 보조 코드 파일입니다.
# 상수, 스키마, 로그 같은 공통 흐름을 담고 있습니다.

from pathlib import Path


SERVER_DIR = Path(__file__).resolve().parents[1].resolve()
SERVER_DATA_DIR = (SERVER_DIR / "data").resolve()
SERVER_CLIP_DIR = (SERVER_DATA_DIR / "clips").resolve()
SERVER_EVENT_THUMBNAIL_DIR = (SERVER_DATA_DIR / "event_thumbnails").resolve()
SERVER_SOURCE_PREVIEW_DIR = (SERVER_DATA_DIR / "source_previews").resolve()
SERVER_UPLOAD_SOURCE_DIR = (SERVER_DATA_DIR / "uploaded_sources").resolve()
SERVER_SOURCE_CACHE_DIR = (SERVER_DATA_DIR / "source_cache").resolve()
DATABASE_PATH = (SERVER_DATA_DIR / "monitor.db").resolve()

ENABLE_SERVER_REQUEST_LOG = True
SERVER_REQUEST_LOG_SUMMARY_INTERVAL_SECONDS = 5.0
SERVER_REQUEST_LOG_SUMMARY_PATHS = (
    "/health",
    "/api/frame-detections",
    "/api/frame-detections/current",
    "/api/frame-detections/latest",
    "/api/source-previews",
    "/api/source-previews/latest",
    "/api/source-streams/{source_key:path}",
    "/api/source-status",
    "/api/sources",
    "/api/sources/overview",
    "/api/events",
    "/api/events/latest",
    "/api/events/detail",
    "/api/event-thumbnails/{thumbnail_name}",
)
SERVER_REQUEST_LOG_IMMEDIATE_MIN_STATUS = 400


def ensure_server_dirs() -> None:
    SERVER_DATA_DIR.mkdir(parents=True, exist_ok=True)
    SERVER_CLIP_DIR.mkdir(parents=True, exist_ok=True)
    SERVER_EVENT_THUMBNAIL_DIR.mkdir(parents=True, exist_ok=True)
    SERVER_SOURCE_PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    SERVER_UPLOAD_SOURCE_DIR.mkdir(parents=True, exist_ok=True)
    SERVER_SOURCE_CACHE_DIR.mkdir(parents=True, exist_ok=True)
