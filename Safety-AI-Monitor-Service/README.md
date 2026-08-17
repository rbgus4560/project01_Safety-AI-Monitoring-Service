# AI Safety Monitor Portfolio

CCTV / USB 카메라 기반 **AI 안전 관제 시스템**입니다.

기존 팀프로젝트에서 구현한 `Client → Server → Viewer` 구조를 기반으로 전체 구조를 다시 분석하고, 개인 포트폴리오용으로 **Viewer UI/UX, 관제 화면, 카메라 관리, 실행 환경 및 일부 런타임 문제를 수정·개선한 프로젝트**입니다.

전체 데이터 흐름은 다음과 같습니다.

```text
Camera
  ↓
Client
  ↓
AI Object Detection
  ↓
Server
  ↓
Viewer
```

* **Client**는 각 PC의 카메라에 접근하고 AI 객체 탐지를 수행합니다.
* **Server**는 Client가 전달한 상태와 탐지 결과를 관리하고 이벤트를 저장합니다.
* **Viewer**는 Server API를 통해 카메라 상태, 관제 화면, 이벤트, 카메라 그룹 및 설정을 관리합니다.

---

# 프로젝트 배경

본 프로젝트는 기존 팀프로젝트인 **AI Safety Monitoring Service**를 기반으로 개인 포트폴리오 형태로 개선한 프로젝트입니다.

기존 팀프로젝트에서 구현된 AI 탐지 및 Client / Server / Viewer 구조를 유지하면서, 개인적으로 전체 실행 흐름을 분석하고 다음 부분을 수정했습니다.

## Personal Modification

* Viewer UI / UX 재구성
* 관리자 로그인 화면 구성
* Viewer 상단 메뉴 구조 개선
* Live Monitoring 화면 재구성
* 1 / 4 / 9 분할 관제 기능
* 카메라 그룹 생성 및 선택 UI
* 관제 배치 저장 기능
* 카메라 이름 관리 UI
* 관리자 / 카메라 설정 페이지 구성
* 창 크기에 따른 관제 레이아웃 개선
* Viewer 서버 URL 설정 오류 수정
* Client Windows 빌드 오류 수정
* Client 전체 데이터 새로고침 기능 복구
* Server → Viewer → Client 실행 흐름 재검증
* 실행용 BAT 및 환경 구성 확인

AI 모델 학습 및 기존 Client / Server 핵심 통신 구조는 팀프로젝트 기반 기능이며, 개인 수정 범위와 구분하여 관리합니다.

---

# 현재 검증 상태

현재 개발 PC에서 다음 항목까지 동작을 확인했습니다.

| 항목                     | 상태              |
| ---------------------- | --------------- |
| FastAPI Server 실행      | ✅ 확인            |
| Server Health Check    | ✅ 확인            |
| Viewer Windows 실행      | ✅ 확인            |
| Viewer 관리자 로그인         | ✅ 확인            |
| Viewer → Server API 연결 | ✅ 확인            |
| Client Windows Build   | ✅ 확인            |
| Client Windows 실행      | ✅ 확인            |
| 카메라 목록 UI              | ✅ 확인            |
| 1 / 4 / 9 분할 UI        | ✅ 확인            |
| 카메라 그룹 UI              | ✅ 확인            |
| 관제 배치 UI               | ✅ 확인            |
| 실제 USB 카메라 입력          | ⏳ 미검증           |
| 실시간 YOLO 추론            | ⏳ 실카메라 확보 후 검증  |
| Viewer 실시간 영상 표시       | ⏳ 실카메라 확보 후 검증  |
| 이벤트 생성 / 클립 저장         | ⏳ 실카메라 기반 최종 검증 |
| 다른 PC 배포 테스트           | ⏳ 예정            |

> 현재 카메라 장비를 준비하지 못한 상태이므로 실제 카메라 → AI 추론 → Server → Viewer 전체 파이프라인은 최종 검증 전 상태입니다.

---

# 시스템 구조

```text
┌──────────────────────┐
│        Client        │
│                      │
│ USB Camera / CCTV    │
│ YOLO Detection       │
│ Embedded FastAPI     │
└──────────┬───────────┘
           │
           │ Detection / Status / Preview
           ▼
┌──────────────────────┐
│        Server        │
│                      │
│ FastAPI              │
│ Account / Camera     │
│ Rule / Event         │
│ Database             │
└──────────┬───────────┘
           │
           │ API
           ▼
┌──────────────────────┐
│        Viewer        │
│                      │
│ Monitoring           │
│ Camera Group         │
│ Event / Rule         │
│ Admin Management     │
└──────────────────────┘
```

---

# 프로젝트 구성

