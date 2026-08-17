# Model weights

GitHub 저장소에는 대용량 모델 가중치를 포함하지 않습니다.

실행 전에 학습한 모델 파일을 아래 경로에 배치하세요.

```text
safety_monitor_client/embedded_backend/app/analysis/models/weights/best.pt
```

TensorRT 엔진을 사용할 경우 `best.engine`도 같은 폴더에서 사용합니다.
`run_client.bat`은 `best.pt` 또는 `best.engine` 중 하나가 존재해야 실행을 계속합니다.
