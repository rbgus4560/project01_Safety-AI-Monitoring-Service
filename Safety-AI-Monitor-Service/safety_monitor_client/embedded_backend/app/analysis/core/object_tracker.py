# 분석 파이프라인 안에서 사용하는 object_tracker 기능을 분리한 파일입니다.
# pipeline.py에서 조립되는 분석 부품 중 하나입니다.

from dataclasses import dataclass

from core.detection_model import Box, Detection, DetectionResult

# 이 파일은 person 객체에만 간단한 추적 ID를 붙입니다.
# 현재 프로젝트는 사람별 event_key를 만들 때 이 track_id를 사용합니다.

@dataclass
class TrackState:
    # 이전 프레임에서 본 사람 위치와 박스 크기를 기억해 같은 사람인지 추정합니다.
    box: Box
    center_x: int
    center_y: int
    missed_frames: int


class PersonTracker:
    # IoU와 중심점 거리를 함께 사용하는 간단한 추적기입니다.
    # 박스 크기가 클수록 허용 이동 거리를 늘려 카메라 흔들림과 박스 떨림에 덜 민감하게 합니다.
    def __init__(self, max_distance: int = 100, max_missing_frames: int = 30) -> None:
        self.max_distance = max(1, max_distance)
        self.max_missing_frames = max(1, max_missing_frames)
        self.next_track_id = 1
        self.tracks: dict[int, TrackState] = {}

    def update(self, result: DetectionResult) -> DetectionResult:
        # person 객체에만 추적 ID를 붙여 이후 EventFilter와 로그가 사람별로 동작하게 합니다.
        person_detections = [
            detection
            for detection in result.detections
            if detection.name.strip().lower() == "person"
        ]
        if not person_detections:
            self._increase_missed_frames()
            self._remove_lost_tracks()
            return result

        unmatched_track_ids = set(self.tracks.keys())
        for detection in person_detections:
            matched_track_id = self._find_best_track(
                detection=detection,
                candidate_track_ids=unmatched_track_ids,
            )

            if matched_track_id is None:
                matched_track_id = self.next_track_id
                self.next_track_id += 1

            detection.track_id = matched_track_id
            center_x, center_y = detection.box.center()
            self.tracks[matched_track_id] = TrackState(
                box=detection.box,
                center_x=center_x,
                center_y=center_y,
                missed_frames=0,
            )
            unmatched_track_ids.discard(matched_track_id)

        for track_id in unmatched_track_ids:
            self.tracks[track_id].missed_frames += 1

        self._remove_lost_tracks()
        return result

    def _find_best_track(
        self,
        detection: Detection,
        candidate_track_ids: set[int],
    ) -> int | None:
        # IoU가 높으면 우선 같은 객체로 보고, IoU가 낮아도 박스 크기에 비례한 거리 안이면 이어 붙입니다.
        center_x, center_y = detection.box.center()
        best_track_id = None
        best_score = None

        for track_id in candidate_track_ids:
            track = self.tracks[track_id]
            iou = self._box_iou(detection.box, track.box)
            distance = abs(track.center_x - center_x) + abs(track.center_y - center_y)
            dynamic_distance = self._dynamic_distance_limit(detection.box, track.box)

            if iou < 0.10 and distance > dynamic_distance:
                continue

            score = (iou * 1000.0) - (distance / max(1.0, dynamic_distance))
            if best_score is None or score > best_score:
                best_score = score
                best_track_id = track_id

        return best_track_id

    def _dynamic_distance_limit(self, current_box: Box, previous_box: Box) -> float:
        current_size = max(current_box.width(), current_box.height())
        previous_size = max(previous_box.width(), previous_box.height())
        size_based_limit = max(current_size, previous_size) * 0.55
        return max(float(self.max_distance), float(size_based_limit))

    def _box_iou(self, left: Box, right: Box) -> float:
        inter_x1 = max(left.x1, right.x1)
        inter_y1 = max(left.y1, right.y1)
        inter_x2 = min(left.x2, right.x2)
        inter_y2 = min(left.y2, right.y2)
        inter_width = max(0, inter_x2 - inter_x1)
        inter_height = max(0, inter_y2 - inter_y1)
        inter_area = inter_width * inter_height
        if inter_area <= 0:
            return 0.0

        left_area = left.width() * left.height()
        right_area = right.width() * right.height()
        union_area = left_area + right_area - inter_area
        if union_area <= 0:
            return 0.0
        return inter_area / union_area

    def _increase_missed_frames(self) -> None:
        for track in self.tracks.values():
            track.missed_frames += 1

    def _remove_lost_tracks(self) -> None:
        lost_track_ids = [
            track_id
            for track_id, track in self.tracks.items()
            if track.missed_frames > self.max_missing_frames
        ]
        for track_id in lost_track_ids:
            del self.tracks[track_id]
