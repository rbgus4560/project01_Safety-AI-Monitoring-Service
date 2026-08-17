# 카메라나 영상 소스를 구분하기 위한 source_key와 slug를 만드는 파일입니다.
# DB, 이벤트, 클립이 같은 소스를 가리키도록 식별자를 맞춥니다.

from pathlib import Path


def build_source_key(
    source_type: str,
    source_value: str,
    *,
    client_id: str = "",
    session_id: str = "",
) -> str:
    normalized_type = source_type.strip().lower()
    normalized_value = normalize_source_value(source_value)
    normalized_client_id = normalize_source_value(client_id)
    normalized_session_id = normalize_source_value(session_id)
    owner_identity = normalized_client_id or normalized_session_id
    if owner_identity:
        return f"{normalized_type}|owner={owner_identity}|{normalized_value}"
    return f"{normalized_type}|{normalized_value}"


def build_source_slug(
    source_type: str,
    source_value: str,
    *,
    client_id: str = "",
    session_id: str = "",
) -> str:
    source_key = build_source_key(
        source_type,
        source_value,
        client_id=client_id,
        session_id=session_id,
    )
    return f"src_{_fnv1a32(source_key):08x}"


def normalize_source_value(source_value: str) -> str:
    return source_value.strip().replace("\\", "/").lower()


def normalize_video_source_value(source_value: str) -> str:
    return str(Path(source_value).resolve())


def extract_clip_name(record: dict) -> str:
    server_clip_name = str(record.get("server_clip_name", "")).strip()
    if server_clip_name:
        return server_clip_name

    server_clip_path = str(record.get("server_clip_path", "")).strip()
    if server_clip_path:
        return Path(server_clip_path).name

    clip_url = str(record.get("clip_url", "")).strip()
    if clip_url:
        return Path(clip_url).name

    return ""


def _fnv1a32(text: str) -> int:
    result = 0x811C9DC5
    for char in text:
        result ^= ord(char)
        result = (result * 0x01000193) & 0xFFFFFFFF
    return result
