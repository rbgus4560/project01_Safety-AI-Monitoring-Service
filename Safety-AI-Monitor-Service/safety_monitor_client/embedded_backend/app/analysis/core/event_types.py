# 분석 파이프라인 안에서 사용하는 event_types 기능을 분리한 파일입니다.
# pipeline.py에서 조립되는 분석 부품 중 하나입니다.

from enum import Enum


class EventType(Enum):
    NO_HELMET = "NO_HELMET"
    DANGER_ZONE = "DANGER_ZONE"
    FALL_DOWN = "FALL_DOWN"
    FIRE_DETECTED = "FIRE_DETECTED"
    SMOKE_DETECTED = "SMOKE_DETECTED"
    LOITERING = "LOITERING"
    UNKNOWN = "UNKNOWN"


class EventLevel(Enum):
    INFO = "INFO"
    WARNING = "WARNING"
    DANGER = "DANGER"
    CRITICAL = "CRITICAL"


class EventStatus(Enum):
    START = "START"
    ACTIVE = "ACTIVE"
    END = "END"
