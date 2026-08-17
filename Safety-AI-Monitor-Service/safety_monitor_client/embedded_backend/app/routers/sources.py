# sources 관련 API 엔드포인트를 모아둔 파일입니다.
# @router.get/post 아래 함수들이 실제 HTTP 요청을 처리하는 부분입니다.

from pathlib import Path
from uuid import uuid4
from fastapi import APIRouter, File, Form, HTTPException, Query, Request, UploadFile

from app.config import CLIENT_SOURCE_CACHE_DIR, CLIENT_UPLOAD_SOURCE_DIR
from app.log_utils import log_line
from app.realtime_hub import realtime_update_hub
from app.schemas import (
    SourceActionResponse,
    SourceConfigUpdateRequest,
    SourceCreateRequest,
    SourceDisplayNameUpdateRequest,
    SourceItem,
    SourceListResponse,
    SourceUpsertResponse,
)
from app.source_manager import AnalysisSourceManager
from app.source_rule_config import normalize_rule_config

router = APIRouter(prefix="/api/sources", tags=["sources"])


def _manager_from_request(request: Request) -> AnalysisSourceManager:
    manager = getattr(request.app.state, "source_manager", None)
    if not isinstance(manager, AnalysisSourceManager):
        raise HTTPException(status_code=500, detail="source manager is not ready")
    return manager


@router.get("", response_model=SourceListResponse)
def list_sources(request: Request) -> SourceListResponse:
    manager = _manager_from_request(request)
    records = manager.list_registered_sources()
    items = [SourceItem(**_decorate_source_record(record)) for record in records]
    return SourceListResponse(count=len(items), items=items)


@router.post("", response_model=SourceUpsertResponse)
def register_source(
    payload: SourceCreateRequest,
    request: Request,
) -> SourceUpsertResponse:
    manager = _manager_from_request(request)
    item = manager.register_source(
        source_type=payload.source_type,
        source_value=payload.source_value,
        client_id=payload.client_id,
        session_id=payload.session_id,
        reset_existing=payload.reset_existing,
        start_immediately=payload.start_immediately,
    )
    realtime_update_hub.publish(
        "source_changed",
        action="registered",
        source_key=str(item.get("source_key", "")).strip(),
    )
    return SourceUpsertResponse(ok=True, item=SourceItem(**_decorate_source_record(item)))


@router.post("/upload", response_model=SourceUpsertResponse)
async def upload_video_source(
    request: Request,
    file: UploadFile = File(...),
    client_id: str = Form(default=""),
    session_id: str = Form(default=""),
    reset_existing: bool = Form(default=True),
    start_immediately: bool = Form(default=True),
) -> SourceUpsertResponse:
    filename = Path(file.filename or "uploaded_video.mp4").name
    suffix = Path(filename).suffix.lower() or ".mp4"
    saved_path = CLIENT_UPLOAD_SOURCE_DIR / f"{uuid4().hex}{suffix}"
    CLIENT_UPLOAD_SOURCE_DIR.mkdir(parents=True, exist_ok=True)
    try:
        with saved_path.open("wb") as output:
            while True:
                chunk = await file.read(1024 * 1024)
                if not chunk:
                    break
                output.write(chunk)
    finally:
        await file.close()
    if not saved_path.exists() or saved_path.stat().st_size <= 0:
        saved_path.unlink(missing_ok=True)
        raise HTTPException(status_code=400, detail="uploaded file is empty")

    manager = _manager_from_request(request)
    try:
        item = manager.register_source(
            source_type="video",
            source_value=str(saved_path.resolve()),
            client_id=client_id,
            session_id=session_id,
            reset_existing=reset_existing,
            start_immediately=start_immediately,
        )
    except Exception as error:
        saved_path.unlink(missing_ok=True)
        raise HTTPException(status_code=400, detail=str(error)) from error
    realtime_update_hub.publish("source_changed", action="registered", source_key=str(item.get("source_key", "")).strip())
    return SourceUpsertResponse(ok=True, item=SourceItem(**_decorate_source_record(item)))


