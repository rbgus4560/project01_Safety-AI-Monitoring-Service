# SQLite DB 테이블 생성과 데이터 조회/저장 함수를 모아둔 파일입니다.
# 이벤트, 소스 상태, 프레임 탐지 결과가 이 계층을 통해 저장됩니다.

import json
import sqlite3
from contextlib import contextmanager
from datetime import datetime
from pathlib import Path
from typing import Iterator

from app.event_normalizer import normalize_event_record

from app.source_identity import extract_clip_name


def init_db(db_path: Path) -> None:
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
                display_name TEXT NOT NULL DEFAULT '',
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
        _ensure_source_display_name_column(connection)
    prune_legacy_camera_client_variants(db_path)
    from app.portfolio_auth import ensure_portfolio_tables
    ensure_portfolio_tables(db_path)


def _ensure_source_display_name_column(connection: sqlite3.Connection) -> None:
    columns = {
        str(row["name"])
        for row in connection.execute("PRAGMA table_info(sources)").fetchall()
    }
    if "display_name" not in columns:
        connection.execute("ALTER TABLE sources ADD COLUMN display_name TEXT NOT NULL DEFAULT ''")

@contextmanager
def _connect(db_path: Path) -> Iterator[sqlite3.Connection]:
    connection = sqlite3.connect(db_path, timeout=30, check_same_thread=False)
    connection.row_factory = sqlite3.Row
    try:
        yield connection
        connection.commit()
    finally:
        connection.close()


def insert_event(db_path: Path, event_record: dict) -> dict:
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


def merge_latest_event(db_path: Path, event_record: dict) -> dict | None:
    incoming_record = dict(event_record)
    incoming_record["received_at"] = str(
        incoming_record.get("received_at", "")
    ).strip() or datetime.now().isoformat()
    event_key = str(incoming_record.get("event_key", "")).strip()
    source_key = str(incoming_record.get("source_key", "")).strip()
    status = str(incoming_record.get("status", "")).strip()
    if not event_key or not source_key or not status:
        return None

    target_statuses = [status]
    if status.upper() == "END":
        target_statuses = ["START", "END"]
    placeholders = ", ".join("?" for _ in target_statuses)

    with _connect(db_path) as connection:
        row = connection.execute(
            f"""
            SELECT id, payload_json
            FROM events
            WHERE event_key = ? AND source_key = ? AND status IN ({placeholders})
            ORDER BY CASE status WHEN 'START' THEN 0 ELSE 1 END, id DESC
            LIMIT 1
            """,
            (event_key, source_key, *target_statuses),
        ).fetchone()
        if row is None:
            return None

        merged_record = _decode_payload(row["payload_json"])
        merged_record.update(incoming_record)
        merged_record = normalize_event_record(merged_record)
        payload_json = json.dumps(merged_record, ensure_ascii=False)
        connection.execute(
            """
            UPDATE events
            SET event_type = ?,
                status = ?,
                source_type = ?,
                source_value = ?,
                client_id = ?,
                session_id = ?,
                source_time_seconds = ?,
                received_at = ?,
                payload_json = ?
            WHERE id = ?
            """,
            (
                str(merged_record.get("event_type", "")).strip(),
                str(merged_record.get("status", "")).strip(),
                str(merged_record.get("source_type", "")).strip(),
                str(merged_record.get("source_value", "")).strip(),
                str(merged_record.get("client_id", "")).strip(),
                str(merged_record.get("session_id", "")).strip(),
                _to_float(merged_record.get("source_time_seconds")),
                str(merged_record.get("received_at", "")).strip(),
                payload_json,
                int(row["id"]),
            ),
        )
    return merged_record


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
        source_key = str(item.get("source_key", "")).strip()
        composite_key = f"{source_key}|{event_key}" if source_key else event_key
        if composite_key in latest_by_key:
            latest_by_key.pop(composite_key)
        latest_by_key[composite_key] = item
    return list(latest_by_key.values())


def find_events_by_key(
    db_path: Path,
    event_key: str,
    *,
    source_key: str | None = None,
) -> list[dict]:
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
    saved_record = dict(status_record)
    saved_record["updated_at"] = str(saved_record.get("updated_at", "")).strip() or (
        datetime.now().isoformat()
    )
    source_key = str(saved_record.get("source_key", "")).strip()
    with _connect(db_path) as connection:
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


