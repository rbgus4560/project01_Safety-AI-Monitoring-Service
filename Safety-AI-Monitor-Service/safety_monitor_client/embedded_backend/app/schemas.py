# 프로젝트 여러 곳에서 함께 사용하는 보조 코드 파일입니다.
# 상수, 스키마, 로그 같은 공통 흐름을 담고 있습니다.

from typing import Any

from pydantic import BaseModel

# 이 파일은 FastAPI 응답 모델 모음입니다.
# Pydantic 모델은 서버가 어떤 JSON 형태를 돌려주는지 문서처럼 보여 주는 역할도 합니다.

class EventListResponse(BaseModel):
    """이벤트 목록 응답의 기본 구조를 정의합니다."""
    count: int
    items: list[dict[str, Any]]


class SourceSummaryItem(BaseModel):
    """소스별 이벤트 요약 정보를 나타내는 항목입니다."""
    source_key: str
    source_type: str
    source_value: str
    event_count: int
    latest_received_at: str


class SourceSummaryListResponse(BaseModel):
    """소스 요약 목록 응답 구조를 정의합니다."""
    count: int
    items: list[SourceSummaryItem]


class SourceItem(BaseModel):
    """단일 소스의 상세 정보 응답 형식입니다."""
    source_key: str
    source_slug: str
    display_name: str = ""
    source_type: str
    source_value: str
    source_duration_seconds: float = 0.0
    server_media_path: str = ""
    media_url: str = ""
    preview_url: str = ""
    original_source_type: str = ""
    original_source_value: str = ""
    client_id: str = ""
    session_id: str = ""
    desired_running: bool = True
    rule_config: dict[str, Any] = {}
    created_at: str
    updated_at: str


class SourceListResponse(BaseModel):
    """소스 목록 응답 구조를 정의합니다."""
    count: int
    items: list[SourceItem]


class SourceCreateRequest(BaseModel):
    """소스 생성 요청에 필요한 입력값을 정의합니다."""
    source_type: str
    source_value: str
    client_id: str = ""
    session_id: str = ""
    reset_existing: bool = True
    start_immediately: bool = True


class SourceUpsertResponse(BaseModel):
    """소스 생성/수정 결과를 반환하는 응답 구조입니다."""
    ok: bool
    item: SourceItem


class SourceDisplayNameUpdateRequest(BaseModel):
    """소스 표시 이름 변경 요청입니다."""
    display_name: str = ""


class SourceConfigUpdateRequest(BaseModel):
    """소스 규칙 설정 변경 요청을 정의합니다."""
    rule_config: dict[str, Any]


class SourceActionResponse(BaseModel):
    """소스 시작/중지 같은 액션 결과 응답 구조입니다."""
    ok: bool
    source_key: str
    state: str


class SourceStatusItem(BaseModel):
    """소스 상태 정보를 나타내는 항목입니다."""
    source_key: str
    source_type: str
    source_value: str
    client_id: str = ""
    session_id: str = ""
    state: str
    is_running: bool
    source_fps: float = 0.0
    source_duration_seconds: float = 0.0
    last_frame_id: int = -1
    last_source_time_seconds: float = 0.0
    avg_object_detection_ms: float = 0.0
    error_message: str = ""
    updated_at: str


class SourceStatusListResponse(BaseModel):
    """소스 상태 목록 응답 구조를 정의합니다."""
    count: int
    items: list[SourceStatusItem]


class SourceStatusUpsertResponse(BaseModel):
    """소스 상태 저장 결과 응답 구조입니다."""
    ok: bool
    item: dict[str, Any]


class EventDetailResponse(BaseModel):
    """단일 이벤트 상세 조회 응답 구조입니다."""
    event_key: str
    item: dict[str, Any]


class EventHistoryResponse(BaseModel):
    """이벤트 히스토리 조회 응답 구조입니다."""
    event_key: str
    count: int
    items: list[dict[str, Any]]


class EventCreateResponse(BaseModel):
    """이벤트 생성 결과 응답 구조입니다."""
    ok: bool
    item: dict[str, Any]


class ClipItem(BaseModel):
    """클립 파일 정보를 나타내는 항목입니다."""
    name: str
    path: str
    url: str


class ClipListResponse(BaseModel):
    """클립 목록 응답 구조를 정의합니다."""
    count: int
    items: list[ClipItem]


class ClipUploadResponse(BaseModel):
    """클립 업로드 결과를 반환하는 응답 구조입니다."""
    ok: bool
    name: str
    path: str
    url: str
    size_bytes: int
    event_key: str | None = None


class FrameDetectionCreateResponse(BaseModel):
    """프레임 탐지 결과 생성 응답 구조입니다."""
    ok: bool
    item: dict[str, Any]


class FrameDetectionSnapshotResponse(BaseModel):
    """프레임 탐지 스냅샷 조회 결과 구조입니다."""
    found: bool
    item: dict[str, Any] | None


class HealthResponse(BaseModel):
    """헬스 체크 응답 형식을 정의합니다."""
    status: str
    event_log_path: str
    event_log_exists: bool


class ResetDataResponse(BaseModel):
    """데이터 초기화 결과 응답 구조입니다."""
    ok: bool
    source_key: str
    cleared_events: bool
    deleted_event_count: int
    deleted_clip_count: int


class RemoteServerConfigUpdateRequest(BaseModel):
    """원격 서버 주소 변경 요청 형식입니다."""
    remote_server_base_url: str


class RemoteServerConfigResponse(BaseModel):
    """원격 서버 설정 응답 형식입니다."""
    ok: bool
    remote_server_base_url: str
