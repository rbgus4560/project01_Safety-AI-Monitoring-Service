# FastAPI 앱을 생성하고 필요한 router를 연결하는 파일입니다.
# 앱 시작/종료 처리와 공통 미들웨어 설정이 포함되어 있습니다.

from contextlib import asynccontextmanager
from time import monotonic
from time import perf_counter

from fastapi import FastAPI
from fastapi import Request
from fastapi.middleware.cors import CORSMiddleware

from app.config import ANALYSIS_DEVICE
from app.config import MODEL_PATH
from app.config import MODEL_TYPE
from app.config import PREFER_TENSORRT_ENGINE
from pathlib import Path
from app.dashboard_page import build_dashboard_html
from app.config import DATABASE_PATH
from app.config import ENABLE_SERVER_REQUEST_LOG
from app.config import SERVER_REQUEST_LOG_SUMMARY_INTERVAL_SECONDS
from app.config import SERVER_REQUEST_LOG_SUMMARY_PATHS
from app.config import ensure_client_dirs
from app.database import init_db
from app.log_utils import log_line
from app.reporting_api import remote_server_reporter
from app.routers.admin import router as admin_router
from app.routers.clips import router as clips_router
from app.routers.events import router as events_router
from app.routers.frame_detections import router as frame_detections_router
from app.routers.realtime import router as realtime_router
from app.routers.sources import router as sources_router
from app.routers.source_media import router as source_media_router
from app.routers.source_previews import router as source_previews_router
from app.routers.source_streams import router as source_streams_router
from app.routers.source_status import router as source_status_router
from app.schemas import HealthResponse
from app.source_manager import AnalysisSourceManager


ensure_client_dirs()         # 서버 시작 전 필요 폴더 생성
init_db(DATABASE_PATH)       # DB 파일 생성 및 테이블 초기화


@asynccontextmanager
async def lifespan(app: FastAPI):
    source_manager = AnalysisSourceManager()            # 카메라/분석 소스 관리 객체 생성
    app.state.source_manager = source_manager           # FastAPI 앱 전역 상태에 저장
    app.state.database_path = DATABASE_PATH         
    app.state.request_log_stats = {}                    # 요청 로그 통계 저장용 딕셔너리
    app.state.request_log_last_flush = monotonic()      # 마지막 로그 출력 시각
    source_manager.bootstrap()                          # 등록된 소수(카메라 등) 로드
    try:
        yield                                           # 서버 실행
    finally:
        if ENABLE_SERVER_REQUEST_LOG:                   # 서버 종료 직전 로그 저장
            _flush_request_log_summary(app, force=True)
        source_manager.shutdown()                       # 카메라 분석 스레드 종료

# FastAPI 앱 생성
app = FastAPI(title="Safety Monitor Client", lifespan=lifespan)

# CORS 미들웨어 설정
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],     # 허용할 출처
    allow_credentials=True,  # 쿠키 인증 허용
    allow_methods=["*"],     # GET, POST, DELETE 등 모든 메서드 허용
    allow_headers=["*"],     # 모든 헤더 허용
)

# Router 등록: 각 파일에 정의된 API들을 FastAPI 앱에 연결
app.include_router(events_router)
app.include_router(clips_router)
app.include_router(admin_router)
app.include_router(frame_detections_router)
app.include_router(source_status_router)
app.include_router(sources_router)
app.include_router(source_media_router)
app.include_router(source_previews_router)
app.include_router(source_streams_router)
app.include_router(realtime_router)

