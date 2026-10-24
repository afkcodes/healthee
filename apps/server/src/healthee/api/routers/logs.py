"""Manual logging — POST /api/log, GET /api/log/recent, DELETE /api/log/{id} (free tier).

Thin: the POST body is a pydantic ``LogRequest``; each handler opens one
transaction and call the read service (writes go to ``manual_entry`` / ``weight_log``).
"""

from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, HTTPException

from healthee.core.db import tenant_transaction
from healthee.core.request_auth import CurrentUser
from healthee.read.logs import LogRequest, delete_entry, log_recent, record_log

router = APIRouter(tags=["logs"])


@router.post("/api/log")
def post_log(user: CurrentUser, req: LogRequest) -> dict:
    """Record a manual log (caffeine/alcohol/meditation/exercise/weight/fasting…)."""
    with tenant_transaction(user.id) as cur:
        return record_log(cur, user.id, req)


@router.get("/api/log/recent")
def get_log_recent(user: CurrentUser, days: int = 7) -> dict:
    """Recent manual logs + current fasting status."""
    with tenant_transaction(user.id) as cur:
        return log_recent(cur, user.id, days)


@router.delete("/api/log/{entry_id}")
def delete_log(user: CurrentUser, entry_id: UUID) -> dict:
    """Undo one manual log entry. 404 when it does not exist or is not the caller's."""
    with tenant_transaction(user.id) as cur:
        deleted = delete_entry(cur, user.id, entry_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="no such log entry")
    return {"ok": True}
