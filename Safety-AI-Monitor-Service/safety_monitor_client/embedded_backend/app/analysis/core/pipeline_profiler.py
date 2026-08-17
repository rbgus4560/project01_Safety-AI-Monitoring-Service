# 분석 파이프라인 안에서 사용하는 pipeline_profiler 기능을 분리한 파일입니다.
# pipeline.py에서 조립되는 분석 부품 중 하나입니다.

from __future__ import annotations

from time import perf_counter

from app.log_utils import log_line


class PipelineProfiler:
    def __init__(
        self,
        *,
        enabled: bool,
        log_interval_frames: int = 120,
        source_label: str = "",
    ) -> None:
        self.enabled = enabled
        self.log_interval_frames = max(1, log_interval_frames)
        self.source_label = source_label
        self.frame_count = 0
        self.stage_totals: dict[str, float] = {}
        self.frame_started_at = 0.0

    def begin_frame(self) -> None:
        if not self.enabled:
            return
        self.frame_started_at = perf_counter()

    def measure(self, stage_name: str, callback):
        if not self.enabled:
            return callback()

        started_at = perf_counter()
        result = callback()
        elapsed = perf_counter() - started_at
        self.stage_totals[stage_name] = self.stage_totals.get(stage_name, 0.0) + elapsed
        return result

    def end_frame(self) -> None:
        if not self.enabled:
            return

        elapsed = perf_counter() - self.frame_started_at
        self.stage_totals["frame_total"] = self.stage_totals.get("frame_total", 0.0) + elapsed
        self.frame_count += 1
        if self.frame_count < self.log_interval_frames:
            return

        averages = {
            stage_name: (total / self.frame_count) * 1000.0
            for stage_name, total in self.stage_totals.items()
        }
        source_text = self.source_label or "unknown-source"
        total_ms = averages.get("frame_total", 0.0)
        ranked_stages = sorted(
            (
                (stage_name, elapsed_ms)
                for stage_name, elapsed_ms in averages.items()
                if stage_name != "frame_total" and elapsed_ms >= 0.05
            ),
            key=lambda item: item[1],
            reverse=True,
        )
        top_parts = [
            f"{stage_name}={elapsed_ms:.1f}ms"
            for stage_name, elapsed_ms in ranked_stages[:4]
        ]
        log_line(
            "PERF",
            source=source_text,
            frames=self.frame_count,
            avg=f"{total_ms:.1f}ms/frame",
            total=f"{total_ms:.1f}ms",
            top=" ".join(top_parts) if top_parts else "none",
        )
        self.frame_count = 0
        self.stage_totals.clear()
