from __future__ import annotations

import hashlib
import hmac
import secrets
import sqlite3
from datetime import datetime, timedelta
from pathlib import Path

PBKDF2_ITERATIONS = 180_000
TOKEN_TTL_HOURS = 24


def _now() -> str:
    return datetime.now().isoformat(timespec="seconds")


def _hash_password(password: str, *, salt_hex: str | None = None) -> tuple[str, str]:
    salt = bytes.fromhex(salt_hex) if salt_hex else secrets.token_bytes(16)
    digest = hashlib.pbkdf2_hmac(
        "sha256", password.encode("utf-8"), salt, PBKDF2_ITERATIONS
    )
    return salt.hex(), digest.hex()


def _connect(db_path: Path) -> sqlite3.Connection:
    connection = sqlite3.connect(db_path, timeout=30, check_same_thread=False)
    connection.row_factory = sqlite3.Row
    return connection


def ensure_portfolio_tables(db_path: Path) -> None:
    with _connect(db_path) as connection:
        connection.executescript(
            """
            CREATE TABLE IF NOT EXISTS users (
                username TEXT PRIMARY KEY,
                password_salt TEXT NOT NULL,
                password_hash TEXT NOT NULL,
                role TEXT NOT NULL,
                display_name TEXT NOT NULL,
                is_active INTEGER NOT NULL DEFAULT 1,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS user_sessions (
                token TEXT PRIMARY KEY,
                username TEXT NOT NULL,
                role TEXT NOT NULL,
                expires_at TEXT NOT NULL,
                created_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS client_registration_codes (
                code TEXT PRIMARY KEY,
                is_active INTEGER NOT NULL DEFAULT 1,
                used_by_client_id TEXT NOT NULL DEFAULT '',
                created_at TEXT NOT NULL,
                used_at TEXT NOT NULL DEFAULT ''
            );

            CREATE TABLE IF NOT EXISTS registered_clients (
                client_id TEXT PRIMARY KEY,
                client_name TEXT NOT NULL,
                auth_token TEXT NOT NULL,
                is_active INTEGER NOT NULL DEFAULT 1,
                last_ip TEXT NOT NULL DEFAULT '',
                last_seen_at TEXT NOT NULL DEFAULT '',
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS camera_groups (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                username TEXT NOT NULL,
                name TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_camera_groups_username
            ON camera_groups(username, id);

            CREATE TABLE IF NOT EXISTS group_cameras (
                group_id INTEGER NOT NULL,
                source_key TEXT NOT NULL,
                position INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (group_id, source_key)
            );

            CREATE TABLE IF NOT EXISTS viewer_layouts (
                username TEXT PRIMARY KEY,
                grid_count INTEGER NOT NULL DEFAULT 4,
                active_group_id INTEGER,
                source_order_json TEXT NOT NULL DEFAULT '[]',
                updated_at TEXT NOT NULL
            );
            """
        )
        connection.commit()

    _seed_user(db_path, "admin", "admin1234", "ADMIN", "관리자")
    _seed_user(db_path, "operator", "operator1234", "OPERATOR", "운영자")
    seed_registration_code(db_path, "SM-DEMO-2026")


def _seed_user(
    db_path: Path, username: str, password: str, role: str, display_name: str
) -> None:
    with _connect(db_path) as connection:
        existing = connection.execute(
            "SELECT username FROM users WHERE username = ?", (username,)
        ).fetchone()
        if existing is not None:
            return
        salt, digest = _hash_password(password)
        now = _now()
        connection.execute(
            """
            INSERT INTO users (
                username, password_salt, password_hash, role, display_name,
                is_active, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, 1, ?, ?)
            """,
            (username, salt, digest, role, display_name, now, now),
        )
        connection.commit()


def verify_login(db_path: Path, username: str, password: str) -> dict | None:
    with _connect(db_path) as connection:
        row = connection.execute(
            "SELECT * FROM users WHERE username = ?", (username.strip(),)
        ).fetchone()
        if row is None or int(row["is_active"] or 0) != 1:
            return None
        _, digest = _hash_password(password, salt_hex=str(row["password_salt"]))
        if not hmac.compare_digest(digest, str(row["password_hash"])):
            return None

        token = secrets.token_urlsafe(32)
        expires = datetime.now() + timedelta(hours=TOKEN_TTL_HOURS)
        connection.execute(
            "INSERT INTO user_sessions (token, username, role, expires_at, created_at) VALUES (?, ?, ?, ?, ?)",
            (token, row["username"], row["role"], expires.isoformat(), _now()),
        )
        connection.commit()
        return {
            "token": token,
            "username": str(row["username"]),
            "role": str(row["role"]),
            "display_name": str(row["display_name"]),
            "expires_at": expires.isoformat(),
        }


