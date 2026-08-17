# admin 관련 API 엔드포인트를 모아둔 파일입니다.
# @router.get/post 아래 함수들이 실제 HTTP 요청을 처리하는 부분입니다.

from fastapi import APIRouter, Body, HTTPException, Request
import json

from app.config import (
    CLIENT_CLIP_DIR,
    DATABASE_PATH,
    CLIENT_SETTINGS_PATH,
    ensure_client_dirs,
)
from app.database import reset_source_data
from app.log_utils import log_line
from app.reporting_api import remote_server_reporter
from app.schemas import (
    RemoteServerConfigResponse,
    ResetDataResponse,
)

# 이 파일은 source_key 기준으로 서버 저장소를 초기화하는 관리용 API를 제공합니다.

router = APIRouter(prefix="/api/admin", tags=["admin"])


@router.post("/reset-data", response_model=ResetDataResponse)
def reset_data(
    payload: dict = Body(...),
) -> ResetDataResponse:
    ensure_client_dirs()

    source_key = str(payload.get("source_key", "")).strip()
    source_slug = str(payload.get("source_slug", "")).strip()
    if not source_key:
        raise HTTPException(status_code=400, detail="source_key is required")

    cleared_events, deleted_event_count, deleted_clip_count = reset_source_data(
        DATABASE_PATH,
        source_key=source_key,
        source_slug=source_slug,
        server_clip_dir=CLIENT_CLIP_DIR,
    )

    return ResetDataResponse(
        ok=True,
        source_key=source_key,
        cleared_events=cleared_events,
        deleted_event_count=deleted_event_count,
        deleted_clip_count=deleted_clip_count,
    )


@router.put("/remote-server", response_model=RemoteServerConfigResponse)
def update_remote_server(
    request: Request,
    payload: dict = Body(...),
) -> RemoteServerConfigResponse:
    next_base_url = str(payload.get("remote_server_base_url", "")).strip().rstrip("/")
    if not next_base_url:
        raise HTTPException(
            status_code=400,
            detail="remote_server_base_url is required",
        )

    remote_server_reporter.set_base_url(next_base_url)
    settings_payload: dict[str, object] = {}
    if CLIENT_SETTINGS_PATH.exists():
        try:
            decoded = json.loads(CLIENT_SETTINGS_PATH.read_text(encoding="utf-8"))
            if isinstance(decoded, dict):
                settings_payload.update(decoded)
        except json.JSONDecodeError:
            settings_payload = {}
    settings_payload["remote_server_base_url"] = next_base_url
    CLIENT_SETTINGS_PATH.write_text(
        json.dumps(
            settings_payload,
            ensure_ascii=True,
            indent=2,
        ),
        encoding="utf-8",
    )

    manager = getattr(request.app.state, "source_manager", None)
    if manager is not None:
        try:
            manager.sync_all_to_server()
        except Exception as error:
            log_line(
                "WARN",
                message="remote server changed but source sync failed",
                error=error,
            )

    return RemoteServerConfigResponse(
        ok=True,
        remote_server_base_url=next_base_url,
    )