# 요청 로그 기능(누가, 어떤, 얼마나를 기록하기 위함)
if ENABLE_SERVER_REQUEST_LOG:

    def _record_request_summary(
        app: FastAPI,
        *,
        client_host: str,
        path: str,
        elapsed_ms: float,
        status_code: int,
    ) -> None:
        """
        특정 API 요청 통계를 누적 저장

        예)
        /api/events

        호출 횟수
        평균 응답 시간
        최대 응답 시간
        마지막 상태 코드

        등을 기록한다.
        """
        stats = app.state.request_log_stats
        key = (client_host, path)
        entry = stats.get(key)
        if entry is None:
            entry = {
                "count": 0,
                "total_ms": 0.0,
                "max_ms": 0.0,
                "last_status": status_code,
            }
            stats[key] = entry
        entry["count"] += 1
        entry["total_ms"] += elapsed_ms
        entry["max_ms"] = max(entry["max_ms"], elapsed_ms)
        entry["last_status"] = status_code

    def _flush_request_log_summary(app: FastAPI, force: bool = False) -> None:
        """
        누적된 로그를 실제 로그 파일에 출력

        일정 시간마다 호출됨
        """
        stats = app.state.request_log_stats
        if not stats:
            return
        now = monotonic()
        elapsed = now - app.state.request_log_last_flush
        if not force and elapsed < SERVER_REQUEST_LOG_SUMMARY_INTERVAL_SECONDS:
            return
        for (client_host, path), entry in list(stats.items()):
            count = int(entry["count"])
            if count <= 0:
                continue
            average_ms = float(entry["total_ms"]) / count
            max_ms = float(entry["max_ms"])
            last_status = int(entry["last_status"])
            log_line(
                "REQ-SUM",
                client=client_host,
                path=path,
                count=count,
                avg=f"{average_ms:.1f}ms",
                max=f"{max_ms:.1f}ms",
                last_status=last_status,
                window=f"{elapsed:.1f}s",
            )
        stats.clear()
        app.state.request_log_last_flush = now

    @app.middleware("http")
    async def log_requests(request: Request, call_next):
        """
        모든 HTTP 요청을 가로채는 미들웨어

        처리 순서

        클라이언트 요청
            ↓
        log_requests()
            ↓
        실제 API 실행
            ↓
        응답
        """
        started_at = perf_counter()  # 시작 시간 기록
        client_host = request.client.host if request.client else "-"
        method = request.method.upper()
        path = request.url.path
        query = request.url.query
        display_path = f"{path}?{query}" if query else path
        try: # 실제 API 실행
            response = await call_next(request)
        except Exception as error:
            elapsed_ms = (perf_counter() - started_at) * 1000.0
            log_line(
                "REQ",
                client=client_host,
                method=method,
                path=display_path,
                status=500,
                duration=f"{elapsed_ms:.1f}ms",
                error=error,
            )
            raise

        elapsed_ms = (perf_counter() - started_at) * 1000.0
        # 특정 API는 요약 통계로 저장
        if path in SERVER_REQUEST_LOG_SUMMARY_PATHS:
            _record_request_summary(
                app,
                client_host=client_host,
                path=path,
                elapsed_ms=elapsed_ms,
                status_code=response.status_code,
            )
            _flush_request_log_summary(app)
        else:
            # 일반 API는 즉시 로그 출력
            log_line(
                "REQ",
                client=client_host,
                method=method,
                path=display_path,
                status=response.status_code,
                duration=f"{elapsed_ms:.1f}ms",
            )
        return response

# 서버 상태 확인 API: 서버가 정상 동작 중인지 확인
@app.get("/health", response_model=HealthResponse)
def health() -> HealthResponse:
    return HealthResponse(
        status=f"ok (server={remote_server_reporter.base_url})",
        event_log_path=str(DATABASE_PATH),
        event_log_exists=DATABASE_PATH.exists(),
    )

# 메인 페이지: 대시보드 HTML 반환
@app.get("/")
def dashboard():
    return build_dashboard_html()

# 클라이언트 설정 조회 API: 현재 서버 설정은 프론트엔드에 전달
@app.get("/api/client/config")
def client_config() -> dict[str, object]:
    #TensorRT 엔진 파일 경로 생성
    engine_path = MODEL_PATH.with_suffix(".engine")
    # Ultralytics 설정 폴더
    ultralytics_config_dir = (
        Path(__file__).resolve().parent / "data" / "ultralytics"
    ).resolve()
    return {
        "remote_server_base_url": remote_server_reporter.base_url,
        "analysis_device": ANALYSIS_DEVICE,
        "model_type": MODEL_TYPE,
        "prefer_tensorrt_engine": PREFER_TENSORRT_ENGINE,
        "model_path": str(MODEL_PATH),
        "model_exists": MODEL_PATH.exists(),
        "engine_path": str(engine_path),
        "engine_exists": engine_path.exists(),
        "yolo_config_dir": str(ultralytics_config_dir),
        "database_path": str(DATABASE_PATH),
    }