def resolve_session(db_path: Path, token: str) -> dict | None:
    normalized = token.strip()
    if not normalized:
        return None
    with _connect(db_path) as connection:
        row = connection.execute(
            "SELECT * FROM user_sessions WHERE token = ?", (normalized,)
        ).fetchone()
        if row is None:
            return None
        try:
            if datetime.fromisoformat(str(row["expires_at"])) < datetime.now():
                connection.execute("DELETE FROM user_sessions WHERE token = ?", (normalized,))
                connection.commit()
                return None
        except ValueError:
            return None
        user = connection.execute(
            "SELECT * FROM users WHERE username = ?", (row["username"],)
        ).fetchone()
        if user is None or int(user["is_active"] or 0) != 1:
            return None
        return {
            "username": str(user["username"]),
            "role": str(user["role"]),
            "display_name": str(user["display_name"]),
        }


def logout(db_path: Path, token: str) -> None:
    with _connect(db_path) as connection:
        connection.execute("DELETE FROM user_sessions WHERE token = ?", (token.strip(),))
        connection.commit()


def list_users(db_path: Path) -> list[dict]:
    with _connect(db_path) as connection:
        rows = connection.execute(
            "SELECT username, role, display_name, is_active, created_at, updated_at FROM users ORDER BY username"
        ).fetchall()
    return [
        {
            "username": str(row["username"]),
            "role": str(row["role"]),
            "display_name": str(row["display_name"]),
            "is_active": bool(row["is_active"]),
            "created_at": str(row["created_at"]),
            "updated_at": str(row["updated_at"]),
        }
        for row in rows
    ]


def create_user(
    db_path: Path,
    *,
    username: str,
    password: str,
    role: str,
    display_name: str,
) -> dict:
    normalized_username = username.strip()
    normalized_role = role.strip().upper()
    if not normalized_username or len(password) < 4:
        raise ValueError("username and password(4+ chars) are required")
    if normalized_role not in {"ADMIN", "OPERATOR"}:
        raise ValueError("role must be ADMIN or OPERATOR")
    salt, digest = _hash_password(password)
    now = _now()
    with _connect(db_path) as connection:
        connection.execute(
            """
            INSERT INTO users (
                username, password_salt, password_hash, role, display_name,
                is_active, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, 1, ?, ?)
            """,
            (
                normalized_username,
                salt,
                digest,
                normalized_role,
                display_name.strip() or normalized_username,
                now,
                now,
            ),
        )
        connection.commit()
    return {
        "username": normalized_username,
        "role": normalized_role,
        "display_name": display_name.strip() or normalized_username,
        "is_active": True,
    }


def set_user_active(db_path: Path, username: str, is_active: bool) -> bool:
    with _connect(db_path) as connection:
        cursor = connection.execute(
            "UPDATE users SET is_active = ?, updated_at = ? WHERE username = ?",
            (1 if is_active else 0, _now(), username.strip()),
        )
        if not is_active:
            connection.execute(
                "DELETE FROM user_sessions WHERE username = ?", (username.strip(),)
            )
        connection.commit()
        return cursor.rowcount > 0


def seed_registration_code(db_path: Path, code: str) -> None:
    normalized = code.strip().upper()
    if not normalized:
        return
    with _connect(db_path) as connection:
        connection.execute(
            "INSERT OR IGNORE INTO client_registration_codes (code, is_active, created_at) VALUES (?, 1, ?)",
            (normalized, _now()),
        )
        connection.commit()


def create_registration_code(db_path: Path) -> str:
    code = f"SM-{secrets.token_hex(3).upper()}"
    seed_registration_code(db_path, code)
    return code


