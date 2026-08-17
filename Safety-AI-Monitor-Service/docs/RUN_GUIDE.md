# 실행/빌드 가이드

이 문서는 다른 PC에서 `git pull` 이후 서버, 뷰어, 클라이언트를 빌드하고 실행 테스트할 수 있도록 정리한 절차입니다.

권장 실행 순서는 항상 다음과 같습니다.

```text
서버 실행 -> 뷰어 실행 -> 서버 PC 클라이언트 실행 -> 다른 PC 클라이언트 실행
```

## 0. 반드시 먼저 확인할 것

### 워크스페이스 경로

Flutter Windows 빌드는 경로가 길면 실패하기 쉽습니다. 저장소는 `Desktop`, `OneDrive`, `Downloads` 아래가 아니라 C 또는 D 드라이브 루트 근처의 짧은 실제 경로에 둡니다.

권장 예시:

```text
C:\safety_monitor_workspace
D:\safety_monitor_workspace
C:\hiyoung_team_github\safety_monitor_workspace
```

피해야 하는 예시:

```text
C:\Users\...\Desktop\...\safety_monitor_workspace
C:\Users\...\OneDrive\...\safety_monitor_workspace
C:\Users\...\Downloads\...\safety_monitor_workspace
```

배치파일은 워크스페이스 경로 길이가 `80`자 이상이면 중단합니다. 이 경우 코드를 고치는 문제가 아니라 폴더를 짧은 경로로 옮겨야 합니다.

### 배치파일이 바로 꺼지는 것처럼 보일 때

`run_client.bat`, `run_viewer.bat`는 실행 파일을 `start` 명령으로 새 창에서 띄운 뒤 배치파일 창 자체는 종료됩니다. 앱 창이 실제로 뜬다면 정상입니다.

앱 창도 안 뜨고 배치파일 창이 바로 사라지면, 더블클릭하지 말고 `cmd`에서 직접 실행합니다.

```bat
cd /d C:\hiyoung_team_github\safety_monitor_workspace
run_viewer.bat
```

또는 로그 파일로 남겨서 확인합니다. `logs` 폴더가 없으면 먼저 만듭니다.

```bat
if not exist logs mkdir logs
run_viewer.bat > logs\run_viewer_manual.log 2>&1
run_client.bat > logs\run_client_manual.log 2>&1
build_viewer.bat > logs\build_viewer_manual.log 2>&1
build_client.bat > logs\build_client_manual.log 2>&1
```

실행 중 창이 바로 닫히는 가장 흔한 원인은 다음입니다.

- 워크스페이스 경로가 너무 김
- Python 3.12가 설치되지 않았거나 PATH에 없음
- Flutter SDK가 `flutter\bin\flutter.bat` 위치에 없고 PATH에도 없음
- Visual Studio C++ Build Tools 또는 Windows SDK가 없음
- 모델 파일 `best.pt` 또는 `best.engine`이 없음
- 서버 URL을 `127.0.0.1`로 넣어서 다른 PC에서 자기 자신을 보고 있음
- 서버 PC 방화벽에서 8000 포트가 막힘

## 1. 처음 받은 PC에서 준비

워크스페이스 루트에서 실행합니다.

```bat
cd /d C:\hiyoung_team_github\safety_monitor_workspace
check_environment.bat
install_dependencies.bat all
```

`install_dependencies.bat all`은 다음을 준비합니다.

- 루트 `.venv` Python 가상환경 생성
- 서버 FastAPI 의존성 설치
- 클라이언트 내장 백엔드 의존성 설치

서버만 준비할 때:

```bat
install_dependencies.bat server
```

클라이언트 내장 백엔드까지 준비할 때:

```bat
install_dependencies.bat client
```

## 2. 서버 실행

서버 PC에서 실행합니다.

```bat
run_server.bat
```

서버는 아래 주소로 열립니다.

```text
http://0.0.0.0:8000
```

서버 PC 자기 자신에서 확인할 때:

```text
http://127.0.0.1:8000/health
```

다른 PC에서 확인할 때는 서버 PC의 IPv4 주소를 사용합니다.

```text
http://192.168.24.114:8000/health
```

`run_server.bat` 실행 시 사용 가능한 서버 URL 목록이 콘솔에 출력됩니다. 다른 PC의 뷰어/클라이언트에는 그 주소를 입력합니다.

