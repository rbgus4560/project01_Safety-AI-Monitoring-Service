# event_thumbnails 관련 API 엔드포인트를 모아둔 파일입니다.
# @router.get/post 아래 함수들이 실제 HTTP 요청을 처리하는 부분입니다.

from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse

from app.config import SERVER_EVENT_THUMBNAIL_DIR


router = APIRouter(prefix="/api/event-thumbnails", tags=["event-thumbnails"])


@router.get("/{thumbnail_name}")
def get_event_thumbnail(thumbnail_name: str) -> FileResponse:
    normalized_name = thumbnail_name.strip()
    if (
        not normalized_name
        or "/" in normalized_name
        or "\\" in normalized_name
        or ".." in normalized_name
    ):
        raise HTTPException(status_code=400, detail="invalid thumbnail name")
    if not normalized_name.lower().endswith((".jpg", ".jpeg")):
        raise HTTPException(status_code=400, detail="invalid thumbnail type")

    thumbnail_path = (SERVER_EVENT_THUMBNAIL_DIR / normalized_name).resolve()
    try:
        thumbnail_path.relative_to(SERVER_EVENT_THUMBNAIL_DIR)
    except ValueError as error:
        raise HTTPException(status_code=400, detail="invalid thumbnail path") from error

    if not thumbnail_path.exists() or not thumbnail_path.is_file():
        raise HTTPException(status_code=404, detail="thumbnail not found")

    return FileResponse(
        path=thumbnail_path,
        filename=thumbnail_path.name,
        media_type="image/jpeg",
    )
