# Safety Monitor Portfolio

기존 팀프로젝트를 기반으로 개인 포트폴리오용으로 확장한 **분산형 AI 안전 관제 시스템**입니다.

## 핵심 구조

```text
현장 PC (Safety Client)
  ├─ USB Camera 0 / 1 / 2 ... 또는 테스트 Video File
  ├─ YOLO 추론
  └─ Preview / Detection / Status 전송
              ↓
중앙 PC (Safety Server :8000)
  ├─ Client / Camera / User / 권한 관리
  ├─ Camera Rule / ROI / Event 관리
  ├─ SQLite DB
  └─ Event Clip / Thumbnail 저장
              ↓
관제 PC (Safety Viewer)
  ├─ ADMIN / OPERATOR 로그인
  ├─ 1 / 4 / 9 분할 실시간 관제
  ├─ 사용자별 Camera Group / Layout
  ├─ Event History / 확인 처리 / Clip 재생
  └─ Admin Rule / Client / User 관리
```

## 원본 팀프로젝트 대비 주요 확장

- Viewer 로그인과 ADMIN / OPERATOR 권한
- 서버 API의 실제 관리자 권한 검사
- Client 최초 1회 등록 코드 + 장치 토큰 인증
- Client 1개에서 여러 USB Camera index(0, 1, 2...) 관리
- USB Camera가 없어도 Video File을 가상 Camera처럼 등록 가능
- 카메라 표시 이름
- 사용자별 Camera Group
- 사용자별 1 / 4 / 9 분할 Layout 저장/복원
- Camera별 안전모/위험구역/Confidence/Event Cooldown 설정
- Event History, 확인/미확인 상태, 기존 Event Clip 재생
- 관리자 Client / Camera / User 관리
- Client/Viewer Dark HMI UI 통일

> 이벤트 Rule 판정과 Clip 생성은 안정성을 위해 기존 구조를 유지하여 **중앙 Server**가 담당합니다. AI 추론은 각 Client에서 분산 수행합니다.

## 실행 전에

Windows 기준으로 Git, Python 3.12, Flutter SDK, Visual Studio의 `Desktop development with C++` 워크로드가 필요합니다.

프로젝트는 경로를 짧게 두는 것을 권장합니다.

```text
C:\myproject\SafetyMonitor_Portfolio
```

## AI 모델 파일

GitHub에는 대용량 모델 가중치(`*.pt`, `*.engine`)를 커밋하지 않습니다.
실행 전 학습한 모델을 아래 위치에 배치합니다.

```text
safety_monitor_client/embedded_backend/app/analysis/models/weights/best.pt
```

자세한 내용은 해당 폴더의 `README.md`를 참고하세요.

## 최초 준비 및 빌드

PowerShell에서 Workspace 루트로 이동합니다.

```powershell
.\check_environment.bat
.\install_dependencies.bat all
.\build_viewer.bat
.\build_client.bat
```

기존 short-junction 빌드에서 발생하던 Flutter Git 인식 문제를 피하기 위해 Viewer/Client 빌드 스크립트는 **실제 프로젝트 경로에서 직접 빌드**하도록 수정되어 있습니다.

## 실행 순서

터미널 3개를 엽니다.

```powershell
# Terminal 1
.\run_server.bat

# Terminal 2
.\run_viewer.bat

# Terminal 3
.\run_client.bat
```

같은 PC에서 Server에 접속할 주소:

```text
http://127.0.0.1:8000
```

다른 PC에서 접속할 때는 Server 실행 창에 표시되는 LAN 주소를 사용합니다.

```text
예: http://192.168.0.13:8000
```

## 기본 로그인

```text
ADMIN
ID: admin
PW: admin1234

OPERATOR
ID: operator
PW: operator1234
```

## Client 최초 등록

최초 실행 시 Client 등록 화면이 표시됩니다.

```text
기본 1회용 등록 코드: SM-DEMO-2026
```

이미 사용했다면 Viewer의 관리자 화면에서 새 등록 코드를 생성합니다.

## 9개 UI 화면

### Client
1. C01 최초 Client 등록 / 서버 연결
2. C02 Client 메인 대시보드
3. C03 Camera 추가 / 설정

### Viewer
4. V01 로그인
5. V02 Live Monitoring
6. V03 Event History
7. V04 Event 상세 / Clip
8. V05 Camera Rule
9. V06 관리자 관리

디자인 기준 이미지는 `docs/portfolio_ui_storyboard.png`에 있습니다.

## 카메라가 없을 때

Client의 `카메라 추가`에서 `Video File (테스트용)`을 선택하면 영상 파일을 Camera처럼 등록하여 다중 소스, Viewer Layout, Rule, Event UI를 테스트할 수 있습니다.

## 실제 USB Camera 최종 테스트

학교에서 USB Camera 2~3대를 연결하여 다음을 확인합니다.

- Camera index 0 / 1 / 2 동시 등록
- 각 Camera별 독립 YOLO 추론
- Viewer의 독립 Camera 표시 및 1/4/9 분할
- 한 Camera 분리 시 나머지 Camera 계속 동작
- 재연결 후 복구
- 안전모 / 위험구역 Event 발생
- Event History 및 Clip 재생

## 상세 문서

- `PORTFOLIO_TEST_GUIDE.md` : 빌드/실행/테스트 순서
- `PORTFOLIO_CHANGELOG.md` : 기존 프로젝트 대비 변경점
- `DB_SCHEMA.md` : 기존 DB 설명
- `docs/portfolio_ui_storyboard.png` : 9개 UI 기준 이미지

## 테스트 상태

코드 제작 환경에서 다음을 확인했습니다.

- Python 전체 syntax/compile 검사
- FastAPI 로그인/권한/Client 등록/Token API smoke test
- Camera 0 + Camera 1 동시 소스 등록 smoke test
- Camera Group / Viewer Layout / Rule 저장 API smoke test
- Client embedded backend의 다중 Camera 및 Video File 등록 smoke test

Windows Flutter 빌드와 실제 USB Camera 입력은 사용자 Windows 환경에서 최종 검증해야 합니다.
