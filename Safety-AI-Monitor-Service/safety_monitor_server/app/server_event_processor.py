# 서버에서 탐지 결과를 기준으로 이벤트 시작과 종료를 판단하는 파일입니다.
# 룰 적용, 이벤트 저장, 클립 연결 흐름이 이 파일에 모여 있습니다.

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta
from threading import RLock
from typing import Any

from app.config import DATABASE_PATH
from app.database import get_source, insert_event, merge_latest_event
from app.event_normalizer import normalize_event_record
from app.realtime_hub import realtime_update_hub
from app.server_clip_recorder import server_clip_recorder
from app.source_rule_config import normalize_rule_config, to_roi_tuple


@dataclass
class _ActiveEventState:
    event_key: str
    event_type: str
    message: str
    level: str
    source_key: str
    source_slug: str
    source_type: str
    source_value: str
    client_id: str
    session_id: str
    person_id: int | None
    started_at: datetime
    last_seen_at: datetime
    started_frame_id: int
    last_frame_id: int
    source_time_seconds: float
    source_time_text: str
    started_source_time_text: str
    related_detections: list[dict[str, Any]]
    danger_zone_roi: dict[str, int] | None = None
    cooldown_seconds: float = 3.0
    missed_frames: int = 0


class ServerEventProcessor:
    def __init__(self, *, end_missing_frames: int = 5) -> None:
        self.end_missing_frames = max(1, end_missing_frames)
        self._lock = RLock()
        self._active_by_source_key: dict[str, dict[str, _ActiveEventState]] = {}
        self._cooldown_until_by_source_event: dict[str, datetime] = {}

    def process_frame(self, frame_record: dict[str, Any]) -> list[dict[str, Any]]:
        source_key = str(frame_record.get("source_key", "")).strip()
        if not source_key:
            return []

        source_record = get_source(DATABASE_PATH, source_key)
        if source_record is None:
            return []

        candidates = self._build_candidates(source_record=source_record, frame_record=frame_record)
        saved_events: list[dict[str, Any]] = []
        with self._lock:
            active_map = self._active_by_source_key.setdefault(source_key, {})
            seen_keys = set(candidates.keys())

            for match_key, candidate in candidates.items():
                active_state = active_map.get(match_key)
                if active_state is None:
                    cooldown_key = f"{source_key}|{str(candidate.get('event_type', '')).strip()}"
                    cooldown_until = self._cooldown_until_by_source_event.get(cooldown_key)
                    candidate_time = _parse_datetime(candidate.get("created_at")) or datetime.now()
                    if cooldown_until is not None and candidate_time < cooldown_until:
                        continue
                    reusable_key = self._find_reusable_active_key(
                        candidate=candidate,
                        active_map=active_map,
                        seen_keys=seen_keys,
                    )
                    if reusable_key is not None:
                        active_state = active_map.pop(reusable_key)
                        active_map[match_key] = active_state
                    else:
                        state = _ActiveEventState(
                            event_key=str(candidate.get("event_key", "")).strip(),
                            event_type=str(candidate["event_type"]),
                            message=str(candidate["message"]),
                            level=str(candidate["level"]),
                            source_key=source_key,
                            source_slug=str(candidate["source_slug"]),
                            source_type=str(candidate["source_type"]),
                            source_value=str(candidate["source_value"]),
                            client_id=str(candidate["client_id"]),
                            session_id=str(candidate["session_id"]),
                            person_id=_read_int_or_none(candidate.get("person_id")),
                            started_at=_parse_datetime(candidate.get("created_at")) or datetime.now(),
                            last_seen_at=_parse_datetime(candidate.get("created_at")) or datetime.now(),
                            started_frame_id=_read_int(candidate.get("frame_id"), default=-1),
                            last_frame_id=_read_int(candidate.get("frame_id"), default=-1),
                            source_time_seconds=_read_float(candidate.get("source_time_seconds")),
                            source_time_text=str(candidate.get("source_time_text", "")),
                            started_source_time_text=str(
                                candidate.get("started_source_time_text")
                                or candidate.get("source_time_text", "")
                            ),
                            related_detections=_normalize_detections(
                                candidate.get("related_detections")
                            ),
                            danger_zone_roi=_normalize_roi_dict(candidate.get("danger_zone_roi")),
                            cooldown_seconds=max(0.0, _read_float(candidate.get("event_cooldown_seconds"))),
                        )
                        active_map[match_key] = state
                        saved_events.append(self._save_event(self._build_start_event(candidate)))
                        continue

                active_state.last_seen_at = _parse_datetime(candidate.get("created_at")) or datetime.now()
                active_state.last_frame_id = _read_int(candidate.get("frame_id"), default=-1)
                active_state.source_time_seconds = _read_float(candidate.get("source_time_seconds"))
                active_state.source_time_text = str(candidate.get("source_time_text", ""))
                active_state.related_detections = _normalize_detections(
                    candidate.get("related_detections")
                )
                active_state.danger_zone_roi = _normalize_roi_dict(candidate.get("danger_zone_roi"))
                active_state.missed_frames = 0

            ended_keys: list[str] = []
            for match_key, active_state in active_map.items():
                if match_key in seen_keys:
                    continue
                active_state.missed_frames += 1
                if active_state.missed_frames >= self.end_missing_frames:
                    end_event = self._build_end_event(active_state)
                    end_event.update(self._build_clip_fields(active_state))
                    saved_events.append(self._save_event(end_event))
                    if active_state.cooldown_seconds > 0:
                        self._cooldown_until_by_source_event[f"{source_key}|{active_state.event_type}"] = (
                            active_state.last_seen_at + timedelta(seconds=active_state.cooldown_seconds)
                        )
                    ended_keys.append(match_key)

            for match_key in ended_keys:
                active_map.pop(match_key, None)

            if not active_map:
                self._active_by_source_key.pop(source_key, None)

        return saved_events

    def _find_reusable_active_key(
        self,
        *,
        candidate: dict[str, Any],
        active_map: dict[str, _ActiveEventState],
        seen_keys: set[str],
    ) -> str | None:
        # tracker ID가 바뀌거나 탐지가 잠깐 끊긴 경우에도 같은 위치의 같은 룰 이벤트는 이어 붙입니다.
        candidate_type = str(candidate.get("event_type", "")).strip()
        if not candidate_type:
            return None
        candidate_roi = _normalize_roi_dict(candidate.get("danger_zone_roi"))
        candidate_detections = _normalize_detections(candidate.get("related_detections"))
        best_key = None
        best_score = 0.0
        for active_key, active_state in active_map.items():
            if active_key in seen_keys:
                continue
            if active_state.event_type != candidate_type:
                continue
            if active_state.danger_zone_roi != candidate_roi:
                continue
            score = _detection_similarity_score(
                active_state.related_detections,
                candidate_detections,
            )
            if score > best_score:
                best_score = score
                best_key = active_key
        if best_key is None or best_score < 0.20:
            return None
        return best_key

    def close_source(self, source_key: str) -> list[dict[str, Any]]:
        normalized_source_key = source_key.strip()
        if not normalized_source_key:
            return []
        with self._lock:
            active_map = self._active_by_source_key.pop(normalized_source_key, {})
        saved_events: list[dict[str, Any]] = []
        for active_state in active_map.values():
            end_event = self._build_end_event(active_state)
            end_event.update(self._build_clip_fields(active_state))
            saved_events.append(self._save_event(end_event))
            if active_state.cooldown_seconds > 0:
                self._cooldown_until_by_source_event[f"{normalized_source_key}|{active_state.event_type}"] = (
                    active_state.last_seen_at + timedelta(seconds=active_state.cooldown_seconds)
                )
        return saved_events

    def clear_source(self, source_key: str) -> None:
        normalized_source_key = source_key.strip()
        if not normalized_source_key:
            return
        with self._lock:
            self._active_by_source_key.pop(normalized_source_key, None)
        for key in list(self._cooldown_until_by_source_event):
            if key.startswith(f"{normalized_source_key}|"):
                self._cooldown_until_by_source_event.pop(key, None)
        server_clip_recorder.clear_source(normalized_source_key)

    def clear_all(self) -> None:
        with self._lock:
            self._active_by_source_key.clear()
            self._cooldown_until_by_source_event.clear()
        server_clip_recorder.clear_all()

    def _build_candidates(
        self,
        *,
        source_record: dict[str, Any],
        frame_record: dict[str, Any],
    ) -> dict[str, dict[str, Any]]:
        rule_config = normalize_rule_config(source_record.get("rule_config"))
        confidence_threshold = _read_float(rule_config.get("confidence_threshold"))
        cooldown_seconds = max(0.0, _read_float(rule_config.get("event_cooldown_seconds")))
        detections = [
            detection
            for detection in _normalize_detections(frame_record.get("detections"))
            if _read_float(detection.get("score")) >= confidence_threshold
        ]
        source_key = str(source_record.get("source_key", "")).strip()
        source_slug = str(source_record.get("source_slug", "")).strip()
        source_type = str(source_record.get("source_type", "")).strip()
        source_value = str(source_record.get("source_value", "")).strip()
        client_id = str(source_record.get("client_id", "")).strip()
        session_id = str(source_record.get("session_id", "")).strip()
        created_at = str(frame_record.get("received_at", "")).strip() or datetime.now().isoformat()
        frame_id = _read_int(frame_record.get("frame_id"), default=-1)
        source_time_seconds = _read_float(frame_record.get("source_time_seconds"))
        source_time_text = str(frame_record.get("source_time_text", "")).strip()

        candidates: dict[str, dict[str, Any]] = {}
        danger_zone_roi = to_roi_tuple(rule_config.get("danger_zone_roi"))

        if bool(rule_config.get("use_no_helmet_rule", True)):
            for event in _build_no_helmet_candidates(
                detections=detections,
                source_key=source_key,
                source_slug=source_slug,
                source_type=source_type,
                source_value=source_value,
                client_id=client_id,
                session_id=session_id,
                created_at=created_at,
                frame_id=frame_id,
                source_time_seconds=source_time_seconds,
                source_time_text=source_time_text,
            ):
                event["event_cooldown_seconds"] = cooldown_seconds
                candidates[str(event["match_key"])] = event
        if bool(rule_config.get("use_danger_zone_rule", False)) and danger_zone_roi is not None:
            for event in _build_danger_zone_candidates(
                detections=detections,
                roi=danger_zone_roi,
                source_key=source_key,
                source_slug=source_slug,
                source_type=source_type,
                source_value=source_value,
                client_id=client_id,
                session_id=session_id,
                created_at=created_at,
                frame_id=frame_id,
                source_time_seconds=source_time_seconds,
                source_time_text=source_time_text,
                danger_zone_roi=danger_zone_roi,
            ):
                event["event_cooldown_seconds"] = cooldown_seconds
                candidates[str(event["match_key"])] = event

        return _deduplicate_candidates(candidates)

    def _build_start_event(self, candidate: dict[str, Any]) -> dict[str, Any]:
        payload = dict(candidate)
        payload.pop("match_key", None)
        payload["status"] = "START"
        payload["started_at"] = payload.get("created_at")
        payload["ended_at"] = None
        payload["duration_seconds"] = 0.0
        payload["started_frame_id"] = payload.get("frame_id")
        payload["ended_frame_id"] = None
        return payload

    def _build_end_event(self, state: _ActiveEventState) -> dict[str, Any]:
        duration_seconds = max(
            0.0,
            (state.last_seen_at - state.started_at).total_seconds(),
        )
        return {
            "event_key": state.event_key,
            "event_type": state.event_type,
            "status": "END",
            "level": state.level,
            "message": state.message,
            "frame_id": state.last_frame_id,
            "person_id": state.person_id,
            "created_at": state.last_seen_at.isoformat(),
            "started_at": state.started_at.isoformat(),
            "ended_at": state.last_seen_at.isoformat(),
            "duration_seconds": duration_seconds,
            "started_frame_id": state.started_frame_id,
            "ended_frame_id": state.last_frame_id,
            "clip_path": "",
            "source_type": state.source_type,
            "source_value": state.source_value,
            "source_key": state.source_key,
            "source_slug": state.source_slug,
            "client_id": state.client_id,
            "session_id": state.session_id,
            "source_time_seconds": state.source_time_seconds,
            "source_time_text": state.source_time_text,
            "started_source_time_text": state.started_source_time_text,
            "ended_source_time_text": state.source_time_text,
            "related_detections": list(state.related_detections),
            "danger_zone_roi": state.danger_zone_roi,
        }

    def _build_clip_fields(self, state: _ActiveEventState) -> dict[str, object]:
        clip_fields = server_clip_recorder.encode_event_clip(
            source_key=state.source_key,
            source_slug=state.source_slug,
            event_key=state.event_key,
            started_at=state.started_at,
            ended_at=state.last_seen_at,
        )
        return clip_fields or {}

    def _save_event(self, event_record: dict[str, Any]) -> dict[str, Any]:
        normalized = normalize_event_record(event_record)
        saved_record = None
        if str(normalized.get("status", "")).strip().upper() == "END":
            saved_record = merge_latest_event(DATABASE_PATH, normalized)
        if saved_record is None:
            saved_record = insert_event(DATABASE_PATH, normalized)
        realtime_update_hub.publish(
            "event_changed",
            source_key=str(saved_record.get("source_key", "")).strip(),
            event_key=str(saved_record.get("event_key", "")).strip(),
            status=str(saved_record.get("status", "")).strip(),
            event_type=str(saved_record.get("event_type", "")).strip(),
        )
        return saved_record


