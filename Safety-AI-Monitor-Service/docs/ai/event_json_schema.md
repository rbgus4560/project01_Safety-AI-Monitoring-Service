# event_json_schema.md

## 목적

- 이벤트 JSON은 서버가 최종 저장하는 공통 이벤트 계약입니다.
- 객체 탐지 결과는 클라이언트가 보내지만, 이벤트 판정은 서버가 수행합니다.
- 이 문서는 서버 DB `events.payload_json`과 이벤트 조회 API 응답에 적용됩니다.
- `*_event_log.txt`는 보조 로그이고, 주 조회 경로는 서버 API입니다.

## 기록 단위

- 이벤트 1건 또는 같은 이벤트의 상태 변경 1건이 1레코드입니다.
- 같은 `source_key + event_key`에 대해 `START`, `END`가 누적될 수 있습니다.
- 최신 상태만 필요하면 같은 `source_key + event_key` 기준 마지막 레코드를 사용합니다.

## 주요 필드

| 필드 | 타입 | 설명 |
| --- | --- | --- |
| `event_key` | `string` | 이벤트 식별 키 |
| `event_type` | `string` | `NO_HELMET`, `DANGER_ZONE` 등 |
| `status` | `string` | `START`, `ACTIVE`, `END` |
| `level` | `string` | `WARNING`, `DANGER` 등 |
| `message` | `string` | 사용자 표시용 메시지 |
| `frame_id` | `integer` | 이벤트 기준 프레임 |
| `person_id` | `integer?` | 관련 사람 track id |
| `source_key` | `string` | 소스 식별 키 |
| `source_type` | `string` | `camera`, `video`, `stream` |
| `source_value` | `string` | 원본 소스 값 |
| `source_slug` | `string` | 파일명/표시용 안전 slug |
| `client_id` | `string` | 소유 클라이언트 식별자 |
| `session_id` | `string` | 세션 식별자 |
| `source_time_seconds` | `number` | 원본 기준 시각 |
| `source_time_text` | `string` | 원본 기준 시각 문자열 |
| `started_source_time_text` | `string` | 이벤트 시작 시각 |
| `ended_source_time_text` | `string` | 이벤트 종료 시각 |
| `duration_seconds` | `number` | 이벤트 지속 시간 |
| `clip_path` | `string` | 로컬 fallback 클립 경로 |
| `clip_url` | `string?` | 서버 클립 URL |
| `server_clip_name` | `string?` | 서버 클립 파일명 |
| `clip_available` | `boolean` | 재생 가능한 클립 존재 여부 |
| `thumbnail_url` | `string?` | 이벤트 로그 프리뷰 썸네일 URL |
| `thumbnail_name` | `string?` | 썸네일 파일명 |
| `related_detections` | `array<object>` | 판단 근거 탐지 목록 |
| `danger_zone_roi` | `object?` | 위험구역 이벤트 발생 당시 ROI 좌표 |

## danger_zone_roi

위험구역 이벤트에는 이벤트 발생 당시 적용된 ROI를 저장합니다.

```json
{
  "x1": 120,
  "y1": 80,
  "x2": 620,
  "y2": 500
}
```

이 값은 과거 이벤트 클립을 재생할 때 현재 룰 설정이 아니라 당시 ROI를 오버레이하기 위해 사용합니다.

## 클립/썸네일 정책

- 서버 클립이 있으면 `clip_url` 기준으로 재생합니다.
- 이벤트 로그 프리뷰 이미지는 `thumbnail_url`을 사용합니다.
- 서버는 수신 프리뷰 프레임 버퍼를 이용해 이벤트 종료 시 MP4 클립과 첫 프레임 기반 썸네일을 생성합니다.
- 로컬 경로만 있으면 fallback 재생이 가능하지만, 현재 뷰어 기본 경로는 서버 URL입니다.

## 소비 측 가이드

- 이벤트 상세/클립 재생은 `source_key + event_key` 기준으로 찾는 것이 안전합니다.
- 선택된 카메라가 있으면 해당 `source_key` 이벤트만 표시합니다.
- 선택된 카메라가 없으면 전체 이벤트를 표시합니다.
- 프레임 박스 표시는 이벤트 JSON이 아니라 프레임 탐지 스냅샷 API를 기준으로 합니다.