```text
SafetyMonitor_Portfolio_v1/
│
├─ safety_monitor_client/
│  ├─ lib/
│  ├─ embedded_backend/
│  └─ ...
│
├─ safety_monitor_server/
│  ├─ main.py
│  └─ ...
│
├─ safety_monitor_viewer/
│  ├─ lib/
│  ├─ server_config.json
│  └─ ...
│
├─ client_server_viewer_model/
├─ docs/
├─ scripts/
│
├─ check_environment.bat
├─ install_dependencies.bat
├─ build_client.bat
├─ build_viewer.bat
│
├─ run_server.bat
├─ run_client.bat
├─ run_viewer.bat
│
├─ requirements.txt
├─ requirements-server.txt
└─ README.md
```

---

# 기술 스택

## Client

* Flutter
* Dart
* Python
* FastAPI
* YOLO
* OpenCV
* TensorRT
* CUDA

## Server

* Python
* FastAPI
* SQLite
* REST API
* WebSocket

## Viewer

* Flutter
* Dart
* HTTP API
* WebSocket

## Development Environment

* Windows 10 / 11
* Python 3.12
* Flutter SDK
* Visual Studio C++ Build Tools
* Git / GitHub

---

# Client

경로:

```text
safety_monitor_client/
```

Client는 실제 영상 소스와 AI 추론을 담당합니다.

## 주요 역할

* USB 카메라 연결
* 카메라 영상 입력
* YOLO 객체 탐지
* Source 등록
* Client 상태 전송
* Heartbeat 전송
* Preview Frame 전송
* Detection Result 전송
* Server와 상태 동기화

Client 내부에는 Flutter GUI와 Python 기반 분석 프로세스를 연결하기 위한 Embedded Backend가 포함되어 있습니다.

기본 Embedded Backend 주소:

```text
http://127.0.0.1:8100
```

---

# AI Detection

사용 모델은 기존 팀프로젝트에서 학습한 YOLO 기반 안전모 탐지 모델을 사용합니다.

주요 Class:

```text
YES_Helmet
NO_Helmet
Person
```

예상 탐지 흐름:

```text
Camera Frame
    ↓
YOLO
    ↓
Object Detection
    ↓
Detection Result
    ↓
Server
```

Client는 객체 탐지를 수행하며 이벤트 최종 판정과 저장은 Server가 담당합니다.

---

# Server

경로:

```text
safety_monitor_server/
```

중앙 Server는 전체 시스템의 데이터 관리 역할을 담당합니다.

## 주요 역할

* Client 등록
* Camera Source 관리
* Client Heartbeat 관리
* Camera 상태 관리
* Detection Result 수신
* Preview Frame 관리
* 사용자 / 권한 관리
* Camera Rule 관리
* Event 관리
* Camera Group 관리
* Viewer Layout 관리
* Viewer API 제공

기본 Server 주소:

```text
http://127.0.0.1:8000
```

다른 PC에서 Server에 접근할 경우 Server PC의 IPv4 주소를 사용합니다.

예:

```text
http://192.168.0.100:8000
```

---

# Server Health Check

Server 실행 후 브라우저에서 다음 주소를 확인합니다.

```text
http://127.0.0.1:8000/health
```

정상적으로 응답한다면 FastAPI Server가 정상 실행 중입니다.

FastAPI API 문서는 다음 주소에서 확인할 수 있습니다.

```text
http://127.0.0.1:8000/docs
```

---

# Viewer

경로:

```text
safety_monitor_viewer/
```

Viewer는 중앙 관제 프로그램 역할을 합니다.

Viewer는 Client에 직접 접속하지 않고 **Server를 통해 Camera / Event / Rule 데이터를 관리**합니다.

## 주요 기능

* 관리자 로그인
* Server 연결
* 연결된 Camera 목록 확인
* Camera 이름 변경
* Live Monitoring
* 1분할 / 4분할 / 9분할
* Camera Group 생성
* Camera Group 선택
* Camera Layout 저장
* Camera Rule 설정
* Event 조회
* 관리자 기능

---

# Viewer 로그인

Viewer 실행 시 로그인 화면이 표시됩니다.

Viewer는 설정된 Server 주소를 이용하여 로그인 API를 호출합니다.

Server 주소 형식은 반드시 다음과 같이 Protocol을 포함해야 합니다.

```text
http://127.0.0.1:8000
```

잘못된 예:

```text
127.0.0.1:8000
```

Viewer 기본 Server 설정 파일:

```text
safety_monitor_viewer/server_config.json
```

예:

```json
{
  "api_base_url": "http://127.0.0.1:8000"
}
```

---

# Viewer 화면 구성

Viewer는 크게 세 영역으로 구성됩니다.

