# 프로젝트 여러 곳에서 함께 사용하는 보조 코드 파일입니다.
# 상수, 스키마, 로그 같은 공통 흐름을 담고 있습니다.

from __future__ import annotations

from datetime import datetime
import os
from pathlib import Path
import sys
import threading


_ANSI_RESET = "\033[0m"
_TAG_COLORS = {
    "REQ": "\033[96m",
    "REQ-SUM": "\033[36m",
    "PUSH": "\033[92m",
    "SRC": "\033[94m",
    "PROGRESS": "\033[92m",
    "PERF": "\033[95m",
    "WARN": "\033[93m",
    "ERROR": "\033[91m",
    "MODEL": "\033[90m",
}

_LOG_FILE_LOCK = threading.Lock()


def _enable_windows_ansi() -> bool:
    """Windows 콘솔에서 ANSI 색상 코드를 활성화할 수 있는지 확인합니다."""
    if os.environ.get("NO_COLOR"):
        return False
    if not hasattr(sys.stdout, "isatty") or not sys.stdout.isatty():
        return False
    if os.name != "nt":
        return True
    try:
        import ctypes

        kernel32 = ctypes.windll.kernel32
        handle = kernel32.GetStdHandle(-11)
        if handle == 0 or handle == -1:
            return False
        mode = ctypes.c_uint()
        if kernel32.GetConsoleMode(handle, ctypes.byref(mode)) == 0:
            return False
        enable_vt = 0x0004
        if mode.value & enable_vt:
            return True
        if kernel32.SetConsoleMode(handle, mode.value | enable_vt) == 0:
            return False
        return True
    except Exception:
        return False


_USE_COLOR = _enable_windows_ansi()

_REQUEST_PATH_ALIASES = {
    "/api/frame-detections/current": "frame-now",
    "/api/frame-detections/latest": "frame-latest",
    "/api/source-status": "source-status",
    "/api/sources": "sources",
    "/api/events": "events",
    "/api/events/latest": "events-latest",
    "/api/events/detail": "event-detail",
    "/health": "health",
}


def _shorten_path_text(value: str) -> str:
    """긴 요청 경로를 읽기 쉬운 짧은 형태로 축약합니다."""
    normalized = value.strip()
    if not normalized:
        return "-"
    alias = _REQUEST_PATH_ALIASES.get(normalized)
    if alias:
        return alias
    if "?" in normalized:
        base, _, query = normalized.partition("?")
        base_alias = _REQUEST_PATH_ALIASES.get(base, base)
        query_parts = [part for part in query.split("&") if part]
        if not query_parts:
            return base_alias
        if len(query_parts) == 1:
            return f"{base_alias}?{query_parts[0]}"
        return f"{base_alias}?{query_parts[0]}+{len(query_parts) - 1}"
    return normalized


def _shorten_source_text(value: str) -> str:
    """소스 문자열을 콘솔에 맞게 짧고 명확하게 줄입니다."""
    normalized = value.strip()
    if not normalized:
        return "-"
    source_type = ""
    source_value = normalized
    if "|" in normalized:
        source_type, source_value = normalized.split("|", 1)
    source_value = source_value.strip()
    compact_value = source_value
    lowered = source_value.lower()
    if lowered.startswith(("http://", "https://", "rtsp://")):
        compact_value = source_value[:64]
        if len(source_value) > 64:
            compact_value += "..."
    else:
        compact_value = Path(source_value).name or source_value
    if source_type:
        return f"{source_type}|{compact_value}"
    return compact_value


def _shorten_stage_text(value: str) -> str:
    """긴 단계 설명을 길이 제한에 맞게 잘라서 표시합니다."""
    text = value.strip()
    if not text:
        return "-"
    if len(text) <= 72:
        return text
    return f"{text[:69]}..."


def _shorten_error_text(value: str) -> str:
    """오류 메시지를 너무 길지 않게 축약해서 표시합니다."""
    text = value.strip()
    if not text:
        return "-"
    if len(text) <= 80:
        return text
    return f"{text[:77]}..."


def _format_value(value: object) -> str:
    """로그 값이 None일 때는 '-'로, 그 외에는 문자열 형태로 정리합니다."""
    if value is None:
        return "-"
    text = str(value).strip()
    return text if text else "-"


def _build_field_text(fields: dict[str, object]) -> str:
    """로그 필드를 읽기 쉬운 순서로 조합해 한 줄 문자열로 만듭니다."""
    preferred_order = [
        "action",
        "source",
        "type",
        "client",
        "state",
        "running",
        "frame",
        "progress",
        "path",
        "method",
        "status",
        "duration",
        "count",
        "avg",
        "max",
        "window",
        "model",
        "stride",
        "target_fps",
        "frames",
        "total",
        "top",
        "reason",
        "wait",
        "error",
    ]
    ordered_keys = [key for key in preferred_order if key in fields]
    ordered_keys.extend(key for key in fields.keys() if key not in ordered_keys)
    parts: list[str] = []
    for key in ordered_keys:
        value = fields[key]
        if value is None:
            continue
        text = _format_value(value)
        if key == "source":
            text = _shorten_source_text(text)
        elif key == "path":
            text = _shorten_path_text(text)
        elif key == "top":
            text = _shorten_stage_text(text)
        parts.append(f"{key}={text}")
    return " ".join(parts)


