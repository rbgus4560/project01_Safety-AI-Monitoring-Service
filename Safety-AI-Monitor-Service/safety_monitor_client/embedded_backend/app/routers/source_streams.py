# source_streams 관련 API 엔드포인트를 모아둔 파일입니다.
# @router.get/post 아래 함수들이 실제 HTTP 요청을 처리하는 부분입니다.

from __future__ import annotations

import asyncio

from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import Response, StreamingResponse

from app.routers.source_previews import source_preview_path

router = APIRouter(prefix="/api/source-streams", tags=["source-streams"])


@router.get("/{source_key:path}")
async def stream_source(
    source_key: str,
    single: bool = Query(default=False),
):
    normalized_source_key = source_key.strip()
    if not normalized_source_key:
        raise HTTPException(status_code=400, detail="source_key is required")

    if single:
        jpeg_bytes = _read_preview_bytes(normalized_source_key)
        if jpeg_bytes is None:
            raise HTTPException(status_code=404, detail="source preview not found")
        return Response(content=jpeg_bytes, media_type="image/jpeg")

    async def _frame_generator():
        last_signature = b""
        while True:
            jpeg_bytes = _read_preview_bytes(normalized_source_key)
            if jpeg_bytes and jpeg_bytes != last_signature:
                last_signature = jpeg_bytes
                yield b"--frame\r\n"
                yield b"Content-Type: image/jpeg\r\n"
                yield f"Content-Length: {len(jpeg_bytes)}\r\n\r\n".encode("ascii")
                yield jpeg_bytes
                yield b"\r\n"
            await asyncio.sleep(0.03)

    return StreamingResponse(
        _frame_generator(),
        media_type="multipart/x-mixed-replace; boundary=frame",
        headers={
            "Cache-Control": "no-cache, no-store, must-revalidate",
            "Pragma": "no-cache",
            "Expires": "0",
        },
    )


def _read_preview_bytes(source_key: str) -> bytes | None:
    preview_path = source_preview_path(source_key)
    if not preview_path.exists() or not preview_path.is_file():
        return None
    try:
        return preview_path.read_bytes()
    except OSError:
        return None
