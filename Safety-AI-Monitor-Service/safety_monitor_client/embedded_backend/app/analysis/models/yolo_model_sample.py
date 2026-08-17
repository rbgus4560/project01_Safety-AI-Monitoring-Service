# 객체 탐지 모델을 불러오고 추론 결과를 프로젝트 형식으로 바꾸는 파일입니다.
# 모델 로딩, 디바이스 선택, 탐지 결과 변환 흐름이 포함되어 있습니다.

import os
from pathlib import Path

import numpy as np
import torch

from core.detection_model import Box, Detection, DetectionModel, DetectionResult
from models.yolo_runtime_helper import build_yolo_runtime

# 이 파일은 Ultralytics YOLO 결과를 DetectionResult 공통 형식으로 바꾸는 어댑터입니다.


class YoloModelSample(DetectionModel):
    # 실제 YOLO 모델을 프로젝트 공통 인터페이스에 맞춰 감싼 구현체입니다.
    def __init__(
        self,
        model_path: str,
        min_confidence: float = 0.5,
        device: str = "cuda:0",
        require_cuda: bool = True,
        prefer_tensorrt_engine: bool = True,
    ) -> None:
        self.model_path = model_path
        self.min_confidence = min_confidence
        self.model = None
        self.requested_device = device
        self.require_cuda = require_cuda
        self.prefer_tensorrt_engine = prefer_tensorrt_engine
        self.device = "cpu"
        self.person_confidence = 0.2
        self.safety_confidence = 0.6
        self.runtime_model_path = model_path
        self.predict_kwargs: dict[str, object] = {}
        self.last_inference_ms = 0.0

    def load(self) -> None:
        # Keep Ultralytics writable even in restricted Windows environments.
        os.environ.setdefault(
            "YOLO_CONFIG_DIR",
            str(Path(__file__).resolve().parents[3] / "data" / "ultralytics"),
        )

        try:
            from ultralytics import YOLO
        except ModuleNotFoundError as error:
            raise RuntimeError(
                "YOLO 모델을 사용하려면 ultralytics 설치가 필요합니다. "
                "예: pip install ultralytics"
            ) from error

        self.runtime_model_path = self._resolve_runtime_model_path()
        if not Path(self.runtime_model_path).exists():
            raise RuntimeError(
                f"YOLO 가중치 파일을 찾을 수 없습니다: {self.runtime_model_path}"
            )

        self.model, self.runtime_model_path, self.device, self.predict_kwargs = (
            build_yolo_runtime(
                yolo_cls=YOLO,
                model_path=self.model_path,
                requested_device=self.requested_device,
                require_cuda=self.require_cuda,
                prefer_tensorrt_engine=self.prefer_tensorrt_engine,
            )
        )

    def predict(self, frame: np.ndarray, frame_id: int) -> DetectionResult:
        # 모델 원본 출력은 그대로 흘리지 않고 Detection/Box 구조로 변환합니다.
        if self.model is None:
            raise RuntimeError("YoloModelSample.load()를 먼저 호출해야 합니다.")

        # 이 어댑터는 비디오 경로가 아니라 "프레임 1장"을 받으므로 stream=True 제너레이터보다
        # 단일 결과 리스트로 즉시 받아오는 편이 파이프라인과 더 잘 맞습니다.
        self.last_inference_ms = 0.0
        person_results = self.model.predict(
            source=frame,
            conf=self.person_confidence,
            classes=[2],
            stream=False,
            verbose=False,
            **self.predict_kwargs,
        )
        self.last_inference_ms += self._sum_inference_ms(person_results)
        safety_results = self.model.predict(
            source=frame,
            conf=self.safety_confidence,
            classes=[0, 1],
            stream=False,
            verbose=False,
            **self.predict_kwargs,
        )
        self.last_inference_ms += self._sum_inference_ms(safety_results)

        person_result = person_results[0] if person_results else None
        safety_result = safety_results[0] if safety_results else None
        merged_result = self._merge_results(person_result, safety_result)
        detections = self._to_detections(
            merged_result,
            min_confidence=min(self.person_confidence, self.safety_confidence),
        )

        return DetectionResult(frame_id=frame_id, detections=detections)

    def get_name(self) -> str:
        return "YoloModelSample"

    def get_last_inference_ms(self) -> float:
        return self.last_inference_ms

    def _resolve_runtime_model_path(self) -> str:
        model_path = Path(self.model_path)
        if not self.prefer_tensorrt_engine:
            return str(model_path)
        if model_path.suffix.lower() == ".engine":
            return str(model_path)

        engine_path = model_path.with_suffix(".engine")
        if engine_path.exists():
            return str(engine_path)

        return str(model_path)

    def _sum_inference_ms(self, results) -> float:
        total = 0.0
        for result in results or []:
            speed = getattr(result, "speed", None)
            if not isinstance(speed, dict):
                continue
            value = speed.get("inference", 0.0)
            if isinstance(value, (int, float)):
                total += float(value)
        return total

    def _merge_results(self, person_result, safety_result):
        if person_result is None:
            return safety_result
        if safety_result is None:
            return person_result
        if person_result.boxes is None or person_result.boxes.data is None:
            return safety_result
        if safety_result.boxes is None or safety_result.boxes.data is None:
            return person_result

        person_result.boxes.data = torch.cat(
            [person_result.boxes.data, safety_result.boxes.data],
            dim=0,
        )
        return person_result

    def _to_detections(self, result, min_confidence: float | None = None) -> list[Detection]:
        detections = []
        if result is None or result.boxes is None:
            return detections

        names = result.names
        threshold = self.min_confidence if min_confidence is None else min_confidence

        for box_data in result.boxes:
            score = float(box_data.conf[0])
            if score < threshold:
                continue

            class_id = int(box_data.cls[0])
            name = names[class_id]
            x1, y1, x2, y2 = box_data.xyxy[0].tolist()

            detections.append(
                Detection(
                    name=name,
                    score=score,
                    box=Box(
                        x1=int(x1),
                        y1=int(y1),
                        x2=int(x2),
                        y2=int(y2),
                    ),
                )
            )

        return detections