def register_client(
    db_path: Path, *, code: str, client_name: str, last_ip: str = ""
) -> dict | None:
    normalized_code = code.strip().upper()
    with _connect(db_path) as connection:
        row = connection.execute(
            "SELECT * FROM client_registration_codes WHERE code = ? AND is_active = 1",
            (normalized_code,),
        ).fetchone()
        if row is None:
            return None
        client_id = f"EDGE-{secrets.token_hex(4).upper()}"
        auth_token = secrets.token_urlsafe(32)
        now = _now()
        connection.execute(
            """
            INSERT INTO registered_clients (
                client_id, client_name, auth_token, is_active, last_ip,
                last_seen_at, created_at, updated_at
            ) VALUES (?, ?, ?, 1, ?, ?, ?, ?)
            """,
            (
                client_id,
                client_name.strip() or client_id,
                auth_token,
                last_ip.strip(),
                now,
                now,
                now,
            ),
        )
        connection.execute(
            "UPDATE client_registration_codes SET is_active = 0, used_by_client_id = ?, used_at = ? WHERE code = ?",
            (client_id, now, normalized_code),
        )
        connection.commit()
    return {
        "client_id": client_id,
        "client_name": client_name.strip() or client_id,
        "auth_token": auth_token,
        "is_active": True,
    }


def list_registered_clients(db_path: Path) -> list[dict]:
    with _connect(db_path) as connection:
        rows = connection.execute(
            "SELECT client_id, client_name, is_active, last_ip, last_seen_at, created_at, updated_at FROM registered_clients ORDER BY created_at DESC"
        ).fetchall()
    return [
        {
            "client_id": str(row["client_id"]),
            "client_name": str(row["client_name"]),
            "is_active": bool(row["is_active"]),
            "last_ip": str(row["last_ip"]),
            "last_seen_at": str(row["last_seen_at"]),
            "created_at": str(row["created_at"]),
            "updated_at": str(row["updated_at"]),
        }
        for row in rows
    ]


def set_client_active(db_path: Path, client_id: str, is_active: bool) -> bool:
    with _connect(db_path) as connection:
        cursor = connection.execute(
            "UPDATE registered_clients SET is_active = ?, updated_at = ? WHERE client_id = ?",
            (1 if is_active else 0, _now(), client_id.strip()),
        )
        connection.commit()
        return cursor.rowcount > 0


def list_camera_groups(db_path: Path, username: str) -> list[dict]:
    normalized_user = username.strip()
    with _connect(db_path) as connection:
        groups = connection.execute(
            "SELECT id, name, created_at, updated_at FROM camera_groups WHERE username = ? ORDER BY id",
            (normalized_user,),
        ).fetchall()
        result: list[dict] = []
        for group in groups:
            cameras = connection.execute(
                "SELECT source_key FROM group_cameras WHERE group_id = ? ORDER BY position, source_key",
                (int(group["id"]),),
            ).fetchall()
            result.append({
                "id": int(group["id"]),
                "name": str(group["name"]),
                "source_keys": [str(row["source_key"]) for row in cameras],
                "created_at": str(group["created_at"]),
                "updated_at": str(group["updated_at"]),
            })
    return result


def save_camera_group(
    db_path: Path,
    *,
    username: str,
    name: str,
    source_keys: list[str],
    group_id: int | None = None,
) -> dict:
    normalized_user = username.strip()
    normalized_name = name.strip()
    if not normalized_name:
        raise ValueError("group name is required")
    ordered_keys: list[str] = []
    seen: set[str] = set()
    for source_key in source_keys:
        key = str(source_key).strip()
        if key and key not in seen:
            ordered_keys.append(key)
            seen.add(key)
    now = _now()
    with _connect(db_path) as connection:
        if group_id is None:
            cursor = connection.execute(
                "INSERT INTO camera_groups (username, name, created_at, updated_at) VALUES (?, ?, ?, ?)",
                (normalized_user, normalized_name, now, now),
            )
            saved_group_id = int(cursor.lastrowid)
        else:
            row = connection.execute(
                "SELECT id FROM camera_groups WHERE id = ? AND username = ?",
                (group_id, normalized_user),
            ).fetchone()
            if row is None:
                raise ValueError("camera group not found")
            saved_group_id = int(group_id)
            connection.execute(
                "UPDATE camera_groups SET name = ?, updated_at = ? WHERE id = ?",
                (normalized_name, now, saved_group_id),
            )
            connection.execute("DELETE FROM group_cameras WHERE group_id = ?", (saved_group_id,))
        for position, source_key in enumerate(ordered_keys):
            connection.execute(
                "INSERT INTO group_cameras (group_id, source_key, position) VALUES (?, ?, ?)",
                (saved_group_id, source_key, position),
            )
        connection.commit()
    return {"id": saved_group_id, "name": normalized_name, "source_keys": ordered_keys}


