# 프로젝트에서 런타임 엔진이 정상적으로 준비되었는지 확인하는 보조 스크립트입니다.
# 모델 경로, 디바이스, TensorRT/ONNX 관련 의존성 상태를 점검합니다.

from __future__ import annotations

import importlib.util
import os
import sys
from pathlib import Path


# 현재 스크립트가 위치한 백엔드 디렉터리를 기준으로 경로를 설정합니다.
BACKEND_DIR = Path(__file__).resolve().parent
ANALYSIS_DIR = (BACKEND_DIR / "app" / "analysis").resolve()
ULTRALYTICS_CONFIG_DIR = (BACKEND_DIR / "data" / "ultralytics").resolve()
ULTRALYTICS_CONFIG_DIR.mkdir(parents=True, exist_ok=True)

# Ultralytics가 참조할 설정 디렉터리를 환경 변수로 지정합니다.
os.environ.setdefault("YOLO_CONFIG_DIR", str(ULTRALYTICS_CONFIG_DIR))

# 분석 모듈을 직접 import할 수 있도록 sys.path에 추가합니다.
if str(ANALYSIS_DIR) not in sys.path:
    sys.path.insert(0, str(ANALYSIS_DIR))

from app.config import (  # noqa: E402
    ANALYSIS_DEVICE,
    ANALYSIS_REQUIRE_CUDA,
    MODEL_PATH,
    PREFER_TENSORRT_ENGINE,
    TENSORRT_EXPORT_BATCH,
    TENSORRT_EXPORT_DYNAMIC,
    TENSORRT_EXPORT_HALF,
    TENSORRT_EXPORT_IMGSZ,
)
from app.analysis.models.device_helper import resolve_torch_device  # noqa: E402
from app.analysis.models.yolo_runtime_helper import resolve_runtime_model_path  # noqa: E402


def _has_module(name: str) -> bool:
    """지정한 Python 모듈이 설치되어 있는지 확인합니다."""
    return importlib.util.find_spec(name) is not None


def main() -> int:
    """런타임 모델 경로와 엔진 파일이 정상적으로 준비되어 있는지 검증합니다."""
    import torch
    from ultralytics import YOLO

    # 요청된 분석 디바이스와 CUDA 요구 여부에 따라 torch 디바이스를 결정합니다.
    device = resolve_torch_device(
        requested_device=ANALYSIS_DEVICE,
        require_cuda=ANALYSIS_REQUIRE_CUDA,
    )

    # YOLO 모델 경로를 실제 실행 환경에 맞게 해석합니다.
    runtime_model_path = Path(
        resolve_runtime_model_path(
            yolo_cls=YOLO,
            model_path=str(MODEL_PATH),
            device=device,
            prefer_tensorrt_engine=PREFER_TENSORRT_ENGINE,
        )
    ).resolve()

    # TensorRT 엔진 파일 경로를 계산합니다.
    engine_path = MODEL_PATH.with_suffix(".engine").resolve()

    # 현재 상태를 로그로 출력해 디버깅에 활용합니다.
    print(f"model_path={MODEL_PATH}")
    print(f"runtime_model_path={runtime_model_path}")
    print(f"engine_path={engine_path}")
    print(f"cuda_available={torch.cuda.is_available()}")
    print(f"analysis_device={device}")
    print(f"tensorrt_export_imgsz={TENSORRT_EXPORT_IMGSZ}")
    print(f"tensorrt_export_half={TENSORRT_EXPORT_HALF}")
    print(f"tensorrt_export_dynamic={TENSORRT_EXPORT_DYNAMIC}")
    print(f"tensorrt_export_batch={TENSORRT_EXPORT_BATCH}")
    print(f"tensorrt_available={_has_module('tensorrt')}")
    print(f"onnx_available={_has_module('onnx')}")
    print(f"onnxslim_available={_has_module('onnxslim')}")
    print(f"onnxruntime_available={_has_module('onnxruntime')}")
    print(f"yolo_config_dir={ULTRALYTICS_CONFIG_DIR}")

    # 해석된 런타임 모델 파일이 실제로 존재하는지 확인합니다.
    if not runtime_model_path.exists():
        print("ERROR: runtime model path does not exist.")
        return 1

    # CUDA 기반 실행이 아니면 실패로 처리합니다.
    if not device.lower().startswith("cuda"):
        print("ERROR: analysis device is not CUDA.")
        return 1

    # TensorRT 엔진을 강제로 사용하도록 설정했는데, 실제 경로가 엔진 파일이 아니면 실패합니다.
    if PREFER_TENSORRT_ENGINE and runtime_model_path.suffix.lower() != ".engine":
        print("ERROR: TensorRT engine was requested, but runtime did not resolve to a .engine file.")
        return 1

    # .engine 파일로 해석되었다면 해당 엔진 파일이 디스크에 실제로 존재하는지 다시 확인합니다.
    if runtime_model_path.suffix.lower() == ".engine" and not engine_path.exists():
        print("ERROR: runtime resolved to .engine but the engine file was not found on disk.")
        return 1

    print("runtime_engine_ready=true")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
