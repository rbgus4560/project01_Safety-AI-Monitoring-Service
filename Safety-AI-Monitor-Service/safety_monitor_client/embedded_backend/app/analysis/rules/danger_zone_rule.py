# 탐지 결과가 특정 안전 룰에 해당하는지 판단하는 파일입니다.
# 조건 판정과 이벤트 생성 흐름이 이 파일에 들어 있습니다.

from datetime import datetime

from core.detection_model import Detection, DetectionResult
from core.event_rule import Event, EventRule
from core.event_types import EventLevel, EventType

# 이 파일은 사람 중심점이 위험구역 ROI 안에 들어왔는지 검사하는 룰입니다.


class DangerZoneRule(EventRule):
    # ROI(rectangle, 사각형 구역) 안에 사람이 들어오면 DANGER_ZONE 이벤트를 만듭니다.
    def __init__(self, roi: tuple[int, int, int, int]) -> None:
        self.roi = roi

    def check(self, result: DetectionResult) -> list[Event]:
        events = []
        for detection in result.detections:
            if detection.name != "person":
                continue

            if self._is_center_in_roi(detection):
                events.append(
                    Event(
                        event_type=EventType.DANGER_ZONE,
                        message="위험구역 진입 이벤트 발생",
                        frame_id=result.frame_id,
                        created_at=result.event_created_at or datetime.now(),
                        level=EventLevel.DANGER,
                        related_detections=[detection],
                        source_time_seconds=result.source_time_seconds,
                        source_time_text=result.source_time_text,
                    )
                )

        return events

    def _is_center_in_roi(self, detection: Detection) -> bool:
        roi_x1, roi_y1, roi_x2, roi_y2 = self.roi
        center_x, center_y = detection.box.center()
        return roi_x1 <= center_x <= roi_x2 and roi_y1 <= center_y <= roi_y2

    def get_name(self) -> str:
        return "DangerZoneRule"
