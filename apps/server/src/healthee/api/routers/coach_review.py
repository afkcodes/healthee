"""POST /api/coach/review — this week's coach review, written once when first opened.

Thin (standards §2): gate -> ``generate_week`` -> shape. ``CoachUser`` is the same premium
gate as ``/api/coach`` and charges one coach question up front. The FIRST call in an ISO
week generates and stores the review; every later call returns the stored one and refunds
the charge, because an answer read from storage cost nothing and a slot is never billed
for work we did not do. A call that delivered nothing (no readings to write from, or the
write failed) refunds too. The Sunday job writes through the same ``generate_week``, so the
Coach screen and the ledger's ``pattern`` read one stored review.
"""

from __future__ import annotations

from datetime import date, datetime

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, ConfigDict

from healthee.api import gate
from healthee.api.gate import CoachUser
from healthee.core.tenancy import user_today
from healthee.jobs import coach_review_view as shape
from healthee.jobs.coach_weekly import ReviewBusyError, generate_week

router = APIRouter(tags=["coach"])


class _Wire(BaseModel):
    model_config = ConfigDict(extra="forbid")


class ReviewJob(_Wire):
    """The week's job, with the id the existing adopt endpoint takes."""

    action: str
    metric: str
    target: float
    unit: str
    days_required: int
    slot: str
    floor: str
    counts_when: str
    challenge_id: int


class CoachReview(_Wire):
    week: str
    week_from: date
    week_to: date
    review: str | None
    pattern: str | None
    job: ReviewJob | None
    today_line: str | None
    rationale: str | None
    evidence_grade: int | None
    research_note_ids: list[str]
    generated_at: datetime
    cached: bool


@router.post("/api/coach/review", response_model=CoachReview)
def post_review(request: Request, user: CoachUser) -> dict:
    """The review for this week: generated on the first call, stored, then served for free."""
    today = user_today(user.timezone)
    try:
        stored, cached = generate_week(user.id, user.timezone, today)
    except ReviewBusyError as exc:
        gate.refund_ai_use(request, user)
        raise HTTPException(status_code=503, detail=str(exc), headers={"Retry-After": "5"}) from exc
    except Exception:
        # Re-raised unchanged for the error handler; only the refund must happen first.
        gate.refund_ai_use(request, user)
        raise
    if stored is None:
        gate.refund_ai_use(request, user)
        return shape.no_data_view(user.id, today)
    if cached:
        gate.refund_ai_use(request, user)
    return shape.view(stored, user.id, today, cached=cached)
