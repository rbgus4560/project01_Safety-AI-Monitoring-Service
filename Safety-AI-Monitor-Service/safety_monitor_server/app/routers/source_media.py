# source_media 관련 API 엔드포인트를 모아둔 파일입니다.
# @router.get/post 아래 함수들이 실제 HTTP 요청을 처리하는 부분입니다.

from pathlib import Path

from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse

from app.config import SERVER_SOURCE_CACHE_DIR, SERVER_UPLOAD_SOURCE_DIR

router = APIRouter(prefix="/api/source-media", tags=["source-media"])


@router.get("/{bucket}/{file_name}")
def get_source_media(bucket: str, file_name: str) -> FileResponse:
    normalized_bucket = bucket.strip().lower()
    normalized_name = file_name.strip()
    if (
        not normalized_name
        or "/" in normalized_name
        or "\\" in normalized_name
        or ".." in normalized_name
    ):
        raise HTTPException(status_code=400, detail="invalid source media name")

    if normalized_bucket == "uploaded":
        root_dir = SERVER_UPLOAD_SOURCE_DIR
    elif normalized_bucket == "cached":
        root_dir = SERVER_SOURCE_CACHE_DIR
    else:
        raise HTTPException(status_code=400, detail="invalid source media bucket")

    media_path = (root_dir / normalized_name).resolve()
    try:
        media_path.relative_to(root_dir)
    except ValueError as error:
        raise HTTPException(status_code=400, detail="invalid source media path") from error

    if not media_path.exists() or not media_path.is_file():
        raise HTTPException(status_code=404, detail="source media not found")

    return FileResponse(
        path=media_path,
        filename=media_path.name,
        media_type="video/mp4",
    )