def _decorate_source_record(record: dict) -> dict:
    next_record = dict(record)
    next_record["rule_config"] = normalize_rule_config(next_record.get("rule_config"))
    source_type = str(next_record.get("source_type", "")).strip().lower()
    source_value = str(next_record.get("source_value", "")).strip()
    next_record["server_media_path"] = ""
    next_record["media_url"] = ""
    source_key = str(next_record.get("source_key", "")).strip()
    next_record["preview_url"] = (
        f"/api/source-previews/latest?source_key={source_key}"
        if source_key
        else ""
    )

    if source_type != "video" or not source_value:
        return next_record

    try:
        media_path = Path(source_value).resolve()
    except OSError:
        return next_record

    uploaded_root = CLIENT_UPLOAD_SOURCE_DIR.resolve()
    cached_root = CLIENT_SOURCE_CACHE_DIR.resolve()
    try:
        media_path.relative_to(uploaded_root)
        next_record["server_media_path"] = f"uploaded_sources/{media_path.name}"
        next_record["media_url"] = f"/api/source-media/uploaded/{media_path.name}"
        return next_record
    except ValueError:
        pass

    try:
        media_path.relative_to(cached_root)
        next_record["server_media_path"] = f"source_cache/{media_path.name}"
        next_record["media_url"] = f"/api/source-media/cached/{media_path.name}"
    except ValueError:
        pass

    return next_record


@router.patch("/{source_key:path}/display-name", response_model=SourceUpsertResponse)
def update_source_display_name(
    source_key: str,
    payload: SourceDisplayNameUpdateRequest,
    request: Request,
) -> SourceUpsertResponse:
    manager = _manager_from_request(request)
    try:
        item = manager.update_source_display_name(source_key, display_name=payload.display_name)
    except KeyError as error:
        raise HTTPException(status_code=404, detail="source not found") from error
    realtime_update_hub.publish("source_changed", action="display_name_updated", source_key=source_key.strip())
    return SourceUpsertResponse(ok=True, item=SourceItem(**_decorate_source_record(item)))


@router.post("/{source_key:path}/start", response_model=SourceActionResponse)
def start_source(source_key: str, request: Request) -> SourceActionResponse:
    manager = _manager_from_request(request)
    log_line("SRC", action="api-start", source=source_key.strip())
    try:
        manager.start_source(source_key)
    except KeyError as error:
        raise HTTPException(status_code=404, detail="source not found") from error
    realtime_update_hub.publish(
        "source_changed",
        action="started",
        source_key=source_key.strip(),
    )
    return SourceActionResponse(ok=True, source_key=source_key, state="starting")


@router.post("/{source_key:path}/stop", response_model=SourceActionResponse)
def stop_source(source_key: str, request: Request) -> SourceActionResponse:
    manager = _manager_from_request(request)
    log_line("SRC", action="api-stop", source=source_key.strip())
    record = manager.stop_source(source_key)
    if record is None:
        raise HTTPException(status_code=404, detail="source not found")
    realtime_update_hub.publish(
        "source_changed",
        action="stopped",
        source_key=source_key.strip(),
    )
    return SourceActionResponse(ok=True, source_key=source_key, state="stopped")


@router.post("/{source_key:path}/restart", response_model=SourceActionResponse)
def restart_source(source_key: str, request: Request) -> SourceActionResponse:
    manager = _manager_from_request(request)
    log_line("SRC", action="api-restart", source=source_key.strip())
    try:
        manager.restart_source(source_key)
    except KeyError as error:
        raise HTTPException(status_code=404, detail="source not found") from error
    realtime_update_hub.publish(
        "source_changed",
        action="restarted",
        source_key=source_key.strip(),
    )
    return SourceActionResponse(ok=True, source_key=source_key, state="starting")


@router.patch("/{source_key:path}/config", response_model=SourceUpsertResponse)
def update_source_config(
    source_key: str,
    payload: SourceConfigUpdateRequest,
    request: Request,
) -> SourceUpsertResponse:
    manager = _manager_from_request(request)
    try:
        item = manager.update_source_rule_config(
            source_key,
            rule_config=payload.rule_config,
        )
    except KeyError as error:
        raise HTTPException(status_code=404, detail="source not found") from error
    realtime_update_hub.publish(
        "source_changed",
        action="config_updated",
        source_key=source_key.strip(),
    )
    return SourceUpsertResponse(ok=True, item=SourceItem(**_decorate_source_record(item)))


@router.delete("/{source_key:path}", response_model=SourceActionResponse)
def delete_source(
    source_key: str,
    request: Request,
    clear_data: bool = Query(default=False),
) -> SourceActionResponse:
    manager = _manager_from_request(request)
    log_line("SRC", action="api-delete", source=source_key.strip())
    ok = manager.remove_source(source_key, clear_data=clear_data)
    if not ok:
        raise HTTPException(status_code=404, detail="source not found")
    realtime_update_hub.publish(
        "source_changed",
        action="deleted",
        source_key=source_key.strip(),
    )
    return SourceActionResponse(ok=True, source_key=source_key, state="deleted")