def delete_camera_group(db_path: Path, *, username: str, group_id: int) -> bool:
    with _connect(db_path) as connection:
        row = connection.execute(
            "SELECT id FROM camera_groups WHERE id = ? AND username = ?",
            (group_id, username.strip()),
        ).fetchone()
        if row is None:
            return False
        connection.execute("DELETE FROM group_cameras WHERE group_id = ?", (group_id,))
        connection.execute("DELETE FROM camera_groups WHERE id = ?", (group_id,))
        connection.execute(
            "UPDATE viewer_layouts SET active_group_id = NULL, updated_at = ? WHERE username = ? AND active_group_id = ?",
            (_now(), username.strip(), group_id),
        )
        connection.commit()
        return True


def get_viewer_layout(db_path: Path, username: str) -> dict:
    import json
    with _connect(db_path) as connection:
        row = connection.execute(
            "SELECT grid_count, active_group_id, source_order_json, updated_at FROM viewer_layouts WHERE username = ?",
            (username.strip(),),
        ).fetchone()
    if row is None:
        return {"grid_count": 4, "active_group_id": None, "source_order": [], "updated_at": ""}
    try:
        source_order = json.loads(str(row["source_order_json"] or "[]"))
    except Exception:
        source_order = []
    if not isinstance(source_order, list):
        source_order = []
    return {
        "grid_count": int(row["grid_count"] or 4),
        "active_group_id": int(row["active_group_id"]) if row["active_group_id"] is not None else None,
        "source_order": [str(item) for item in source_order if str(item).strip()],
        "updated_at": str(row["updated_at"]),
    }


def save_viewer_layout(
    db_path: Path,
    *,
    username: str,
    grid_count: int,
    active_group_id: int | None,
    source_order: list[str],
) -> dict:
    import json
    normalized_grid = grid_count if grid_count in {1, 4, 9} else 4
    ordered: list[str] = []
    seen: set[str] = set()
    for item in source_order:
        key = str(item).strip()
        if key and key not in seen:
            ordered.append(key)
            seen.add(key)
    if active_group_id is not None:
        with _connect(db_path) as connection:
            exists = connection.execute(
                "SELECT 1 FROM camera_groups WHERE id = ? AND username = ?",
                (active_group_id, username.strip()),
            ).fetchone()
        if exists is None:
            active_group_id = None
    now = _now()
    with _connect(db_path) as connection:
        connection.execute(
            """
            INSERT INTO viewer_layouts (username, grid_count, active_group_id, source_order_json, updated_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(username) DO UPDATE SET
                grid_count=excluded.grid_count,
                active_group_id=excluded.active_group_id,
                source_order_json=excluded.source_order_json,
                updated_at=excluded.updated_at
            """,
            (username.strip(), normalized_grid, active_group_id, json.dumps(ordered, ensure_ascii=False), now),
        )
        connection.commit()
    return {"grid_count": normalized_grid, "active_group_id": active_group_id, "source_order": ordered, "updated_at": now}


def touch_registered_client(db_path: Path, *, client_id: str, last_ip: str = "") -> None:
    normalized = client_id.strip()
    if not normalized:
        return
    with _connect(db_path) as connection:
        connection.execute(
            "UPDATE registered_clients SET last_seen_at = ?, last_ip = CASE WHEN ? = '' THEN last_ip ELSE ? END, updated_at = ? WHERE client_id = ?",
            (_now(), last_ip.strip(), last_ip.strip(), _now(), normalized),
        )
        connection.commit()


def validate_client_token(db_path: Path, *, client_id: str, auth_token: str) -> bool | None:
    """Return None for legacy/unregistered clients, True for valid registered clients, False for invalid/disabled ones."""
    normalized = client_id.strip()
    if not normalized:
        return None
    with _connect(db_path) as connection:
        row = connection.execute(
            "SELECT auth_token, is_active FROM registered_clients WHERE client_id = ?", (normalized,)
        ).fetchone()
    if row is None:
        return None
    return bool(row["is_active"]) and hmac.compare_digest(str(row["auth_token"]), auth_token.strip())
