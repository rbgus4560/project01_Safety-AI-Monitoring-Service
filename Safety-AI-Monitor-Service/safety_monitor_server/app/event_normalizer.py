# 이벤트 payload의 누락값과 클립 경로를 공통 형태로 맞추는 파일입니다.
# 서버와 뷰어가 같은 이벤트 구조를 사용하도록 값을 정리합니다.

from copy import deepcopy
from pathlib import PurePosixPath
from typing import Any
from urllib.parse import urlsplit

# 이 파일은 POST /api/events로 들어온 이벤트를 저장 전에 정리합니다.
# 특히 clip_url, clip_path, preferred_clip_source 같은 클립 접근 필드를 서버 기준으로 맞춰 줍니다.

def normalize_event_record(event_record: dict[str, Any]) -> dict[str, Any]:
    # 원본 dict는 최대한 보존하고, 클라이언트가 바로 쓰기 쉬운 보조 필드만 보강합니다.
    normalized = deepcopy(event_record)

    clip_url = _clean_string(normalized.get("clip_url"))
    clip_path = _clean_string(normalized.get("clip_path"))
    server_clip_name = _clean_string(normalized.get("server_clip_name"))
    server_clip_path = _clean_string(normalized.get("server_clip_path"))
    thumbnail_url = _clean_string(normalized.get("thumbnail_url"))
    thumbnail_name = _clean_string(normalized.get("thumbnail_name"))

    if not server_clip_name and clip_url:
        server_clip_name = _extract_clip_name_from_url(clip_url)
        if server_clip_name:
            normalized["server_clip_name"] = server_clip_name

    if not server_clip_path and server_clip_name:
        server_clip_path = f"clips/{server_clip_name}"
        normalized["server_clip_path"] = server_clip_path

    if not thumbnail_name and thumbnail_url:
        thumbnail_name = _extract_thumbnail_name_from_url(thumbnail_url)
        if thumbnail_name:
            normalized["thumbnail_name"] = thumbnail_name

    if not thumbnail_url and thumbnail_name:
        normalized["thumbnail_url"] = f"/api/event-thumbnails/{thumbnail_name}"

    if clip_url:
        normalized["clip_available"] = True
        normalized["preferred_clip_source"] = "server"
    elif clip_path:
        normalized["clip_available"] = True
        normalized["preferred_clip_source"] = "local"
    else:
        normalized["clip_available"] = False
        normalized["preferred_clip_source"] = ""

    if "clip_upload_ok" not in normalized:
        normalized["clip_upload_ok"] = bool(clip_url)

    return normalized


def _clean_string(value: Any) -> str:
    if value is None:
        return ""
    if not isinstance(value, str):
        value = str(value)
    return value.strip()


def _extract_clip_name_from_url(clip_url: str) -> str:
    # /api/clips/sample.mp4 같은 상대 URL에서 파일명만 뽑아 server_clip_name 보강에 사용합니다.
    path_text = urlsplit(clip_url).path.strip()
    if not path_text:
        return ""

    path = PurePosixPath(path_text)
    parts = [part for part in path.parts if part not in {"", "/"}]
    if len(parts) < 3:
        return ""
    if parts[:2] != ["api", "clips"]:
        return ""

    name = path.name.strip()
    if not name.lower().endswith(".mp4"):
        return ""
    return name


def _extract_thumbnail_name_from_url(thumbnail_url: str) -> str:
    path_text = urlsplit(thumbnail_url).path.strip()
    if not path_text:
        return ""

    path = PurePosixPath(path_text)
    parts = [part for part in path.parts if part not in {"", "/"}]
    if len(parts) < 3:
        return ""
    if parts[:2] != ["api", "event-thumbnails"]:
        return ""

    name = path.name.strip()
    if not name.lower().endswith((".jpg", ".jpeg")):
        return ""
    return name
