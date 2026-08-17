# 분석 파이프라인 안에서 사용하는 frame_detection_recorder 기능을 분리한 파일입니다.
# pipeline.py에서 조립되는 분석 부품 중 하나입니다.

import time
from pathlib import Path

import requests

from app.log_utils import log_line
from core.async_workers import AsyncLatestWorker
from core.detection_model import DetectionResult
from core.event_serializer import serialize_detection


class FrameDetectionRecorder:
    # 프레임 단위 전체 탐지 결과를 JSON Lines로 저장합니다.
    # 이벤트 로그와 달리 현재 프레임의 실제 탐지 객체를 그대로 복원하기 위한 용도입니다.
    def __init__(
        self,
        log_path: str,
        *,
        post_url: str = "",
        timeout_seconds: float = 1.0,
        max_post_fps: float = 8.0,
    ) -> None:
        self.log_path = Path(log_path)
        self.log_path.parent.mkdir(parents=True, exist_ok=True)
        self.post_url = post_url.strip()
        self.timeout_seconds = timeout_seconds
        self.max_post_fps = max(0.0, max_post_fps)
        self.last_posted_at = 0.0
        self.session = requests.Session()
        self.post_worker: AsyncLatestWorker[dict] | None = None
        if self.post_url:
            self.post_worker = AsyncLatestWorker(
                name="frame-detection-post-worker",
                consumer=self._post_record_sync,
            )

    def write(
        self,
        result: DetectionResult,
        *,
        source_type: str,
        source_value: str,
        source_key: str,
        source_slug: str,
        frame_width: int,
        frame_height: int,
    ) -> None:
        record = {
            "frame_id": result.frame_id,
            "source_type": source_type,
            "source_value": source_value,
            "source_key": source_key,
            "source_slug": source_slug,
            "source_time_seconds": result.source_time_seconds,
            "source_time_text": result.source_time_text,
            "frame_width": frame_width,
            "frame_height": frame_height,
            "detections": [
                serialize_detection(detection)
                for detection in result.detections
            ],
        }
        self._post_record(record)

    def _post_record(self, record: dict) -> None:
        if not self.post_url:
            return
        now_ts = time.time()
        if self.max_post_fps > 0:
            min_interval = 1.0 / self.max_post_fps
            if (now_ts - self.last_posted_at) < min_interval:
                return
        self.last_posted_at = now_ts
        if self.post_worker is not None:
            self.post_worker.submit(dict(record))

    def _post_record_sync(self, record: dict) -> None:
        try:
            self.session.post(
                self.post_url,
                json=record,
                timeout=self.timeout_seconds,
            )
        except requests.RequestException as error:
            log_line("WARN", message="frame detection post failed", error=error)

    def close(self) -> None:
        if self.post_worker is not None:
            self.post_worker.close(timeout_seconds=max(15.0, self.timeout_seconds + 5.0))
        self.session.close()
