# 객체 탐지 모델을 불러오고 추론 결과를 프로젝트 형식으로 바꾸는 파일입니다.
# 모델 로딩, 디바이스 선택, 탐지 결과 변환 흐름이 포함되어 있습니다.

import torch


def resolve_torch_device(*, requested_device: str = "cuda:0", require_cuda: bool = False) -> str:
    normalized_device = requested_device.strip() or "cuda:0"
    normalized_device_lower = normalized_device.lower()
    wants_cuda = normalized_device_lower.startswith("cuda")

    if not wants_cuda:
        return normalized_device

    if not torch.cuda.is_available():
        if require_cuda:
            raise RuntimeError(
                "CUDA GPU 실행이 필요하지만 현재 PyTorch가 CUDA를 사용할 수 없습니다. "
                "CUDA 지원 PyTorch 설치와 GPU 드라이버 인식을 확인해 주세요."
            )
        return "cpu"

    device_index = _parse_cuda_device_index(normalized_device_lower)
    device_count = torch.cuda.device_count()
    if device_index >= device_count:
        raise RuntimeError(
            f"요청한 CUDA 장치({normalized_device})를 찾을 수 없습니다. "
            f"현재 사용 가능한 CUDA 장치 수: {device_count}"
        )

    try:
        torch.cuda.get_device_properties(device_index)
    except Exception as error:
        raise RuntimeError(
            f"CUDA 장치 초기화에 실패했습니다: {normalized_device}"
        ) from error

    return normalized_device


def _parse_cuda_device_index(device_name: str) -> int:
    if ":" not in device_name:
        return 0

    _, index_text = device_name.split(":", 1)
    try:
        return int(index_text)
    except ValueError as error:
        raise RuntimeError(f"지원하지 않는 CUDA 장치 형식입니다: {device_name}") from error