def _build_no_helmet_candidates(
    *,
    detections: list[dict[str, Any]],
    source_key: str,
    source_slug: str,
    source_type: str,
    source_value: str,
    client_id: str,
    session_id: str,
    created_at: str,
    frame_id: int,
    source_time_seconds: float,
    source_time_text: str,
) -> list[dict[str, Any]]:
    candidates: list[dict[str, Any]] = []
    no_helmet_labels = {"no_helmet", "nohelmet", "without_helmet", "no helmet"}
    direct_detections = [
        detection
        for detection in detections
        if str(detection.get("name", "")).strip().lower() in no_helmet_labels
    ]
    if direct_detections:
        for detection in direct_detections:
            candidates.append(
                _build_candidate_event(
                    event_type="NO_HELMET",
                    level="WARNING",
                    message="안전모 미착용 의심 이벤트 발생",
                    detection=detection,
                    created_at=created_at,
                    frame_id=frame_id,
                    source_key=source_key,
                    source_slug=source_slug,
                    source_type=source_type,
                    source_value=source_value,
                    client_id=client_id,
                    session_id=session_id,
                    source_time_seconds=source_time_seconds,
                    source_time_text=source_time_text,
                )
            )
        return candidates

    persons = [
        detection
        for detection in detections
        if str(detection.get("name", "")).strip().lower() == "person"
    ]
    helmets = [
        detection
        for detection in detections
        if str(detection.get("name", "")).strip().lower() in {"helmet", "hardhat", "yes_helmet", "yes helmet"}
    ]
    heads = [
        detection
        for detection in detections
        if str(detection.get("name", "")).strip().lower() == "head"
    ]
    for person in persons:
        head_box = _make_head_box(_normalize_box(person.get("box")))
        if head_box is None:
            continue
        if any(_is_detection_in_box(head_box, helmet) for helmet in helmets):
            continue
        if heads and not any(_is_detection_in_box(head_box, head) for head in heads):
            continue
        candidates.append(
            _build_candidate_event(
                event_type="NO_HELMET",
                level="WARNING",
                message="안전모 미착용 의심 이벤트 발생",
                detection=person,
                created_at=created_at,
                frame_id=frame_id,
                source_key=source_key,
                source_slug=source_slug,
                source_type=source_type,
                source_value=source_value,
                client_id=client_id,
                session_id=session_id,
                source_time_seconds=source_time_seconds,
                source_time_text=source_time_text,
            )
        )
    return candidates


