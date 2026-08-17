# 문서 모음

현재 프로젝트는 `클라이언트 -> 서버 -> 뷰어` 구조를 기준으로 동작합니다.

## 현재 구조 요약

- 클라이언트가 로컬 카메라 소스를 소유합니다.
- 클라이언트가 객체 탐지를 수행합니다.
- 서버가 룰을 적용해 이벤트를 판정하고 저장합니다.
- 서버가 이벤트 클립과 썸네일을 생성합니다.
- 뷰어는 서버에서 프리뷰 스트림, 상태, 이벤트, 클립, 썸네일을 조회합니다.
- 뷰어는 서버에 소스별 룰 설정을 저장합니다.

## 추천 읽는 순서

- 전체 구조: [../README.md](../README.md)
- 실행 절차: [../RUN_GUIDE.md](../RUN_GUIDE.md)
- 서버 DB 구조: [../DB_SCHEMA.md](../DB_SCHEMA.md)
- 이벤트 JSON 계약: [ai/event_json_schema.md](./ai/event_json_schema.md)
- 발표/시연 체크: [demo_checklist.md](./demo_checklist.md)
- 아키텍처 메모: [ai/ARCHITECTURE_NOTES.md](./ai/ARCHITECTURE_NOTES.md)
