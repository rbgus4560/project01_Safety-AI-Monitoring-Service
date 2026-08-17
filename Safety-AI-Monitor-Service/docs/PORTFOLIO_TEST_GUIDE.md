# Safety Monitor Portfolio Version - 실행/테스트 가이드

이 폴더는 기존 팀프로젝트를 기반으로 포트폴리오용 UI와 관리 기능을 확장한 버전입니다.

## 1. 추가된 핵심 기능

- Viewer 로그인: ADMIN / OPERATOR
- 서버에서 실제 역할 권한 검사
- Client 최초 등록 코드 + 장치 토큰 발급
- 등록된 Client 토큰을 이용한 소스/상태/탐지 데이터 인증
- 한 Client에서 여러 USB Camera index(0, 1, 2...) 등록 가능
- USB 카메라가 없을 때 Video File을 가상 카메라처럼 추가 가능
- 카메라 표시 이름 설정
- 사용자별 Camera Group 생성/삭제
- 사용자별 1 / 4 / 9 분할 레이아웃과 카메라 순서 저장
- 관리자 Camera Rule: 안전모, 위험구역 ROI, Confidence, Event Cooldown
- Event History / 확인 처리 / 기존 Event Clip 재생
- 관리자 Client/Camera 및 사용자 관리 화면
- UI 색상은 Viewer/Client의 `lib/ui/portfolio_theme.dart`에서 일괄 변경 가능

UI 기준 이미지는 `docs/portfolio_ui_storyboard.png`에 있습니다.

## 2. 최초 빌드

PowerShell에서 workspace 루트로 이동합니다.

```powershell
cd C:\myproject\hiyoung_team_github\safety_monitor_workspace
```

환경/의존성:

```powershell
.\check_environment.bat
.\install_dependencies.bat all
```

Viewer:

```powershell
.\build_viewer.bat
```

Client:

```powershell
.\build_client.bat
```

> 기존 short junction 빌드에서 Flutter Git 오류가 났던 부분을 포트폴리오 버전에서는 실제 프로젝트 경로에서 직접 빌드하도록 단순화했습니다.

## 3. 실행 순서

터미널 3개를 사용합니다.

```powershell
# Terminal 1
.\run_server.bat

# Terminal 2
.\run_viewer.bat

# Terminal 3
.\run_client.bat
```

같은 PC에서 테스트할 중앙 서버 주소:

```text
http://127.0.0.1:8000
```

다른 PC에서 중앙 서버로 접속할 때는 Server 창에 표시되는 LAN 주소(예: `http://192.168.0.13:8000`)를 사용합니다.

## 4. 기본 테스트 계정

```text
관리자
ID: admin
PW: admin1234

운영자
ID: operator
PW: operator1234
```

관리자는 Camera Rule / Client / 사용자 관리에 접근할 수 있고, 운영자는 관제 및 Event 확인 위주로 사용합니다.

## 5. Client 최초 등록

Client를 처음 실행하면 C01 등록 화면이 나옵니다.

최초 테스트에서는 아래 기본 등록 코드를 사용할 수 있습니다.

```text
SM-DEMO-2026
```

이 코드는 1회용입니다. 이미 사용했다면 Viewer에서 관리자 로그인 후 `관리 → Client / Camera 관리 → Client 등록 코드 생성`으로 새 코드를 만듭니다.

등록 성공 시 Client 폴더에 다음 파일이 생성됩니다.

- `client_identity.json`
- `client_settings.json`

재등록 테스트를 하려면 Client를 종료하고 위 identity 파일을 삭제한 뒤 새 등록 코드를 사용합니다.

## 6. USB 카메라가 없는 상태의 테스트

현재 카메라가 없다면 Client의 `카메라 추가`에서 `Video File (테스트용)`을 선택합니다. 서로 다른 테스트 영상 2~3개를 추가해 다중 소스 구조를 확인할 수 있습니다.

확인 항목:

1. Client에 영상 소스 여러 개가 각각 표시되는가
2. Viewer 카메라 목록에 각각 별도 source로 표시되는가
3. 1/4/9 분할이 바뀌는가
4. Camera Group 생성 후 해당 그룹만 필터링되는가
5. `배치 저장` 후 Viewer를 다시 실행했을 때 레이아웃이 복원되는가
6. Admin이 Rule을 저장할 수 있는가
7. Operator가 관리자 Rule/API를 변경할 수 없는가
8. Event History와 상세 팝업이 열리는가

## 7. 학교에서 실제 USB 카메라 테스트

Client의 `카메라 추가`에서 USB Camera를 선택하고 index를 0, 1, 2 순서로 등록합니다.

최종 성공 기준:

- USB 카메라 2~3대 동시 등록
- 각 카메라가 서로 다른 source_key / Camera ID로 유지
- 각 카메라 YOLO 추론
- Viewer에서 각각 독립적으로 표시
- 카메라 하나를 제거해도 나머지는 계속 동작
- 제거된 카메라만 reconnecting/offline으로 표시
- 다시 연결하면 복구
- 안전모/위험구역 Event 발생
- Event 상세 및 기존 Clip 재생 확인

## 8. 화면 구성

### Client
- C01 최초 Client 등록 / 서버 연결
- C02 Client 메인 대시보드
- C03 카메라 추가 / 설정

### Viewer
- V01 로그인
- V02 Live Monitoring
- V03 Event History
- V04 Event 상세 / Clip
- V05 Camera Rule
- V06 관리자 관리

## 9. 색상 변경

색상은 아래 두 파일에 집중되어 있습니다.

```text
safety_monitor_viewer/lib/ui/portfolio_theme.dart
safety_monitor_client/lib/ui/portfolio_theme.dart
```

현재는 dark navy + teal 계열이며, 나중에 색상만 수정해도 전체 UI에 반영되도록 구성했습니다.

## 10. 현재 구현 방향

현재 원본 프로젝트의 중요한 동작은 유지합니다.

- AI 추론: Client
- 실시간 Preview/Detection 전송: Client → Central Server
- Event 판정/중복 억제/Clip 생성: Central Server
- DB / Clip / Thumbnail 저장: Central Server PC
- Live/Event/Rule/Admin UI: Viewer

포트폴리오 버전에서는 기존 Event Clip 로직을 새로 뜯지 않고 재사용해 안정성을 우선했습니다.