def _build_danger_zone_candidates(
    *,
    detections: list[dict[str, Any]],
    roi: tuple[int, int, int, int],
    source_key: str,
    source_slug: str,
    source_type: str,
    source_value: str,
    client_id: str,
    session_id: str,
    created_at: str,
    frame_id: int,
    source_time_seconds: float,
    source_time_text: str,
    danger_zone_roi: tuple[int, int, int, int],
) -> list[dict[str, Any]]:
    candidates: list[dict[str, Any]] = []
    target_labels = {"person"}
    for detection in detections:
        label = str(detection.get("name", "")).strip().lower()
        if label not in target_labels:
            continue
        box = _normalize_box(detection.get("box"))
        if box is None or not _box_intersects_roi(box, roi):
            continue
        candidate = _build_candidate_event(
            event_type="DANGER_ZONE",
            level="DANGER",
            message="위험구역 내 사람 감지",
            detection=detection,
            created_at=created_at,
            frame_id=frame_id,
            source_key=source_key,
            source_slug=source_slug,
            source_type=source_type,
            source_value=source_value,
            client_id=client_id,
            session_id=session_id,
            source_time_seconds=source_time_seconds,
            source_time_text=source_time_text,
            danger_zone_roi=danger_zone_roi,
        )
        candidates.append(candidate)
    return candidates


