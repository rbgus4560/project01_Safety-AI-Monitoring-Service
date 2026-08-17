# 프로젝트 여러 곳에서 함께 사용하는 보조 코드 파일입니다.
# 상수, 스키마, 로그 같은 공통 흐름을 담고 있습니다.

import os
import json
from pathlib import Path


# 클라이언트 런타임이 사용하는 주요 디렉터리 경로를 정의합니다.
CLIENT_DIR = Path(__file__).resolve().parents[1].resolve()
CLIENT_APP_DIR = CLIENT_DIR.parent.resolve()
WORKSPACE_DIR = CLIENT_APP_DIR.parent.resolve()
CLIENT_SETTINGS_PATH = (CLIENT_APP_DIR / "client_settings.json").resolve()
CLIENT_DATA_DIR = (CLIENT_DIR / "data").resolve()
CLIENT_CLIP_DIR = (CLIENT_DATA_DIR / "clips").resolve()
CLIENT_SOURCE_PREVIEW_DIR = (CLIENT_DATA_DIR / "source_previews").resolve()
CLIENT_SOURCE_CACHE_DIR = (CLIENT_DATA_DIR / "source_cache").resolve()
CLIENT_UPLOAD_SOURCE_DIR = (CLIENT_DATA_DIR / "uploaded_sources").resolve()
DATABASE_PATH = (CLIENT_DATA_DIR / "monitor.db").resolve()
ANALYSIS_DIR = (CLIENT_DIR / "app" / "analysis").resolve()
ANALYSIS_WEIGHTS_DIR = (ANALYSIS_DIR / "models" / "weights").resolve()

def _read_settings_remote_server_url() -> str:
    """클라이언트 설정 파일에서 원격 서버 주소를 읽어옵니다."""
    try:
        decoded = json.loads(CLIENT_SETTINGS_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return ""
    if not isinstance(decoded, dict):
        return ""
    return str(decoded.get("remote_server_base_url", "")).strip().rstrip("/")


# 원격 서버 주소는 환경 변수 우선, 그다음 설정 파일, 마지막으로 기본값 순으로 결정합니다.
REMOTE_SERVER_BASE_URL = (
    os.environ.get("SAFETY_MONITOR_SERVER_URL", "").strip().rstrip("/")
    or _read_settings_remote_server_url()
    or "http://127.0.0.1:8000"
)
HTTP_TIMEOUT_SECONDS = 15.0

# 분석 런타임에서 사용할 모델과 추론 설정입니다.
MODEL_TYPE = "yolo"
MODEL_PATH = (ANALYSIS_WEIGHTS_DIR / "best.pt").resolve()
PERSON_MODEL_PATH = (ANALYSIS_WEIGHTS_DIR / "person_detect.pt").resolve()
SAFETY_MODEL_PATH = (ANALYSIS_WEIGHTS_DIR / "good1.pt").resolve()
PREFER_TENSORRT_ENGINE = True
# TensorRT 엔진 export 시 사용할 입력 크기와 옵션입니다.
TENSORRT_EXPORT_IMGSZ = 640
TENSORRT_EXPORT_HALF = True
TENSORRT_EXPORT_DYNAMIC = False
TENSORRT_EXPORT_BATCH = 1
MIN_CONFIDENCE = 0.3
ANALYSIS_DEVICE = "cuda:0"
ANALYSIS_REQUIRE_CUDA = True
MODEL_INPUT_MAX_WIDTH = 1024
ANALYSIS_TARGET_FPS = 0.0

# 위험 상황 규칙, 추적기, 이벤트 저장 관련 설정입니다.
USE_NO_HELMET_RULE = True
NO_HELMET_HEAD_RATIO = 0.3
NO_HELMET_OVERLAP_RATIO = 0.2
USE_DANGER_ZONE_RULE = False
DANGER_ZONE_ROI = (100, 200, 500, 600)
EVENT_COOLDOWN_SECONDS = 3
EVENT_END_MISSING_FRAMES = 30
TRACK_MAX_DISTANCE = 100
TRACK_MAX_MISSING_FRAMES = 60
SAVE_EVENT_CLIP = True
EVENT_CLIP_BEFORE_SECONDS = 1
EVENT_CLIP_WRITE_QUEUE_SIZE = 512
FRAME_DETECTION_POST_MAX_FPS = 15.0
SOURCE_STATUS_POST_MIN_INTERVAL_SECONDS = 1.0
ENABLE_PIPELINE_PERF_LOG = True
PIPELINE_PERF_LOG_INTERVAL_FRAMES = 120
ENABLE_SERVER_REQUEST_LOG = True
SERVER_REQUEST_LOG_SUMMARY_INTERVAL_SECONDS = 5.0
SERVER_REQUEST_LOG_SUMMARY_PATHS = (
    "/api/frame-detections/current",
    "/api/source-status",
    "/api/sources",
    "/api/events",
)
ANALYSIS_PROGRESS_LOG_INTERVAL_SECONDS = 10.0


def ensure_client_dirs() -> None:
    """클라이언트가 사용하는 데이터 디렉터리를 미리 생성합니다."""
    CLIENT_DATA_DIR.mkdir(parents=True, exist_ok=True)
    CLIENT_CLIP_DIR.mkdir(parents=True, exist_ok=True)
    CLIENT_SOURCE_PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    CLIENT_SOURCE_CACHE_DIR.mkdir(parents=True, exist_ok=True)
    CLIENT_UPLOAD_SOURCE_DIR.mkdir(parents=True, exist_ok=True)
    ANALYSIS_WEIGHTS_DIR.mkdir(parents=True, exist_ok=True)
