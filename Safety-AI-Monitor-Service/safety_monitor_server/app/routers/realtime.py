# realtime 관련 API 엔드포인트를 모아둔 파일입니다.
# @router.get/post 아래 함수들이 실제 HTTP 요청을 처리하는 부분입니다.

from fastapi import APIRouter
from fastapi import WebSocket

from app.realtime_hub import realtime_update_hub

router = APIRouter(tags=["realtime"])


@router.websocket("/ws/updates")
async def updates_socket(websocket: WebSocket) -> None:
    await realtime_update_hub.serve(websocket)
