# clips 관련 API 엔드포인트를 모아둔 파일입니다.
# @router.get/post 아래 함수들이 실제 HTTP 요청을 처리하는 부분입니다.

from pathlib import Path

from fastapi import APIRouter, File, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse

from app.config import SERVER_CLIP_DIR
from app.config import DATABASE_PATH
from app.database import merge_latest_event
from app.schemas import ClipItem, ClipListResponse, ClipUploadResponse

# 이 파일은 서버 소유 mp4 클립 업로드/조회 API를 담당합니다.
# Python AI Worker는 POST /api/clips로 업로드하고, Flutter는 GET /api/clips/{clip_name}으로 재생할 수 있습니다.

router = APIRouter(prefix="/api/clips", tags=["clips"])


@router.post("", response_model=ClipUploadResponse)
async def upload_clip(
    file: UploadFile = File(...),
    event_key: str | None = Form(default=None),
    source_key: str | None = Form(default=None),
    source_slug: str | None = Form(default=None),
) -> ClipUploadResponse:
    # multipart/form-data는 파일 업로드용 HTTP 요청 형식입니다.
    # 업로드된 mp4는 반드시 서버 data/clips 아래에만 저장되도록 제한합니다.
    original_name = Path(file.filename or "").name.strip()
    if not original_name:
        raise HTTPException(status_code=400, detail="file name is required")
    if "/" in original_name or "\\" in original_name or ".." in original_name:
        raise HTTPException(status_code=400, detail="invalid file name")
    if not original_name.lower().endswith(".mp4"):
        raise HTTPException(status_code=400, detail="only mp4 files are allowed")

    normalized_source_slug = str(source_slug or "").strip()
    clip_file_name = original_name
    if normalized_source_slug:
        clip_file_name = f"{normalized_source_slug}__{original_name}"

    clip_path = _build_unique_clip_path(clip_file_name)

    size_bytes = 0
    try:
        with clip_path.open("wb") as output_file:
            while True:
                chunk = await file.read(1024 * 1024)
                if not chunk:
                    break
                output_file.write(chunk)
                size_bytes += len(chunk)
    except Exception as error:
        raise HTTPException(status_code=500, detail="failed to save clip") from error
    finally:
        await file.close()

    normalized_event_key = event_key.strip() if event_key else ""
    normalized_source_key = source_key.strip() if source_key else ""
    if normalized_event_key and normalized_source_key:
        merge_latest_event(
            DATABASE_PATH,
            {
                "event_key": normalized_event_key,
                "source_key": normalized_source_key,
                "status": "END",
                "clip_path": "",
                "clip_url": f"/api/clips/{clip_path.name}",
                "server_clip_path": f"clips/{clip_path.name}",
                "server_clip_name": clip_path.name,
                "clip_available": True,
                "preferred_clip_source": "server",
            },
        )

    return ClipUploadResponse(
        ok=True,
        name=clip_path.name,
        path=f"clips/{clip_path.name}",
        url=f"/api/clips/{clip_path.name}",
        size_bytes=size_bytes,
        event_key=event_key.strip() if event_key else None,
    )


@router.get("", response_model=ClipListResponse)
def list_clips() -> ClipListResponse:
    # 서버가 현재 소유한 mp4 파일 목록을 클라이언트가 확인할 때 사용합니다.
    items = [
        ClipItem(
            name=clip_path.name,
            path=f"clips/{clip_path.name}",
            url=f"/api/clips/{clip_path.name}",
        )
        for clip_path in sorted(SERVER_CLIP_DIR.glob("*.mp4"))
        if clip_path.is_file()
    ]
    return ClipListResponse(count=len(items), items=items)


@router.get("/{clip_name}")
def get_clip(clip_name: str) -> FileResponse:
    # mp4 파일 일부만 전송하는 206 Partial Content 응답도 브라우저/플레이어에서는 정상적일 수 있습니다.
    normalized_name = clip_name.strip()
    if (
        not normalized_name
        or "/" in normalized_name
        or "\\" in normalized_name
        or ".." in normalized_name
    ):
        raise HTTPException(status_code=400, detail="invalid clip name")

    clip_path = (SERVER_CLIP_DIR / normalized_name).resolve()
    try:
        clip_path.relative_to(SERVER_CLIP_DIR)
    except ValueError as error:
        raise HTTPException(status_code=400, detail="invalid clip path") from error

    if not clip_path.exists() or not clip_path.is_file():
        raise HTTPException(status_code=404, detail="clip not found")

    return FileResponse(
        path=clip_path,
        filename=clip_path.name,
        media_type="video/mp4",
    )


def _build_unique_clip_path(file_name: str) -> Path:
    candidate = (SERVER_CLIP_DIR / file_name).resolve()
    stem = Path(file_name).stem
    suffix = Path(file_name).suffix
    index = 1

    while candidate.exists():
        candidate = (SERVER_CLIP_DIR / f"{stem}_{index}{suffix}").resolve()
        index += 1

    try:
        candidate.relative_to(SERVER_CLIP_DIR)
    except ValueError as error:
        raise HTTPException(status_code=400, detail="invalid clip path") from error

    return candidate