다른 PC에서 `/health`가 열리지 않으면 서버 PC에서 관리자 권한으로 실행합니다.

```bat
setup_server_firewall.bat
```

서버 로그 파일:

```text
logs\server.log
```

서버 역할:

- 클라이언트 source 등록 관리
- 클라이언트 heartbeat/source status 수신
- 프레임 탐지 결과 저장
- 서버 기준 룰 판정
- 이벤트 DB 저장
- 이벤트 클립/썸네일 관리
- 뷰어 API와 실시간 상태 제공

## 3. 뷰어 빌드와 실행

### 빌드만 먼저 확인

다른 PC에서 `git pull` 직후에는 먼저 빌드만 따로 확인하는 것을 권장합니다.

```bat
build_viewer.bat
```

빌드 성공 후 실행 파일 위치:

```text
safety_monitor_viewer\build\windows\x64\runner\Release\safety_monitor_viewer.exe
```

### 실행

```bat
run_viewer.bat
```

서버 URL 입력 예시:

```text
http://192.168.24.114:8000
```

서버 PC에서 뷰어를 실행한다면 아래도 가능합니다.

```text
http://127.0.0.1:8000
```

다른 PC에서 뷰어를 실행할 때는 `127.0.0.1`을 넣으면 안 됩니다. 다른 PC의 `127.0.0.1`은 서버 PC가 아니라 그 PC 자신입니다.

뷰어 주요 확인 항목:

- 서버 health check 성공 여부
- 좌측 카메라 리스트 표시 여부
- Live Monitoring 영상 표시 여부
- 이벤트 로그 표시 여부
- 카메라 이름 편집 저장 여부
- 위험구역 ROI 편집/저장 여부
- 이벤트 클릭 시 해당 타일에서 클립 재생 여부

## 4. 클라이언트 빌드와 실행

### 모델 파일 확인

클라이언트 실행 전 아래 폴더에 `best.pt` 또는 `best.engine` 중 하나가 있어야 합니다.

```text
safety_monitor_client\embedded_backend\app\analysis\models\weights
```

없으면 `run_client.bat`가 중단됩니다.

### 빌드만 먼저 확인

```bat
build_client.bat
```

빌드 성공 후 실행 파일 위치:

```text
safety_monitor_client\build\windows\x64\runner\Release\safety_monitor_client.exe
```

### 실행

```bat
run_client.bat
```

서버 URL 입력 예시:

```text
http://192.168.24.114:8000
```

서버 PC에서 클라이언트를 실행한다면 아래도 가능합니다.

```text
http://127.0.0.1:8000
```

다른 PC에서 클라이언트를 실행할 때는 반드시 서버 PC IPv4 주소를 넣습니다.

클라이언트 로그 파일:

```text
logs\client.log
```

클라이언트 역할:

- 로컬 0번 카메라 사용
- 객체 탐지만 수행
- 서버로 source presence, heartbeat, preview, frame detection 전송
- 룰 판정과 이벤트 기록은 하지 않음

## 5. 전체 테스트 순서

### 서버 PC

```bat
cd /d C:\hiyoung_team_github\safety_monitor_workspace
run_server.bat
```

서버 창은 닫지 않습니다.

### 뷰어 PC

서버 PC와 같은 PC여도 되고, 다른 PC여도 됩니다.

```bat
cd /d C:\hiyoung_team_github\safety_monitor_workspace
run_viewer.bat
```

서버 URL 입력:

```text
http://<서버PC IPv4>:8000
```

### 서버 PC 클라이언트

```bat
run_client.bat
```

서버 URL 입력:

```text
http://127.0.0.1:8000
```

또는 서버 PC IPv4 주소도 가능합니다.

### 다른 PC 클라이언트

```bat
run_client.bat
```

서버 URL 입력:

```text
http://<서버PC IPv4>:8000
```

정상 상태:

- 클라이언트 콘솔에서 서버 health check 성공
- 뷰어 좌측 카메라 리스트에 카메라 추가
- Live Monitoring에 영상 표시
- 클라이언트 연결이 끊기면 뷰어에서 해당 카메라가 사라짐
- 같은 source_key가 다시 연결되면 기존 display_name으로 다시 표시

