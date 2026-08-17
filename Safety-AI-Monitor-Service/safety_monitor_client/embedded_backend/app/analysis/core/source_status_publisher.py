# 분석 파이프라인 안에서 사용하는 source_status_publisher 기능을 분리한 파일입니다.
# pipeline.py에서 조립되는 분석 부품 중 하나입니다.

from datetime import datetime

import requests

from app.log_utils import log_line
from core.async_workers import AsyncLatestWorker


class SourceStatusPublisher:
    def __init__(
        self,
        *,
        post_url: str,
        timeout_seconds: float = 1.0,
        min_interval_seconds: float = 0.5,
    ) -> None:
        self.post_url = post_url.strip()
        self.timeout_seconds = timeout_seconds
        self.min_interval_seconds = min_interval_seconds
        self._last_posted_at = 0.0
        self._last_payload_signature = ""
        self._session = requests.Session()
        self._post_worker = AsyncLatestWorker(
            name="source-status-post-worker",
            consumer=self._post_payload_sync,
        )

    def publish(
        self,
        *,
        source_key: str,
        source_type: str,
        source_value: str,
        source_fps: float,
        client_id: str,
        session_id: str,
        state: str,
        is_running: bool,
        source_duration_seconds: float = 0.0,
        last_frame_id: int = -1,
        last_source_time_seconds: float = 0.0,
        avg_object_detection_ms: float = 0.0,
        error_message: str = "",
        force: bool = False,
    ) -> None:
        if not self.post_url or not source_key.strip():
            return

        now_ts = datetime.now().timestamp()
        if not force and (now_ts - self._last_posted_at) < self.min_interval_seconds:
            return

        payload = {
            "source_key": source_key,
            "source_type": source_type,
            "source_value": source_value,
            "client_id": client_id,
            "session_id": session_id,
            "state": state,
            "is_running": is_running,
            "source_fps": source_fps,
            "source_duration_seconds": source_duration_seconds,
            "last_frame_id": last_frame_id,
            "last_source_time_seconds": last_source_time_seconds,
            "avg_object_detection_ms": avg_object_detection_ms,
            "error_message": error_message,
            "updated_at": datetime.now().isoformat(),
        }
        signature = (
            f"{source_key}|{state}|{1 if is_running else 0}|{last_frame_id}|"
            f"{last_source_time_seconds:.3f}|{error_message}"
        )
        if not force and signature == self._last_payload_signature:
            return

        self._post_worker.submit(payload)
        self._last_posted_at = now_ts
        self._last_payload_signature = signature

    def _post_payload_sync(self, payload: dict[str, object]) -> None:
        try:
            self._session.post(
                self.post_url,
                json=payload,
                timeout=self.timeout_seconds,
            )
        except requests.RequestException as error:
            log_line("WARN", message="source status post failed", error=error)

    def close(self) -> None:
        self._post_worker.close(timeout_seconds=max(15.0, self.timeout_seconds + 5.0))
        self._session.close()
