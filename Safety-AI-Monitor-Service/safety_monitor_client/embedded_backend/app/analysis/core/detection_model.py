# 분석 파이프라인 안에서 사용하는 detection_model 기능을 분리한 파일입니다.
# pipeline.py에서 조립되는 분석 부품 중 하나입니다.

from abc import ABC, abstractmethod
from dataclasses import dataclass
from datetime import datetime

import numpy as np

# 이 파일은 모델 공통 출력 형식을 정의합니다.
# 어떤 모델을 쓰더라도 DetectionResult만 맞추면 나머지 파이프라인은 같은 방식으로 동작합니다.

@dataclass
class Box:
    # 화면 위 바운딩 박스 좌표입니다.
    x1: int
    y1: int
    x2: int
    y2: int

    def width(self) -> int:
        return max(0, self.x2 - self.x1)

    def height(self) -> int:
        return max(0, self.y2 - self.y1)

    def center(self) -> tuple[int, int]:
        # 박스의 중심 좌표를 계산한다
        return ((self.x1 + self.x2) // 2, (self.y1 + self.y2) // 2)


@dataclass
class Detection:
    # 모델이 한 객체를 탐지한 결과입니다.
    name: str
    score: float
    box: Box
    track_id: int | None = None


@dataclass
class DetectionResult:
    # 한 프레임의 공통 추론 결과입니다.
    # EventRule은 이 구조만 보고 이벤트를 판단합니다.
    frame_id: int
    detections: list[Detection]
    source_time_seconds: float = 0.0
    source_time_text: str = ""
    event_created_at: datetime | None = None


class DetectionModel(ABC):
    # 모든 객체 탐지 모델이 따라야 하는 기본 구조입니다.
    # 새 모델을 붙일 때는 이 인터페이스만 맞추면 됩니다.

    @abstractmethod
    def load(self) -> None:
        pass

    @abstractmethod
    def predict(self, frame: np.ndarray, frame_id: int) -> DetectionResult:
        pass

    @abstractmethod
    def get_name(self) -> str:
        pass

    def get_last_inference_ms(self) -> float:
        return 0.0
