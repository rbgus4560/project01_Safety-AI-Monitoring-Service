# 분석 파이프라인 안에서 사용하는 event_rule 기능을 분리한 파일입니다.
# pipeline.py에서 조립되는 분석 부품 중 하나입니다.

from abc import ABC, abstractmethod
from dataclasses import dataclass
from datetime import datetime

from core.detection_model import Detection
from core.event_types import EventLevel, EventStatus, EventType

# 이 파일은 이벤트 공통 구조와 EventRule 인터페이스를 정의합니다.
# 룰은 DetectionResult를 받아 Event 목록으로 바꾸는 역할만 담당합니다.

@dataclass
class Event:
    # 룰이 만든 이벤트 공통 구조입니다.
    # 이후 EventFilter가 START/ACTIVE/END 상태를 관리하고, EventHandler가 후처리합니다.
    event_type: EventType
    message: str
    frame_id: int
    created_at: datetime
    level: EventLevel
    related_detections: list[Detection]
    status: EventStatus = EventStatus.ACTIVE
    started_at: datetime | None = None
    ended_at: datetime | None = None
    duration_seconds: float = 0.0
    event_key: str = ""
    started_frame_id: int | None = None
    ended_frame_id: int | None = None
    clip_path: str = ""
    source_time_seconds: float = 0.0
    source_time_text: str = ""
    started_source_time_text: str = ""
    ended_source_time_text: str = ""

    def __post_init__(self) -> None:
        if self.started_at is None:
            self.started_at = self.created_at
        if self.started_frame_id is None:
            self.started_frame_id = self.frame_id
        if not self.event_key:
            self.event_key = self.event_type.value
        if not self.started_source_time_text:
            self.started_source_time_text = self.source_time_text

    @property
    def person_id(self) -> int | None:
        # 현재 구조에서는 첫 번째 관련 탐지의 track_id를 대표 person_id로 사용합니다.
        if not self.related_detections:
            return None
        return self.related_detections[0].track_id


class EventRule(ABC):
    # 새로운 위험상황을 추가하려면 EventRule을 상속받고 check()에서 Event 목록을 반환하면 됩니다.

    @abstractmethod
    def check(self, result) -> list[Event]:
        pass

    @abstractmethod
    def get_name(self) -> str:
        pass