def list_source_statuses(
    db_path: Path,
    *,
    client_id: str | None = None,
    session_id: str | None = None,
) -> list[dict]:
    query = "SELECT payload_json FROM source_status WHERE 1=1"
    parameters: list[object] = []
    if client_id is not None:
        query += " AND client_id = ?"
        parameters.append(client_id)
    if session_id is not None:
        query += " AND session_id = ?"
        parameters.append(session_id)
    query += " ORDER BY updated_at DESC, source_key DESC"
    with _connect(db_path) as connection:
        rows = connection.execute(query, parameters).fetchall()
    return [_decode_payload(row["payload_json"]) for row in rows]


def get_source_status(db_path: Path, source_key: str) -> dict | None:
    with _connect(db_path) as connection:
        row = connection.execute(
            "SELECT payload_json FROM source_status WHERE source_key = ?",
            (source_key,),
        ).fetchone()
    if row is None:
        return None
    return _decode_payload(row["payload_json"])


def delete_source_status(db_path: Path, source_key: str) -> bool:
    with _connect(db_path) as connection:
        deleted_count = connection.execute(
            "DELETE FROM source_status WHERE source_key = ?",
            (source_key,),
        ).rowcount
    return deleted_count > 0


def prune_orphan_source_statuses(db_path: Path) -> int:
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
    saved_record = dict(source_record)
    now_text = datetime.now().isoformat()
    saved_record["created_at"] = str(saved_record.get("created_at", "")).strip() or now_text
    saved_record["updated_at"] = str(saved_record.get("updated_at", "")).strip() or now_text
    source_key = str(saved_record.get("source_key", "")).strip()
    with _connect(db_path) as connection:
        connection.execute(
            """
            INSERT INTO sources (
                source_key, source_slug, display_name, source_type, source_value,
                original_source_type, original_source_value, client_id, session_id,
                desired_running, created_at, updated_at, payload_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(source_key) DO UPDATE SET
                source_slug=excluded.source_slug,
                display_name=excluded.display_name,
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
                str(saved_record.get("display_name", "")).strip(),
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


def list_sources(
    db_path: Path,
    *,
    client_id: str | None = None,
    session_id: str | None = None,
) -> list[dict]:
    query = "SELECT payload_json FROM sources WHERE 1=1"
    parameters: list[object] = []
    if client_id is not None:
        query += " AND client_id = ?"
        parameters.append(client_id)
    if session_id is not None:
        query += " AND session_id = ?"
        parameters.append(session_id)
    query += " ORDER BY updated_at DESC, source_key DESC"
    with _connect(db_path) as connection:
        rows = connection.execute(query, parameters).fetchall()
    return [_decode_payload(row["payload_json"]) for row in rows]


def list_source_overviews(
    db_path: Path,
    *,
    client_id: str | None = None,
    session_id: str | None = None,
) -> list[dict]:
    query = """
        SELECT
            s.source_key,
            s.payload_json AS source_payload_json,
            ss.payload_json AS status_payload_json,
            (
                SELECT MAX(received_at)
                FROM events e
                WHERE e.source_key = s.source_key
            ) AS last_event_received_at,
            (
                SELECT MAX(received_at)
                FROM frame_detections fd
                WHERE fd.source_key = s.source_key
            ) AS last_frame_received_at
        FROM sources s
        LEFT JOIN source_status ss
            ON ss.source_key = s.source_key
        WHERE 1=1
    """
    parameters: list[object] = []
    if client_id is not None:
        query += " AND s.client_id = ?"
        parameters.append(client_id)
    if session_id is not None:
        query += " AND s.session_id = ?"
        parameters.append(session_id)
    query += " ORDER BY COALESCE(ss.updated_at, s.updated_at) DESC, s.source_key DESC"

    with _connect(db_path) as connection:
        rows = connection.execute(query, parameters).fetchall()

    items: list[dict] = []
    for row in rows:
        source_payload = _decode_payload(row["source_payload_json"])
        status_payload = _decode_payload(row["status_payload_json"] or "{}")
        items.append(
            {
                "client_id": str(source_payload.get("client_id", "")).strip(),
                "session_id": str(source_payload.get("session_id", "")).strip(),
                "source_key": str(source_payload.get("source_key", "")).strip(),
                "source_slug": str(source_payload.get("source_slug", "")).strip(),
                "display_name": str(source_payload.get("display_name", "")).strip(),
                "source_type": str(source_payload.get("source_type", "")).strip(),
                "source_value": str(source_payload.get("source_value", "")).strip(),
                "source_duration_seconds": _to_float(
                    source_payload.get("source_duration_seconds")
                ),
                "media_url": str(source_payload.get("media_url", "")).strip(),
                "preview_url": str(source_payload.get("preview_url", "")).strip(),
                "desired_running": bool(source_payload.get("desired_running", False)),
                "state": str(status_payload.get("state", "")).strip() or "unknown",
                "is_running": bool(status_payload.get("is_running", False)),
                "source_fps": _to_float(status_payload.get("source_fps")),
                "last_frame_id": _to_int(
                    status_payload.get("last_frame_id"),
                    default=-1,
                ),
                "last_source_time_seconds": _to_float(
                    status_payload.get("last_source_time_seconds")
                ),
                "last_event_received_at": str(row["last_event_received_at"] or ""),
                "last_frame_received_at": str(row["last_frame_received_at"] or ""),
                "error_message": str(status_payload.get("error_message", "")).strip(),
                "updated_at": str(
                    status_payload.get("updated_at")
                    or source_payload.get("updated_at")
                    or ""
                ).strip(),
            }
        )
    return items


def get_source(db_path: Path, source_key: str) -> dict | None:
    with _connect(db_path) as connection:
        row = connection.execute(
            "SELECT payload_json FROM sources WHERE source_key = ?",
            (source_key,),
        ).fetchone()
    if row is None:
        return None
    return _decode_payload(row["payload_json"])


def delete_source(db_path: Path, source_key: str) -> bool:
    with _connect(db_path) as connection:
        deleted_count = connection.execute(
            "DELETE FROM sources WHERE source_key = ?",
            (source_key,),
        ).rowcount
    return deleted_count > 0


def prune_legacy_camera_client_variants(
    db_path: Path,
    *,
    keep_client_id: str = "",
) -> list[str]:
    sources = list_sources(db_path)
    camera_sources_by_owner: dict[str, list[dict]] = {}
    for source in sources:
        source_type = str(source.get("source_type", "")).strip().lower()
        source_value = str(source.get("source_value", "")).strip()
        client_id = str(source.get("client_id", "")).strip()
        if source_type != "camera" or source_value != "0" or not client_id:
            continue
        owner_key = _canonical_camera_client_id(client_id)
        camera_sources_by_owner.setdefault(owner_key, []).append(source)

    removed_source_keys: list[str] = []
    for variants in camera_sources_by_owner.values():
        if len(variants) <= 1:
            continue

        keep_source_key = _select_camera_variant_to_keep(
            variants,
            keep_client_id=keep_client_id,
        )
        for source in variants:
            source_key = str(source.get("source_key", "")).strip()
            if not source_key or source_key == keep_source_key:
                continue
            delete_source(db_path, source_key)
            delete_source_status(db_path, source_key)
            removed_source_keys.append(source_key)

    if removed_source_keys:
        prune_orphan_source_statuses(db_path)
        prune_orphan_source_data(db_path)
    return removed_source_keys


def _select_camera_variant_to_keep(
    variants: list[dict],
    *,
    keep_client_id: str,
) -> str:
    normalized_keep_client_id = keep_client_id.strip()
    if normalized_keep_client_id:
        for source in variants:
            if str(source.get("client_id", "")).strip() == normalized_keep_client_id:
                return str(source.get("source_key", "")).strip()

    unsuffixed = [
        source
        for source in variants
        if _canonical_camera_client_id(str(source.get("client_id", "")).strip())
        == str(source.get("client_id", "")).strip()
    ]
    candidates = unsuffixed or variants
    candidates.sort(
        key=lambda source: (
            str(source.get("updated_at", "")).strip(),
            str(source.get("source_key", "")).strip(),
        ),
        reverse=True,
    )
    return str(candidates[0].get("source_key", "")).strip()


def _canonical_camera_client_id(client_id: str) -> str:
    normalized = client_id.strip().lower()
    parts = normalized.rsplit("_", 1)
    if (
        len(parts) == 2
        and len(parts[1]) == 6
        and all(char in "0123456789abcdef" for char in parts[1])
    ):
        return parts[0]
    return normalized


def set_source_desired_running(
    db_path: Path,
    *,
    source_key: str,
    desired_running: bool,
) -> dict | None:
    record = get_source(db_path, source_key)
    if record is None:
        return None
    record["desired_running"] = desired_running
    record["updated_at"] = datetime.now().isoformat()
    return upsert_source(db_path, record)



def clear_all_event_data(db_path: Path) -> tuple[int, int, int, int]:
    with _connect(db_path) as connection:
        deleted_event_count = connection.execute("DELETE FROM events").rowcount
        deleted_frame_count = connection.execute("DELETE FROM frame_detections").rowcount
        connection.execute("DELETE FROM frame_detections_latest")
        deleted_status_count = connection.execute("DELETE FROM source_status").rowcount
        deleted_source_count = connection.execute("DELETE FROM sources").rowcount
    return deleted_event_count, deleted_frame_count, deleted_status_count, deleted_source_count
def reset_source_data(db_path: Path, *, source_key: str, source_slug: str, server_clip_dir: Path, server_thumbnail_dir: Path | None = None) -> tuple[bool, int, int]:
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

    if server_thumbnail_dir is not None:
        remaining_thumbnail_names = {
            thumbnail_name
            for thumbnail_name in (_extract_thumbnail_name(record) for record in kept_records)
            if thumbnail_name
        }
        removed_thumbnail_names = {
            thumbnail_name
            for thumbnail_name in (_extract_thumbnail_name(record) for record in removed_records)
            if thumbnail_name and thumbnail_name not in remaining_thumbnail_names
        }
        for thumbnail_name in removed_thumbnail_names:
            thumbnail_path = server_thumbnail_dir / thumbnail_name
            if thumbnail_path.exists() and thumbnail_path.is_file():
                thumbnail_path.unlink()
        if source_slug:
            for thumbnail_path in server_thumbnail_dir.glob(f"{source_slug}__*.jp*g"):
                if not thumbnail_path.is_file() or thumbnail_path.name in remaining_thumbnail_names:
                    continue
                thumbnail_path.unlink()

    return bool(removed_records), deleted_event_count, deleted_clip_count


def _extract_thumbnail_name(record: dict) -> str:
    thumbnail_name = str(record.get("thumbnail_name", "")).strip()
    if thumbnail_name:
        return thumbnail_name
    thumbnail_url = str(record.get("thumbnail_url", "")).strip()
    if not thumbnail_url:
        return ""
    return thumbnail_url.replace("\\", "/").rstrip("/").split("/")[-1]


def migrate_legacy_analysis_paths(
    db_path: Path,
    *,
    legacy_source_cache_dir: Path,
    server_source_cache_dir: Path,
) -> int:
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
    next_value = value.replace(legacy_raw, server_raw)
    next_value = next_value.replace(legacy_norm, server_norm)
    return next_value


def _decode_payload(payload_json: str) -> dict:
    try:
        decoded = json.loads(payload_json)
    except json.JSONDecodeError:
        return {}
    return decoded if isinstance(decoded, dict) else {}


def _to_float(value: object) -> float:
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


def acknowledge_latest_event(
    db_path: Path,
    *,
    event_key: str,
    source_key: str = "",
    acknowledged_by: str = "",
) -> dict | None:
    query = "SELECT id, payload_json FROM events WHERE event_key = ?"
    params: list[object] = [event_key.strip()]
    if source_key.strip():
        query += " AND source_key = ?"
        params.append(source_key.strip())
    query += " ORDER BY id DESC LIMIT 1"
    with _connect(db_path) as connection:
        row = connection.execute(query, params).fetchone()
        if row is None:
            return None
        payload = _decode_payload(row["payload_json"])
        payload["acknowledged"] = True
        payload["acknowledged_by"] = acknowledged_by.strip()
        payload["acknowledged_at"] = datetime.now().isoformat(timespec="seconds")
        connection.execute(
            "UPDATE events SET payload_json = ? WHERE id = ?",
            (json.dumps(payload, ensure_ascii=False), int(row["id"])),
        )
        return payload
