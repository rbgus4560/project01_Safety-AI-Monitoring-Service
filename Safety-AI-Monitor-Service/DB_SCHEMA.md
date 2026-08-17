# 서버 DB 스키마 문서

이 문서는 `safety_monitor_server`의 SQLite DB가 무엇을 저장하는지 설명합니다.

## 기본 정보

- DB 파일: `safety_monitor_server/data/monitor.db`
- 기준 코드: `safety_monitor_server/app/database.py`
- DB 엔진: SQLite

## 이 DB가 담당하는 일

서버 DB는 다음 데이터를 저장합니다.

- 등록된 카메라/소스 메타데이터
- 소스별 최신 실행 상태
- 프레임 탐지 결과 이력
- 소스별 최신 프레임 탐지 결과
- 서버가 판정한 이벤트
- 이벤트 클립/썸네일과 연결되는 부가 정보

중요한 점:

- 객체 탐지 자체는 클라이언트가 수행합니다.
- 서버는 클라이언트가 보낸 탐지 결과와 서버 DB의 소스별 룰 설정을 이용해 이벤트를 판정합니다.
- 이벤트 클립과 썸네일 파일은 DB 테이블이 아니라 서버 파일시스템에 저장되고, `events.payload_json`에 URL/파일명이 기록됩니다.

## 파일 저장 위치

| 경로 | 설명 |
| --- | --- |
| `safety_monitor_server/data/monitor.db` | SQLite DB |
| `safety_monitor_server/data/clips/` | 서버가 생성한 이벤트 MP4 클립 |
| `safety_monitor_server/data/event_thumbnails/` | 이벤트 로그 프리뷰 JPG 썸네일 |
| `safety_monitor_server/data/source_previews/` | 최신 프리뷰/스트림용 캐시 |

## 테이블 목록

- `sources`
- `source_status`
- `frame_detections`
- `frame_detections_latest`
- `events`

---

## 1. sources

서버가 알고 있는 소스 자체의 메타데이터를 저장합니다.

현재 운영 정책에서는 원격 클라이언트 1개가 로컬 `0`번 카메라 1개를 등록하는 흐름이 기본입니다.

### 주요 컬럼

| 컬럼명 | 설명 |
| --- | --- |
| `source_key` | 소스 식별자. 클라이언트 소유자 정보가 포함됨 |
| `source_slug` | 파일명/클립명 생성에 쓰는 안전한 이름 |
| `source_type` | `camera`, `video`, `stream` |
| `source_value` | 소스 원본 값. 현재 카메라는 보통 `0` |
| `original_source_type` | 처음 등록 당시 타입 |
| `original_source_value` | 처음 등록 당시 값 |
| `client_id` | 소유 클라이언트 식별자 |
| `session_id` | 소유 세션 식별자 |
| `desired_running` | 재연결 후 자동 재개 여부 |
| `created_at` | 등록 시각 |
| `updated_at` | 마지막 갱신 시각 |
| `payload_json` | 소스 전체 정보 JSON |

### payload_json 안의 대표 정보

- `rule_config`
- `source_duration_seconds`
- `preview_url`
- `media_url`
- `server_media_path`

### rule_config

```json
{
  "use_no_helmet_rule": true,
  "use_danger_zone_rule": false,
  "danger_zone_roi": {
    "x1": 100,
    "y1": 120,
    "x2": 640,
    "y2": 480
  }
}
```

- `use_danger_zone_rule`은 위험구역 이벤트 판정 ON/OFF입니다.
- `danger_zone_roi`는 ROI 좌표 저장값입니다.
- ROI 저장만으로 `use_danger_zone_rule`이 자동 ON 되지는 않습니다.

---

## 2. source_status

소스별 최신 실행 상태 1건을 저장합니다.

예:

- `registered`
- `starting`
- `model_loading`
- `running`
- `stopped`
- `disconnected`
- `error`

### 주요 컬럼

| 컬럼명 | 설명 |
| --- | --- |
| `source_key` | 소스 식별자 |
| `source_type` | 소스 종류 |
| `source_value` | 소스 값 |
| `client_id` | 소유 클라이언트 식별자 |
| `session_id` | 세션 식별자 |
| `state` | 현재 상태 |
| `is_running` | 실행 여부 |
| `source_fps` | 소스 FPS |
| `last_frame_id` | 마지막 처리 프레임 |
| `last_source_time_seconds` | 마지막 처리 시각 |
| `error_message` | 오류 메시지 |
| `updated_at` | 마지막 heartbeat 시각 |
| `payload_json` | 상태 전체 JSON |

