# 이벤트 발생 전후의 프레임을 모아 짧은 mp4 클립으로 저장하는 모듈입니다.
# 이 파일은 소스별로 프레임을 임시 버퍼에 쌓아두고, 이벤트가 발생한 시점 기준으로
# 사전/사후 구간을 포함한 영상 파일과 썸네일을 생성하는 역할을 담당합니다.

from __future__ import annotations

import hashlib
import re
from collections import deque
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path
from threading import RLock

import cv2
import numpy as np

from app.config import SERVER_CLIP_DIR, SERVER_EVENT_THUMBNAIL_DIR


@dataclass(frozen=True)
class _BufferedFrame:
    captured_at: datetime
    jpeg_bytes: bytes


class ServerClipRecorder:
    """소스별 프레임 버퍼를 관리하고 이벤트 클립을 생성하는 녹화기입니다."""

    def __init__(
        self,
        *,
        clip_dir: Path,
        buffer_seconds: float = 45.0,
        before_seconds: float = 3.0,
        after_seconds: float = 1.0,
        fallback_fps: float = 10.0,
    ) -> None:
        # 클립이 저장될 디렉터리와, 이벤트 발생 전후에 포함할 프레임 범위를 설정한다.
        # 버퍼 시간은 너무 짧으면 이벤트 직전 상황을 놓칠 수 있으므로 최소값을 보장한다.
        self.clip_dir = clip_dir
        self.buffer_seconds = max(5.0, buffer_seconds)
        self.before_seconds = max(0.0, before_seconds)
        self.after_seconds = max(0.0, after_seconds)
        self.fallback_fps = max(1.0, fallback_fps)
        self._frames_by_source_key: dict[str, deque[_BufferedFrame]] = {}
        self._lock = RLock()

    def add_frame(
        self,
        *,
        source_key: str,
        jpeg_bytes: bytes,
        captured_at: datetime | None = None,
    ) -> None:
        # 새로 들어온 프레임을 소스별 버퍼에 저장한다.
        # 빈 소스 키나 빈 이미지 데이터는 처리하지 않아 불필요한 저장을 막는다.
        normalized_source_key = source_key.strip()
        if not normalized_source_key or not jpeg_bytes:
            return
        frame = _BufferedFrame(
            captured_at=captured_at or datetime.now(),
            jpeg_bytes=bytes(jpeg_bytes),
        )
        # 버퍼는 일정 시간만 유지되며, 너무 오래된 프레임은 자동으로 제거한다.
        # 이를 통해 이벤트 발생 전후의 짧은 영상만 남기고 메모리 사용을 제어한다.
        cutoff = frame.captured_at - timedelta(seconds=self.buffer_seconds)
        with self._lock:
            frames = self._frames_by_source_key.setdefault(
                normalized_source_key,
                deque(),
            )
            frames.append(frame)
            while frames and frames[0].captured_at < cutoff:
                frames.popleft()

    def encode_event_clip(
        self,
        *,
        source_key: str,
        source_slug: str,
        event_key: str,
        started_at: datetime,
        ended_at: datetime,
    ) -> dict[str, object] | None:
        # 이벤트가 발생한 소스 기준으로, 해당 소스의 버퍼에서 이벤트 구간에 해당하는 프레임만 골라낸다.
        # 시작 시간은 before_seconds만큼 앞당기고, 종료 시간은 after_seconds만큼 뒤로 확장해
        # 이벤트 직전/직후 상황까지 포함할 수 있게 한다.
        normalized_source_key = source_key.strip()
        if not normalized_source_key:
            return None

        start_window = started_at - timedelta(seconds=self.before_seconds)
        end_window = ended_at + timedelta(seconds=self.after_seconds)
        with self._lock:
            buffered = list(self._frames_by_source_key.get(normalized_source_key, ()))

        selected = [
            frame
            for frame in buffered
            if start_window <= frame.captured_at <= end_window
        ]
        if not selected:
            return None

        # JPEG 바이트를 OpenCV 이미지로 복원한다.
        # 디코딩에 실패한 프레임은 제외하고, 남은 프레임만 영상으로 조합한다.
        decoded_frames = [_decode_jpeg(frame.jpeg_bytes) for frame in selected]
        decoded_frames = [frame for frame in decoded_frames if frame is not None]
        if not decoded_frames:
            return None

        # 클립 저장 디렉터리가 없으면 생성하고, 파일명 규칙에 따라 저장 경로를 만든다.
        self.clip_dir.mkdir(parents=True, exist_ok=True)
        clip_name = self._build_clip_name(
            source_key=normalized_source_key,
            source_slug=source_slug,
            event_key=event_key,
            ended_at=ended_at,
        )
        clip_path = (self.clip_dir / clip_name).resolve()
        thumbnail_name = f"{Path(clip_name).stem}.jpg"
        thumbnail_path = (SERVER_EVENT_THUMBNAIL_DIR / thumbnail_name).resolve()

        # 첫 프레임의 크기를 기준으로 영상의 폭/높이를 결정하고, 프레임 간 간격을 추정한다.
        # 이 값이 너무 낮거나 높으면 영상 재생 품질이 나빠질 수 있어 범위 내로 보정한다.
        height, width = decoded_frames[0].shape[:2]
        fps = self._estimate_fps(selected)
        writer = cv2.VideoWriter(
            str(clip_path),
            cv2.VideoWriter_fourcc(*"mp4v"),
            fps,
            (width, height),
        )
        if not writer.isOpened():
            return None
        try:
            # 각 프레임을 영상 파일에 순서대로 기록한다.
            # 크기가 다르면 동일한 해상도로 맞춰 리사이즈한 뒤 저장한다.
            for frame in decoded_frames:
                next_frame = frame
                if frame.shape[1] != width or frame.shape[0] != height:
                    next_frame = cv2.resize(frame, (width, height))
                writer.write(next_frame)
        finally:
            writer.release()

        # 저장된 파일이 실제로 생성되었는지 확인하고, 비어 있으면 실패로 처리한다.
        if not clip_path.exists() or clip_path.stat().st_size <= 0:
            clip_path.unlink(missing_ok=True)
            return None

        try:
            # 썸네일은 이벤트 대표 이미지로 쓰이므로 별도 디렉터리에 저장한다.
            SERVER_EVENT_THUMBNAIL_DIR.mkdir(parents=True, exist_ok=True)
            thumbnail_path.write_bytes(selected[0].jpeg_bytes)
        except OSError:
            thumbnail_name = ""

        return {
            "clip_path": str(clip_path),
            "clip_url": f"/api/clips/{clip_name}",
            "server_clip_name": clip_name,
            "server_clip_path": f"clips/{clip_name}",
            "thumbnail_url": f"/api/event-thumbnails/{thumbnail_name}" if thumbnail_name else "",
            "thumbnail_name": thumbnail_name,
            "clip_available": True,
            "clip_upload_ok": True,
            "preferred_clip_source": "server",
        }

    def clear_all(self) -> None:
        # 메모리 상의 모든 소스 버퍼를 초기화해 새 세션을 시작할 수 있게 한다.
        with self._lock:
            self._frames_by_source_key.clear()

    def clear_source(self, source_key: str) -> None:
        # 특정 소스의 프레임 버퍼만 제거한다.
        # 소스가 재등록되거나 연결이 끊겼을 때 정리용으로 사용한다.
        normalized_source_key = source_key.strip()
        if not normalized_source_key:
            return
        with self._lock:
            self._frames_by_source_key.pop(normalized_source_key, None)

    def _estimate_fps(self, frames: list[_BufferedFrame]) -> float:
        # 프레임 수와 시간 간격을 바탕으로 적절한 FPS를 계산한다.
        # 너무 적은 수의 프레임이면 기본값을 사용하고, 과도한 값은 제한해서 영상 품질이 깨지지 않게 한다.
        if len(frames) < 2:
            return self.fallback_fps
        duration_seconds = max(
            0.001,
            (frames[-1].captured_at - frames[0].captured_at).total_seconds(),
        )
        fps = (len(frames) - 1) / duration_seconds
        return max(1.0, min(30.0, fps or self.fallback_fps))

    def _build_clip_name(
        self,
        *,
        source_key: str,
        source_slug: str,
        event_key: str,
        ended_at: datetime,
    ) -> str:
        # 저장 파일명은 소스 식별 정보와 이벤트 고유값, 종료 시간으로 구성한다.
        # 동일 이벤트가 중복 저장되지 않도록 해시를 포함하고, 사람이 읽기 쉬운 slug도 함께 사용한다.
        slug = _sanitize_slug(source_slug) or hashlib.sha1(
            source_key.encode("utf-8")
        ).hexdigest()[:12]
        event_digest = hashlib.sha1(event_key.encode("utf-8")).hexdigest()[:10]
        timestamp = ended_at.strftime("%Y%m%d_%H%M%S_%f")
        return f"{slug}__server_event__{timestamp}__{event_digest}.mp4"


def _decode_jpeg(jpeg_bytes: bytes):
    # JPEG 바이트를 OpenCV가 이해할 수 있는 이미지 배열로 변환한다.
    # 이 과정이 실패하면 해당 프레임은 영상 생성에서 제외한다.
    image_array = np.frombuffer(jpeg_bytes, dtype=np.uint8)
    frame = cv2.imdecode(image_array, cv2.IMREAD_COLOR)
    return frame


def _sanitize_slug(value: str) -> str:
    # 파일명에 안전하게 들어가도록 문자열을 소문자/언더스코어 형식으로 정리한다.
    # 특수문자는 밑줄로 대체하고, 너무 긴 값은 잘라서 저장 경로 문제를 방지한다.
    normalized = value.strip().lower()
    normalized = re.sub(r"[^a-z0-9_.-]+", "_", normalized)
    normalized = normalized.strip("._-")
    return normalized[:80]


server_clip_recorder = ServerClipRecorder(clip_dir=SERVER_CLIP_DIR)

