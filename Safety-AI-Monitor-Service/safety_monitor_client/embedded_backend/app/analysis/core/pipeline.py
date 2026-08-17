# 분석 파이프라인 안에서 사용하는 pipeline 기능을 분리한 파일입니다.
# pipeline.py에서 조립되는 분석 부품 중 하나입니다.

from datetime import datetime
import threading

import cv2
from app.log_utils import log_line

from core.detection_model import Box, DetectionModel, DetectionResult
from core.event_clip_recorder import EventClipRecorder
from core.event_filter import EventFilter
from core.event_handler import EventHandler
from core.event_rule import EventRule
from core.frame_detection_recorder import FrameDetectionRecorder
from core.frame_source import FrameSource
from core.object_tracker import PersonTracker
from core.pipeline_profiler import PipelineProfiler
from core.source_status_publisher import SourceStatusPublisher
from typing import Any

# 이 파일은 실제 프레임 처리 루프를 담당합니다.
# 프레임을 읽고, DetectionResult를 만들고, EventRule/EventFilter/EventHandler 흐름을 순서대로 실행합니다.

_MODEL_LOAD_LOCK = threading.Lock()


class VideoPipeline:
    # 하나의 입력 소스를 끝까지 분석하는 실행 단위입니다.
    # Python AI Worker의 핵심 루프가 이 클래스 안에 있습니다.
    def __init__(
        self,
        frame_source: FrameSource,
        model: DetectionModel,
        rules: list[EventRule],
        handlers: list[EventHandler],
        event_filter: EventFilter,
        tracker: PersonTracker,
        clip_recorder: EventClipRecorder,
        frame_detection_recorder: FrameDetectionRecorder,
        show_screen: bool,
        restart_checker=None,
        source_type: str = "",
        source_value: str = "",
        source_key: str = "",
        source_slug: str = "",
        client_id: str = "",
        session_id: str = "",
        source_fps: float = 0.0,
        source_duration_seconds: float = 0.0,
        source_status_publisher: SourceStatusPublisher | None = None,
        preview_publisher: Any | None = None,
        analysis_target_fps: float = 0.0,
        model_input_max_width: int = 0,
        enable_perf_log: bool = False,
        perf_log_interval_frames: int = 120,
    ) -> None:
        self.frame_source = frame_source
        self.model = model
        self.rules = rules
        self.handlers = handlers
        self.event_filter = event_filter
        self.tracker = tracker
        self.clip_recorder = clip_recorder
        self.frame_detection_recorder = frame_detection_recorder
        self.show_screen = show_screen
        self.screen_available = show_screen
        self.source_time_mode = "real"
        self.restart_checker = restart_checker
        self.source_type = source_type
        self.source_value = source_value
        self.source_key = source_key
        self.source_slug = source_slug
        self.client_id = client_id
        self.session_id = session_id
        self.source_fps = source_fps
        self.source_duration_seconds = max(0.0, source_duration_seconds)
        self.source_status_publisher = source_status_publisher
        self.preview_publisher = preview_publisher
        self.analysis_target_fps = max(0.0, analysis_target_fps)
        self.model_input_max_width = max(0, model_input_max_width)
        self.last_processed_frame_id = -1
        self.last_processed_source_time_seconds = 0.0
        self.object_detection_total_seconds = 0.0
        self.object_detection_frame_count = 0
        self.object_detection_seen_frame_count = 0
        self.analysis_frame_stride = 1
        self.profiler = PipelineProfiler(
            enabled=enable_perf_log,
            log_interval_frames=perf_log_interval_frames,
            source_label=source_key or source_value,
        )

    def run(self) -> str:
        # 이 함수가 실제 분석 루프입니다.
        # 매 프레임마다 모델 추론 -> 이벤트 판정 -> 상태 관리 -> 로그/클립 저장이 이어집니다.
        frame_id = 0
        stop_reason = "completed"
        first_frame_logged = False
        first_predict_logged = False

        log_line("SRC", action="open", source=self.source_key, type=self.source_type)
        self.frame_source.open()
        log_line("SRC", action="opened", source=self.source_key, fps=f"{self.source_fps:.2f}")
        self.analysis_frame_stride = self._build_analysis_frame_stride()
        if self.analysis_frame_stride > 1:
            log_line(
                "SRC",
                action="analysis-stride",
                source=self.source_key,
                stride=self.analysis_frame_stride,
                target_fps=f"{self.analysis_target_fps:.2f}",
            )
        log_line(
            "SRC",
            action="model-load",
            source=self.source_key,
            model=self.model.get_name(),
        )
        with _MODEL_LOAD_LOCK:
            self.model.load()
        log_line(
            "SRC",
            action="model-ready",
            source=self.source_key,
            model=self.model.get_name(),
        )
        if self.frame_source.__class__.__name__ == "VideoFileFrameSource":
            self.source_time_mode = "video"
        self._publish_source_status(
            state="running",
            is_running=True,
            force=True,
        )

        try:
            while True:
                self.profiler.begin_frame()
                if self._should_restart():
                    stop_reason = "source_changed"
                    break

                ok, frame = self.profiler.measure(
                    "frame_read",
                    self.frame_source.read,
                )
                if not ok:
                    if self.source_type in {"stream", "camera"}:
                        stop_reason = "disconnected"
                    break
                if not first_frame_logged:
                    log_line(
                        "SRC",
                        action="first-frame",
                        source=self.source_key,
                        frame=frame_id,
                    )
                    first_frame_logged = True
                now = datetime.now()

                if self.analysis_frame_stride > 1 and (frame_id % self.analysis_frame_stride) != 0:
                    frame_id += 1
                    self.profiler.end_frame()
                    continue

                inference_frame, scale_back_x, scale_back_y = self.profiler.measure(
                    "prepare_inference_frame",
                    lambda: self._prepare_inference_frame(frame),
                )

                result = self.profiler.measure(
                    "model_predict",
                    lambda: self._predict_and_record_detection_time(
                        inference_frame,
                        frame_id,
                    ),
                )
                if scale_back_x != 1.0 or scale_back_y != 1.0:
                    result = self.profiler.measure(
                        "restore_detection_scale",
                        lambda: self._restore_detection_result_scale(
                            result,
                            scale_back_x=scale_back_x,
                            scale_back_y=scale_back_y,
                        ),
                    )
                if not first_predict_logged:
                    log_line(
                        "SRC",
                        action="first-predict",
                        source=self.source_key,
                        frame=frame_id,
                        detections=len(result.detections),
                    )
                    first_predict_logged = True
                self._fill_result_time(result=result, now=now, frame_id=frame_id)
                result = self.profiler.measure(
                    "tracker_update",
                    lambda: self.tracker.update(result),
                )
                self.profiler.measure(
                    "frame_detection_write",
                    lambda: self.frame_detection_recorder.write(
                        result,
                        source_type=self.source_type,
                        source_value=self.source_value,
                        source_key=self.source_key,
                        source_slug=self.source_slug,
                        frame_width=frame.shape[1],
                        frame_height=frame.shape[0],
                    ),
                )
                if self.preview_publisher is not None:
                    self.profiler.measure(
                        "source_preview_publish",
                        lambda: self.preview_publisher.publish(
                            frame=frame,
                            result=result,
                            source_key=self.source_key,
                        ),
                    )
                self.last_processed_frame_id = result.frame_id
                self.last_processed_source_time_seconds = result.source_time_seconds
                self.profiler.measure(
                    "source_status_publish",
                    lambda: self._publish_source_status(
                        state="running",
                        is_running=True,
                        last_frame_id=result.frame_id,
                        last_source_time_seconds=result.source_time_seconds,
                    ),
                )

                def _run_rules() -> list[object]:
                    next_events = []
                    for rule in self.rules:
                        next_events.extend(rule.check(result))
                    return next_events

                events = self.profiler.measure("rule_check", _run_rules)

                state_events = self.profiler.measure(
                    "event_filter_update",
                    lambda: self.event_filter.update(
                        events=events,
                    ),
                )
                active_events = self.profiler.measure(
                    "active_event_lookup",
                    lambda: self.event_filter.get_active_events(
                        frame_id=frame_id,
                        now=now,
                    ),
                )
                self._attach_source_context(state_events)
                self._attach_source_context(active_events)
                self.profiler.measure(
                    "clip_update",
                    lambda: self.clip_recorder.update(
                        frame=frame,
                        frame_id=frame_id,
                        active_events=active_events,
                        state_events=state_events,
                    ),
                )

                def _handle_state_events() -> None:
                    for event in state_events:
                        for handler in self.handlers:
                            handler.handle(event)

                self.profiler.measure("state_event_handlers", _handle_state_events)

                def _handle_active_events() -> None:
                    for event in active_events:
                        for handler in self.handlers:
                            if handler.__class__.__name__ in {
                                "LogEventHandler",
                                "JsonEventHandler",
                                "HttpEventHandler",
                            }:
                                handler.handle(event)

                self.profiler.measure("active_event_handlers", _handle_active_events)

                if self.screen_available:
                    display_frame = self.profiler.measure(
                        "display_render",
                        lambda: self._make_display_frame(
                            frame=frame,
                            result=result,
                            events=active_events,
                        ),
                    )
                    if not self._show_frame(display_frame):
                        self.screen_available = False
                    elif cv2.waitKey(1) & 0xFF == ord("q"):
                        break

                frame_id += 1
                self.profiler.end_frame()
        finally:
            closed_events = self.event_filter.close_all()
            self._attach_source_context(closed_events)
            self.clip_recorder.finalize(closed_events)
            for event in closed_events:
                for handler in self.handlers:
                    handler.handle(event)
            self.frame_source.release()
            self._close_screen()
            self._publish_source_status(
                state=stop_reason if stop_reason != "completed" else "completed",
                is_running=False,
                last_frame_id=self.last_processed_frame_id,
                last_source_time_seconds=self.last_processed_source_time_seconds,
                force=True,
            )
            self.frame_detection_recorder.close()
            for handler in self.handlers:
                close = getattr(handler, "close", None)
                if callable(close):
                    close()
            if self.source_status_publisher is not None:
                self.source_status_publisher.close()

        return stop_reason

    def _build_analysis_frame_stride(self) -> int:
        if self.analysis_target_fps <= 0:
            return 1
        if self.source_fps <= 0:
            return 1
        if self.source_fps <= self.analysis_target_fps:
            return 1
        return max(1, int(round(self.source_fps / self.analysis_target_fps)))

    def _prepare_inference_frame(self, frame) -> tuple[object, float, float]:
        if self.model_input_max_width <= 0:
            return frame, 1.0, 1.0

        height, width = frame.shape[:2]
        if width <= self.model_input_max_width:
            return frame, 1.0, 1.0

        resize_ratio = self.model_input_max_width / max(1, width)
        next_width = max(1, int(round(width * resize_ratio)))
        next_height = max(1, int(round(height * resize_ratio)))
        resized_frame = cv2.resize(
            frame,
            (next_width, next_height),
            interpolation=cv2.INTER_AREA,
        )
        return resized_frame, width / next_width, height / next_height

    def _restore_detection_result_scale(
        self,
        result: DetectionResult,
        *,
        scale_back_x: float,
        scale_back_y: float,
    ) -> DetectionResult:
        for detection in result.detections:
            detection.box = Box(
                x1=int(round(detection.box.x1 * scale_back_x)),
                y1=int(round(detection.box.y1 * scale_back_y)),
                x2=int(round(detection.box.x2 * scale_back_x)),
                y2=int(round(detection.box.y2 * scale_back_y)),
            )
        return result

    def _should_restart(self) -> bool:
        if self.restart_checker is None:
            return False

        try:
            return bool(self.restart_checker())
        except Exception:
            return False

    def _show_frame(self, frame) -> bool:
        try:
            cv2.imshow("Safety AI Monitor", frame)
            return True
        except cv2.error as error:
            log_line("WARN", message="OpenCV 화면 표시를 사용할 수 없습니다", error=error)
            return False

    def _close_screen(self) -> None:
        if not self.screen_available:
            return

        try:
            cv2.destroyAllWindows()
        except cv2.error as error:
            log_line("WARN", message="OpenCV 창 정리를 건너뜁니다", error=error)

    def _make_display_frame(self, frame, result, events):
        display_frame = frame.copy()

        for detection in result.detections:
            x1 = detection.box.x1
            y1 = detection.box.y1
            x2 = detection.box.x2
            y2 = detection.box.y2

            color = _color_for_detection_name(detection.name)
            cv2.rectangle(display_frame, (x1, y1), (x2, y2), color, 2)
            label = f"{detection.name} {detection.score:.2f}"
            cv2.putText(
                display_frame,
                label,
                (x1, max(20, y1 - 8)),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.6,
                color,
                2,
            )

        event_y = 30
        for event in events:
            person_text = ""
            if event.person_id is not None:
                person_text = f" person={event.person_id}"
            event_text = (
                f"{event.level.value} {event.message}"
                f"{person_text} {event.duration_seconds:.1f}s"
            )
            cv2.putText(
                display_frame,
                event_text,
                (10, event_y),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.7,
                (0, 0, 255),
                2,
            )
            event_y += 30

        return display_frame

    def _fill_result_time(self, result, now: datetime, frame_id: int) -> None:
        source_seconds = self.frame_source.get_time_seconds()
        if self.source_time_mode == "video":
            if source_seconds is None:
                source_seconds = frame_id / max(1.0, self.frame_source.get_fps())
            result.source_time_seconds = source_seconds
            result.source_time_text = self._format_video_time(source_seconds)
            result.event_created_at = datetime.fromtimestamp(source_seconds)
            return

        result.source_time_seconds = 0.0 if source_seconds is None else source_seconds
        result.source_time_text = now.isoformat(timespec="seconds")
        result.event_created_at = now

    def _format_video_time(self, seconds_value: float) -> str:
        total_ms = max(0, int(seconds_value * 1000))
        minutes = (total_ms // 60000) % 60
        seconds = (total_ms // 1000) % 60
        milliseconds = total_ms % 1000
        hours = total_ms // 3600000
        if hours > 0:
            return f"{hours:02d}:{minutes:02d}:{seconds:02d}.{milliseconds:03d}"
        return f"{minutes:02d}:{seconds:02d}.{milliseconds:03d}"

    def _attach_source_context(self, events: list[object]) -> None:
        for event in events:
            setattr(event, "source_type", self.source_type)
            setattr(event, "source_value", self.source_value)
            setattr(event, "source_key", self.source_key)
            setattr(event, "source_slug", self.source_slug)
            setattr(event, "client_id", self.client_id)
            setattr(event, "session_id", self.session_id)

    def _publish_source_status(
        self,
        *,
        state: str,
        is_running: bool,
        last_frame_id: int = -1,
        last_source_time_seconds: float = 0.0,
        error_message: str = "",
        force: bool = False,
    ) -> None:
        if self.source_status_publisher is None:
            return

        self.source_status_publisher.publish(
            source_key=self.source_key,
            source_type=self.source_type,
            source_value=self.source_value,
            source_fps=self.source_fps,
            client_id=self.client_id,
            session_id=self.session_id,
            state=state,
            is_running=is_running,
            source_duration_seconds=self.source_duration_seconds,
            last_frame_id=last_frame_id,
            last_source_time_seconds=last_source_time_seconds,
            avg_object_detection_ms=self._average_object_detection_ms(),
            error_message=error_message,
            force=force,
        )

    def _predict_and_record_detection_time(
        self,
        inference_frame: object,
        frame_id: int,
    ) -> DetectionResult:
        result = self.model.predict(inference_frame, frame_id)
        inference_ms = self.model.get_last_inference_ms()
        self.object_detection_seen_frame_count += 1
        if inference_ms <= 0.0:
            return result
        if self._should_skip_detection_metric_frame():
            return result

        self.object_detection_total_seconds += inference_ms / 1000.0
        self.object_detection_frame_count += 1
        return result

    def _average_object_detection_ms(self) -> float:
        if self.object_detection_frame_count <= 0:
            return 0.0
        return (
            self.object_detection_total_seconds
            / self.object_detection_frame_count
        ) * 1000.0

    def _should_skip_detection_metric_frame(self) -> bool:
        if self.source_time_mode != "video":
            return False
        return self.object_detection_seen_frame_count <= 50

def _color_for_detection_name(name: str) -> tuple[int, int, int]:
    normalized = str(name or "").strip().lower()
    if normalized in {"yes_helmet", "helmet", "hardhat"}:
        return (0, 255, 0)
    if normalized in {"no_helmet", "without_helmet", "no helmet"}:
        return (0, 0, 255)
    if normalized == "person":
        return (0, 255, 255)
    return (0, 255, 255)
