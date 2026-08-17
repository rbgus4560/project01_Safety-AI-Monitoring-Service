# SQLite DB 테이블 생성과 데이터 조회/저장 함수를 모아둔 파일입니다.
# 이벤트, 소스 상태, 프레임 탐지 결과가 이 계층을 통해 저장됩니다.

import json
import sqlite3
from contextlib import contextmanager
from datetime import datetime
from pathlib import Path
from typing import Iterator

from app.source_identity import extract_clip_name


def init_db(db_path: Path) -> None:
    """데이터베이스 파일과 필요한 테이블을 생성합니다."""
    db_path.parent.mkdir(parents=True, exist_ok=True)
    with _connect(db_path) as connection:
        connection.executescript(
            """
            PRAGMA journal_mode=WAL;
            PRAGMA synchronous=NORMAL;

            CREATE TABLE IF NOT EXISTS events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                event_key TEXT NOT NULL,
                event_type TEXT NOT NULL,
                status TEXT NOT NULL,
                source_key TEXT NOT NULL,
                source_type TEXT NOT NULL,
                source_value TEXT NOT NULL,
                client_id TEXT NOT NULL,
                session_id TEXT NOT NULL,
                source_time_seconds REAL NOT NULL,
                received_at TEXT NOT NULL,
                payload_json TEXT NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_events_source_key
            ON events(source_key, id);

            CREATE INDEX IF NOT EXISTS idx_events_event_key
            ON events(event_key, id);

            CREATE TABLE IF NOT EXISTS frame_detections (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                source_key TEXT NOT NULL,
                source_time_seconds REAL NOT NULL,
                frame_id INTEGER NOT NULL,
                received_at TEXT NOT NULL,
                payload_json TEXT NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_frame_detections_source_time
            ON frame_detections(source_key, source_time_seconds, id);

            CREATE TABLE IF NOT EXISTS frame_detections_latest (
                source_key TEXT PRIMARY KEY,
                source_time_seconds REAL NOT NULL,
                frame_id INTEGER NOT NULL,
                received_at TEXT NOT NULL,
                payload_json TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS source_status (
                source_key TEXT PRIMARY KEY,
                source_type TEXT NOT NULL,
                source_value TEXT NOT NULL,
                client_id TEXT NOT NULL,
                session_id TEXT NOT NULL,
                state TEXT NOT NULL,
                is_running INTEGER NOT NULL,
                source_fps REAL NOT NULL,
                last_frame_id INTEGER NOT NULL,
                last_source_time_seconds REAL NOT NULL,
                error_message TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                payload_json TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS sources (
                source_key TEXT PRIMARY KEY,
                source_slug TEXT NOT NULL,
                source_type TEXT NOT NULL,
                source_value TEXT NOT NULL,
                original_source_type TEXT NOT NULL,
                original_source_value TEXT NOT NULL,
                client_id TEXT NOT NULL,
                session_id TEXT NOT NULL,
                desired_running INTEGER NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                payload_json TEXT NOT NULL
            );
            """
        )


@contextmanager
def _connect(db_path: Path) -> Iterator[sqlite3.Connection]:
    """SQLite 연결을 열고, 사용이 끝나면 자동으로 커밋 및 종료합니다."""
    connection = sqlite3.connect(db_path, timeout=30, check_same_thread=False)
    connection.row_factory = sqlite3.Row
    try:
        yield connection
        connection.commit()
    finally:
        connection.close()


