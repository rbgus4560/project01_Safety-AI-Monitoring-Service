# 객체 탐지 모델을 불러오고 추론 결과를 프로젝트 형식으로 바꾸는 파일입니다.
# 모델 로딩, 디바이스 선택, 탐지 결과 변환 흐름이 포함되어 있습니다.

import os
from pathlib import Path

import numpy as np

from core.detection_model import Box, Detection, DetectionModel, DetectionResult
from models.device_helper import resolve_torch_device
from models.yolo_runtime_helper import (
    build_predict_kwargs,
    load_yolo_model,
    resolve_runtime_model_path,
)

# 이 파일은 사람 전용 YOLO와 안전모 전용 YOLO를 함께 돌려 결과를 합치는 어댑터입니다.


class EnsembleYoloModel(DetectionModel):
    def __init__(
        self,
        person_model_path: str,
        safety_model_path: str,
        min_confidence: float = 0.5,
        device: str = "cuda:0",
        require_cuda: bool = True,
        prefer_tensorrt_engine: bool = True,
        person_class_map: dict[str, str] | None = None,
        safety_class_map: dict[str, str] | None = None,
    ) -> None:
        self.person_model_path = person_model_path
        self.safety_model_path = safety_model_path
        self.min_confidence = min_confidence
        self.person_model = None
        self.safety_model = None
        self.requested_device = device
        self.require_cuda = require_cuda
        self.prefer_tensorrt_engine = prefer_tensorrt_engine
        self.device = "cpu"
        self.runtime_person_model_path = person_model_path
        self.runtime_safety_model_path = safety_model_path
        self.person_predict_kwargs: dict[str, object] = {}
        self.safety_predict_kwargs: dict[str, object] = {}
        self.person_class_map = person_class_map or {
            "person": "person",
        }
        self.safety_class_map = safety_class_map or {
            "helmet": "helmet",
            "hardhat": "helmet",
        }
        self.last_inference_ms = 0.0

    def load(self) -> None:
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

        self.device = resolve_torch_device(
            requested_device=self.requested_device,
            require_cuda=self.require_cuda,
        )
        self.runtime_person_model_path = resolve_runtime_model_path(
            yolo_cls=YOLO,
            model_path=self.person_model_path,
            device=self.device,
            prefer_tensorrt_engine=self.prefer_tensorrt_engine,
        )
        self.runtime_safety_model_path = resolve_runtime_model_path(
            yolo_cls=YOLO,
            model_path=self.safety_model_path,
            device=self.device,
            prefer_tensorrt_engine=self.prefer_tensorrt_engine,
        )

        for model_path in [
            self.runtime_person_model_path,
            self.runtime_safety_model_path,
        ]:
            if not Path(model_path).exists():
                raise RuntimeError(
                    f"YOLO 가중치 파일을 찾을 수 없습니다: {model_path}"
                )

        self.person_model = load_yolo_model(
            yolo_cls=YOLO,
            model_path=self.runtime_person_model_path,
        )
        self.safety_model = load_yolo_model(
            yolo_cls=YOLO,
            model_path=self.runtime_safety_model_path,
        )
        self.person_predict_kwargs = build_predict_kwargs(
            runtime_model_path=self.runtime_person_model_path,
            device=self.device,
        )
        self.safety_predict_kwargs = build_predict_kwargs(
            runtime_model_path=self.runtime_safety_model_path,
            device=self.device,
        )

    def predict(self, frame: np.ndarray, frame_id: int) -> DetectionResult:
        if self.person_model is None or self.safety_model is None:
            raise RuntimeError("EnsembleYoloModel.load()를 먼저 호출해야 합니다.")

        detections = []
        self.last_inference_ms = 0.0
        detections.extend(
            self._predict_with_model(
                model=self.person_model,
                frame=frame,
                class_map=self.person_class_map,
                predict_kwargs=self.person_predict_kwargs,
            )
        )
        detections.extend(
            self._predict_with_model(
                model=self.safety_model,
                frame=frame,
                class_map=self.safety_class_map,
                predict_kwargs=self.safety_predict_kwargs,
            )
        )
        return DetectionResult(frame_id=frame_id, detections=detections)

    def get_name(self) -> str:
        return "EnsembleYoloModel"

    def get_last_inference_ms(self) -> float:
        return self.last_inference_ms

    def _predict_with_model(
        self,
        model,
        frame: np.ndarray,
        class_map: dict[str, str],
        predict_kwargs: dict[str, object],
    ) -> list[Detection]:
        results = model.predict(
            frame,
            stream=False,
            verbose=False,
            **predict_kwargs,
        )
        detections: list[Detection] = []

        for result in results:
            self.last_inference_ms += self._read_inference_ms(result)
            names = result.names
            for box_data in result.boxes:
                score = float(box_data.conf[0])
                if score < self.min_confidence:
                    continue

                class_id = int(box_data.cls[0])
                raw_name = str(names[class_id]).strip().lower()
                mapped_name = class_map.get(raw_name)
                if not mapped_name:
                    continue

                x1, y1, x2, y2 = box_data.xyxy[0].tolist()
                detections.append(
                    Detection(
                        name=mapped_name,
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

    def _read_inference_ms(self, result) -> float:
        speed = getattr(result, "speed", None)
        if not isinstance(speed, dict):
            return 0.0
        value = speed.get("inference", 0.0)
        if isinstance(value, (int, float)):
            return float(value)
        return 0.0