def _compact_field_text(tag: str, fields: dict[str, object]) -> str:
    """태그 종류에 따라 짧고 적절한 형식으로 필드 문자열을 압축합니다."""
    def _text(key: str) -> str:
        value = fields.get(key)
        if value is None:
            return ""
        text = _format_value(value)
        if key == "source":
            return _shorten_source_text(text)
        if key == "path":
            return _shorten_path_text(text)
        if key == "top":
            return _shorten_stage_text(text)
        if key == "error":
            return _shorten_error_text(text)
        return text

    def _push(parts: list[str], label: str, value: str) -> None:
        if value and value != "-":
            parts.append(f"{label}{value}")

    parts: list[str] = []

    if tag == "REQ":
        _push(parts, "", _text("path"))
        _push(parts, "", _text("status"))
        _push(parts, "", _text("duration"))
        error_text = _text("error")
        if error_text:
            _push(parts, "err=", error_text)
        return " ".join(parts)

    if tag == "REQ-SUM":
        _push(parts, "", _text("path"))
        _push(parts, "x", _text("count"))
        _push(parts, "avg=", _text("avg"))
        _push(parts, "max=", _text("max"))
        last_status = _text("last_status")
        if last_status and last_status != "200":
            _push(parts, "status=", last_status)
        return " ".join(parts)

    if tag == "PUSH":
        _push(parts, "", _text("event"))
        _push(parts, "x", _text("clients"))
        source_text = _text("source")
        if source_text:
            _push(parts, "", source_text)
        action_text = _text("action")
        if action_text:
            _push(parts, "", action_text)
        state_text = _text("state")
        if state_text:
            _push(parts, "", state_text)
        return " ".join(parts)

    if tag == "SRC":
        _push(parts, "", _text("action"))
        _push(parts, "", _text("source"))
        action = _text("action")
        if action in {"start", "open", "retry"}:
            _push(parts, "(", _text("type") + ")" if _text("type") else "")
        if action in {"opened"}:
            _push(parts, "fps=", _text("fps"))
        if action in {"analysis-stride"}:
            _push(parts, "stride=", _text("stride"))
            _push(parts, "target=", _text("target_fps"))
        if action in {"model-load", "model-ready"}:
            _push(parts, "", _text("model"))
        if action in {"first-frame", "first-predict"}:
            _push(parts, "f=", _text("frame"))
            _push(parts, "det=", _text("detections"))
        if action in {"stop", "retry", "stop-request"}:
            _push(parts, "reason=", _text("reason"))
        if action == "retry":
            _push(parts, "wait=", _text("wait"))
        return " ".join(parts)

    if tag == "PROGRESS":
        _push(parts, "", _text("source"))
        _push(parts, "", _text("progress"))
        state_text = _text("state")
        if state_text and state_text not in {"running"}:
            _push(parts, "", state_text)
        error_text = _text("error")
        if error_text:
            _push(parts, "err=", error_text)
        return " ".join(parts)

    if tag == "PERF":
        _push(parts, "", _text("source"))
        _push(parts, "avg=", _text("avg"))
        _push(parts, "total=", _text("total"))
        _push(parts, "", _text("top"))
        return " ".join(parts)

    if tag in {"WARN", "ERROR"}:
        _push(parts, "", _text("source"))
        _push(parts, "", _text("path"))
        error_text = _text("error")
        if error_text:
            _push(parts, "err=", error_text)
        return " ".join(parts)

    return _build_field_text(fields)


def log_line(tag: str, message: str = "", **fields: object) -> None:
    """태그와 필드를 포함한 로그 한 줄을 콘솔과 로그 파일에 출력합니다."""
    timestamp = datetime.now().strftime("%H:%M:%S")
    prefix = f"[{timestamp}] [{tag}]"
    if _USE_COLOR:
        color = _TAG_COLORS.get(tag, "")
        if color:
            prefix = f"{color}{prefix}{_ANSI_RESET}"
    field_text = _compact_field_text(tag, fields)
    plain_prefix = f"[{timestamp}] [{tag}]"
    if message and field_text:
        line = f"{plain_prefix} {message} {field_text}"
        print(f"{prefix} {message} {field_text}", flush=True)
        _append_log_file(line)
        return
    if message:
        line = f"{plain_prefix} {message}"
        print(f"{prefix} {message}", flush=True)
        _append_log_file(line)
        return
    if field_text:
        line = f"{plain_prefix} {field_text}"
        print(f"{prefix} {field_text}", flush=True)
        _append_log_file(line)
        return
    print(prefix, flush=True)
    _append_log_file(plain_prefix)


def _append_log_file(line: str) -> None:
    """설정된 로그 파일에 한 줄씩 기록합니다."""
    log_file = os.environ.get("SAFETY_MONITOR_LOG_FILE", "").strip()
    if not log_file:
        return
    try:
        path = Path(log_file).resolve()
        path.parent.mkdir(parents=True, exist_ok=True)
        with _LOG_FILE_LOCK:
            with path.open("a", encoding="utf-8") as output:
                output.write(line)
                output.write("\n")
    except OSError:
        return
