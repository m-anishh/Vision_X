"""
Local Dev Auth Fallback
Used automatically when SUPABASE_URL is not configured, so the app can be
run and tested end-to-end without a real Supabase project. Issues real
JWTs (signed with JWT_SECRET_KEY) and stores users in a local JSON file.

NOT for production use - swap in real Supabase credentials to use the
Supabase-backed auth path in backend/api/auth.py instead.
"""

from __future__ import annotations

import json
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Optional

import bcrypt
import jwt

from backend.core.config import settings
from backend.core.exceptions import AuthenticationError, ValidationError

USERS_FILE = Path(__file__).resolve().parent.parent / "data" / "dev_users.json"
USERS_FILE.parent.mkdir(parents=True, exist_ok=True)


def _hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


def _verify_password(password: str, password_hash: str) -> bool:
    return bcrypt.checkpw(password.encode("utf-8"), password_hash.encode("utf-8"))


def _load_users() -> dict:
    if not USERS_FILE.exists():
        return {}
    try:
        return json.loads(USERS_FILE.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return {}


def _save_users(users: dict) -> None:
    USERS_FILE.write_text(json.dumps(users, indent=2), encoding="utf-8")


def _issue_tokens(user_id: str, email: str) -> dict:
    now = datetime.now(timezone.utc)
    access_exp = now + timedelta(minutes=settings.JWT_ACCESS_TOKEN_EXPIRE_MINUTES)
    refresh_exp = now + timedelta(days=settings.JWT_REFRESH_TOKEN_EXPIRE_DAYS)

    access_token = jwt.encode(
        {"sub": user_id, "email": email, "type": "access", "exp": access_exp, "iss": settings.JWT_ISSUER},
        settings.JWT_SECRET_KEY,
        algorithm=settings.JWT_ALGORITHM,
    )
    refresh_token = jwt.encode(
        {"sub": user_id, "email": email, "type": "refresh", "exp": refresh_exp, "iss": settings.JWT_ISSUER},
        settings.JWT_SECRET_KEY,
        algorithm=settings.JWT_ALGORITHM,
    )
    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "expires_at": int(access_exp.timestamp()),
    }


def register_user(email: str, password: str, full_name: str) -> dict:
    users = _load_users()
    email_key = email.strip().lower()

    if email_key in users:
        raise ValidationError(message="An account with this email already exists")

    user_id = str(uuid.uuid4())
    users[email_key] = {
        "id": user_id,
        "email": email,
        "full_name": full_name,
        "password_hash": _hash_password(password),
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    _save_users(users)

    session = _issue_tokens(user_id, email)
    return {
        "user": {"id": user_id, "email": email, "full_name": full_name},
        "session": session,
    }


def login_user(email: str, password: str) -> dict:
    users = _load_users()
    record = users.get(email.strip().lower())

    if record is None or not _verify_password(password, record["password_hash"]):
        raise AuthenticationError(message="Invalid email or password")

    session = _issue_tokens(record["id"], record["email"])
    return {
        "user": {"id": record["id"], "email": record["email"], "full_name": record["full_name"]},
        "session": session,
    }


def update_profile(user_id: str, full_name: Optional[str] = None, avatar_url: Optional[str] = None) -> dict:
    users = _load_users()
    for record in users.values():
        if record["id"] == user_id:
            if full_name is not None:
                record["full_name"] = full_name
            if avatar_url is not None:
                record["avatar_url"] = avatar_url
            _save_users(users)
            return {
                "id": record["id"],
                "email": record["email"],
                "full_name": record["full_name"],
                "avatar_url": record.get("avatar_url"),
            }
    raise AuthenticationError(message="User not found")


def get_user_by_id(user_id: str) -> Optional[dict]:
    users = _load_users()
    for record in users.values():
        if record["id"] == user_id:
            return {
                "id": record["id"],
                "email": record["email"],
                "full_name": record["full_name"],
                "avatar_url": record.get("avatar_url"),
            }
    return None


def verify_token(token: str) -> dict:
    try:
        payload = jwt.decode(
            token,
            settings.JWT_SECRET_KEY,
            algorithms=[settings.JWT_ALGORITHM],
            issuer=settings.JWT_ISSUER,
        )
    except jwt.PyJWTError as exc:
        raise AuthenticationError(message="Invalid or expired token") from exc

    return {"sub": payload["sub"], "email": payload.get("email", "")}


def refresh_tokens(refresh_token: str) -> dict:
    payload = verify_token(refresh_token)
    return _issue_tokens(payload["sub"], payload["email"])
