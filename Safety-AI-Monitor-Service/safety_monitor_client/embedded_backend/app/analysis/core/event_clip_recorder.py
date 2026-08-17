# 이벤트 발생 전후 프레임을 모아 mp4 클립으로 저장하는 파일입니다.
# 프레임 버퍼 관리와 클립 파일 생성 흐름이 포함되어 있습니다.

from collections import deque
from dataclasses import dataclass
from pathlib import Path

import cv2

from core.async_workers import AsyncTaskWorker
from core.event_rule import Event
from core.event_types import EventStatus


@dataclass
class ClipFrame:
    frame_id: int
    frame: object


@dataclass
class ClipState:
    writer: object
    clip_path: str
    last_frame_id: int


@dataclass
class _ClipCommand:
    kind: str
    event_key: str
    event: Event | None = None
    frame: object | None = None
    frame_id: int = -1


class EventClipRecorder:
    # EventStatus.START/END 흐름에 맞춰 비디오 파일 쓰기를 관리합니다.
    def __init__(
        self,
        enabled: bool,
        clip_dir: str,
        fps: float,
        before_seconds: float,
        source_slug: str = "",
        queue_size: int = 512,
    ) -> None:
        self.enabled = enabled
        self.clip_dir = Path(clip_dir)
        self.fps = fps if fps > 0 else 30.0
        self.before_seconds = max(0.0, before_seconds)
        self.before_frame_count = max(1, int(self.fps * self.before_seconds))
        self.frame_buffer: deque[ClipFrame] = deque(maxlen=self.before_frame_count)
        self.clip_states: dict[str, ClipState] = {}
        self.source_slug = source_slug.strip()
        self.clip_path_by_event_key: dict[str, str] = {}
        self.worker: AsyncTaskWorker[_ClipCommand] | None = None
        if self.enabled:
            self.worker = AsyncTaskWorker[_ClipCommand](
                name="clip-write-worker",
                consumer=self._consume_command,
                max_queue_size=queue_size,
            )

    def update(
        self,
        frame,
        frame_id: int,
        active_events: list[Event],
        state_events: list[Event],
    ) -> None:
        if not self.enabled:
            return

        self.frame_buffer.append(ClipFrame(frame_id=frame_id, frame=frame))

        for event in state_events:
            if event.status == EventStatus.START:
                self._submit_command(
                    _ClipCommand(
                        kind="start",
                        event_key=event.event_key,
                        event=event,
                        frame=frame,
                        frame_id=frame_id,
                    )
                )

        for event in active_events:
            self._submit_command(
                _ClipCommand(
                    kind="write",
                    event_key=event.event_key,
                    frame=frame,
                    frame_id=frame_id,
                )
            )

        for event in state_events:
            if event.status == EventStatus.END:
                self._submit_command(
                    _ClipCommand(
                        kind="finish",
                        event_key=event.event_key,
                        event=event,
                    )
                )
                if self.worker is not None:
                    self.worker.drain()

    def finalize(self, events: list[Event]) -> None:
        if not self.enabled:
            return

        for event in events:
            self._submit_command(
                _ClipCommand(
                    kind="finish",
                    event_key=event.event_key,
                    event=event,
                )
            )

        if self.worker is not None:
            self.worker.close()
            self.worker = None

        for event in events:
            clip_path = self.clip_path_by_event_key.get(event.event_key, "")
            if clip_path:
                event.clip_path = clip_path

    def _submit_command(self, command: _ClipCommand) -> None:
        if self.worker is None:
            return
        submitted = self.worker.submit(command, timeout_seconds=0.1)
        if not submitted:
            self._consume_command(command)

    def _consume_command(self, command: _ClipCommand) -> None:
        if command.kind == "start" and command.event is not None and command.frame is not None:
            self._start_clip(
                event=command.event,
                frame=command.frame,
                frame_id=command.frame_id,
            )
            return
        if command.kind == "write" and command.frame is not None:
            self._write_active_frame(
                event_key=command.event_key,
                frame=command.frame,
                frame_id=command.frame_id,
            )
            return
        if command.kind == "finish" and command.event is not None:
            self._finish_clip(command.event)

    def _start_clip(self, event: Event, frame, frame_id: int) -> None:
        if event.event_key in self.clip_states:
            return

        height, width = frame.shape[:2]
        self.clip_dir.mkdir(parents=True, exist_ok=True)
        clip_name = (
            f"{event.event_type.value}_{event.person_id or 'x'}_{event.started_frame_id}.mp4"
        )
        if self.source_slug:
            clip_name = f"{self.source_slug}__{clip_name}"
        clip_path = str((self.clip_dir / clip_name).resolve())
        writer = cv2.VideoWriter(
            clip_path,
            cv2.VideoWriter_fourcc(*"mp4v"),
            self.fps,
            (width, height),
        )
        if not writer.isOpened():
            return

        clip_state = ClipState(
            writer=writer,
            clip_path=clip_path,
            last_frame_id=-1,
        )
        self.clip_states[event.event_key] = clip_state
        self.clip_path_by_event_key[event.event_key] = clip_path

        writer.write(frame)
        clip_state.last_frame_id = frame_id

    def _write_active_frame(self, event_key: str, frame, frame_id: int) -> None:
        clip_state = self.clip_states.get(event_key)
        if clip_state is None:
            return
        if frame_id <= clip_state.last_frame_id:
            return

        clip_state.writer.write(frame)
        clip_state.last_frame_id = frame_id

    def _finish_clip(self, event: Event) -> None:
        clip_state = self.clip_states.pop(event.event_key, None)
        if clip_state is None:
            return

        clip_state.writer.release()
        event.clip_path = clip_state.clip_path
