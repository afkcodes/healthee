"""GET /api/coach/ledger — "Every yes, checked".

Thin (standards §2): authenticated owner -> one owner-scoped read -> shape the response.
It uses the ordinary ``CurrentUser``, NOT the AI gate: nothing here is generated. Every
number is read from the owner's own strap data and the verdict rule lives in
``healthee.challenges.day_verdicts``.

The models describe the wire and forbid extras, so a field added to the ledger cannot
silently vanish from the response. ``from``/``to`` are Python keywords, hence aliases.
"""

from __future__ import annotations

from datetime import date
from typing import Annotated, Literal

from fastapi import APIRouter, Query
from pydantic import BaseModel, ConfigDict, Field

from healthee.challenges import record
from healthee.core.db import tenant_transaction
from healthee.core.request_auth import CurrentUser

router = APIRouter(tags=["coach"])


class _Wire(BaseModel):
    model_config = ConfigDict(extra="forbid", populate_by_name=True)


class Measured(_Wire):
    """What the strap read that day. All null when nothing was measured."""

    value: float | None
    unit: str | None
    label: str | None


class LedgerEntry(_Wire):
    """One checked day of one yes."""

    date: date
    title: str
    verdict: Literal["done", "partial", "missed", "no_data", "uncheckable"]
    measured: Measured
    source: Literal["challenge", "recommendation"]
    ref_id: int


class LedgerWeek(_Wire):
    """One Mon-Sun week, whole even when the window starts inside it."""

    from_: date = Field(alias="from")
    to: date
    ideas_given: int
    yeses: int
    entries: list[LedgerEntry]


class Totals(_Wire):
    done: int
    partial: int
    missed: int
    no_data: int
    uncheckable: int


class DoneRate(_Wire):
    """``provable`` is done + partial + missed: the days the strap could judge."""

    done: int
    provable: int


class Ledger(_Wire):
    window: Literal["week", "month", "all"]
    from_: date = Field(alias="from")
    to: date
    ideas_given: int
    yeses: int
    totals: Totals
    done_rate: DoneRate
    weeks: list[LedgerWeek]
    pattern: str | None


@router.get("/api/coach/ledger", response_model=Ledger, response_model_by_alias=True)
def get_ledger(
    user: CurrentUser, window: Annotated[Literal["week", "month", "all"], Query()] = "week"
) -> Ledger:
    """Every yes in ``window``, each day checked against what the strap measured."""
    with tenant_transaction(user.id) as cur:
        payload = record.build_ledger(cur, user.id, user.timezone, window)
    return Ledger.model_validate(payload)