```text
┌─────────────────────────────────────────────────────────────┐
│ SAFETY MONITOR         EVENT  CAMERA SETTING  ADMIN        │
├──────────────┬─────────────────────────┬────────────────────┤
│              │                         │                    │
│ Camera List  │    Live Monitoring      │   Event / Rule     │
│              │                         │                    │
│              │                         │                    │
└──────────────┴─────────────────────────┴────────────────────┘
```

## 왼쪽

Camera 목록을 표시합니다.

* Camera 이름
* Camera 상태
* Client 상태
* Camera 선택
* Camera 이름 수정

## 중앙

Live Monitoring 영역입니다.

지원 Layout:

```text
1분할
4분할
9분할
```

Camera Group에 따라 표시할 Camera를 선택할 수 있습니다.

## 오른쪽

선택 Camera와 관련된 정보를 표시합니다.

* Event
* Detection
* Rule
* Camera Detail

---

# Camera Group

Viewer에서 여러 Camera를 하나의 Group으로 관리할 수 있습니다.

예:

```text
공장 1층
 ├─ 출입구 카메라
 ├─ 작업장 카메라
 └─ 창고 카메라
```

또는

```text
학교
 ├─ 학교 컴퓨터 1번
 └─ 이동현 PC
```

## 그룹 생성

Camera Group 관리 버튼을 선택합니다.

1. 그룹 이름을 입력합니다.
2. 그룹에 포함할 Camera를 선택합니다.
3. `그룹 저장`을 선택합니다.

그룹 이름을 입력하지 않은 경우:

```text
그룹 이름을 입력해주세요.
```

Camera를 선택하지 않은 경우:

```text
카메라를 하나 이상 선택해주세요.
```

Server 저장에 실패한 경우:

```text
그룹 저장에 실패했습니다.
```

---

# Live Monitoring

Live Monitoring 화면에서는 Camera를 여러 개 배치할 수 있습니다.

지원 모드:

```text
1분할
4분할
9분할
```

현재 선택된 Camera Group에 포함된 Camera만 표시할 수 있습니다.

Camera Group이 없는 경우 기본값은:

```text
전체 카메라
```

입니다.

관제 배치는 Viewer Layout으로 Server에 저장할 수 있습니다.

---

# Viewer UI 개선

기존 Viewer를 개인 포트폴리오용 관제 UI로 재구성했습니다.

## 주요 변경 사항

### 상단 Navigation

기존 Server URL 입력 / Apply Server 영역을 제거하고 로그인 단계에서 Server 주소를 설정하도록 변경했습니다.

현재 메뉴:

```text
SAFETY MONITOR

이벤트
카메라 설정
관리
사용자
로그아웃
```

### Live Monitoring Toolbar

기존 UI의 크기와 간격을 재조정했습니다.

```text
Live Monitoring

[1분할] [4분할] [9분할]
[전체 카메라 ▼]
[그룹 관리]
[배치 저장]
```

* 버튼 크기 통일
* Icon Button 크기 통일
* Component 간격 조정
* Camera Group Dropdown 크기 조정
* Layout Control 영역 정리

---

# Window Layout

본 프로그램은 Desktop Monitoring Program을 기준으로 설계했습니다.

작은 창 크기에서 UI Component가 지나치게 축소되지 않도록 최소 Content Width를 적용합니다.

예:

```text
1280px 이상 권장
```

기본 구조:

```text
Camera Panel
    +
Live Monitoring
    +
Event / Rule Panel
```

중앙 Live Monitoring 영역이 남은 공간을 확장해서 사용합니다.

---

# 관리자 기능

관리자 계정으로 로그인할 경우 다음 기능을 사용할 수 있습니다.

* Camera 설정
* Rule 설정
* 사용자 / 권한 관리
* Camera Group 관리
* Viewer Layout 관리

일반 사용자는 관제 기능 중심으로 사용할 수 있도록 역할을 분리할 수 있습니다.

---

# Camera Rule

Camera별로 안전 관련 Rule을 설정할 수 있습니다.

예:

```text
안전모 미착용
위험구역 진입
```

안전모 미착용 Rule:

```text
NO_Helmet
```

탐지를 기준으로 Server에서 Event를 판단합니다.

위험구역 Rule은 사람이 설정된 ROI 영역에 진입했는지 기준으로 판단합니다.

---

# 실행 전 환경 확인

프로젝트 Root에서 다음 명령을 실행합니다.

```bat
check_environment.bat
```

주요 확인 항목:

* Python
* Python Virtual Environment
* Flutter
* Windows Build Environment
* 프로젝트 경로

---

# 의존성 설치

처음 실행하는 PC에서는 다음 명령으로 필요한 의존성을 설치합니다.

```bat
install_dependencies.bat
```

또는 프로젝트 설정에 따라:

