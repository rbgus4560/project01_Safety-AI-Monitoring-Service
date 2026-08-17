# Safety Monitor Server

서버는 중앙 저장소이자 이벤트 판정/클립 생성 서버입니다.

## 서버가 담당하는 일

- 등록 소스 메타데이터 저장
- 소스별 최신 상태 저장
- 최신 프리뷰 이미지와 프리뷰 스트림 제공
- 프레임 탐지 결과 저장
- 소스별 `rule_config`를 읽어 이벤트 판정
- 이벤트 DB 저장
- 이벤트 클립 MP4 생성
- 이벤트 썸네일 JPG 생성
- 이벤트/클립/썸네일 조회 API 제공
- 뷰어에서 변경한 룰 설정 저장
- 뷰어/클라이언트용 실시간 업데이트 제공

## 서버가 하지 않는 일

- 로컬 카메라 직접 열기
- 클라이언트 대신 GPU 추론 실행
- YOLO 가중치/TensorRT 엔진 관리
- 뷰어 UI 렌더링

## 현재 구조에서 중요한 점

- 객체 탐지 자체는 클라이언트가 수행합니다.
- 이벤트 판정과 중앙 저장은 서버가 수행합니다.
- 이벤트 클립과 썸네일은 서버가 수신 프리뷰 프레임 버퍼를 기반으로 생성합니다.
- 뷰어는 서버만 바라봅니다.
- 룰 설정은 뷰어에서 변경하고 서버 DB에 저장됩니다.

## 주요 데이터 위치

```text
safety_monitor_server/data/monitor.db
safety_monitor_server/data/clips/
safety_monitor_server/data/event_thumbnails/
safety_monitor_server/data/source_previews/
```

## 실행

루트에서 실행합니다.

```bat
run_server.bat
```

직접 실행할 때:

```bat
cd safety_monitor_server
..\.venv\Scripts\python.exe -m uvicorn main:app --host 0.0.0.0 --port 8000
```
