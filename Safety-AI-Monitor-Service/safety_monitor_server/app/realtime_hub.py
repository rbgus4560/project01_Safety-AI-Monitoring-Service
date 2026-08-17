# WebSocket으로 화면에 실시간 갱신 알림을 보내는 허브 파일입니다.
# 이벤트나 소스 상태 변경 신호를 연결된 클라이언트들에게 전달합니다.

from __future__ import annotations

import asyncio
import json
import threading
from time import monotonic
from typing import Any

from fastapi import WebSocket
from fastapi import WebSocketDisconnect

from app.log_utils import log_line


class RealtimeUpdateHub:
    def __init__(self) -> None:
        # 멀티스레드 환경에서 _listeners나 상태 변수들에 동시 접근하는 것을 막기 위한 재진입 가능 락(RLock)
        self._lock = threading.RLock()
        
        # 연결된 클라이언트(리스너)들을 관리하는 딕셔너리
        # Key: 큐 객체의 고유 ID (id(queue))
        # Value: 해당 클라이언트가 동작 중인 asyncio 이벤트 루프와 메시지를 담을 비동기 큐의 튜플
        self._listeners: dict[int, tuple[asyncio.AbstractEventLoop, asyncio.Queue[str]]] = {}
        
        # 너무 잦은 로그 발생을 막기 위해, 특정 이벤트(예: 상태 변경)의 발생 횟수를 잠시 모아두는 딕셔너리
        self._summary_counts: dict[str, int] = {}
        
        # 로그 요약을 마지막으로 배출(flush)한 시간을 기록 (monotonic은 OS의 절대적인 시간을 측정하여 시간 왜곡을 방지함)
        self._summary_last_flush = monotonic()
        
        # 로그를 모아서 출력할 주기 (5초)
        self._summary_interval_seconds = 5.0

    async def serve(self, websocket: WebSocket) -> None:
        """
        FastAPI의 WebSocket 라우터 엔드포인트에서 호출되는 메서드입니다.
        클라이언트가 연결되면 이 메서드가 실행되어 연결을 유지하고 메시지를 전송합니다.
        """
        # 1. 클라이언트의 웹소켓 연결 요청 수락
        await websocket.accept()
        
        # 2. 이 클라이언트 전용으로 사용할 메시지 큐 생성 (최대 128개 메시지 대기 가능)
        queue: asyncio.Queue[str] = asyncio.Queue(maxsize=128)
        listener_id = id(queue)
        loop = asyncio.get_running_loop()
        
        # 3. 스레드 락을 걸고 새로 생성된 큐와 루프를 리스너 목록에 등록
        with self._lock:
            self._listeners[listener_id] = (loop, queue)
            listener_count = len(self._listeners)
            
        # 4. 클라이언트 연결 성공 로그 출력
        log_line("PUSH", event="client-connect", clients=listener_count)
        
        try:
            # 5. 무한 루프를 돌며 큐에 메시지가 들어오기를 기다렸다가, 들어오면 웹소켓으로 전송
            while True:
                payload = await queue.get() # publish()에서 큐에 데이터를 넣어주면 여기서 깨어남
                await websocket.send_text(payload)
        except WebSocketDisconnect:
            # 클라이언트가 정상적/비정상적으로 연결을 끊었을 때 발생하는 예외 처리 (무시하고 finally로 이동)
            pass
        finally:
            # 6. 연결이 종료되면 리스너 목록에서 해당 클라이언트를 안전하게 제거
            with self._lock:
                self._listeners.pop(listener_id, None)
                listener_count = len(self._listeners)
            # 연결 해제 로그 출력
            log_line("PUSH", event="client-disconnect", clients=listener_count)

    def publish(self, message_type: str, **payload: Any) -> None:
        """
        서버의 다른 로직(동기/비동기 무관)에서 호출하여, 
        연결된 모든 웹소켓 클라이언트에게 메시지를 브로드캐스트하는 메서드입니다.
        """
        # 1. 전송할 메시지를 JSON 문자열로 인코딩 (한글 깨짐 방지를 위해 ensure_ascii=False)
        message = {"type": message_type, **payload}
        encoded = json.dumps(message, ensure_ascii=False)
        
        # 2. 락을 걸고 현재 연결된 리스너 목록의 복사본(리스트)을 생성
        # (순회하는 동안 딕셔너리 크기가 변경되어 발생하는 런타임 에러 방지)
        with self._lock:
            listeners = list(self._listeners.items())
            listener_count = len(listeners)
            
        # 연결된 클라이언트가 없으면 바로 종료
        if listener_count <= 0:
            return
            
        # 3. 메시지 발송 로그 기록 (종류에 따라 요약 기록할지 즉시 기록할지 내부에서 결정)
        self._log_publish(
            message_type=message_type,
            listener_count=listener_count,
            payload=payload,
        )
        
        stale_listener_ids: list[int] = []
        
        # 4. 모든 클라이언트의 큐에 메시지 삽입
        for listener_id, (loop, queue) in listeners:
            try:
                # publish가 일반 동기 스레드에서 호출될 수 있으므로, 
                # 비동기 이벤트 루프에 안전하게 작업을 넘기기 위해 call_soon_threadsafe 사용
                loop.call_soon_threadsafe(self._enqueue_message, queue, encoded)
            except RuntimeError:
                # 루프가 닫혀있는 등 예외가 발생하면 죽은 리스너로 간주하고 ID 수집
                stale_listener_ids.append(listener_id)

        # 5. 죽은 리스너(stale)가 발견되었다면 목록에서 제거 정리
        if stale_listener_ids:
            with self._lock:
                for listener_id in stale_listener_ids:
                    self._listeners.pop(listener_id, None)

    def _log_publish(
        self,
        *,
        message_type: str,
        listener_count: int,
        payload: dict[str, Any],
    ) -> None:
        """메시지 전송 로그를 처리합니다. 빈번한 이벤트는 요약하고, 나머지는 즉시 출력합니다."""
        # 상태 변경 이벤트는 너무 자주 발생할 수 있으므로, 즉시 로그를 찍지 않고 카운트만 증가시킴
        if message_type == "source_status_changed":
            self._record_publish_summary(
                message_type=message_type,
                listener_count=listener_count,
            )
            return

        # 다른 일반 이벤트 로그를 찍기 전에, 모아둔 요약 로그가 있다면 시간 체크 후 출력(flush)
        self._flush_publish_summary(force=False, listener_count=listener_count)
        
        # 즉시 로그 출력
        log_line(
            "PUSH",
            event=message_type,
            clients=listener_count,
            source=str(payload.get("source_key", "")).strip() or None,
            action=str(payload.get("action", "")).strip() or None,
            state=str(payload.get("state", "")).strip() or None,
        )

    def _record_publish_summary(
        self,
        *,
        message_type: str,
        listener_count: int,
    ) -> None:
        """빈번하게 발생하는 이벤트의 호출 횟수를 누적합니다."""
        with self._lock:
            # 딕셔너리에 해당 메시지 타입의 카운트를 1 증가
            self._summary_counts[message_type] = self._summary_counts.get(message_type, 0) + 1
            
        # 카운트 누적 후, 요약 주기가 지났는지 확인하여 지났다면 로그로 출력(flush)
        self._flush_publish_summary(force=False, listener_count=listener_count)

    def _flush_publish_summary(self, *, force: bool, listener_count: int) -> None:
        """일정 시간(5초) 동안 모인 요약 카운트를 실제 로그로 배출(출력)하고 초기화합니다."""
        now = monotonic()
        with self._lock:
            elapsed = now - self._summary_last_flush
            
            # 강제(force) 배출이 아니고, 설정된 5초가 아직 안 지났다면 그냥 리턴
            if not force and elapsed < self._summary_interval_seconds:
                return
                
            # 배출 조건이 충족되었다면 현재까지의 카운트를 복사하고 딕셔너리 초기화
            summary_counts = dict(self._summary_counts)
            self._summary_counts.clear()
            self._summary_last_flush = now
            
        # 복사해둔 카운트 정보를 바탕으로 요약 로그(PUSH-SUM) 출력
        for message_type, count in summary_counts.items():
            if count <= 0:
                continue
            log_line(
                "PUSH-SUM",
                event=message_type,
                count=count,
                clients=listener_count,
                window=f"{elapsed:.1f}s", # 몇 초 동안 모인 데이터인지 기록
            )

    @staticmethod
    def _enqueue_message(queue: asyncio.Queue[str], payload: str) -> None:
        """
        비동기 큐에 실제 메시지를 밀어넣는 정적 메서드입니다.
        큐가 꽉 차있을 때 데드락(무한 대기)에 빠지는 것을 막기 위해 가장 오래된 메시지를 버립니다.
        """
        # 큐가 꽉 찼다면 (maxsize=128에 도달)
        if queue.full():
            try:
                # 대기 없이(nowait) 가장 오래된 메시지 하나를 꺼내서 버림(Drop)
                queue.get_nowait()
            except asyncio.QueueEmpty:
                pass
                
        try:
            # 공간이 확보된 큐에 새로운 메시지를 대기 없이 삽입
            queue.put_nowait(payload)
        except asyncio.QueueFull:
            # 만약 그 찰나의 순간에 또 큐가 찼다면 무시 (안전장치)
            pass

realtime_update_hub = RealtimeUpdateHub()