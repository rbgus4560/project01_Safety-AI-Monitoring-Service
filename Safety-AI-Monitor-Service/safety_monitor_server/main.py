# FastAPI 앱 진입점입니다.
# 서버가 시작될 때 데이터베이스 초기화, 라우터 등록, 요청 로깅 미들웨어 설정을 담당합니다.
# 이 파일의 역할은 애플리케이션의 전역 구성을 조립하고, 요청이 들어올 때 공통적으로 처리해야 하는
# 초기화/정리/로깅 행동을 한 곳에서 관리하는 것입니다.

from contextlib import asynccontextmanager
from time import monotonic
from time import perf_counter

from fastapi import FastAPI
from fastapi import Request
from fastapi.middleware.cors import CORSMiddleware

from app.config import (
    DATABASE_PATH,
    ENABLE_SERVER_REQUEST_LOG,
    SERVER_REQUEST_LOG_IMMEDIATE_MIN_STATUS,
    SERVER_REQUEST_LOG_SUMMARY_INTERVAL_SECONDS,
    SERVER_REQUEST_LOG_SUMMARY_PATHS,
    ensure_server_dirs,
)
from app.database import init_db
from app.log_utils import log_line
from app.routers.admin import router as admin_router
from app.routers.clips import router as clips_router
from app.routers.event_thumbnails import router as event_thumbnails_router
from app.routers.events import router as events_router
from app.routers.frame_detections import router as frame_detections_router
from app.routers.realtime import router as realtime_router
from app.routers.portfolio import router as portfolio_router
from app.routers.source_media import router as source_media_router
from app.routers.source_previews import router as source_previews_router
from app.routers.source_streams import router as source_streams_router
from app.routers.sources import router as sources_router
from app.routers.source_status import router as source_status_router
from app.schemas import HealthResponse


ensure_server_dirs()
init_db(DATABASE_PATH)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # 애플리케이션 생명주기 동안 공유할 상태를 저장한다.
    # 특히 요청 통계와 마지막 로그 flush 시각은 미들웨어가 계속 참조하므로
    # 앱 인스턴스의 state에 보관해 두는 방식으로 관리한다.
    app.state.database_path = DATABASE_PATH
    app.state.request_log_stats = {}
    app.state.request_log_last_flush = monotonic()
    try:
        # 앱이 실제로 실행되는 동안은 별도 처리 없이 yield를 통해 FastAPI에 제어권을 넘긴다.
        # 이 구간에서 들어오는 요청들이 모두 이 lifespan 컨텍스트 안에서 동작한다.
        yield
    finally:
        # 서버가 종료될 때 남아 있는 요청 요약 로그가 있다면 강제로 비우고 마무리한다.
        # 이렇게 하지 않으면 종료 직전 통계가 유실될 수 있다.
        if ENABLE_SERVER_REQUEST_LOG:
            _flush_request_log_summary(app, force=True)


# FastAPI 앱 인스턴스를 생성하고, 서버 전역 설정과 생명주기를 연결한다.
app = FastAPI(title="Safety Monitor Server", lifespan=lifespan)

# 브라우저나 클라이언트에서 API를 호출할 때 CORS 제한이 걸리지 않도록
# 모든 Origin, Method, Header에 대해 허용하는 공통 미들웨어를 등록한다.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 기능별로 분리된 router들을 하나의 앱에 연결한다.
# 각 router는 이벤트, 클립, 썸네일, 소스 상태, 실시간 통신 등
# 특정 도메인에 대한 API 엔드포인트를 담당한다.
app.include_router(events_router)
app.include_router(clips_router)
app.include_router(event_thumbnails_router)
app.include_router(admin_router)
app.include_router(frame_detections_router)
app.include_router(source_status_router)
app.include_router(sources_router)
app.include_router(source_media_router)
app.include_router(source_previews_router)
app.include_router(source_streams_router)
app.include_router(realtime_router)
app.include_router(portfolio_router)


