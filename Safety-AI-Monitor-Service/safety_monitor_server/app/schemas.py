# 프로젝트 여러 곳에서 함께 사용하는 보조 코드 파일입니다.
# 상수, 스키마, 로그 같은 공통 흐름을 담고 있습니다.

from typing import Any

from pydantic import BaseModel

# 이 파일은 FastAPI 응답/요청 모델 모음입니다.
# Pydantic 모델은 서버가 어떤 JSON 형태를 돌려주는지(또는 받는지) 문서처럼 보여 주는 역할도 합니다.
# 자동 생성되는 Swagger UI(API 문서)의 기준이 됩니다.

# -------------------------------------------------------------------
# [ 이벤트 관련 스키마 ]
# 특정 상황(객체 감지, 상태 변경 등)에 대한 기록(Event)을 다룹니다.
# -------------------------------------------------------------------

class EventListResponse(BaseModel):
    """
    조건에 맞는 이벤트 목록을 조회할 때 반환하는 응답 모델입니다.
    """
    count: int                 # 조회된 이벤트의 총 개수
    items: list[dict[str, Any]] # 실제 이벤트 데이터 목록 (다양한 형태가 올 수 있어 dict로 처리)


# -------------------------------------------------------------------
# [ 소스(Source) 요약 관련 스키마 ]
# 카메라, 영상 파일 등 데이터가 유입되는 '소스'의 통계/요약 정보를 다룹니다.
# -------------------------------------------------------------------

class SourceSummaryItem(BaseModel):
    """
    단일 소스의 요약 정보 (주로 통계 정보)
    """
    source_key: str          # 소스를 식별하는 고유 키 (예: 카메라 ID)
    source_type: str         # 소스의 종류 (예: rtsp, mp4 등)
    source_value: str        # 소스의 실제 주소나 경로
    event_count: int         # 해당 소스에서 발생한 총 이벤트 수
    latest_received_at: str  # 가장 마지막으로 데이터를 수신한 시각 (ISO 8601 포맷 등)


class SourceSummaryListResponse(BaseModel):
    """
    여러 소스의 요약 정보 목록을 반환하는 응답 모델
    """
    count: int
    items: list[SourceSummaryItem]


# -------------------------------------------------------------------
# [ 소스(Source) 상세/기본 정보 관련 스키마 ]
# 소스의 메타데이터 및 설정값을 다룹니다.
# -------------------------------------------------------------------

class SourceItem(BaseModel):
    """
    단일 소스의 상세 설정 및 메타데이터를 담는 모델입니다. (DB에 저장되는 핵심 정보들)
    """
    source_key: str              # 고유 식별자
    source_slug: str             # URL이나 파일명에 사용하기 좋은 형태의 이름
    display_name: str = ""       # 화면에 표시될 사용자 친화적 이름
    source_type: str             # 소스 유형 (카메라, 동영상 파일 등)
    source_value: str            # 연결 URL 또는 파일 경로
    source_duration_seconds: float = 0.0 # 영상일 경우 총 길이(초)
    server_media_path: str = ""  # 서버 내부에 저장된 미디어 파일 경로
    media_url: str = ""          # 클라이언트가 접근할 수 있는 미디어 URL
    preview_url: str = ""        # 미리보기 이미지 URL
    original_source_type: str = "" # 원본 소스 유형 (변환 전)
    original_source_value: str = ""# 원본 소스 값
    client_id: str = ""          # 이 소스를 등록/관리하는 클라이언트 ID
    session_id: str = ""         # 현재 연결된 세션 ID
    desired_running: bool = True # 사용자가 이 소스가 실행되기를 원하는지 여부 (목표 상태)
    rule_config: dict[str, Any] = {} # 영상 분석 등에 사용될 규칙/설정값
    created_at: str              # 생성 일시
    updated_at: str              # 마지막 수정 일시


class SourceListResponse(BaseModel):
    """
    등록된 소스들의 목록을 반환하는 응답 모델
    """
    count: int
    items: list[SourceItem]