def _deduplicate_candidates(
    candidates: dict[str, dict[str, Any]],
) -> dict[str, dict[str, Any]]:
    # 같은 프레임에서 tracker id만 다르게 갈라진 같은 룰 이벤트를 하나로 합칩니다.
    merged: dict[str, dict[str, Any]] = {}
    for match_key, candidate in candidates.items():
        duplicate_key = _find_duplicate_candidate_key(candidate, merged)
        if duplicate_key is None:
            merged[match_key] = candidate
            continue
        existing = merged[duplicate_key]
        existing_detections = _normalize_detections(existing.get("related_detections"))
        next_detections = _normalize_detections(candidate.get("related_detections"))
        existing["related_detections"] = _merge_related_detections(
            existing_detections,
            next_detections,
        )
        if _candidate_confidence(candidate) > _candidate_confidence(existing):
            existing["person_id"] = candidate.get("person_id")
    return merged


def _find_duplicate_candidate_key(
    candidate: dict[str, Any],
    merged: dict[str, dict[str, Any]],
) -> str | None:
    candidate_type = str(candidate.get("event_type", "")).strip()
    candidate_roi = _normalize_roi_dict(candidate.get("danger_zone_roi"))
    candidate_detections = _normalize_detections(candidate.get("related_detections"))
    if not candidate_type or not candidate_detections:
        return None
    best_key = None
    best_score = 0.0
    for match_key, existing in merged.items():
        if str(existing.get("event_type", "")).strip() != candidate_type:
            continue
        if _normalize_roi_dict(existing.get("danger_zone_roi")) != candidate_roi:
            continue
        score = _detection_similarity_score(
            _normalize_detections(existing.get("related_detections")),
            candidate_detections,
        )
        if score > best_score:
            best_score = score
            best_key = match_key
    if best_key is None or best_score < 0.20:
        return None
    return best_key