if ENABLE_SERVER_REQUEST_LOG:

    def _record_request_summary(
        app: FastAPI,
        *,
        client_host: str,
        path: str,
        method: str,
        elapsed_ms: float,
        status_code: int,
    ) -> None:
        # 동일한 클라이언트/메서드/경로 조합에 대해 누적 통계를 저장한다.
        # 이 정보는 나중에 평균 응답시간, 최대 응답시간, 상태 코드 분포를 요약하는 데 사용된다.
        stats = app.state.request_log_stats
        key = (client_host, method, path)
        entry = stats.get(key)
        if entry is None:
            entry = {
                "count": 0,
                "total_ms": 0.0,
                "max_ms": 0.0,
                "last_status": status_code,
                "status_counts": {},
            }
            stats[key] = entry
        entry["count"] += 1
        entry["total_ms"] += elapsed_ms
        entry["max_ms"] = max(entry["max_ms"], elapsed_ms)
        entry["last_status"] = status_code
        status_counts = entry["status_counts"]
        status_key = str(status_code)
        status_counts[status_key] = int(status_counts.get(status_key, 0)) + 1

    def _flush_request_log_summary(app: FastAPI, force: bool = False) -> None:
        # 누적된 요청 통계를 주기적으로 로그로 남긴다.
        # force=True일 때는 서버 종료 직전처럼 즉시 강제 flush를 수행한다.
        stats = app.state.request_log_stats
        if not stats:
            return
        now = monotonic()
        elapsed = now - app.state.request_log_last_flush
        # 설정된 간격보다 짧으면 아직 flush할 시점이 아니므로 아무 것도 하지 않는다.
        if not force and elapsed < SERVER_REQUEST_LOG_SUMMARY_INTERVAL_SECONDS:
            return
        for (client_host, method, path), entry in list(stats.items()):
            # 각 요청 패턴별로 평균/최대 응답시간과 마지막 상태 코드를 계산한다.
            count = int(entry["count"])
            if count <= 0:
                continue
            average_ms = float(entry["total_ms"]) / count
            max_ms = float(entry["max_ms"])
            last_status = int(entry["last_status"])
            status_counts = {
                str(status): int(status_count)
                for status, status_count in dict(entry.get("status_counts", {})).items()
            }
            non_ok_statuses = {
                status: status_count
                for status, status_count in status_counts.items()
                if status != "200"
            }
            log_line(
                "REQ-SUM",
                client=client_host,
                path=path,
                method=method,
                count=count,
                avg=f"{average_ms:.1f}ms",
                max=f"{max_ms:.1f}ms",
                last_status=last_status,
                statuses=(
                    ",".join(
                        f"{status}:{status_count}"
                        for status, status_count in sorted(non_ok_statuses.items())
                    )
                    or None
                ),
                window=f"{elapsed:.1f}s",
            )
        stats.clear()
        app.state.request_log_last_flush = now

    def _summarized_request_path(request: Request, raw_path: str) -> str:
        # 요청 경로를 요약용으로 정규화한다.
        # 특정 경로만 통계에 포함하도록 허용 목록과 비교해, 노이즈를 줄인 요약 로그를 남긴다.
        route = request.scope.get("route")
        route_path = str(getattr(route, "path", "") or "").strip()
        if route_path in SERVER_REQUEST_LOG_SUMMARY_PATHS:
            return route_path
        if raw_path in SERVER_REQUEST_LOG_SUMMARY_PATHS:
            return raw_path
        return ""

    @app.middleware("http")
    async def log_requests(request: Request, call_next):
        # 모든 HTTP 요청이 도달하기 전에 시작 시간을 기록한다.
        # 이후 응답이 나가거나 예외가 발생했을 때의 소요 시간을 측정한다.
        started_at = perf_counter()
        client_host = request.client.host if request.client else "-"
        method = request.method.upper()
        path = request.url.path
        query = request.url.query
        display_path = f"{path}?{query}" if query else path
        try:
            # 실제 라우팅/핸들러 실행을 수행한다.
            response = await call_next(request)
        except Exception as error:
            # 예외가 발생하면 500 응답으로 기록하고, 원인을 로그에 남긴 뒤 그대로 전파한다.
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
        # 통계 요약 대상 경로인지 확인한 뒤, 필요하면 집계하고 즉시 로그를 남긴다.
        summary_path = _summarized_request_path(request, path)
        if summary_path:
            _record_request_summary(
                app,
                client_host=client_host,
                path=summary_path,
                method=method,
                elapsed_ms=elapsed_ms,
                status_code=response.status_code,
            )
            _flush_request_log_summary(app)
            if response.status_code < SERVER_REQUEST_LOG_IMMEDIATE_MIN_STATUS:
                return response

            log_line(
                "REQ",
                client=client_host,
                method=method,
                path=display_path,
                status=response.status_code,
                duration=f"{elapsed_ms:.1f}ms",
            )
        else:
            log_line(
                "REQ",
                client=client_host,
                method=method,
                path=display_path,
                status=response.status_code,
                duration=f"{elapsed_ms:.1f}ms",
            )
        return response


@app.get("/health", response_model=HealthResponse)
def health() -> HealthResponse:
    # 서버가 정상적으로 살아 있는지 확인하기 위한 간단한 상태 엔드포인트이다.
    # 클라이언트나 운영 환경에서 서비스 가용성을 점검할 때 사용한다.
    return HealthResponse(
        status="ok",
        event_log_path=str(DATABASE_PATH),
        event_log_exists=DATABASE_PATH.exists(),
    )