```bat
install_dependencies.bat all
```

---

# 권장 실행 순서

## 1. Server 실행

```bat
run_server.bat
```

정상 실행 예:

```text
Application startup complete.
Uvicorn running on http://0.0.0.0:8000
```

---

## 2. Viewer 실행

새 Terminal에서:

```bat
run_viewer.bat
```

Viewer 실행 후 Server에 로그인합니다.

---

## 3. Client 실행

새 Terminal에서:

```bat
run_client.bat
```

정상적으로 실행되면 Client GUI와 AI Backend 상태를 확인합니다.

---

# Build

Viewer Windows Build:

```bat
build_viewer.bat
```

또는 Viewer Directory에서:

```bash
flutter build windows
```

Client Windows Build:

```bat
build_client.bat
```

또는 Client Directory에서:

```bash
flutter build windows
```

---

# 실행 흐름

최종 실행 순서는 다음과 같습니다.

```text
1. Server
      ↓
2. Viewer
      ↓
3. Client
      ↓
4. Camera Connection
      ↓
5. AI Detection
      ↓
6. Server Event Processing
      ↓
7. Viewer Monitoring
```

Server는 시스템 전체에서 먼저 실행해야 합니다.

---

# 발견 및 수정한 문제

개인화 과정에서 다음 문제를 확인하고 수정했습니다.

## Viewer Login Server URL

기존 설정:

```text
127.0.0.1:8000
```

HTTP Protocol이 누락되어 Viewer Login Request가 Server까지 전달되지 않는 문제가 있었습니다.

수정:

```text
http://127.0.0.1:8000
```

---

## Client Windows Build

Client `home_screen.dart`에서 다음 함수가 호출되고 있었지만 정의가 누락되어 있었습니다.

```dart
_refreshAllApiData()
```

필요한 Refresh 기능을 연결하여 Windows Build 오류를 수정했습니다.

확인 결과:

```text
Built build\windows\x64\runner\Release\safety_monitor_client.exe
```

---

# 실행 시 주의사항

## Server URL

같은 PC에서 실행:

```text
http://127.0.0.1:8000
```

다른 PC에서 연결:

```text
http://<SERVER_PC_IP>:8000
```

예:

```text
http://192.168.0.152:8000
```

---

## Firewall

다른 PC에서 Server에 접근할 수 없는 경우 관리자 권한으로 실행합니다.

```bat
setup_server_firewall.bat
```

TCP Port:

```text
8000
```

을 허용합니다.

---

# 경로 권장사항

Flutter Windows Build는 프로젝트 경로가 지나치게 길 경우 문제가 발생할 수 있습니다.

권장:

```text
C:\SafetyMonitor_Portfolio_v1
D:\SafetyMonitor_Portfolio_v1
C:\myproject\SafetyMonitor_Portfolio_v1
```

가능하면 OneDrive, Desktop 등의 깊은 경로는 피하는 것을 권장합니다.

---

# Git 제외 권장 파일

다음 파일은 Git Repository에 포함하지 않는 것을 권장합니다.

```gitignore
.venv/
.dart_tool/
build/
__pycache__/
*.pyc
*.log
.vs/
.idea/
```

TensorRT Engine 또는 대용량 AI Model 역시 Repository 용량을 고려하여 별도 관리할 수 있습니다.

```gitignore
*.engine
```

---

# 향후 개선

현재 Portfolio v1 이후 다음 기능을 추가 검증할 예정입니다.

* [ ] USB Camera 실제 연결 테스트
* [ ] 실시간 YOLO Detection 테스트
* [ ] Viewer 실시간 Preview 확인
* [ ] NO_Helmet Event 발생 테스트
* [ ] Event Clip 저장 확인
* [ ] Viewer Event Clip 재생 확인
* [ ] 여러 Camera 동시 연결 테스트
* [ ] 다른 PC Client 연결 테스트
* [ ] 다른 PC Viewer 연결 테스트
* [ ] Windows 설치형 패키지 제작
* [ ] RTSP CCTV 지원
* [ ] ONVIF Camera 연동 검토

---

# 프로젝트 목표

기존 단일 AI Detection Demo 수준에서 확장하여,

```text
AI Detection
      +
Client / Server 분리
      +
Central Monitoring
      +
Camera Management
      +
Event Management
```

구조를 가진 **실제 운용 프로그램 형태의 AI 안전 관제 시스템**으로 발전시키는 것을 목표로 합니다.

---

# 현재 버전

```text
Safety Monitor Portfolio v1
```

현재 버전은 **UI / 실행 환경 / Viewer 관제 구조 개인화 및 기본 실행 검증 단계**입니다.

실카메라 기반 전체 Pipeline 검증은 후속 테스트로 진행합니다.
