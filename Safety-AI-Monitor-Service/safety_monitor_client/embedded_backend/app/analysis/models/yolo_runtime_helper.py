# 객체 탐지 모델을 불러오고 추론 결과를 프로젝트 형식으로 바꾸는 파일입니다.
# 모델 로딩, 디바이스 선택, 탐지 결과 변환 흐름이 포함되어 있습니다.

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from app.config import (
    TENSORRT_EXPORT_BATCH,
    TENSORRT_EXPORT_DYNAMIC,
    TENSORRT_EXPORT_HALF,
    TENSORRT_EXPORT_IMGSZ,
)
from app.log_utils import log_line
from models.device_helper import resolve_torch_device


def build_yolo_runtime(
    *,
    yolo_cls,
    model_path: str,
    requested_device: str,
    require_cuda: bool,
    prefer_tensorrt_engine: bool,
) -> tuple[Any, str, str, dict[str, Any]]:
    device = resolve_torch_device(
        requested_device=requested_device,
        require_cuda=require_cuda,
    )
    log_line(
        "MODEL",
        action="device",
        model=Path(model_path).name,
        device=device,
        tensorrt="yes" if prefer_tensorrt_engine else "no",
    )
    runtime_model_path = resolve_runtime_model_path(
        yolo_cls=yolo_cls,
        model_path=model_path,
        device=device,
        prefer_tensorrt_engine=prefer_tensorrt_engine,
    )
    log_line(
        "MODEL",
        action="runtime",
        model=Path(runtime_model_path).name,
        path=runtime_model_path,
    )
    try:
        log_line("MODEL", action="load-start", model=Path(runtime_model_path).name)
        model = load_yolo_model(
            yolo_cls=yolo_cls,
            model_path=runtime_model_path,
        )
        log_line("MODEL", action="load-ready", model=Path(runtime_model_path).name)
    except Exception as error:
        log_line(
            "WARN",
            message="YOLO runtime load failed",
            model=Path(runtime_model_path).name,
            error=error,
        )
        fallback_model_path = _fallback_model_path_for_tensorrt_error(
            model_path=model_path,
            runtime_model_path=runtime_model_path,
            error=error,
        )
        if fallback_model_path is None:
            raise
        runtime_model_path = fallback_model_path
        log_line("MODEL", action="fallback", model=Path(runtime_model_path).name)
        model = load_yolo_model(
            yolo_cls=yolo_cls,
            model_path=runtime_model_path,
        )
        log_line("MODEL", action="load-ready", model=Path(runtime_model_path).name)
    predict_kwargs = build_predict_kwargs(
        runtime_model_path=runtime_model_path,
        device=device,
    )
    return model, runtime_model_path, device, predict_kwargs


def resolve_runtime_model_path(
    *,
    yolo_cls,
    model_path: str,
    device: str,
    prefer_tensorrt_engine: bool,
) -> str:
    resolved_path = Path(model_path)
    if not prefer_tensorrt_engine:
        if not resolved_path.exists():
            raise RuntimeError(f"YOLO 가중치 파일을 찾을 수 없습니다: {resolved_path}")
        return str(resolved_path)
    if resolved_path.suffix.lower() == ".engine":
        if not _is_tensorrt_available():
            pt_path = resolved_path.with_suffix(".pt")
            if pt_path.exists():
                return str(pt_path)
        return str(resolved_path)

    engine_path = resolved_path.with_suffix(".engine")
    if not resolved_path.exists():
        if engine_path.exists() and _is_tensorrt_available():
            if _engine_matches_export_config(
                engine_path=engine_path,
                source_model_path=resolved_path,
                device=device,
            ):
                return str(engine_path)
            raise RuntimeError(
                "기존 TensorRT engine의 export 설정을 검증할 수 없고 "
                f"원본 YOLO 가중치 파일도 없습니다: {resolved_path}"
            )
        raise RuntimeError(f"YOLO 가중치 파일을 찾을 수 없습니다: {resolved_path}")

    if (
        engine_path.exists()
        and _is_tensorrt_available()
        and _engine_matches_export_config(
            engine_path=engine_path,
            source_model_path=resolved_path,
            device=device,
        )
    ):
        return str(engine_path)

    if _can_export_tensorrt_engine(model_path=resolved_path, device=device):
        try:
            return _export_tensorrt_engine(
                yolo_cls=yolo_cls,
                model_path=resolved_path,
                device=device,
            )
        except Exception as error:
            if not _is_tensorrt_related_error(error):
                raise

    return str(resolved_path)


