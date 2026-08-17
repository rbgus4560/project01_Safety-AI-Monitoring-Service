# 프로젝트 여러 곳에서 함께 사용하는 보조 코드 파일입니다.
# 상수, 스키마, 로그 같은 공통 흐름을 담고 있습니다.

from __future__ import annotations

import threading
from time import monotonic
from typing import Any

from fastapi import Request

from app.log_utils import log_line


_LOCK = threading.Lock()
_STATUS_STATE: dict[str, dict[str, object]] = {}
_FRAME_STATE: dict[str, dict[str, object]] = {}
_PREVIEW_STATE: dict[str, float] = {}


def request_host(request: Request) -> str:
    client = request.client
    if client is None:
        return "-"
    return str(client.host or "-")


def log_source_upsert(
    *,
    source_key: str,
    source_type: str,
    source_value: str,
    client_id: str,
    session_id: str,
    remote_host: str,
    existed: bool,
    removed_source_keys: list[str],
) -> None:
    log_line(
        "CONN",
        action="source-upsert",
        source=source_key,
        type=source_type,
        value=source_value,
        client=client_id or "-",
        session=session_id or "-",
        remote=remote_host,
        existed=existed,
        removed=",".join(removed_source_keys) if removed_source_keys else "-",
    )


def log_status_receive(*, status_record: dict[str, Any], remote_host: str) -> None:
    source_key = str(status_record.get("source_key", "")).strip()
    if not source_key:
        return
    state = str(status_record.get("state", "")).strip() or "unknown"
    running = bool(status_record.get("is_running", False))
    frame_id = _read_int(status_record.get("last_frame_id"), default=-1)
    error = str(status_record.get("error_message", "")).strip()
    now = monotonic()
    should_log = False
    with _LOCK:
        previous = _STATUS_STATE.get(source_key, {})
        if (
            previous.get("state") != state
            or previous.get("running") != running
            or previous.get("error") != error
        ):
            should_log = True
        if frame_id >= 0:
            previous_frame = _read_int(previous.get("frame"), default=-1)
            if previous_frame < 0 or frame_id - previous_frame >= 120:
                should_log = True
        previous_at = float(previous.get("at", 0.0) or 0.0)
        if now - previous_at >= 10.0:
            should_log = True
        if should_log:
            _STATUS_STATE[source_key] = {
                "state": state,
                "running": running,
                "frame": frame_id,
                "error": error,
                "at": now,
            }
    if not should_log:
        return
    log_line(
        "CONN",
        action="status",
        source=source_key,
        client=str(status_record.get("client_id", "")).strip() or "-",
        session=str(status_record.get("session_id", "")).strip() or "-",
        remote=remote_host,
        state=state,
        running=running,
        frame=frame_id,
        fps=status_record.get("source_fps"),
        error=error or None,
    )


def log_frame_receive(*, frame_record: dict[str, Any], remote_host: str) -> None:
    source_key = str(frame_record.get("source_key", "")).strip()
    if not source_key:
        return
    frame_id = _read_int(frame_record.get("frame_id"), default=-1)
    now = monotonic()
    should_log = False
    with _LOCK:
        previous = _FRAME_STATE.get(source_key, {})
        previous_frame = _read_int(previous.get("frame"), default=-1)
        previous_at = float(previous.get("at", 0.0) or 0.0)
        if previous_frame < 0 or frame_id - previous_frame >= 120 or now - previous_at >= 10.0:
            should_log = True
            _FRAME_STATE[source_key] = {"frame": frame_id, "at": now}
    if not should_log:
        return
    detections = frame_record.get("detections", [])
    detection_count = len(detections) if isinstance(detections, list) else 0
    log_line(
        "CONN",
        action="frame",
        source=source_key,
        client=str(frame_record.get("client_id", "")).strip() or "-",
        session=str(frame_record.get("session_id", "")).strip() or "-",
        remote=remote_host,
        frame=frame_id,
        detections=detection_count,
    )


def log_preview_receive(*, source_key: str, byte_count: int, remote_host: str) -> None:
    now = monotonic()
    should_log = False
    with _LOCK:
        previous_at = _PREVIEW_STATE.get(source_key, 0.0)
        if now - previous_at >= 10.0:
            should_log = True
            _PREVIEW_STATE[source_key] = now
    if not should_log:
        return
    log_line(
        "CONN",
        action="preview",
        source=source_key,
        remote=remote_host,
        bytes=byte_count,
    )


def log_stream_request(
    *,
    source_key: str,
    remote_host: str,
    single: bool,
    found_source: bool,
    found_preview: bool,
) -> None:
    log_line(
        "CONN",
        action="stream-get",
        source=source_key,
        remote=remote_host,
        single=single,
        source_found=found_source,
        preview_found=found_preview,
    )


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