def _merge_related_detections(
    left: list[dict[str, Any]],
    right: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    merged = [dict(item) for item in left]
    for detection in right:
        detection_box = _normalize_box(detection.get("box"))
        if detection_box is None:
            merged.append(dict(detection))
            continue
        if any(
            _box_similarity_score(existing_box, detection_box) >= 0.60
            for existing_box in (
                _normalize_box(item.get("box")) for item in merged
            )
            if existing_box is not None
        ):
            continue
        merged.append(dict(detection))
    return merged


def _candidate_confidence(candidate: dict[str, Any]) -> float:
    detections = _normalize_detections(candidate.get("related_detections"))
    confidence_values = [
        _read_float(detection.get("confidence"))
        for detection in detections
    ]
    return max(confidence_values) if confidence_values else 0.0


def _detection_similarity_score(
    previous_detections: list[dict[str, Any]],
    current_detections: list[dict[str, Any]],
) -> float:
    best_score = 0.0
    for previous in previous_detections:
        previous_box = _normalize_box(previous.get("box"))
        if previous_box is None:
            continue
        for current in current_detections:
            current_box = _normalize_box(current.get("box"))
            if current_box is None:
                continue
            score = _box_similarity_score(previous_box, current_box)
            best_score = max(best_score, score)
    return best_score


def _box_similarity_score(left: dict[str, int], right: dict[str, int]) -> float:
    iou = _box_iou(left, right)
    if iou >= 0.10:
        return max(0.20, iou)

    left_center_x = (int(left["x1"]) + int(left["x2"])) / 2.0
    left_center_y = (int(left["y1"]) + int(left["y2"])) / 2.0
    right_center_x = (int(right["x1"]) + int(right["x2"])) / 2.0
    right_center_y = (int(right["y1"]) + int(right["y2"])) / 2.0
    distance = abs(left_center_x - right_center_x) + abs(left_center_y - right_center_y)
    dynamic_limit = max(
        120.0,
        max(_box_width(left), _box_height(left), _box_width(right), _box_height(right)) * 0.75,
    )
    if distance > dynamic_limit:
        return 0.0
    return 0.20 + (0.30 * (1.0 - (distance / dynamic_limit)))


def _box_iou(left: dict[str, int], right: dict[str, int]) -> float:
    inter_x1 = max(int(left["x1"]), int(right["x1"]))
    inter_y1 = max(int(left["y1"]), int(right["y1"]))
    inter_x2 = min(int(left["x2"]), int(right["x2"]))
    inter_y2 = min(int(left["y2"]), int(right["y2"]))
    inter_width = max(0, inter_x2 - inter_x1)
    inter_height = max(0, inter_y2 - inter_y1)
    inter_area = inter_width * inter_height
    if inter_area <= 0:
        return 0.0
    union_area = (_box_width(left) * _box_height(left)) + (_box_width(right) * _box_height(right)) - inter_area
    if union_area <= 0:
        return 0.0
    return inter_area / union_area


def _box_width(box: dict[str, int]) -> int:
    return max(1, int(box["x2"]) - int(box["x1"]))


def _box_height(box: dict[str, int]) -> int:
    return max(1, int(box["y2"]) - int(box["y1"]))


def _box_intersects_roi(box: dict[str, int], roi: tuple[int, int, int, int]) -> bool:
    roi_x1, roi_y1, roi_x2, roi_y2 = roi
    return not (
        int(box["x2"]) < roi_x1
        or int(box["x1"]) > roi_x2
        or int(box["y2"]) < roi_y1
        or int(box["y1"]) > roi_y2
    )

def _build_candidate_event(
    *,
    event_type: str,
    level: str,
    message: str,
    detection: dict[str, Any],
    created_at: str,
    frame_id: int,
    source_key: str,
    source_slug: str,
    source_type: str,
    source_value: str,
    client_id: str,
    session_id: str,
    source_time_seconds: float,
    source_time_text: str,
    danger_zone_roi: tuple[int, int, int, int] | None = None,
) -> dict[str, Any]:
    person_id = _read_int_or_none(detection.get("track_id"))
    # 서버 이벤트는 카메라별 룰 상태를 기준으로 관리합니다.
    # tracker id가 흔들려도 같은 룰 이벤트가 여러 개로 갈라지지 않도록 match_key는 룰 단위로 고정합니다.
    match_key = event_type
    event_key = f"{match_key}:start:{frame_id}"
    return {
        "match_key": match_key,
        "event_key": event_key,
        "event_type": event_type,
        "status": "ACTIVE",
        "level": level,
        "message": message,
        "frame_id": frame_id,
        "person_id": person_id,
        "created_at": created_at,
        "started_at": created_at,
        "ended_at": None,
        "duration_seconds": 0.0,
        "started_frame_id": frame_id,
        "ended_frame_id": None,
        "clip_path": "",
        "source_type": source_type,
        "source_value": source_value,
        "source_key": source_key,
        "source_slug": source_slug,
        "client_id": client_id,
        "session_id": session_id,
        "source_time_seconds": source_time_seconds,
        "source_time_text": source_time_text,
        "started_source_time_text": source_time_text,
        "ended_source_time_text": "",
        "related_detections": [_normalize_detection(detection)],
        "danger_zone_roi": _roi_tuple_to_dict(danger_zone_roi),
    }


def _roi_tuple_to_dict(value: tuple[int, int, int, int] | None) -> dict[str, int] | None:
    if value is None:
        return None
    x1, y1, x2, y2 = value
    return {"x1": int(x1), "y1": int(y1), "x2": int(x2), "y2": int(y2)}


def _normalize_roi_dict(value: object) -> dict[str, int] | None:
    if not isinstance(value, dict):
        return None
    try:
        x1 = int(value.get("x1"))
        y1 = int(value.get("y1"))
        x2 = int(value.get("x2"))
        y2 = int(value.get("y2"))
    except (TypeError, ValueError):
        return None
    return {"x1": min(x1, x2), "y1": min(y1, y2), "x2": max(x1, x2), "y2": max(y1, y2)}
def _normalize_detections(value: object) -> list[dict[str, Any]]:
    if not isinstance(value, list):
        return []
    items: list[dict[str, Any]] = []
    for item in value:
        if not isinstance(item, dict):
            continue
        items.append(_normalize_detection(item))
    return items


def _normalize_detection(value: dict[str, Any]) -> dict[str, Any]:
    return {
        "name": str(value.get("name", "")).strip(),
        "score": _read_float(value.get("score")),
        "track_id": _read_int_or_none(value.get("track_id")),
        "box": _normalize_box(value.get("box")),
    }


def _normalize_box(value: object) -> dict[str, int] | None:
    if not isinstance(value, dict):
        return None
    try:
        x1 = int(value.get("x1"))
        y1 = int(value.get("y1"))
        x2 = int(value.get("x2"))
        y2 = int(value.get("y2"))
    except (TypeError, ValueError):
        return None
    left = min(x1, x2)
    right = max(x1, x2)
    top = min(y1, y2)
    bottom = max(y1, y2)
    if left == right or top == bottom:
        return None
    return {"x1": left, "y1": top, "x2": right, "y2": bottom}


def _make_head_box(person_box: dict[str, int] | None, head_ratio: float = 0.3) -> dict[str, int] | None:
    if person_box is None:
        return None
    head_height = max(1, int((person_box["y2"] - person_box["y1"]) * head_ratio))
    return {
        "x1": person_box["x1"],
        "y1": person_box["y1"],
        "x2": person_box["x2"],
        "y2": person_box["y1"] + head_height,
    }


def _is_detection_in_box(head_box: dict[str, int], detection: dict[str, Any], overlap_ratio: float = 0.2) -> bool:
    box = _normalize_box(detection.get("box"))
    if box is None:
        return False
    center_x = int((box["x1"] + box["x2"]) / 2)
    center_y = int((box["y1"] + box["y2"]) / 2)
    if (
        head_box["x1"] <= center_x <= head_box["x2"]
        and head_box["y1"] <= center_y <= head_box["y2"]
    ):
        return True

    overlap_x1 = max(head_box["x1"], box["x1"])
    overlap_y1 = max(head_box["y1"], box["y1"])
    overlap_x2 = min(head_box["x2"], box["x2"])
    overlap_y2 = min(head_box["y2"], box["y2"])
    overlap_width = max(0, overlap_x2 - overlap_x1)
    overlap_height = max(0, overlap_y2 - overlap_y1)
    overlap_area = overlap_width * overlap_height
    head_area = max(1, (head_box["x2"] - head_box["x1"]) * (head_box["y2"] - head_box["y1"]))
    return (overlap_area / head_area) >= overlap_ratio


def _parse_datetime(value: object) -> datetime | None:
    if isinstance(value, datetime):
        return value
    if isinstance(value, str):
        try:
            return datetime.fromisoformat(value.strip())
        except ValueError:
            return None
    return None


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


def _read_int_or_none(value: object) -> int | None:
    if value is None or value == "":
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(value)
    if isinstance(value, str):
        try:
            return int(value)
        except ValueError:
            return None
    return None


# 라이브 소스의 END 판정 타이밍을 클라이언트 쪽 clip 종료 기준과 비슷하게 맞춥니다.
server_event_processor = ServerEventProcessor(end_missing_frames=60)