### 비고

- 뷰어의 연결 상태 점, 시작 지연 오버레이, 오프라인 판정에 사용됩니다.

---

## 3. frame_detections

클라이언트가 보낸 프레임 단위 탐지 결과 이력을 저장합니다.

### 주요 컬럼

| 컬럼명 | 설명 |
| --- | --- |
| `id` | 자동 증가 PK |
| `source_key` | 소스 식별자 |
| `source_time_seconds` | 원본 영상 기준 시각 |
| `frame_id` | 프레임 번호 |
| `received_at` | 서버 수신 시각 |
| `payload_json` | 탐지 결과 전체 JSON |

### 비고

- 서버 이벤트 판정의 입력 데이터입니다.
- 뷰어의 객체 탐지 박스/ROI 기준 프레임 크기 계산에도 사용됩니다.

---

## 4. frame_detections_latest

소스별 최신 탐지 결과 1건만 저장하는 캐시 테이블입니다.

### 주요 컬럼

| 컬럼명 | 설명 |
| --- | --- |
| `source_key` | 소스 식별자 |
| `source_time_seconds` | 최신 탐지 시각 |
| `frame_id` | 최신 프레임 번호 |
| `received_at` | 서버 저장 시각 |
| `payload_json` | 최신 탐지 JSON |

### 비고

- 실시간 모니터링에서 최신 박스를 빠르게 조회할 때 사용합니다.

---

## 5. events

서버가 최종 판정한 이벤트 기록을 저장합니다.

예:

- `NO_HELMET`
- `DANGER_ZONE`
- 이벤트 `START` / `END` 상태
- 같은 `source_key + event_key`의 이벤트는 START로 생성된 행을 END로 갱신해 하나의 이벤트 수명주기로 관리합니다.

### 주요 컬럼

| 컬럼명 | 설명 |
| --- | --- |
| `id` | 자동 증가 PK |
| `event_key` | 같은 이벤트 흐름을 묶는 키 |
| `event_type` | 이벤트 종류 |
| `status` | `START`, `ACTIVE`, `END` |
| `source_key` | 이벤트가 발생한 소스 |
| `source_type` | 소스 종류 |
| `source_value` | 소스 값 |
| `client_id` | 소유 클라이언트 식별자 |
| `session_id` | 세션 식별자 |
| `source_time_seconds` | 이벤트 시점 |
| `received_at` | 서버 저장 시각 |
| `payload_json` | 이벤트 전체 JSON |

### payload_json 안의 대표 정보

- `message`
- `level`
- `started_source_time_text`
- `ended_source_time_text`
- `clip_url`
- `server_clip_name`
- `clip_available`
- `thumbnail_url`
- `thumbnail_name`
- `related_detections`
- `danger_zone_roi`

### danger_zone_roi

위험구역 이벤트의 경우 이벤트 발생 당시 적용된 ROI 좌표를 함께 저장합니다. 이 값은 나중에 룰 설정이 바뀌어도 과거 이벤트 클립 재생 시 당시 ROI 사각형을 오버레이하기 위한 값입니다.

---

## 관리/초기화

뷰어의 테스트용 `DB Clear` 버튼은 서버의 `/api/admin/clear-events`를 호출합니다.

초기화 대상:

- `events`
- `frame_detections`
- `frame_detections_latest`
- `data/clips/*.mp4`
- `data/event_thumbnails/*.jpg`
- 서버 메모리상의 진행 중 이벤트 상태

`sources`와 `source_status`는 카메라 등록/연결 상태 유지를 위해 전체 DB Clear 대상에서 제외됩니다.

## 테이블 관계

핵심 연결 키는 `source_key`입니다.

- `sources`: 소스 메타데이터 기준 테이블
- `source_status`: 소스별 최신 상태
- `frame_detections`: 소스의 탐지 이력
- `frame_detections_latest`: 소스의 최신 탐지 캐시
- `events`: 소스에서 발생한 이벤트 이력

## 요약

현재 서버 DB는 “클라이언트가 보낸 분석 결과를 중앙 저장하고, 서버가 룰을 적용해 이벤트/클립/썸네일을 만드는 구조”를 기준으로 설계되어 있습니다.
