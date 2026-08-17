# project01_Safety-AI-Monitoring-Service

Client-Server-Viewer 구조를 가진 **AI 안전 관제 시스템 개인화 프로젝트**입니다.

기존 팀프로젝트에서 구현한 안전모 탐지 및 관제 시스템을 기반으로, 전체 실행 흐름을 다시 분석하고 개인 포트폴리오 형태로 정리했습니다.  
본 저장소에서는 기존 기능을 그대로 새로 만든 것처럼 설명하지 않고, **팀프로젝트 기반 기능**과 **개인적으로 수정·정리한 범위**를 분리하여 작성합니다.

---

## 1. 프로젝트 개요

이 프로젝트는 카메라 영상을 Client에서 처리하고, Server가 상태·이벤트·설정을 관리하며, Viewer가 관제 화면을 제공하는 구조입니다.

```text
Camera
  ↓
Client - AI Detection
  ↓
Server - API / Event / DB
  ↓
Viewer - Monitoring UI
```

### 역할 분리

| 구성 | 역할 |
|---|---|
| Client | 카메라 접근, YOLO 탐지, 상태 및 탐지 결과 전송 |
| Server | Client 상태 관리, API 제공, 이벤트 및 설정 저장 |
| Viewer | 관리자 로그인, 카메라 목록, 실시간 관제 화면, 이벤트/설정 관리 |

---

## 2. 프로젝트 배경

방학 초기에는 MFC 기반 개인 포트폴리오를 계획했지만, 실제 진행 과정에서 기존 AI 안전 관제 팀프로젝트를 다시 실행하고 구조를 이해하는 데 예상보다 많은 시간이 필요했습니다.

따라서 방학 중에는 신규 프로젝트를 무리하게 추가하기보다, 기존 팀프로젝트를 다음 방향으로 개인화했습니다.

- 기존 Client / Server / Viewer 구조 재실행
- Viewer 화면 구조와 메뉴 정리
- 관리자 로그인 및 Server 연결 확인
- Camera Group / Layout UI 정리
- 실행 중 발생한 로그인 및 빌드 오류 수정
- GitHub / README 형태로 정리

---

## 3. 기존 팀프로젝트 기능

기존 팀프로젝트 기반 기능입니다.

- YOLO 기반 안전모 착용 여부 탐지
- `YES_Helmet`, `NO_Helmet`, `Person` 클래스 활용
- Client / Server / Viewer 분리 구조
- Client에서 카메라 영상 처리 및 탐지
- Server에서 상태 및 이벤트 관리
- Viewer에서 관제 화면과 이벤트 확인
- FastAPI 기반 API 구조
- Flutter Windows 기반 Client / Viewer UI

---

## 4. 개인 수정 및 개선 내용

개인적으로 수정·정리한 주요 내용입니다.

### Viewer UI / UX 개선

- Viewer 상단 메뉴 정리
- `Apply Server` 영역 제거 및 로그인 단계 Server URL 사용
- Live Monitoring 화면 재구성
- 1분할 / 4분할 / 9분할 버튼 정리
- Camera Group Dropdown 크기 및 간격 조정
- 폴더 / 저장 아이콘 버튼 크기 통일
- 창 축소 시 레이아웃이 깨지는 문제 개선 방향 정리

### 카메라 및 레이아웃 UI 개선

- Camera 목록 UI 확인
- Camera 이름 수정 UI 확인
- Camera Group 생성 UI 정리
- Group 저장 시 입력 검증 추가
- Viewer Layout 저장 UI 정리

### 실행 및 빌드 오류 수정

- Viewer 로그인 실패 원인 확인
- `server_config.json`의 Server URL 형식 수정
- Client Windows Build 실패 원인 확인
- `_refreshAllApiData()` 누락 함수 복구
- Server → Viewer → Client 실행 흐름 재확인

---

## 5. 현재 검증 상태

현재 개발 PC에서 확인한 범위입니다.

| 항목 | 상태 |
|---|---|
| FastAPI Server 실행 | 확인 |
| `/health` API 확인 | 확인 |
| Viewer Windows 실행 | 확인 |
| Viewer 관리자 로그인 | 확인 |
| Viewer → Server 로그인 API 호출 | 확인 |
| Client Windows Build | 확인 |
| Client Windows 실행 | 확인 |
| Viewer UI / Camera List 화면 | 확인 |
| 1 / 4 / 9 분할 UI | 확인 |
| Camera Group UI | 확인 |
| 실제 USB Camera 연결 | 미검증 |
| 실시간 YOLO 추론 | 미검증 |
| Viewer 실시간 영상 표시 | 미검증 |
| Event 생성 및 Clip 저장 | 미검증 |
| 다른 PC 연결 테스트 | 예정 |

