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
    """소스 타입, 값, 소유자 정보를 조합해 DB와 이벤트에서 공통으로 쓰는 source_key를 만든다."""
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
    """source_key를 기반으로 사람이 읽기 쉬운 slug 형태의 식별자를 생성한다."""
    source_key = build_source_key(
        source_type,
        source_value,
        client_id=client_id,
        session_id=session_id,
    )
    return f"src_{_fnv1a32(source_key):08x}"


def normalize_source_value(source_value: str) -> str:
    """소스 값을 비교와 저장에 적합한 형태로 정규화한다."""
    return source_value.strip().replace("\\", "/").lower()


def normalize_video_source_value(source_value: str) -> str:
    """영상 소스 경로를 절대 경로로 변환해 일관된 형태로 만든다."""
    return str(Path(source_value).resolve())


def extract_clip_name(record: dict) -> str:
    """클립 레코드에서 표시용 파일 이름을 우선순위에 따라 추출한다."""
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
    """문자열을 32비트 FNV-1a 해시로 변환해 식별자 생성에 사용한다."""
    result = 0x811C9DC5
    for char in text:
        result ^= ord(char)
        result = (result * 0x01000193) & 0xFFFFFFFF
    return result
