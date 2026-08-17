# frame_detections 관련 API 엔드포인트를 모아둔 파일입니다.
# @router.get/post 아래 함수들이 실제 HTTP 요청을 처리하는 부분입니다.

from typing import Any

from fastapi import APIRouter, Body, HTTPException, Query, Request

from app.client_auth import verify_client_request
from app.config import DATABASE_PATH
from app.connection_audit import log_frame_receive, request_host
from app.database import (
    find_current_frame_detection,
    get_latest_frame_detection,
    insert_frame_detection,
)
from app.server_event_processor import server_event_processor
from app.schemas import FrameDetectionCreateResponse, FrameDetectionSnapshotResponse

router = APIRouter(prefix="/api/frame-detections", tags=["frame-detections"])


@router.post("", response_model=FrameDetectionCreateResponse)
def create_frame_detection(
    request: Request,
    frame_record: dict[str, Any] = Body(...),
) -> FrameDetectionCreateResponse:
    if not frame_record:
        raise HTTPException(status_code=400, detail="frame record is required")

    source_key = str(frame_record.get("source_key", "")).strip()
    if not source_key:
        raise HTTPException(status_code=400, detail="source_key is required")

    verify_client_request(request, str(frame_record.get("client_id", "")))

    if "frame_id" not in frame_record:
        raise HTTPException(status_code=400, detail="frame_id is required")

    saved_record = insert_frame_detection(DATABASE_PATH, frame_record)
    log_frame_receive(frame_record=saved_record, remote_host=request_host(request))
    server_event_processor.process_frame(saved_record)
    return FrameDetectionCreateResponse(ok=True, item=saved_record)


@router.get("/current", response_model=FrameDetectionSnapshotResponse)
def get_current_frame_detection(
    source_key: str = Query(min_length=1),
    source_time_seconds: float = Query(ge=0.0),
    tolerance_seconds: float = Query(default=0.12, ge=0.01, le=2.0),
) -> FrameDetectionSnapshotResponse:
    item = find_current_frame_detection(
        DATABASE_PATH,
        source_key=source_key,
        source_time_seconds=source_time_seconds,
        tolerance_seconds=tolerance_seconds,
    )
    return FrameDetectionSnapshotResponse(found=item is not None, item=item)


@router.get("/latest", response_model=FrameDetectionSnapshotResponse)
def get_latest_frame_detection_item(
    source_key: str = Query(min_length=1),
) -> FrameDetectionSnapshotResponse:
    item = get_latest_frame_detection(
        DATABASE_PATH,
        source_key=source_key,
    )
    return FrameDetectionSnapshotResponse(found=item is not None, item=item)
