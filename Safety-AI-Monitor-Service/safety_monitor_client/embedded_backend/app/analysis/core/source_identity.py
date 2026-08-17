# 카메라나 영상 소스를 구분하기 위한 source_key와 slug를 만드는 파일입니다.
# DB, 이벤트, 클립이 같은 소스를 가리키도록 식별자를 맞춥니다.

from pathlib import Path


def build_source_key(source_type: str, source_value: str) -> str:
    normalized_type = source_type.strip().lower()
    normalized_value = normalize_source_value(source_value)
    return f"{normalized_type}|{normalized_value}"


def build_source_slug(source_type: str, source_value: str) -> str:
    source_key = build_source_key(source_type, source_value)
    return f"src_{_fnv1a32(source_key):08x}"


def normalize_source_value(source_value: str) -> str:
    normalized = source_value.strip().replace("\\", "/").lower()
    return normalized


def normalize_video_source_value(source_value: str) -> str:
    return str(Path(source_value).resolve())


def _fnv1a32(text: str) -> int:
    result = 0x811C9DC5
    for char in text:
        result ^= ord(char)
        result = (result * 0x01000193) & 0xFFFFFFFF
    return result
