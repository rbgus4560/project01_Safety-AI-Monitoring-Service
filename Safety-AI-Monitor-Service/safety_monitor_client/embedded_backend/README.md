# Embedded Client Backend

이 백엔드는 Flutter 클라이언트 내부에서 함께 실행되는 로컬 분석 백엔드입니다.

## 역할

- 클라이언트가 등록한 영상 파일, 카메라, 스트림 소스 관리
- 로컬 객체 탐지 실행
- 프리뷰 프레임 생성
- 프레임 탐지 결과 생성
- 소스 상태 heartbeat 생성
- 이벤트 클립 생성 및 서버 업로드
- 서버와 소스 메타데이터/상태 동기화

## 이 백엔드가 하지 않는 일

- 중앙 이벤트 최종 판정
- 여러 클라이언트 데이터 통합 저장
- 뷰어용 중앙 조회 API 제공

이 역할은 서버가 담당합니다.

## 로컬 API

기본 포트:

- `8100`

주요 엔드포인트:

- `GET /health`
- `GET /api/sources`
- `POST /api/sources`
- `POST /api/sources/{source_key}/start`
- `POST /api/sources/{source_key}/stop`
- `POST /api/sources/{source_key}/restart`
- `PATCH /api/sources/{source_key}/config`
- `DELETE /api/sources/{source_key}`

## 실행

일반 사용자는 이 백엔드를 단독으로 실행하지 않습니다.

```powershell
run_client.bat
```