> 현재 USB 카메라 장비를 준비하지 못해 Camera → AI Detection → Server → Viewer → Event 전체 파이프라인은 최종 검증 전입니다.

---

## 6. 프로젝트 폴더 구조

```text
SafetyMonitor_Portfolio_v1/
├─ safety_monitor_client/       # Flutter Client GUI + Embedded Backend
├─ safety_monitor_server/       # FastAPI Server
├─ safety_monitor_viewer/       # Flutter Viewer
├─ client_server_viewer_model/  # 구조 예제
├─ docs/                        # 문서
├─ scripts/                     # 실행 보조 스크립트
├─ run_server.bat
├─ run_viewer.bat
├─ run_client.bat
├─ build_viewer.bat
├─ build_client.bat
├─ check_environment.bat
├─ requirements.txt
└─ requirements-server.txt
```

---

## 7. 실행 환경 및 요구사항

Windows 환경 기준으로 실행했습니다.

- Python 3.12
- Flutter SDK for Windows
- Visual Studio Community 또는 Build Tools
  - Desktop development with C++
  - Windows SDK
  - CMake Tools
- Git
- NVIDIA GPU / CUDA / TensorRT 환경은 AI 추론 최적화 시 필요

---

## 8. 실행 방법

프로젝트 루트에서 환경을 먼저 확인합니다.

```bat
check_environment.bat
```

의존성을 설치합니다.

```bat
install_dependencies.bat all
```

실행 순서는 다음과 같습니다.

```bat
run_server.bat
run_viewer.bat
run_client.bat
```

Server 정상 실행 예시:

```text
Application startup complete.
Uvicorn running on http://0.0.0.0:8000
```

Server Health Check:

```text
http://127.0.0.1:8000/health
```

---

## 9. Viewer 로그인 서버 주소 설정

Viewer는 Server 주소를 기준으로 로그인 API를 호출합니다.

정상 형식:

```text
http://127.0.0.1:8000
```

잘못된 형식:

```text
127.0.0.1:8000
```

`http://`가 빠지면 Viewer에서 로그인 요청이 Server에 도달하지 않을 수 있습니다.

설정 파일:

```text
safety_monitor_viewer/server_config.json
```

예시:

```json
{
  "api_base_url": "http://127.0.0.1:8000"
}
```

---

## 10. 주요 오류 및 해결 기록

### Viewer 로그인 오류

문제:

- Viewer 화면에서는 로그인 실패가 표시됨
- Server 로그에는 Login POST 요청이 찍히지 않음

원인:

- `server_config.json`에 `http://`가 빠진 상태로 저장되어 있었음

수정:

- `http://127.0.0.1:8000` 형태로 수정
- 직접 API 요청과 Viewer 로그인 정상 확인

---

### Client 빌드 오류

문제:

```text
The method '_refreshAllApiData' isn't defined for the type '_HomeScreenState'.
```

원인:

- 새로고침 버튼에서 `_refreshAllApiData()`를 호출하지만 함수 정의가 누락되어 있었음

수정:

- Runtime Config, Registered Sources, Source Status, API Events 갱신 함수를 묶는 `_refreshAllApiData()` 함수 추가
- Windows Client Build 성공 확인

---

## 11. 프로젝트를 통해 배운 점

- 기존 프로젝트를 다시 실행하는 과정에서도 환경 설정과 빌드 오류가 많이 발생할 수 있다는 점
- Server 로그와 Viewer 동작을 비교하면서 요청이 어디까지 도달했는지 확인하는 방법
- Flutter Windows Build 오류를 Dart 코드 기준으로 추적하는 방법
- 프로젝트 README에는 완성된 기능뿐 아니라 검증 상태와 미완료 항목도 분명히 적어야 한다는 점
- 포트폴리오에서는 팀프로젝트 기능과 개인 수정 범위를 구분해야 한다는 점

---

## 12. 향후 작업 계획

- [ ] USB Camera 연결 테스트
- [ ] Client에서 실시간 영상 확인
- [ ] YOLO Detection 동작 확인
- [ ] Viewer에서 실시간 Preview 표시 확인
- [ ] NO_Helmet Event 발생 테스트
- [ ] Event Clip 저장 및 재생 확인
- [ ] 다른 PC Viewer 접속 테스트
- [ ] 다른 PC Client 접속 테스트
- [ ] MFC / OpenCV 실습 결과물 별도 정리
- [ ] C# / .NET 기반 후속 포트폴리오 제작

---

## 13. 현재 버전

```text
Safety Monitor Portfolio v1
```

현재 버전은 **기존 AI 안전 관제 팀프로젝트를 개인 포트폴리오 형태로 정리하고, Viewer UI 및 기본 실행 흐름을 확인한 1차 버전**입니다.

실카메라 기반 전체 파이프라인 검증은 후속 작업으로 진행합니다.