# -------------------------------------------------------------------
# [ 소스 통합 모니터링(Overview) 관련 스키마 ]
# 설정 정보(SourceItem)와 현재 실행 상태(SourceStatusItem)를 하나로 합친 모델입니다.
# 주로 프론트엔드의 대시보드 화면 등에서 한눈에 보기 위해 사용합니다.
# -------------------------------------------------------------------

class SourceOverviewItem(BaseModel):
    """
    소스의 기본 정보와 실시간 구동 상태(에러 여부, 프레임 등)를 종합한 모니터링용 데이터입니다.
    """
    client_id: str = ""
    session_id: str = ""
    source_key: str
    source_slug: str = ""
    display_name: str = ""
    source_type: str
    source_value: str
    source_duration_seconds: float = 0.0
    media_url: str = ""
    preview_url: str = ""
    desired_running: bool = False
    # --- 여기서부터는 실시간 상태 정보 ---
    state: str = "unknown"             # 현재 상태 (running, stopped, error 등)
    is_running: bool = False           # 실제로 데이터(영상 등)를 처리 중인지 여부
    source_fps: float = 0.0            # 초당 프레임 수
    last_frame_id: int = -1            # 마지막으로 처리한 프레임 번호
    last_source_time_seconds: float = 0.0 # 처리된 영상의 재생 시간 (타임스탬프)
    last_event_received_at: str = ""   # 마지막 이벤트 발생 시각
    last_frame_received_at: str = ""   # 마지막 프레임 수신 시각
    error_message: str = ""            # 오류 발생 시 오류 내용
    updated_at: str = ""


class SourceOverviewListResponse(BaseModel):
    """
    모니터링 대시보드용 통합 정보 목록 응답 모델
    """
    count: int
    items: list[SourceOverviewItem]


# -------------------------------------------------------------------
# [ 소스 생성/수정/액션 요청 스키마 ]
# 클라이언트가 서버로 데이터를 보낼 때 사용하는 모델(Request Body)입니다.
# -------------------------------------------------------------------

class SourceCreateRequest(BaseModel):
    """
    새로운 소스를 등록할 때 클라이언트가 보내야 하는 필수 정보
    """
    source_type: str
    source_value: str
    client_id: str = ""
    session_id: str = ""
    reset_existing: bool = True     # 기존에 같은 소스가 있다면 초기화할지 여부
    start_immediately: bool = True  # 등록과 동시에 분석/수집을 시작할지 여부


class SourceUpsertResponse(BaseModel):
    """
    소스 등록(Create) 또는 갱신(Update) 처리 후 결과를 알려주는 응답
    """
    ok: bool             # 성공 여부
    item: SourceItem     # 처리된 소스의 상세 정보


class SourceConfigUpdateRequest(BaseModel):
    """
    소스의 분석 규칙이나 설정(rule_config)만 부분적으로 수정할 때 사용하는 요청
    """
    rule_config: dict[str, Any]


class SourceDisplayNameUpdateRequest(BaseModel):
    """
    소스의 화면 표시 이름(display_name)만 부분적으로 수정할 때 사용하는 요청
    """
    display_name: str = ""


class SourceActionResponse(BaseModel):
    """
    소스에 특정 명령(시작, 정지 등)을 내린 후 그 결과를 알려주는 응답
    """
    ok: bool
    source_key: str
    state: str           # 명령 수행 후의 최종 상태


# -------------------------------------------------------------------
# [ 소스 실시간 상태(Status) 관련 스키마 ]
# 분석 엔진이나 워커가 서버로 소스의 현재 상태를 보고할 때 주로 사용합니다.
# -------------------------------------------------------------------

class SourceStatusItem(BaseModel):
    """
    단일 소스의 '현재 구동 상태'만을 담고 있는 데이터
    """
    source_key: str
    source_type: str
    source_value: str
    client_id: str = ""
    session_id: str = ""
    state: str                   # 예: initializing, playing, disconnected 등
    is_running: bool
    source_fps: float = 0.0
    source_duration_seconds: float = 0.0
    last_frame_id: int = -1
    last_source_time_seconds: float = 0.0
    error_message: str = ""
    updated_at: str


