# source_previews 관련 API 엔드포인트를 모아둔 파일입니다.
# @router.get/post 아래 함수들이 실제 HTTP 요청을 처리하는 부분입니다.

import hashlib
from pathlib import Path

from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse

from app.config import CLIENT_SOURCE_PREVIEW_DIR

router = APIRouter(prefix="/api/source-previews", tags=["source-previews"])


def source_preview_path(source_key: str) -> Path:
    normalized = source_key.strip()
    digest = hashlib.sha1(normalized.encode("utf-8")).hexdigest()
    return (CLIENT_SOURCE_PREVIEW_DIR / f"{digest}.jpg").resolve()


@router.get("/latest")
def get_latest_source_preview(source_key: str) -> FileResponse:
    normalized_source_key = source_key.strip()
    if not normalized_source_key:
        raise HTTPException(status_code=400, detail="source_key is required")

    preview_path = source_preview_path(normalized_source_key)
    if not preview_path.exists() or not preview_path.is_file():
        raise HTTPException(status_code=404, detail="source preview not found")

    return FileResponse(
        path=preview_path,
        filename=preview_path.name,
        media_type="image/jpeg",
    )
