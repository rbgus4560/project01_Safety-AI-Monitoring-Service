# 분석 파이프라인 안에서 사용하는 event_serializer 기능을 분리한 파일입니다.
# pipeline.py에서 조립되는 분석 부품 중 하나입니다.

from datetime import datetime
from enum import Enum

from core.detection_model import Box, Detection
from core.event_rule import Event

# 이 파일은 Event 객체를 JSON 저장과 HTTP 전송에 맞는 순수 dict 구조로 바꿉니다.
# JsonEventHandler와 HttpEventHandler가 같은 직렬화 로직을 공유하기 위해 사용합니다.


def serialize_box(box: Box | None) -> dict[str, int | None] | None:
    # JSON에는 파이썬 객체를 그대로 넣지 않고 값만 남깁니다.
    if box is None:
        return None

    return {
        "x1": box.x1,
        "y1": box.y1,
        "x2": box.x2,
        "y2": box.y2,
    }


def serialize_detection(detection: Detection) -> dict[str, object]:
    return {
        "name": detection.name,
        "score": detection.score,
        "track_id": detection.track_id,
        "box": serialize_box(detection.box),
    }


def serialize_event(event: Event) -> dict[str, object]:
    # Event -> dict 변환의 공통 진입점입니다.
    # 서버 전송 모드와 로컬 JSONL 모드가 같은 스키마를 쓰도록 맞춰 줍니다.
    return {
        "event_key": getattr(event, "event_key", None),
        "event_type": _serialize_value(getattr(event, "event_type", None)),
        "status": _serialize_value(getattr(event, "status", None)),
        "level": _serialize_value(getattr(event, "level", None)),
        "message": getattr(event, "message", None),
        "frame_id": getattr(event, "frame_id", None),
        "person_id": getattr(event, "person_id", None),
        "created_at": _serialize_value(getattr(event, "created_at", None)),
        "started_at": _serialize_value(getattr(event, "started_at", None)),
        "ended_at": _serialize_value(getattr(event, "ended_at", None)),
        "duration_seconds": getattr(event, "duration_seconds", None),
        "started_frame_id": getattr(event, "started_frame_id", None),
        "ended_frame_id": getattr(event, "ended_frame_id", None),
        "clip_path": getattr(event, "clip_path", None),
        "source_type": getattr(event, "source_type", None),
        "source_value": getattr(event, "source_value", None),
        "source_key": getattr(event, "source_key", None),
        "client_id": getattr(event, "client_id", None),
        "session_id": getattr(event, "session_id", None),
        "source_time_seconds": getattr(event, "source_time_seconds", None),
        "source_time_text": getattr(event, "source_time_text", None),
        "started_source_time_text": getattr(
            event, "started_source_time_text", None
        ),
        "ended_source_time_text": getattr(event, "ended_source_time_text", None),
        "related_detections": [
            serialize_detection(detection)
            for detection in getattr(event, "related_detections", [])
        ],
    }


def _serialize_value(value: object) -> object:
    # Enum, datetime 같은 파이썬 전용 타입을 JSON에 맞는 값으로 바꿉니다.
    if value is None:
        return None
    if isinstance(value, Enum):
        return value.value
    if isinstance(value, datetime):
        return value.isoformat()
    return value
