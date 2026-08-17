from __future__ import annotations

from fastapi import HTTPException, Request

from app.config import DATABASE_PATH
from app.portfolio_auth import touch_registered_client, validate_client_token


def verify_client_request(request: Request, client_id: str) -> None:
    """Validate registered EDGE clients while keeping legacy team-project clients compatible."""
    normalized = client_id.strip()
    token = request.headers.get("x-client-token", "").strip()
    result = validate_client_token(DATABASE_PATH, client_id=normalized, auth_token=token)
    if result is False:
        raise HTTPException(status_code=403, detail="client authentication failed")
    if result is True:
        touch_registered_client(
            DATABASE_PATH,
            client_id=normalized,
            last_ip=request.client.host if request.client else "",
        )