class SourceStatusListResponse(BaseModel):
    """
    여러 소스의 현재 상태 목록 응답
    """
    count: int
    items: list[SourceStatusItem]


class SourceStatusUpsertResponse(BaseModel):
    """
    상태 정보 업데이트 완료를 알리는 응답
    """
    ok: bool
    item: dict[str, Any]


# -------------------------------------------------------------------
# [ 이벤트 상세 정보 스키마 ]
# -------------------------------------------------------------------

class EventDetailResponse(BaseModel):
    """
    특정 단일 이벤트의 상세 정보를 요청했을 때의 응답
    """
    event_key: str
    item: dict[str, Any]


class EventHistoryResponse(BaseModel):
    """
    특정 소스나 조건에 대한 이벤트 발생 이력을 반환
    """
    event_key: str
    count: int
    items: list[dict[str, Any]]


class EventCreateResponse(BaseModel):
    """
    외부에서 새로운 이벤트를 강제로 발생(생성)시켰을 때의 응답
    """
    ok: bool
    item: dict[str, Any]


# -------------------------------------------------------------------
# [ 영상/이미지 클립(Clip) 관련 스키마 ]
# 이벤트 발생 전후의 짧은 영상이나 스냅샷 파일들을 관리합니다.
# -------------------------------------------------------------------

class ClipItem(BaseModel):
    """
    저장된 미디어 클립 1개에 대한 정보
    """
    name: str  # 파일명
    path: str  # 서버 내 실제 저장 경로
    url: str   # 클라이언트가 다운로드/시청할 수 있는 URL


class ClipListResponse(BaseModel):
    """
    클립 목록 조회 응답
    """
    count: int
    items: list[ClipItem]


class ClipUploadResponse(BaseModel):
    """
    클라이언트가 서버로 클립 파일을 업로드했을 때의 결과 응답
    """
    ok: bool
    name: str
    path: str
    url: str
    size_bytes: int          # 파일 용량
    event_key: str | None = None # 이 클립이 특정 이벤트와 연관되어 있다면 해당 키 포함


# -------------------------------------------------------------------
# [ 프레임 감지(AI Inference) 관련 스키마 ]
# AI 모델이 특정 프레임에서 물체를 감지한 결과를 주고받을 때 사용합니다.
# -------------------------------------------------------------------

class FrameDetectionCreateResponse(BaseModel):
    """
    감지 결과(Bounding box 등)를 서버에 등록했을 때의 응답
    """
    ok: bool
    item: dict[str, Any]


class FrameDetectionSnapshotResponse(BaseModel):
    """
    특정 시점의 프레임 감지 결과를 조회할 때의 응답
    """
    found: bool                  # 해당 시점에 감지 결과가 존재하는지 여부
    item: dict[str, Any] | None  # 결과가 있다면 데이터 제공, 없으면 None


# -------------------------------------------------------------------
# [ 시스템 및 유틸리티 스키마 ]
# -------------------------------------------------------------------

class HealthResponse(BaseModel):
    """
    서버가 정상적으로 살아있는지 확인(Health Check)하는 API의 응답
    """
    status: str              # 예: "ok", "error" 등
    event_log_path: str      # 서버에 로그가 저장되는 경로 확인용
    event_log_exists: bool   # 해당 경로에 로그 파일이 실제로 존재하는지 여부


class ResetDataResponse(BaseModel):
    """
    특정 소스의 데이터(이벤트, 클립 등)를 초기화/삭제 요청했을 때의 결과 응답
    """
    ok: bool
    source_key: str          # 초기화된 소스 식별자
    cleared_events: bool     # 이벤트 데이터가 지워졌는지 여부
    deleted_event_count: int # 삭제된 이벤트 개수
    deleted_clip_count: int  # 삭제된 영상/이미지 클립 개수