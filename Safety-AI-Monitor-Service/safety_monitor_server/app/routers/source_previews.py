# source_previews 관련 API 엔드포인트를 모아둔 파일입니다.
# @router.get/post 아래 함수들이 실제 HTTP 요청을 처리하는 부분입니다.

import hashlib
from pathlib import Path

from fastapi import APIRouter, File, Form, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse

from app.client_auth import verify_client_request
from app.config import DATABASE_PATH, SERVER_SOURCE_PREVIEW_DIR
from app.database import get_source
from app.connection_audit import log_preview_receive, request_host
from app.server_clip_recorder import server_clip_recorder

router = APIRouter(prefix="/api/source-previews", tags=["source-previews"])


def preview_path_for_source_key(source_key: str) -> Path:
    normalized = source_key.strip()
    digest = hashlib.sha1(normalized.encode("utf-8")).hexdigest()
    return (SERVER_SOURCE_PREVIEW_DIR / f"{digest}.jpg").resolve()


@router.post("")
async def upload_source_preview(
    request: Request,
    source_key: str = Form(...),
    file: UploadFile = File(...),
) -> dict[str, object]:
    normalized_source_key = source_key.strip()
    if not normalized_source_key:
        raise HTTPException(status_code=400, detail="source_key is required")

    source_record = get_source(DATABASE_PATH, normalized_source_key) or {}
    verify_client_request(request, str(source_record.get("client_id", "")))

    preview_path = preview_path_for_source_key(normalized_source_key)
    try:
        preview_bytes = bytearray()
        with preview_path.open("wb") as output:
            while True:
                chunk = await file.read(1024 * 1024)
                if not chunk:
                    break
                output.write(chunk)
                preview_bytes.extend(chunk)
    finally:
        await file.close()

    if not preview_path.exists() or preview_path.stat().st_size <= 0:
        preview_path.unlink(missing_ok=True)
        raise HTTPException(status_code=400, detail="preview upload is empty")

    server_clip_recorder.add_frame(
        source_key=normalized_source_key,
        jpeg_bytes=bytes(preview_bytes),
    )
    log_preview_receive(
        source_key=normalized_source_key,
        byte_count=len(preview_bytes),
        remote_host=request_host(request),
    )

    return {
        "ok": True,
        "source_key": normalized_source_key,
        "url": f"/api/source-previews/latest?source_key={normalized_source_key}",
    }


@router.get("/latest")
def get_latest_source_preview(source_key: str) -> FileResponse:
    normalized_source_key = source_key.strip()
    if not normalized_source_key:
        raise HTTPException(status_code=400, detail="source_key is required")

    preview_path = preview_path_for_source_key(normalized_source_key)
    if not preview_path.exists() or not preview_path.is_file():
        raise HTTPException(status_code=404, detail="source preview not found")

    return FileResponse(
        path=preview_path,
        filename=preview_path.name,
        media_type="image/jpeg",
    )
