"""The page-shaped reads: today, sleep, activity, workouts, recovery, logs, findings.

Each tool is the same payload its `/api/*` GET returns, through the same function. Where
the router is a thin shell over the read (it takes a plain `RequestUser`), the tool calls
the router's own handler, so the free/premium field gating (`gate_free_payload`) and the
reference-day validation are the router's, not a copy that could drift.

`recommendations` is the one AI-authored surface. The API refuses a non-premium owner with
a 402 and, for a premium one, passes straight through (the daily action has no included
cap), so a tool returns the router's own `locked` body for a free owner and never touches
the allowance ledger: a read-only tool must not spend anything.
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from typing import Any

from mcp.server.mcpserver import Context, MCPServer

from healthee.api.gate import DAILY_ACTION, locked_body
from healthee.api.routers import activity as activity_router
from healthee.api.routers import logs as logs_router
from healthee.api.routers import recommendations as recommendations_router
from healthee.api.routers import sleep as sleep_router
from healthee.api.routers import today as today_router
from healthee.api.routers import workouts as workouts_router
from healthee.core.db import tenant_transaction
from healthee.core.entitlement import is_premium
from healthee.core.supabase_auth import RequestUser
from healthee.mcp.tools_common import bounded, read_as_owner
from healthee.read.findings import top_findings
from healthee.read.fitness import workouts_list
from healthee.read.history import history_series
from healthee.read.recovery import recovery_score_payload
from healthee.read.recovery_signals import recovery_signals

_FINDINGS_LIMIT = 20
_RECOVERY_SERIES = ("recovery_score", "rhr_daily", "hrv_sleep_avg")


def _workouts(user: RequestUser, days: int) -> dict:
    cutoff = datetime.now(tz=UTC) - timedelta(days=days)
    with tenant_transaction(user.id) as cur:
        listed = workouts_list(cur, user.id, user.timezone)
    recent = [
        w for w in listed if w["start_iso"] and datetime.fromisoformat(w["start_iso"]) >= cutoff
    ]
    return {"days": days, "n": len(recent), "workouts": recent}


def _recovery(user: RequestUser, days: int) -> dict:
    with tenant_transaction(user.id) as cur:
        return {
            "recovery_score": recovery_score_payload(cur, user.id, user.timezone),
            "signals": recovery_signals(cur, user.id, user.timezone),
            "history": history_series(cur, user.id, user.timezone, _RECOVERY_SERIES, days),
        }


def _findings(user: RequestUser) -> dict:
    with tenant_transaction(user.id) as cur:
        found = top_findings(cur, user.id, user.timezone, limit=_FINDINGS_LIMIT)
    return {
        "findings": found,
        "note": "Personal correlations in this owner's own data (n days, effect size). "
        "Observational and single-subject: not research findings, not causal.",
    }


def _recommendations(user: RequestUser) -> dict:
    if not is_premium(user.id):
        return locked_body(DAILY_ACTION)
    return recommendations_router.get_history(user, days=30, offset=0).model_dump(mode="json")


def register(server: MCPServer) -> None:
    """Attach the page-shaped read tools to `server`."""

    @server.tool()
    async def today(ctx: Context, day: str | None = None) -> dict[str, Any]:
        """The `/api/today` snapshot: headline metrics, baselines, findings, as of `day`
        (YYYY-MM-DD, default the owner's today)."""
        return await read_as_owner(ctx, lambda user: today_router.get_today(user, day))

    @server.tool()
    async def sleep(ctx: Context, day: str | None = None) -> dict[str, Any]:
        """The `/api/sleep` page: the last 30 nights, naps, findings and cutoffs, as of `day`."""
        return await read_as_owner(ctx, lambda user: sleep_router.get_sleep(user, 30, day))

    @server.tool()
    async def sleep_health(ctx: Context, days: int = 30) -> dict[str, Any]:
        """Per-night four-check sleep health score with each check's raw measurement."""
        window = bounded(days)
        return await read_as_owner(
            ctx, lambda user: sleep_router.get_sleep_health_score(user, window)
        )

    @server.tool()
    async def activity(ctx: Context, day: str | None = None) -> dict[str, Any]:
        """The `/api/activity` page: VO2max, training load, MVPA, steps, workouts."""
        return await read_as_owner(ctx, lambda user: activity_router.get_activity(user, day))

    @server.tool()
    async def workouts(ctx: Context, days: int = 30) -> dict[str, Any]:
        """Device-recorded workouts (10 minutes or longer) in the last `days`, newest first.

        Each has `start_iso`; pass it to `workout` for the heart-rate profile and zones.
        """
        window = bounded(days)
        return await read_as_owner(ctx, lambda user: _workouts(user, window))

    @server.tool()
    async def workout(ctx: Context, id: str) -> dict[str, Any]:
        """One workout in detail, by the `start_iso` that `workouts` lists."""
        return await read_as_owner(ctx, lambda user: workouts_router.get_workout(user, id))

    register_logs_and_recovery(server)


def register_logs_and_recovery(server: MCPServer) -> None:
    """Attach recovery, logs, findings and recommendations to `server`."""

    @server.tool()
    async def recovery(ctx: Context, days: int = 30) -> dict[str, Any]:
        """Recovery: today's score and per-factor breakdown, the individual markers
        against the owner's own baseline, and the recent daily history."""
        window = bounded(days)
        return await read_as_owner(ctx, lambda user: _recovery(user, window))

    @server.tool()
    async def recent_logs(ctx: Context, days: int = 30) -> dict[str, Any]:
        """What the owner logged by hand (caffeine, alcohol, meditation, weight, fasting...)."""
        window = bounded(days)
        return await read_as_owner(ctx, lambda user: logs_router.get_log_recent(user, window))

    @server.tool()
    async def findings(ctx: Context) -> dict[str, Any]:
        """The owner's personal correlations, each with its n and effect size."""
        return await read_as_owner(ctx, _findings)

    @server.tool()
    async def recommendations(ctx: Context) -> dict[str, Any]:
        """The last 30 days of recommendations (premium owners; a free owner gets the
        `locked` marker the API returns)."""
        return await read_as_owner(ctx, _recommendations)
