# 분석 파이프라인 안에서 사용하는 frame_source 기능을 분리한 파일입니다.
# pipeline.py에서 조립되는 분석 부품 중 하나입니다.

from abc import ABC, abstractmethod

import cv2
import numpy as np

# 이 파일은 카메라, 영상 파일, 스트림 입력을 같은 방식으로 다루기 위한 추상화입니다.


class FrameSource(ABC):
    # 카메라나 영상 파일 입력이 따라야 하는 기본 구조입니다.

    @abstractmethod
    def open(self) -> None:
        pass

    @abstractmethod
    def read(self) -> tuple[bool, np.ndarray]:
        pass

    @abstractmethod
    def release(self) -> None:
        pass

    @abstractmethod
    def get_fps(self) -> float:
        pass

    @abstractmethod
    def get_time_seconds(self) -> float | None:
        pass


class CameraFrameSource(FrameSource):
    # 웹캠 같은 로컬 카메라 입력용 구현입니다.
    def __init__(self, camera_index: int) -> None:
        self.camera_index = camera_index
        self.cap = None

    def open(self) -> None:
        # 카메라에서 프레임을 읽을 준비를 한다
        self.cap = cv2.VideoCapture(self.camera_index)
        if self.cap is None or not self.cap.isOpened():
            raise RuntimeError(f"카메라를 열 수 없습니다: {self.camera_index}")

    def read(self) -> tuple[bool, np.ndarray]:
        if self.cap is None:
            raise RuntimeError("CameraFrameSource.open()을 먼저 호출해야 합니다.")
        return self.cap.read()

    def release(self) -> None:
        if self.cap is not None:
            self.cap.release()

    def get_fps(self) -> float:
        if self.cap is None:
            return 30.0
        fps = float(self.cap.get(cv2.CAP_PROP_FPS))
        return fps if fps > 0 else 30.0

    def get_time_seconds(self) -> float | None:
        return None


class VideoFileFrameSource(FrameSource):
    # mp4 같은 로컬 영상 파일 입력용 구현입니다.
    def __init__(self, video_path: str, *, start_time_seconds: float = 0.0) -> None:
        self.video_path = video_path
        self.start_time_seconds = start_time_seconds if start_time_seconds > 0 else 0.0
        self.cap = None
        self._fps = 0.0
        self._frame_count = 0.0

    def open(self) -> None:
        # 영상 파일에서 프레임을 읽을 준비를 한다
        self.cap = cv2.VideoCapture(self.video_path)
        if self.cap is None or not self.cap.isOpened():
            raise RuntimeError(f"영상 파일을 열 수 없습니다: {self.video_path}")
        self._fps = float(self.cap.get(cv2.CAP_PROP_FPS))
        self._frame_count = float(self.cap.get(cv2.CAP_PROP_FRAME_COUNT))
        if self.start_time_seconds > 0:
            self.cap.set(cv2.CAP_PROP_POS_MSEC, self.start_time_seconds * 1000.0)

    def read(self) -> tuple[bool, np.ndarray]:
        if self.cap is None:
            raise RuntimeError("VideoFileFrameSource.open()을 먼저 호출해야 합니다.")
        return self.cap.read()

    def release(self) -> None:
        if self.cap is not None:
            self.cap.release()

    def get_fps(self) -> float:
        if self.cap is None:
            temp_cap = cv2.VideoCapture(self.video_path)
            fps = float(temp_cap.get(cv2.CAP_PROP_FPS))
            temp_cap.release()
            return fps if fps > 0 else 30.0
        fps = self._fps if self._fps > 0 else float(self.cap.get(cv2.CAP_PROP_FPS))
        return fps if fps > 0 else 30.0

    def get_time_seconds(self) -> float | None:
        if self.cap is None:
            return None
        fps = self.get_fps()
        frame_index = float(self.cap.get(cv2.CAP_PROP_POS_FRAMES))
        time_ms = float(self.cap.get(cv2.CAP_PROP_POS_MSEC))

        # OpenCV는 일부 mp4에서 POS_MSEC를 비정상적으로 크게 돌려줄 수 있어
        # 진행률 계산은 프레임 번호 기반 시간을 우선 사용합니다.
        if fps > 0 and frame_index > 0:
            frame_based_seconds = max(0.0, (frame_index - 1.0) / fps)
            if time_ms < 0:
                return frame_based_seconds
            time_based_seconds = time_ms / 1000.0
            if (
                self._frame_count > 0
                and time_based_seconds > ((self._frame_count - 1.0) / fps) + (1.0 / fps)
            ):
                return frame_based_seconds
            if abs(time_based_seconds - frame_based_seconds) > max(1.0, 5.0 / fps):
                return frame_based_seconds
            return max(0.0, min(time_based_seconds, frame_based_seconds))

        if time_ms < 0:
            return None
        return time_ms / 1000.0


class StreamFrameSource(FrameSource):
    # RTSP, HTTP 같은 스트림 입력용 구현입니다.
    def __init__(self, stream_url: str) -> None:
        self.stream_url = stream_url
        self.cap = None

    def open(self) -> None:
        # RTSP나 HTTP 같은 스트림 주소에서 프레임을 읽을 준비를 한다
        self.cap = cv2.VideoCapture(self.stream_url)
        if self.cap is None or not self.cap.isOpened():
            raise RuntimeError(f"스트림을 열 수 없습니다: {self.stream_url}")

    def read(self) -> tuple[bool, np.ndarray]:
        if self.cap is None:
            raise RuntimeError("StreamFrameSource.open()을 먼저 호출해야 합니다.")
        return self.cap.read()

    def release(self) -> None:
        if self.cap is not None:
            self.cap.release()

    def get_fps(self) -> float:
        if self.cap is None:
            temp_cap = cv2.VideoCapture(self.stream_url)
            fps = float(temp_cap.get(cv2.CAP_PROP_FPS))
            temp_cap.release()
            return fps if fps > 0 else 30.0
        fps = float(self.cap.get(cv2.CAP_PROP_FPS))
        return fps if fps > 0 else 30.0

    def get_time_seconds(self) -> float | None:
        return None
