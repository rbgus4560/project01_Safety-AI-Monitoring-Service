# events 관련 API 엔드포인트를 모아둔 파일입니다.
# @router.get/post 아래 함수들이 실제 HTTP 요청을 처리하는 부분입니다.

from typing import Any

from fastapi import APIRouter, Body, HTTPException, Query

from app.config import DATABASE_PATH
from app.database import (
    find_events_by_key,
    get_latest_event_by_key,
    list_events as list_events_from_db,
    list_latest_events as list_latest_events_from_db,
    list_source_summaries,
)
from app.schemas import (
    EventCreateResponse,
    EventDetailResponse,
    EventHistoryResponse,
    EventListResponse,
    SourceSummaryItem,
    SourceSummaryListResponse,
)

# 이 파일은 이벤트 저장/조회 API를 담당합니다.
# POST /api/events는 외부 생성 요청을 막고, 이벤트 조회 API만 제공합니다.

router = APIRouter(prefix="/api/events", tags=["events"])


@router.post("", response_model=EventCreateResponse)
def create_event(
    event_record: dict[str, Any] = Body(...),
) -> EventCreateResponse:
    # 클라이언트 내장 백엔드는 이벤트를 생성하지 않습니다.
    # 이벤트 판정/저장/클립 생성은 중앙 서버가 frame_detections를 받아 처리합니다.
    raise HTTPException(
        status_code=410,
        detail="client does not create events; server derives events from frame detections",
    )


@router.get("", response_model=EventListResponse)
def list_events(
    latest_only: bool = False,
    limit: int | None = Query(default=None, ge=1),
    event_type: str | None = None,
    status: str | None = None,
    source_key: str | None = None,
    source_type: str | None = None,
    client_id: str | None = None,
    session_id: str | None = None,
) -> EventListResponse:
    # GET은 서버에서 데이터를 가져오는 요청입니다.
    if latest_only:
        items = list_latest_events_from_db(
            DATABASE_PATH,
            event_type=event_type,
            status=status,
            source_key=source_key,
            source_type=source_type,
            client_id=client_id,
            session_id=session_id,
        )
    else:
        items = list_events_from_db(
            DATABASE_PATH,
            event_type=event_type,
            status=status,
            source_key=source_key,
            source_type=source_type,
            client_id=client_id,
            session_id=session_id,
        )

    if limit is not None:
        items = items[-limit:]

    return EventListResponse(count=len(items), items=items)


@router.get("/latest", response_model=EventListResponse)
def list_latest_events(
    limit: int | None = Query(default=None, ge=1),
    event_type: str | None = None,
    status: str | None = None,
    source_key: str | None = None,
    source_type: str | None = None,
    client_id: str | None = None,
    session_id: str | None = None,
) -> EventListResponse:
    items = list_latest_events_from_db(
        DATABASE_PATH,
        event_type=event_type,
        status=status,
        source_key=source_key,
        source_type=source_type,
        client_id=client_id,
        session_id=session_id,
    )

    if limit is not None:
        items = items[-limit:]

    return EventListResponse(count=len(items), items=items)


@router.get("/sources", response_model=SourceSummaryListResponse)
def list_sources(
    client_id: str | None = None,
    session_id: str | None = None,
) -> SourceSummaryListResponse:
    items = list_source_summaries(
        DATABASE_PATH,
        client_id=client_id,
        session_id=session_id,
    )
    ordered_items = [SourceSummaryItem(**item) for item in items]
    return SourceSummaryListResponse(count=len(ordered_items), items=ordered_items)


@router.get("/detail", response_model=EventDetailResponse | EventHistoryResponse)
def get_event_detail(
    event_key: str = Query(min_length=1),
    latest_only: bool = True,
    source_key: str | None = None,
) -> EventDetailResponse | EventHistoryResponse:
    # event_key 하나를 기준으로 최신 1건 또는 전체 이력을 조회합니다.
    normalized_event_key = event_key.strip()
    if not normalized_event_key:
        raise HTTPException(status_code=400, detail="event_key is required")

    if latest_only:
        item = get_latest_event_by_key(
            DATABASE_PATH,
            normalized_event_key,
            source_key=source_key,
        )
        if item is None:
            raise HTTPException(status_code=404, detail="event_key not found")

        return EventDetailResponse(event_key=normalized_event_key, item=item)

    items = find_events_by_key(
        DATABASE_PATH,
        normalized_event_key,
        source_key=source_key,
    )
    if not items:
        raise HTTPException(status_code=404, detail="event_key not found")

    return EventHistoryResponse(
        event_key=normalized_event_key,
        count=len(items),
        items=items,
    )
