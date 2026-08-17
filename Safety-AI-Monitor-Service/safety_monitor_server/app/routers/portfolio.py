from __future__ import annotations

from fastapi import APIRouter, Header, HTTPException, Request
from pydantic import BaseModel

from app.config import DATABASE_PATH
from app.database import acknowledge_latest_event
from app.portfolio_auth import (
    create_registration_code,
    create_user,
    delete_camera_group,
    get_viewer_layout,
    list_camera_groups,
    list_registered_clients,
    list_users,
    logout,
    register_client,
    resolve_session,
    save_camera_group,
    save_viewer_layout,
    set_client_active,
    set_user_active,
    verify_login,
)

router = APIRouter(prefix="/api/portfolio", tags=["portfolio"])


class LoginRequest(BaseModel):
    username: str
    password: str


class UserCreateRequest(BaseModel):
    username: str
    password: str
    role: str = "OPERATOR"
    display_name: str = ""


class ActiveUpdateRequest(BaseModel):
    is_active: bool


class ClientRegisterRequest(BaseModel):
    client_name: str
    registration_code: str


class CameraGroupRequest(BaseModel):
    name: str
    source_keys: list[str] = []


class ViewerLayoutRequest(BaseModel):
    grid_count: int = 4
    active_group_id: int | None = None
    source_order: list[str] = []


def _extract_bearer(authorization: str | None) -> str:
    value = (authorization or "").strip()
    if value.lower().startswith("bearer "):
        return value[7:].strip()
    return ""


def _require_session(authorization: str | None) -> dict:
    session = resolve_session(DATABASE_PATH, _extract_bearer(authorization))
    if session is None:
        raise HTTPException(status_code=401, detail="login required")
    return session


def _require_admin(authorization: str | None) -> dict:
    session = _require_session(authorization)
    if session.get("role") != "ADMIN":
        raise HTTPException(status_code=403, detail="admin role required")
    return session


@router.post("/auth/login")
def login(payload: LoginRequest):
    result = verify_login(DATABASE_PATH, payload.username, payload.password)
    if result is None:
        raise HTTPException(status_code=401, detail="invalid username or password")
    return {"ok": True, **result}


@router.get("/auth/me")
def me(authorization: str | None = Header(default=None)):
    return {"ok": True, "user": _require_session(authorization)}


@router.post("/auth/logout")
def logout_route(authorization: str | None = Header(default=None)):
    token = _extract_bearer(authorization)
    if token:
        logout(DATABASE_PATH, token)
    return {"ok": True}


@router.get("/users")
def users(authorization: str | None = Header(default=None)):
    _require_admin(authorization)
    return {"ok": True, "items": list_users(DATABASE_PATH)}


@router.post("/users")
def add_user(
    payload: UserCreateRequest,
    authorization: str | None = Header(default=None),
):
    _require_admin(authorization)
    try:
        item = create_user(
            DATABASE_PATH,
            username=payload.username,
            password=payload.password,
            role=payload.role,
            display_name=payload.display_name,
        )
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error
    except Exception as error:
        raise HTTPException(status_code=409, detail="username already exists") from error
    return {"ok": True, "item": item}


@router.patch("/users/{username}/active")
def update_user_active(
    username: str,
    payload: ActiveUpdateRequest,
    authorization: str | None = Header(default=None),
):
    session = _require_admin(authorization)
    if username == session.get("username") and not payload.is_active:
        raise HTTPException(status_code=400, detail="cannot disable current admin")
    if not set_user_active(DATABASE_PATH, username, payload.is_active):
        raise HTTPException(status_code=404, detail="user not found")
    return {"ok": True}


@router.post("/clients/registration-code")
def new_registration_code(authorization: str | None = Header(default=None)):
    _require_admin(authorization)
    return {"ok": True, "registration_code": create_registration_code(DATABASE_PATH)}


@router.post("/clients/register")
def client_register(payload: ClientRegisterRequest, request: Request):
    item = register_client(
        DATABASE_PATH,
        code=payload.registration_code,
        client_name=payload.client_name,
        last_ip=request.client.host if request.client else "",
    )
    if item is None:
        raise HTTPException(status_code=400, detail="invalid or already used registration code")
    return {"ok": True, "item": item}


@router.get("/clients")
def clients(authorization: str | None = Header(default=None)):
    _require_admin(authorization)
    return {"ok": True, "items": list_registered_clients(DATABASE_PATH)}


@router.patch("/clients/{client_id}/active")
def update_client_active(
    client_id: str,
    payload: ActiveUpdateRequest,
    authorization: str | None = Header(default=None),
):
    _require_admin(authorization)
    if not set_client_active(DATABASE_PATH, client_id, payload.is_active):
        raise HTTPException(status_code=404, detail="client not found")
    return {"ok": True}


@router.post("/events/{event_key}/ack")
def acknowledge_event(
    event_key: str,
    source_key: str = "",
    authorization: str | None = Header(default=None),
):
    session = _require_session(authorization)
    item = acknowledge_latest_event(
        DATABASE_PATH,
        event_key=event_key,
        source_key=source_key,
        acknowledged_by=str(session.get("username", "")),
    )
    if item is None:
        raise HTTPException(status_code=404, detail="event not found")
    return {"ok": True, "item": item}


@router.get("/camera-groups")
def camera_groups(authorization: str | None = Header(default=None)):
    session = _require_session(authorization)
    return {"ok": True, "items": list_camera_groups(DATABASE_PATH, str(session["username"]))}


@router.post("/camera-groups")
def add_camera_group(
    payload: CameraGroupRequest,
    authorization: str | None = Header(default=None),
):
    session = _require_session(authorization)
    try:
        item = save_camera_group(
            DATABASE_PATH, username=str(session["username"]), name=payload.name, source_keys=payload.source_keys
        )
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error
    return {"ok": True, "item": item}


@router.put("/camera-groups/{group_id}")
def edit_camera_group(
    group_id: int,
    payload: CameraGroupRequest,
    authorization: str | None = Header(default=None),
):
    session = _require_session(authorization)
    try:
        item = save_camera_group(
            DATABASE_PATH, username=str(session["username"]), name=payload.name,
            source_keys=payload.source_keys, group_id=group_id
        )
    except ValueError as error:
        raise HTTPException(status_code=404, detail=str(error)) from error
    return {"ok": True, "item": item}


@router.delete("/camera-groups/{group_id}")
def remove_camera_group(
    group_id: int, authorization: str | None = Header(default=None)
):
    session = _require_session(authorization)
    if not delete_camera_group(DATABASE_PATH, username=str(session["username"]), group_id=group_id):
        raise HTTPException(status_code=404, detail="camera group not found")
    return {"ok": True}


@router.get("/layout")
def viewer_layout(authorization: str | None = Header(default=None)):
    session = _require_session(authorization)
    return {"ok": True, "item": get_viewer_layout(DATABASE_PATH, str(session["username"]))}


@router.put("/layout")
def update_viewer_layout(
    payload: ViewerLayoutRequest, authorization: str | None = Header(default=None)
):
    session = _require_session(authorization)
    item = save_viewer_layout(
        DATABASE_PATH, username=str(session["username"]), grid_count=payload.grid_count,
        active_group_id=payload.active_group_id, source_order=payload.source_order
    )
    return {"ok": True, "item": item}
