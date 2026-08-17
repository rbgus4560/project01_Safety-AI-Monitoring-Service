# Portfolio Version 변경 요약

## 기존 팀프로젝트에서 유지한 것

- Flutter Client / Viewer, Python FastAPI Server 구조
- Client 로컬 YOLO 추론
- 중앙 서버 영상 Preview / Detection 수신
- 중앙 서버 Event 판정 및 Clip/Thumbnail 생성
- SQLite 기반 이벤트 저장
- Viewer 실시간 관제 및 기존 Clip Player
- ROI 기반 위험구역 구조

## 개인 포트폴리오 버전에서 추가/확장한 것

### UI
- 기존 관제 화면 스타일을 기준으로 Client/Viewer 전체 Dark HMI Theme 통일
- 9개 화면 체계로 재구성
- Theme 파일 분리로 색상 변경 용이

### 계정 / 권한
- Viewer 로그인
- ADMIN / OPERATOR 역할
- 서버 API에서 관리자 기능 권한 검사
- 기본 데모 계정 제공

### Client 등록
- 사람이 매번 로그인하지 않는 장치 등록 방식
- 1회용 등록 코드
- EDGE-* Client ID와 Client auth token 발급
- 등록된 Client의 source/status/detection 요청 token 검증

### 다중 카메라
- 기존 camera index 0 전용 제약 제거
- camera index 0/1/2... 동시 등록 가능
- Video File 업로드/가상 카메라 테스트 지원
- 카메라별 display name

### Viewer 관제
- 1 / 4 / 9 분할
- 사용자별 Camera Group
- 사용자별 배치/순서 저장 및 복원
- Admin/Operator별 메뉴 분리

### Camera Rule
- 안전모 미착용 Rule
- 위험구역 사각형 ROI
- Confidence threshold
- Event cooldown
- 중앙 서버 Event Processor에서 threshold/cooldown 실제 적용

### Event
- Event History 전용 화면
- 검색/필터
- 확인/미확인 처리
- 기존 서버 Clip Player 재사용

### Admin
- 등록 Client 상태
- Client 활성/비활성
- Client 등록 코드 생성
- 사용자 추가
- 사용자 활성/비활성

## 테스트 완료 항목 (코드 제작 환경)

- Python 전체 compileall 성공
- FastAPI API smoke test 성공
  - admin/operator login
  - operator 관리자 API 차단
  - Client 등록/토큰 발급
  - 등록 Client token 검증
  - camera 0 + camera 1 동시 중앙 서버 등록
  - source status / frame detection 전송
  - Admin Rule 변경 + confidence/cooldown 저장
  - Camera Group 생성
  - Viewer Layout 저장/조회
- Client embedded backend smoke test 성공
  - camera 0 + camera 1 동시 로컬 등록
  - display name 변경
  - Video File source upload/등록

## 사용자 PC에서 추가로 확인해야 하는 항목

이 제작 환경에는 Windows Flutter SDK와 실제 USB Camera가 없으므로 아래는 사용자 PC에서 최종 빌드/실행 검증이 필요합니다.

- Flutter Viewer Windows build
- Flutter Client Windows build
- 실제 Server → Viewer → Client 통합 실행
- 실제 USB Camera 2~3대 동시 입력
- YOLO/CUDA/TensorRT 런타임
- 실제 Event/Clip 전체 시나리오