def insert_event(db_path: Path, event_record: dict) -> dict:
    """이벤트 기록을 데이터베이스에 저장하고 저장된 내용을 반환합니다."""
    saved_record = dict(event_record)
    saved_record["received_at"] = str(saved_record.get("received_at", "")).strip() or (
        datetime.now().isoformat()
    )

    with _connect(db_path) as connection:
        connection.execute(
            """
            INSERT INTO events (
                event_key, event_type, status, source_key, source_type, source_value,
                client_id, session_id, source_time_seconds, received_at, payload_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                str(saved_record.get("event_key", "")).strip(),
                str(saved_record.get("event_type", "")).strip(),
                str(saved_record.get("status", "")).strip(),
                str(saved_record.get("source_key", "")).strip(),
                str(saved_record.get("source_type", "")).strip(),
                str(saved_record.get("source_value", "")).strip(),
                str(saved_record.get("client_id", "")).strip(),
                str(saved_record.get("session_id", "")).strip(),
                _to_float(saved_record.get("source_time_seconds")),
                saved_record["received_at"],
                json.dumps(saved_record, ensure_ascii=False),
            ),
        )
    return saved_record


def list_events(
    db_path: Path,
    *,
    event_type: str | None = None,
    status: str | None = None,
    source_key: str | None = None,
    source_type: str | None = None,
    client_id: str | None = None,
    session_id: str | None = None,
) -> list[dict]:
    """조건에 맞는 이벤트 기록 목록을 조회합니다."""
    query = """
        SELECT payload_json
        FROM events
        WHERE 1=1
    """
    parameters: list[object] = []
    query, parameters = _append_common_filters(
        query,
        parameters,
        event_type=event_type,
        status=status,
        source_key=source_key,
        source_type=source_type,
        client_id=client_id,
        session_id=session_id,
    )
    query += " ORDER BY id ASC"

    with _connect(db_path) as connection:
        rows = connection.execute(query, parameters).fetchall()
    return [_decode_payload(row["payload_json"]) for row in rows]


def list_latest_events(
    db_path: Path,
    *,
    event_type: str | None = None,
    status: str | None = None,
    source_key: str | None = None,
    source_type: str | None = None,
    client_id: str | None = None,
    session_id: str | None = None,
) -> list[dict]:
    """같은 이벤트 키를 최신 상태로 정리해 중복 없이 반환합니다."""
    ordered_items = list_events(
        db_path,
        event_type=event_type,
        status=status,
        source_key=source_key,
        source_type=source_type,
        client_id=client_id,
        session_id=session_id,
    )
    latest_by_key: dict[str, dict] = {}
    for item in ordered_items:
        event_key = str(item.get("event_key", "")).strip()
        if event_key in latest_by_key:
            latest_by_key.pop(event_key)
        latest_by_key[event_key] = item
    return list(latest_by_key.values())


def find_events_by_key(
    db_path: Path,
    event_key: str,
    *,
    source_key: str | None = None,
) -> list[dict]:
    """특정 이벤트 키를 가진 기록들을 시간 순으로 조회합니다."""
    query = "SELECT payload_json FROM events WHERE event_key = ?"
    parameters: list[object] = [event_key]
    if source_key is not None:
        query += " AND source_key = ?"
        parameters.append(source_key)
    query += " ORDER BY id ASC"
    with _connect(db_path) as connection:
        rows = connection.execute(query, parameters).fetchall()
    return [_decode_payload(row["payload_json"]) for row in rows]


def get_latest_event_by_key(
    db_path: Path,
    event_key: str,
    *,
    source_key: str | None = None,
) -> dict | None:
    """특정 이벤트 키의 가장 최신 기록 하나만 조회합니다."""
    query = "SELECT payload_json FROM events WHERE event_key = ?"
    parameters: list[object] = [event_key]
    if source_key is not None:
        query += " AND source_key = ?"
        parameters.append(source_key)
    query += " ORDER BY id DESC LIMIT 1"
    with _connect(db_path) as connection:
        row = connection.execute(query, parameters).fetchone()
    if row is None:
        return None
    return _decode_payload(row["payload_json"])


def list_source_summaries(
    db_path: Path,
    *,
    client_id: str | None = None,
    session_id: str | None = None,
) -> list[dict]:
    """각 소스별로 이벤트 개수와 최근 수신 시각 요약 정보를 조회합니다."""
    query = """
        SELECT
            source_key,
            MAX(source_type) AS source_type,
            MAX(source_value) AS source_value,
            COUNT(*) AS event_count,
            MAX(received_at) AS latest_received_at
        FROM events
        WHERE 1=1
    """
    parameters: list[object] = []
    if client_id is not None:
        query += " AND client_id = ?"
        parameters.append(client_id)
    if session_id is not None:
        query += " AND session_id = ?"
        parameters.append(session_id)
    query += """
        GROUP BY source_key
        ORDER BY latest_received_at DESC, source_key DESC
    """

    with _connect(db_path) as connection:
        rows = connection.execute(query, parameters).fetchall()
    return [
        {
            "source_key": str(row["source_key"]),
            "source_type": str(row["source_type"] or ""),
            "source_value": str(row["source_value"] or ""),
            "event_count": int(row["event_count"] or 0),
            "latest_received_at": str(row["latest_received_at"] or ""),
        }
        for row in rows
    ]


def insert_frame_detection(db_path: Path, frame_record: dict) -> dict:
    """프레임 탐지 결과를 저장하고 최신 상태 테이블도 함께 갱신합니다."""
    saved_record = dict(frame_record)
    saved_record["received_at"] = str(saved_record.get("received_at", "")).strip() or (
        datetime.now().isoformat()
    )
    with _connect(db_path) as connection:
        payload_json = json.dumps(saved_record, ensure_ascii=False)
        connection.execute(
            """
            INSERT INTO frame_detections (
                source_key, source_time_seconds, frame_id, received_at, payload_json
            ) VALUES (?, ?, ?, ?, ?)
            """,
            (
                str(saved_record.get("source_key", "")).strip(),
                _to_float(saved_record.get("source_time_seconds")),
                _to_int(saved_record.get("frame_id")),
                saved_record["received_at"],
                payload_json,
            ),
        )
        connection.execute(
            """
            INSERT INTO frame_detections_latest (
                source_key, source_time_seconds, frame_id, received_at, payload_json
            ) VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(source_key) DO UPDATE SET
                source_time_seconds=excluded.source_time_seconds,
                frame_id=excluded.frame_id,
                received_at=excluded.received_at,
                payload_json=excluded.payload_json
            """,
            (
                str(saved_record.get("source_key", "")).strip(),
                _to_float(saved_record.get("source_time_seconds")),
                _to_int(saved_record.get("frame_id")),
                saved_record["received_at"],
                payload_json,
            ),
        )
    return saved_record


def get_latest_frame_detection(db_path: Path, *, source_key: str) -> dict | None:
    """특정 소스의 가장 최근 프레임 탐지 결과를 조회합니다."""
    with _connect(db_path) as connection:
        row = connection.execute(
            """
            SELECT payload_json
            FROM frame_detections_latest
            WHERE source_key = ?
            """,
            (source_key,),
        ).fetchone()
    if row is None:
        return None
    return _decode_payload(row["payload_json"])


def find_current_frame_detection(
    db_path: Path,
    *,
    source_key: str,
    source_time_seconds: float,
    tolerance_seconds: float,
) -> dict | None:
    """주어진 시간에 가장 가까운 프레임 탐지 결과를 찾습니다."""
    with _connect(db_path) as connection:
        latest_row = connection.execute(
            """
            SELECT payload_json, source_time_seconds
            FROM frame_detections_latest
            WHERE source_key = ?
            """,
            (source_key,),
        ).fetchone()
        before_row = connection.execute(
            """
            SELECT payload_json, source_time_seconds
            FROM frame_detections
            WHERE source_key = ? AND source_time_seconds <= ?
            ORDER BY source_time_seconds DESC, id DESC
            LIMIT 1
            """,
            (source_key, source_time_seconds),
        ).fetchone()
        after_row = connection.execute(
            """
            SELECT payload_json, source_time_seconds
            FROM frame_detections
            WHERE source_key = ? AND source_time_seconds > ?
            ORDER BY source_time_seconds ASC, id ASC
            LIMIT 1
            """,
            (source_key, source_time_seconds),
        ).fetchone()

    if (
        latest_row is not None
        and abs(latest_row["source_time_seconds"] - source_time_seconds)
        <= tolerance_seconds
    ):
        return _decode_payload(latest_row["payload_json"])

    best_row: sqlite3.Row | None = None
    if before_row is not None and abs(before_row["source_time_seconds"] - source_time_seconds) <= tolerance_seconds:
        best_row = before_row
    if after_row is not None and abs(after_row["source_time_seconds"] - source_time_seconds) <= tolerance_seconds:
        if best_row is None or abs(after_row["source_time_seconds"] - source_time_seconds) < abs(best_row["source_time_seconds"] - source_time_seconds):
            best_row = after_row

    if best_row is None:
        return None
    return _decode_payload(best_row["payload_json"])


def upsert_source_status(db_path: Path, status_record: dict) -> dict:
    """소스 상태를 저장하거나 기존 상태를 갱신합니다."""
    saved_record = dict(status_record)
    saved_record["updated_at"] = str(saved_record.get("updated_at", "")).strip() or (
        datetime.now().isoformat()
    )
    source_key = str(saved_record.get("source_key", "")).strip()
    with _connect(db_path) as connection:
        state = str(saved_record.get("state", "")).strip().lower()
        should_preserve_average = state in {
            "completed",
            "stopped",
            "disconnected",
            "error",
        }
        if (
            should_preserve_average
            and _to_float(saved_record.get("avg_object_detection_ms")) <= 0.0
        ):
            previous_row = connection.execute(
                "SELECT payload_json FROM source_status WHERE source_key = ?",
                (source_key,),
            ).fetchone()
            if previous_row is not None:
                previous_record = _decode_payload(previous_row["payload_json"])
                previous_average_ms = _to_float(
                    previous_record.get("avg_object_detection_ms")
                )
                if previous_average_ms > 0.0:
                    saved_record["avg_object_detection_ms"] = previous_average_ms

        connection.execute(
            """
            INSERT INTO source_status (
                source_key, source_type, source_value, client_id, session_id, state,
                is_running, source_fps, last_frame_id, last_source_time_seconds,
                error_message, updated_at, payload_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(source_key) DO UPDATE SET
                source_type=excluded.source_type,
                source_value=excluded.source_value,
                client_id=excluded.client_id,
                session_id=excluded.session_id,
                state=excluded.state,
                is_running=excluded.is_running,
                source_fps=excluded.source_fps,
                last_frame_id=excluded.last_frame_id,
                last_source_time_seconds=excluded.last_source_time_seconds,
                error_message=excluded.error_message,
                updated_at=excluded.updated_at,
                payload_json=excluded.payload_json
            """,
            (
                source_key,
                str(saved_record.get("source_type", "")).strip(),
                str(saved_record.get("source_value", "")).strip(),
                str(saved_record.get("client_id", "")).strip(),
                str(saved_record.get("session_id", "")).strip(),
                str(saved_record.get("state", "")).strip(),
                1 if bool(saved_record.get("is_running", False)) else 0,
                _to_float(saved_record.get("source_fps")),
                _to_int(saved_record.get("last_frame_id"), default=-1),
                _to_float(saved_record.get("last_source_time_seconds")),
                str(saved_record.get("error_message", "")).strip(),
                saved_record["updated_at"],
                json.dumps(saved_record, ensure_ascii=False),
            ),
        )
    return saved_record


def list_source_statuses(db_path: Path) -> list[dict]:
    """모든 소스 상태 레코드를 최신 순으로 조회합니다."""
    with _connect(db_path) as connection:
        rows = connection.execute(
            "SELECT payload_json FROM source_status ORDER BY updated_at DESC, source_key DESC"
        ).fetchall()
    return [_decode_payload(row["payload_json"]) for row in rows]


def get_source_status(db_path: Path, source_key: str) -> dict | None:
    """특정 소스의 현재 상태를 조회합니다."""
    with _connect(db_path) as connection:
        row = connection.execute(
            "SELECT payload_json FROM source_status WHERE source_key = ?",
            (source_key,),
        ).fetchone()
    if row is None:
        return None
    return _decode_payload(row["payload_json"])


def delete_source_status(db_path: Path, source_key: str) -> bool:
    """특정 소스의 상태 기록을 삭제합니다."""
    with _connect(db_path) as connection:
        deleted_count = connection.execute(
            "DELETE FROM source_status WHERE source_key = ?",
            (source_key,),
        ).rowcount
    return deleted_count > 0


def prune_orphan_source_statuses(db_path: Path) -> int:
    """더 이상 존재하지 않는 소스의 상태 레코드를 정리합니다."""
    with _connect(db_path) as connection:
        deleted_count = connection.execute(
            """
            DELETE FROM source_status
            WHERE source_key NOT IN (
                SELECT source_key FROM sources
            )
            """
        ).rowcount
    return deleted_count


def prune_orphan_source_data(db_path: Path) -> tuple[int, int, int]:
    """소스가 사라진 이벤트와 프레임 기록을 정리합니다."""
    with _connect(db_path) as connection:
        deleted_events = connection.execute(
            """
            DELETE FROM events
            WHERE source_key NOT IN (
                SELECT source_key FROM sources
            )
            """
        ).rowcount
        deleted_frame_detections = connection.execute(
            """
            DELETE FROM frame_detections
            WHERE source_key NOT IN (
                SELECT source_key FROM sources
            )
            """
        ).rowcount
        deleted_latest_frame_detections = connection.execute(
            """
            DELETE FROM frame_detections_latest
            WHERE source_key NOT IN (
                SELECT source_key FROM sources
            )
            """
        ).rowcount
    return (
        deleted_events,
        deleted_frame_detections,
        deleted_latest_frame_detections,
    )


def upsert_source(db_path: Path, source_record: dict) -> dict:
    """소스 정보를 저장하거나 기존 정보를 갱신합니다."""
    saved_record = dict(source_record)
    now_text = datetime.now().isoformat()
    saved_record["created_at"] = str(saved_record.get("created_at", "")).strip() or now_text
    saved_record["updated_at"] = str(saved_record.get("updated_at", "")).strip() or now_text
    source_key = str(saved_record.get("source_key", "")).strip()
    with _connect(db_path) as connection:
        connection.execute(
            """
            INSERT INTO sources (
                source_key, source_slug, source_type, source_value,
                original_source_type, original_source_value, client_id, session_id,
                desired_running, created_at, updated_at, payload_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(source_key) DO UPDATE SET
                source_slug=excluded.source_slug,
                source_type=excluded.source_type,
                source_value=excluded.source_value,
                original_source_type=excluded.original_source_type,
                original_source_value=excluded.original_source_value,
                client_id=excluded.client_id,
                session_id=excluded.session_id,
                desired_running=excluded.desired_running,
                updated_at=excluded.updated_at,
                payload_json=excluded.payload_json
            """,
            (
                source_key,
                str(saved_record.get("source_slug", "")).strip(),
                str(saved_record.get("source_type", "")).strip(),
                str(saved_record.get("source_value", "")).strip(),
                str(saved_record.get("original_source_type", "")).strip(),
                str(saved_record.get("original_source_value", "")).strip(),
                str(saved_record.get("client_id", "")).strip(),
                str(saved_record.get("session_id", "")).strip(),
                1 if bool(saved_record.get("desired_running", False)) else 0,
                saved_record["created_at"],
                saved_record["updated_at"],
                json.dumps(saved_record, ensure_ascii=False),
            ),
        )
    return saved_record


def list_sources(db_path: Path) -> list[dict]:
    """등록된 모든 소스 정보를 조회합니다."""
    with _connect(db_path) as connection:
        rows = connection.execute(
            "SELECT payload_json FROM sources ORDER BY updated_at DESC, source_key DESC"
        ).fetchall()
    return [_decode_payload(row["payload_json"]) for row in rows]


def get_source(db_path: Path, source_key: str) -> dict | None:
    """특정 소스의 정보를 조회합니다."""
    with _connect(db_path) as connection:
        row = connection.execute(
            "SELECT payload_json FROM sources WHERE source_key = ?",
            (source_key,),
        ).fetchone()
    if row is None:
        return None
    return _decode_payload(row["payload_json"])


def delete_source(db_path: Path, source_key: str) -> bool:
    """특정 소스 정보를 삭제합니다."""
    with _connect(db_path) as connection:
        deleted_count = connection.execute(
            "DELETE FROM sources WHERE source_key = ?",
            (source_key,),
        ).rowcount
    return deleted_count > 0


def set_source_desired_running(
    db_path: Path,
    *,
    source_key: str,
    desired_running: bool,
) -> dict | None:
    """소스의 실행 희망 상태를 변경하고 저장합니다."""
    record = get_source(db_path, source_key)
    if record is None:
        return None
    record["desired_running"] = desired_running
    record["updated_at"] = datetime.now().isoformat()
    return upsert_source(db_path, record)


def reset_source_data(db_path: Path, *, source_key: str, source_slug: str, server_clip_dir: Path) -> tuple[bool, int, int]:
    """특정 소스의 데이터와 관련 클립을 모두 정리합니다."""
    removed_records = list_events(db_path, source_key=source_key)
    kept_records = list_events(db_path)
    kept_records = [
        item for item in kept_records if str(item.get("source_key", "")).strip() != source_key
    ]

    with _connect(db_path) as connection:
        deleted_event_count = connection.execute(
            "DELETE FROM events WHERE source_key = ?",
            (source_key,),
        ).rowcount
        connection.execute(
            "DELETE FROM frame_detections WHERE source_key = ?",
            (source_key,),
        )
        connection.execute(
            "DELETE FROM frame_detections_latest WHERE source_key = ?",
            (source_key,),
        )
        connection.execute(
            "DELETE FROM source_status WHERE source_key = ?",
            (source_key,),
        )

    remaining_clip_names = {
        clip_name
        for clip_name in (extract_clip_name(record) for record in kept_records)
        if clip_name
    }
    removed_clip_names = {
        clip_name
        for clip_name in (extract_clip_name(record) for record in removed_records)
        if clip_name and clip_name not in remaining_clip_names
    }

    deleted_clip_count = 0
    for clip_name in removed_clip_names:
        clip_path = server_clip_dir / clip_name
        if clip_path.exists() and clip_path.is_file():
            clip_path.unlink()
            deleted_clip_count += 1

    if source_slug:
        for clip_path in server_clip_dir.glob(f"{source_slug}__*.mp4"):
            if not clip_path.is_file() or clip_path.name in remaining_clip_names:
                continue
            clip_path.unlink()
            deleted_clip_count += 1

    return bool(removed_records), deleted_event_count, deleted_clip_count


def migrate_legacy_analysis_paths(
    db_path: Path,
    *,
    legacy_source_cache_dir: Path,
    server_source_cache_dir: Path,
) -> int:
    """이전 경로 문자열을 새 경로 문자열로 바꿔 데이터베이스 내용을 마이그레이션합니다."""
    legacy_raw = str(legacy_source_cache_dir.resolve())
    server_raw = str(server_source_cache_dir.resolve())
    legacy_norm = legacy_raw.replace("\\", "/").lower()
    server_norm = server_raw.replace("\\", "/").lower()
    updated_count = 0

    with _connect(db_path) as connection:
        updated_count += _migrate_sources_table(
            connection,
            legacy_raw=legacy_raw,
            server_raw=server_raw,
            legacy_norm=legacy_norm,
            server_norm=server_norm,
        )
        updated_count += _migrate_source_status_table(
            connection,
            legacy_raw=legacy_raw,
            server_raw=server_raw,
            legacy_norm=legacy_norm,
            server_norm=server_norm,
        )
        updated_count += _migrate_payload_only_table(
            connection,
            table_name="events",
            row_key_column="id",
            legacy_raw=legacy_raw,
            server_raw=server_raw,
            legacy_norm=legacy_norm,
            server_norm=server_norm,
        )
        updated_count += _migrate_payload_only_table(
            connection,
            table_name="frame_detections",
            row_key_column="id",
            legacy_raw=legacy_raw,
            server_raw=server_raw,
            legacy_norm=legacy_norm,
            server_norm=server_norm,
        )
        updated_count += _migrate_payload_only_table(
            connection,
            table_name="frame_detections_latest",
            row_key_column="source_key",
            legacy_raw=legacy_raw,
            server_raw=server_raw,
            legacy_norm=legacy_norm,
            server_norm=server_norm,
        )

    return updated_count


def _append_common_filters(
    query: str,
    parameters: list[object],
    *,
    event_type: str | None,
    status: str | None,
    source_key: str | None,
    source_type: str | None,
    client_id: str | None,
    session_id: str | None,
) -> tuple[str, list[object]]:
    """조회 쿼리에 공통 필터 조건을 추가합니다."""
    if event_type is not None:
        query += " AND event_type = ?"
        parameters.append(event_type)
    if status is not None:
        query += " AND status = ?"
        parameters.append(status)
    if source_key is not None:
        query += " AND source_key = ?"
        parameters.append(source_key)
    if source_type is not None:
        query += " AND source_type = ?"
        parameters.append(source_type)
    if client_id is not None:
        query += " AND client_id = ?"
        parameters.append(client_id)
    if session_id is not None:
        query += " AND session_id = ?"
        parameters.append(session_id)
    return query, parameters


def _migrate_sources_table(
    connection: sqlite3.Connection,
    *,
    legacy_raw: str,
    server_raw: str,
    legacy_norm: str,
    server_norm: str,
) -> int:
    """sources 테이블의 경로 관련 값을 새 경로로 바꿉니다."""
    rows = connection.execute(
        """
        SELECT source_key, source_value, original_source_value, payload_json
        FROM sources
        """
    ).fetchall()
    updated = 0
    for row in rows:
        source_key = str(row["source_key"] or "")
        source_value = str(row["source_value"] or "")
        original_source_value = str(row["original_source_value"] or "")
        payload = _decode_payload(row["payload_json"])

        next_source_key = _replace_legacy_text(
            source_key,
            legacy_raw=legacy_raw,
            server_raw=server_raw,
            legacy_norm=legacy_norm,
            server_norm=server_norm,
        )
        next_source_value = _replace_legacy_text(
            source_value,
            legacy_raw=legacy_raw,
            server_raw=server_raw,
            legacy_norm=legacy_norm,
            server_norm=server_norm,
        )
        next_original_source_value = _replace_legacy_text(
            original_source_value,
            legacy_raw=legacy_raw,
            server_raw=server_raw,
            legacy_norm=legacy_norm,
            server_norm=server_norm,
        )

        payload_changed = _rewrite_legacy_payload(
            payload,
            legacy_raw=legacy_raw,
            server_raw=server_raw,
            legacy_norm=legacy_norm,
            server_norm=server_norm,
        )
        if (
            next_source_key == source_key
            and next_source_value == source_value
            and next_original_source_value == original_source_value
            and not payload_changed
        ):
            continue

        payload["source_key"] = next_source_key
        payload["source_value"] = next_source_value
        if "original_source_value" in payload:
            payload["original_source_value"] = next_original_source_value

        connection.execute(
            """
            UPDATE sources
            SET source_key = ?, source_value = ?, original_source_value = ?, payload_json = ?
            WHERE source_key = ?
            """,
            (
                next_source_key,
                next_source_value,
                next_original_source_value,
                json.dumps(payload, ensure_ascii=False),
                source_key,
            ),
        )
        updated += 1
    return updated


def _migrate_source_status_table(
    connection: sqlite3.Connection,
    *,
    legacy_raw: str,
    server_raw: str,
    legacy_norm: str,
    server_norm: str,
) -> int:
    """source_status 테이블의 경로 관련 값을 새 경로로 바꿉니다."""
    rows = connection.execute(
        """
        SELECT source_key, source_value, payload_json
        FROM source_status
        """
    ).fetchall()
    updated = 0
    for row in rows:
        source_key = str(row["source_key"] or "")
        source_value = str(row["source_value"] or "")
        payload = _decode_payload(row["payload_json"])

        next_source_key = _replace_legacy_text(
            source_key,
            legacy_raw=legacy_raw,
            server_raw=server_raw,
            legacy_norm=legacy_norm,
            server_norm=server_norm,
        )
        next_source_value = _replace_legacy_text(
            source_value,
            legacy_raw=legacy_raw,
            server_raw=server_raw,
            legacy_norm=legacy_norm,
            server_norm=server_norm,
        )
        payload_changed = _rewrite_legacy_payload(
            payload,
            legacy_raw=legacy_raw,
            server_raw=server_raw,
            legacy_norm=legacy_norm,
            server_norm=server_norm,
        )
        if (
            next_source_key == source_key
            and next_source_value == source_value
            and not payload_changed
        ):
            continue

        payload["source_key"] = next_source_key
        payload["source_value"] = next_source_value
        connection.execute(
            """
            UPDATE source_status
            SET source_key = ?, source_value = ?, payload_json = ?
            WHERE source_key = ?
            """,
            (
                next_source_key,
                next_source_value,
                json.dumps(payload, ensure_ascii=False),
                source_key,
            ),
        )
        updated += 1
    return updated


def _migrate_payload_only_table(
    connection: sqlite3.Connection,
    *,
    table_name: str,
    row_key_column: str,
    legacy_raw: str,
    server_raw: str,
    legacy_norm: str,
    server_norm: str,
) -> int:
    """payload_json 안의 경로 문자열만 별도로 마이그레이션합니다."""
    rows = connection.execute(
        f"SELECT {row_key_column}, source_key, payload_json FROM {table_name}"
    ).fetchall()
    updated = 0
    for row in rows:
        record_key = row[row_key_column]
        source_key = str(row["source_key"] or "")
        payload = _decode_payload(row["payload_json"])
        next_source_key = _replace_legacy_text(
            source_key,
            legacy_raw=legacy_raw,
            server_raw=server_raw,
            legacy_norm=legacy_norm,
            server_norm=server_norm,
        )
        payload_changed = _rewrite_legacy_payload(
            payload,
            legacy_raw=legacy_raw,
            server_raw=server_raw,
            legacy_norm=legacy_norm,
            server_norm=server_norm,
        )
        if next_source_key == source_key and not payload_changed:
            continue
        payload["source_key"] = next_source_key
        connection.execute(
            f"UPDATE {table_name} SET source_key = ?, payload_json = ? WHERE {row_key_column} = ?",
            (
                next_source_key,
                json.dumps(payload, ensure_ascii=False),
                record_key,
            ),
        )
        updated += 1
    return updated


def _rewrite_legacy_payload(
    payload: dict,
    *,
    legacy_raw: str,
    server_raw: str,
    legacy_norm: str,
    server_norm: str,
) -> bool:
    """payload_json 내부의 레거시 경로 문자열을 새 경로로 치환합니다."""
    changed = False
    for key in ("source_key", "source_value", "original_source_value"):
        value = payload.get(key)
        if not isinstance(value, str):
            continue
        next_value = _replace_legacy_text(
            value,
            legacy_raw=legacy_raw,
            server_raw=server_raw,
            legacy_norm=legacy_norm,
            server_norm=server_norm,
        )
        if next_value == value:
            continue
        payload[key] = next_value
        changed = True
    return changed


def _replace_legacy_text(
    value: str,
    *,
    legacy_raw: str,
    server_raw: str,
    legacy_norm: str,
    server_norm: str,
) -> str:
    """문자열 안의 레거시 경로를 새 경로로 치환합니다."""
    next_value = value.replace(legacy_raw, server_raw)
    next_value = next_value.replace(legacy_norm, server_norm)
    return next_value


def _decode_payload(payload_json: str) -> dict:
    """저장된 JSON 문자열을 딕셔너리로 되돌립니다."""
    try:
        decoded = json.loads(payload_json)
    except json.JSONDecodeError:
        return {}
    return decoded if isinstance(decoded, dict) else {}


def _to_float(value: object) -> float:
    """값을 실수형으로 안전하게 변환합니다."""
    if isinstance(value, float):
        return value
    if isinstance(value, int):
        return float(value)
    if isinstance(value, str):
        try:
            return float(value)
        except ValueError:
            return 0.0
    return 0.0


def _to_int(value: object, *, default: int = 0) -> int:
    """값을 정수형으로 안전하게 변환합니다."""
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(value)
    if isinstance(value, str):
        try:
            return int(value)
        except ValueError:
            return default
    return default
