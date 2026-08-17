# source_status 관련 API 엔드포인트를 모아둔 파일입니다.
# @router.get/post 아래 함수들이 실제 HTTP 요청을 처리하는 부분입니다.

from typing import Any

from fastapi import APIRouter, Body, HTTPException, Query, Request

from app.client_auth import verify_client_request
from app.config import DATABASE_PATH
from app.connection_audit import log_status_receive, request_host
from app.database import list_source_statuses, upsert_source_status
from app.realtime_hub import realtime_update_hub
from app.server_event_processor import server_event_processor
from app.schemas import (
    SourceStatusItem,
    SourceStatusListResponse,
    SourceStatusUpsertResponse,
)

router = APIRouter(prefix="/api/source-status", tags=["source-status"])


@router.post("", response_model=SourceStatusUpsertResponse)
def upsert_status(
    request: Request,
    status_record: dict[str, Any] = Body(...),
) -> SourceStatusUpsertResponse:
    if not status_record:
        raise HTTPException(status_code=400, detail="status record is required")

    source_key = str(status_record.get("source_key", "")).strip()
    if not source_key:
        raise HTTPException(status_code=400, detail="source_key is required")

    verify_client_request(request, str(status_record.get("client_id", "")))

    saved_record = upsert_source_status(DATABASE_PATH, status_record)
    log_status_receive(status_record=saved_record, remote_host=request_host(request))
    realtime_update_hub.publish(
        "source_status_changed",
        source_key=str(saved_record.get("source_key", "")).strip(),
        state=str(saved_record.get("state", "")).strip(),
        is_running=bool(saved_record.get("is_running", False)),
    )
    if not bool(saved_record.get("is_running", False)):
        state = str(saved_record.get("state", "")).strip().lower()
        if state in {"completed", "stopped", "disconnected", "error", "source_changed"}:
            server_event_processor.close_source(
                str(saved_record.get("source_key", "")).strip()
            )
    return SourceStatusUpsertResponse(ok=True, item=saved_record)


@router.get("", response_model=SourceStatusListResponse)
def list_source_status(
    client_id: str | None = Query(default=None),
    session_id: str | None = Query(default=None),
) -> SourceStatusListResponse:
    records = list_source_statuses(
        DATABASE_PATH,
        client_id=client_id,
        session_id=session_id,
    )
    items = [
        SourceStatusItem(
            source_key=str(record.get("source_key", "")).strip(),
            source_type=str(record.get("source_type", "")).strip(),
            source_value=str(record.get("source_value", "")).strip(),
            client_id=str(record.get("client_id", "")).strip(),
            session_id=str(record.get("session_id", "")).strip(),
            state=str(record.get("state", "")).strip() or "idle",
            is_running=bool(record.get("is_running", False)),
            source_fps=_read_float(record.get("source_fps")),
            source_duration_seconds=_read_float(record.get("source_duration_seconds")),
            last_frame_id=_read_int(record.get("last_frame_id"), default=-1),
            last_source_time_seconds=_read_float(
                record.get("last_source_time_seconds")
            ),
            error_message=str(record.get("error_message", "")).strip(),
            updated_at=str(record.get("updated_at", "")).strip(),
        )
        for record in records
    ]
    items.sort(key=lambda item: (item.updated_at, item.source_key), reverse=True)
    return SourceStatusListResponse(count=len(items), items=items)


def _read_float(value: object) -> float:
    if isinstance(value, float):
        return value
    if isinstance(value, int):
        return float(value)
    if isinstance(value, str):
        try:
            return float(value)
        except ValueError:
            return 0.0
    return 0.0


def _read_int(value: object, *, default: int = 0) -> int:
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(value)
    if isinstance(value, str):
        try:
            return int(value)
        except ValueError:
            return default
    return default
