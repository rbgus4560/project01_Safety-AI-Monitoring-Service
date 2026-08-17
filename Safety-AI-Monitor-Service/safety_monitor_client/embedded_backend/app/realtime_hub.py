# WebSocket으로 화면에 실시간 갱신 알림을 보내는 허브 파일입니다.
# 이벤트나 소스 상태 변경 신호를 연결된 클라이언트들에게 전달합니다.

from __future__ import annotations

import asyncio
import json
import threading
from typing import Any

from fastapi import WebSocket
from fastapi import WebSocketDisconnect

from app.log_utils import log_line


class RealtimeUpdateHub:
    """WebSocket 연결된 클라이언트에게 실시간 업데이트를 브로드캐스트하는 허브입니다."""

    def __init__(self) -> None:
        """리스너 목록과 동기화를 위한 잠금을 초기화합니다."""
        self._lock = threading.RLock()
        self._listeners: dict[int, tuple[asyncio.AbstractEventLoop, asyncio.Queue[str]]] = {}

    async def serve(self, websocket: WebSocket) -> None:
        """클라이언트의 WebSocket 연결을 받아 이벤트를 지속적으로 전달합니다."""
        await websocket.accept()
        queue: asyncio.Queue[str] = asyncio.Queue(maxsize=128)
        listener_id = id(queue)
        loop = asyncio.get_running_loop()
        with self._lock:
            self._listeners[listener_id] = (loop, queue)
            listener_count = len(self._listeners)
        log_line("PUSH", event="client-connect", clients=listener_count)
        try:
            while True:
                payload = await queue.get()
                await websocket.send_text(payload)
        except WebSocketDisconnect:
            pass
        finally:
            with self._lock:
                self._listeners.pop(listener_id, None)
                listener_count = len(self._listeners)
            log_line("PUSH", event="client-disconnect", clients=listener_count)

    def publish(self, message_type: str, **payload: Any) -> None:
        """모든 연결된 클라이언트에게 메시지를 비동기적으로 전달합니다."""
        message = {"type": message_type, **payload}
        encoded = json.dumps(message, ensure_ascii=False)
        with self._lock:
            listeners = list(self._listeners.items())
            listener_count = len(listeners)
        if listener_count <= 0:
            return
        log_line(
            "PUSH",
            event=message_type,
            clients=listener_count,
            source=str(payload.get("source_key", "")).strip() or None,
            action=str(payload.get("action", "")).strip() or None,
            state=str(payload.get("state", "")).strip() or None,
        )
        stale_listener_ids: list[int] = []
        for listener_id, (loop, queue) in listeners:
            try:
                loop.call_soon_threadsafe(self._enqueue_message, queue, encoded)
            except RuntimeError:
                stale_listener_ids.append(listener_id)

        if stale_listener_ids:
            with self._lock:
                for listener_id in stale_listener_ids:
                    self._listeners.pop(listener_id, None)

    @staticmethod
    def _enqueue_message(queue: asyncio.Queue[str], payload: str) -> None:
        """이벤트 루프 쪽 큐에 메시지를 안전하게 넣습니다."""
        if queue.full():
            try:
                queue.get_nowait()
            except asyncio.QueueEmpty:
                pass
        try:
            queue.put_nowait(payload)
        except asyncio.QueueFull:
            pass


realtime_update_hub = RealtimeUpdateHub()
