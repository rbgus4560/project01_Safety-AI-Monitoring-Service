# FastAPI 사용 정리

이 문서는 Safety Monitor 프로젝트에서 FastAPI를 왜 사용했는지, 서버-클라이언트-뷰어 구조에서 어떤 역할을 하는지 학습용으로 정리한 문서입니다.

## FastAPI의 특징

FastAPI는 Python으로 HTTP API 서버를 만들기 위한 웹 프레임워크입니다. 이 프로젝트처럼 여러 프로그램이 네트워크로 데이터를 주고받아야 할 때, URL 단위로 기능을 나누고 JSON 응답을 안정적으로 주고받기 좋습니다.

주요 특징은 다음과 같습니다.

- 라우터 기반 구조: `/api/events`, `/api/sources`, `/api/clips`처럼 기능별 URL을 파일 단위로 나누어 관리할 수 있습니다.
- 타입 힌트와 Pydantic 모델: 요청/응답 데이터의 형태를 코드에 명확하게 적을 수 있어, 서버와 UI가 어떤 JSON을 주고받는지 파악하기 쉽습니다.
- 자동 문서화: FastAPI 앱을 실행하면 OpenAPI 문서와 Swagger UI를 통해 API 목록과 요청/응답 형태를 확인할 수 있습니다.
- 비동기 처리 지원: WebSocket, streaming response, 파일 전송처럼 실시간성이 필요한 기능을 비교적 자연스럽게 구성할 수 있습니다.
- Python 생태계 활용: OpenCV, SQLite, YOLO/Ultralytics, TensorRT 관련 Python 코드를 같은 프로세스 안에서 연결하기 쉽습니다.

## 이 프로젝트에서 FastAPI를 사용한 이유

Safety Monitor는 크게 세 프로그램이 협력합니다.

- 서버: 여러 클라이언트가 보낸 프레임 탐지 결과, 이벤트, 클립, 소스 상태를 모아 관리합니다.
- 클라이언트: 각 PC에서 카메라를 열고 AI 분석 결과를 만들며, 내장 FastAPI 백엔드로 로컬 GUI와 통신합니다.
- 뷰어: 서버 API를 호출해 여러 카메라의 상태, 영상, 이벤트 로그, 클립을 표시합니다.

이 구조에서는 각 프로그램이 직접 메모리를 공유할 수 없으므로, HTTP API와 WebSocket 같은 명확한 통신 경계가 필요합니다. FastAPI는 이 경계를 만들기 좋습니다.

## 현재 구조에서 FastAPI가 맡는 역할

### 서버 FastAPI

`safety_monitor_server/main.py`가 서버 FastAPI 앱의 진입점입니다. 서버는 다음 기능을 API로 제공합니다.

- 소스 등록/조회/삭제: 클라이언트 카메라와 스트림을 서버에 등록합니다.
- 소스 상태 조회: 각 카메라가 실행 중인지, 최근 프레임이 들어왔는지 확인합니다.
- 프레임 탐지 수집: 클라이언트가 만든 객체 탐지 결과를 서버 DB에 저장합니다.
- 이벤트 생성/조회: 서버가 룰 설정을 기준으로 이벤트 START/END를 판단하고 저장합니다.
- 클립/썸네일 제공: 이벤트에 연결된 영상 클립과 미리보기 이미지를 뷰어가 가져갈 수 있게 합니다.
- WebSocket 알림: 이벤트나 소스 상태가 바뀌었을 때 뷰어에게 갱신 신호를 보냅니다.

### 클라이언트 내장 FastAPI

`safety_monitor_client/embedded_backend/main.py`가 클라이언트 PC 안에서 실행되는 내장 백엔드입니다. 클라이언트 Flutter GUI는 이 로컬 API를 통해 카메라 실행 상태와 분석 상태를 확인합니다.

클라이언트 내장 FastAPI는 다음 역할을 합니다.

- 카메라/영상 소스 실행 제어
- 로컬 분석 파이프라인 상태 제공
- 프레임 탐지 결과와 미리보기 제공
- 원격 서버로 source presence, frame detection, status를 보고
- GUI가 직접 Python 분석 코드를 다루지 않도록 중간 API 계층 제공

### 뷰어와 FastAPI

뷰어는 Flutter 앱이므로 FastAPI 서버가 아닙니다. 대신 `EventApiService` 같은 서비스 계층을 통해 서버 FastAPI를 호출합니다.

뷰어는 FastAPI API를 이용해 다음 데이터를 가져옵니다.

- 서버 health 상태
- 카메라 목록과 상태
- 실시간 스트림 URL
- 이벤트 로그
- 이벤트 클립과 썸네일
- 룰 설정 조회/저장

## 학습할 때 보면 좋은 흐름

1. 서버 실행 흐름: `safety_monitor_server/main.py`에서 앱 생성과 라우터 등록을 봅니다.
2. 클라이언트 실행 흐름: `safety_monitor_client/embedded_backend/main.py`와 `app/source_manager.py`에서 카메라 worker가 어떻게 시작되는지 봅니다.
3. 분석 흐름: `app/analysis_runtime.py`에서 프레임 소스, 모델, 추적, 서버 보고가 어떻게 연결되는지 봅니다.
4. 이벤트 흐름: 서버의 `app/server_event_processor.py`와 `app/database.py`에서 탐지 결과가 이벤트 DB와 클립으로 바뀌는 과정을 봅니다.
5. 뷰어 표시 흐름: `safety_monitor_viewer/lib/services/event_api_service.dart`, `controllers/api_event_controller.dart`, `screens/home_screen.dart` 순서로 API 데이터가 화면에 표시되는 과정을 봅니다.

## 정리

이 프로젝트에서 FastAPI는 단순한 웹 서버라기보다, 서버/클라이언트/뷰어가 서로 안전하게 데이터를 주고받기 위한 통신 규약 역할을 합니다. 카메라 분석은 Python 쪽에서 처리하고, 화면은 Flutter가 담당하며, FastAPI는 두 세계 사이에서 JSON, 파일, 스트림, WebSocket 이벤트를 연결하는 중심 계층입니다.