def build_predict_kwargs(*, runtime_model_path: str, device: str) -> dict[str, Any]:
    runtime_suffix = Path(runtime_model_path).suffix.lower()
    if runtime_suffix == ".engine":
        return {"imgsz": TENSORRT_EXPORT_IMGSZ}
    return {
        "device": device,
        "imgsz": TENSORRT_EXPORT_IMGSZ,
        "half": TENSORRT_EXPORT_HALF and device.lower().startswith("cuda"),
    }


def _can_export_tensorrt_engine(*, model_path: Path, device: str) -> bool:
    return model_path.suffix.lower() == ".pt" and device.lower().startswith("cuda")


def _export_tensorrt_engine(*, yolo_cls, model_path: Path, device: str) -> str:
    _patch_tensorrt_for_ultralytics_export()
    log_line(
        "MODEL",
        action="engine-export-start",
        model=model_path.name,
        device=device,
    )
    export_model = load_yolo_model(
        yolo_cls=yolo_cls,
        model_path=str(model_path),
    )
    exported_path = export_model.export(
        format="engine",
        device=device,
        imgsz=TENSORRT_EXPORT_IMGSZ,
        half=TENSORRT_EXPORT_HALF,
        dynamic=TENSORRT_EXPORT_DYNAMIC,
        batch=TENSORRT_EXPORT_BATCH,
        verbose=False,
    )
    resolved_exported_path = Path(exported_path).resolve()
    _write_engine_export_meta(
        engine_path=resolved_exported_path,
        source_model_path=model_path,
        device=device,
    )
    log_line(
        "MODEL",
        action="engine-export-ready",
        model=resolved_exported_path.name,
    )
    return str(resolved_exported_path)


def load_yolo_model(*, yolo_cls, model_path: str):
    return yolo_cls(model_path, task="detect")


def _engine_export_config(*, source_model_path: Path, device: str) -> dict[str, Any]:
    source_stat = source_model_path.stat() if source_model_path.exists() else None
    return {
        "format": "engine",
        "device": device,
        "imgsz": TENSORRT_EXPORT_IMGSZ,
        "half": TENSORRT_EXPORT_HALF,
        "dynamic": TENSORRT_EXPORT_DYNAMIC,
        "batch": TENSORRT_EXPORT_BATCH,
        "source_model_path": str(source_model_path.resolve()),
        "source_model_size": int(source_stat.st_size) if source_stat is not None else 0,
        "source_model_mtime_ns": int(source_stat.st_mtime_ns) if source_stat is not None else 0,
    }


def _engine_meta_path(engine_path: Path) -> Path:
    return engine_path.with_suffix(f"{engine_path.suffix}.meta.json")


def _engine_matches_export_config(
    *,
    engine_path: Path,
    source_model_path: Path,
    device: str,
) -> bool:
    meta_path = _engine_meta_path(engine_path)
    if not meta_path.exists():
        return False
    try:
        saved_meta = json.loads(meta_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return False
    return saved_meta == _engine_export_config(
        source_model_path=source_model_path,
        device=device,
    )


def _write_engine_export_meta(
    *,
    engine_path: Path,
    source_model_path: Path,
    device: str,
) -> None:
    meta_path = _engine_meta_path(engine_path)
    meta_path.write_text(
        json.dumps(
            _engine_export_config(source_model_path=source_model_path, device=device),
            ensure_ascii=False,
            indent=2,
            sort_keys=True,
        ),
        encoding="utf-8",
    )


def _patch_tensorrt_for_ultralytics_export() -> None:
    try:
        import tensorrt as trt
    except ImportError:
        return

    if not hasattr(trt.NetworkDefinitionCreationFlag, "EXPLICIT_BATCH"):
        setattr(trt.NetworkDefinitionCreationFlag, "EXPLICIT_BATCH", 0)
    if not hasattr(trt.Builder, "platform_has_fast_fp16"):
        setattr(trt.Builder, "platform_has_fast_fp16", False)
    if not hasattr(trt.Builder, "platform_has_fast_int8"):
        setattr(trt.Builder, "platform_has_fast_int8", False)


def _is_tensorrt_available() -> bool:
    try:
        import tensorrt  # noqa: F401
    except ImportError:
        return False
    return True


def _fallback_model_path_for_tensorrt_error(
    *,
    model_path: str,
    runtime_model_path: str,
    error: Exception,
) -> str | None:
    if Path(runtime_model_path).suffix.lower() != ".engine":
        return None
    if not _is_tensorrt_related_error(error):
        return None

    fallback_path = Path(model_path)
    if fallback_path.exists():
        return str(fallback_path)
    return None


def _is_tensorrt_related_error(error: Exception) -> bool:
    error_text = str(error).lower()
    return "tensorrt" in error_text or isinstance(error, ModuleNotFoundError)