## 6. 빌드 배치파일의 긴 경로 대응

`build_client.bat`, `build_viewer.bat`는 Windows 경로 길이 문제를 줄이기 위해 짧은 junction 경로를 임시로 만듭니다.

```text
C:\smw_build_client
C:\smw_build_viewer
```

정상 종료 또는 실패 종료 시 배치파일이 이 경로를 정리합니다.

만약 강제 종료나 `Ctrl+C` 때문에 남아 있으면 다음 빌드 시작 시 먼저 정리하려고 시도합니다. 그래도 실패하면 관리자 권한 `cmd`에서 직접 제거합니다.

```bat
rmdir C:\smw_build_client
rmdir C:\smw_build_viewer
```

주의: 이 경로는 junction입니다. 실제 워크스페이스를 삭제하는 명령이 아니어야 합니다. `rmdir C:\smw_build_client`처럼 junction 경로만 지정합니다.

## 7. 자주 보는 오류와 대응

### `Workspace path is too long`

저장소 경로가 너무 깁니다. C 또는 D 드라이브 루트 근처로 옮깁니다.

### `Flutter SDK not found`

아래 둘 중 하나가 필요합니다.

- 워크스페이스 루트에 `flutter\bin\flutter.bat` 존재
- 시스템 PATH에서 `flutter` 실행 가능

확인:

```bat
flutter --version
```

### `Windows C++ build tools are missing`

Visual Studio Installer에서 아래 항목을 설치합니다.

```text
Desktop development with C++
Windows 10/11 SDK
MSVC v143 또는 v14x C++ build tools
```

### `media_kit_libs_windows_video_... lastbuildstate` / `MSB3491`

대부분 코드 문제가 아니라 Flutter/MSBuild 중간 산출물 경로 또는 이전 빌드 찌꺼기 문제입니다.

순서대로 시도합니다.

```bat
rmdir C:\smw_build_client
rmdir C:\smw_build_viewer
```

그 다음 프로젝트 build 폴더를 삭제합니다.

```bat
rmdir /s /q safety_monitor_client\build
rmdir /s /q safety_monitor_viewer\build
```

다시 빌드합니다.

```bat
build_client.bat
build_viewer.bat
```

### `No runtime model was found`

클라이언트 모델 파일이 없습니다. 아래 폴더에 `best.pt` 또는 `best.engine`을 둡니다.

```text
safety_monitor_client\embedded_backend\app\analysis\models\weights
```

### 서버 health check는 성공하지만 뷰어/클라이언트 영상이 안 나옴

확인 순서:

1. 뷰어/클라이언트에 입력한 서버 URL이 `http://<서버PC IPv4>:8000`인지 확인합니다.
2. 다른 PC 브라우저에서 `http://<서버PC IPv4>:8000/health`가 열리는지 확인합니다.
3. 서버 PC 방화벽을 확인합니다.
4. 클라이언트 PC의 카메라가 다른 프로그램에서 사용 중인지 확인합니다.
5. `logs\client.log`, `logs\server.log`를 확인합니다.

## 8. 위험구역 ROI 편집 흐름

1. 뷰어에서 카메라를 선택합니다.
2. `위험구역 드래그 편집`을 누릅니다.
3. 기존 ROI가 있으면 영상 위에 표시됩니다.
4. 영상 위에서 새 ROI를 드래그합니다.
5. 드래그 중에는 화면에만 임시 ROI가 반영됩니다.
6. `위험구역 편집 종료`를 누르면 서버에 저장됩니다.
7. ROI 저장만으로 위험구역 룰이 자동 ON 되지는 않습니다.
8. 위험구역 룰 토글 ON/OFF는 이벤트 판정 적용 여부만 제어합니다.
9. 현재 위험구역 룰은 `Person` 탐지 박스가 ROI와 겹치면 이벤트로 판정합니다.

## 9. 테스트용 DB Clear

뷰어 좌상단 `DB Clear`는 테스트용입니다.

삭제 대상:

- 서버 이벤트 DB 레코드
- 프레임 탐지 DB 레코드
- 서버 이벤트 클립 MP4
- 이벤트 썸네일 JPG
- 서버 메모리상의 진행 중 이벤트 상태

운영 UI에서는 숨기거나 제거할 수 있습니다.
