"""Metric tools: the catalogue, a daily series, a statistic, an event comparison.

All reads reuse existing functions — `read.history.history_series` (THE definition of a
dated series), `coach_tools.query_metric` and `coach_tools.compare_event` (already shaped
for a model) — so a number here cannot differ from the one the app draws.
"""

from __future__ import annotations

from typing import Any, Literal

from mcp.server.mcpserver import Context, MCPServer

from healthee.core.db import tenant_transaction
from healthee.core.supabase_auth import RequestUser
from healthee.insights import coach_tools
from healthee.mcp.catalogue import BY_KEY, catalogue_payload
from healthee.mcp.tools_common import bounded, read_as_owner, require_metric
from healthee.read.history import bounded_days, history, history_series

Stat = Literal["avg", "series", "latest", "min", "max", "sum", "trend"]

# `weight_kg` lives in `weight_log`, not `derived_daily`; `query_metric` reads only the
# latter and would answer "no data" for a metric the owner does have. Refuse instead.
_NO_STATS = frozenset({"weight_kg"})


def series_payload(user: RequestUser, metric: str, days: int) -> dict[str, Any]:
    """`{metric, unit, days, n, coverage, series: {iso date: value}}` for one owner."""
    asked = bounded_days(days)
    with tenant_transaction(user.id) as cur:
        points = history_series(cur, user.id, user.timezone, (metric,), asked)[metric]
    entry = BY_KEY[metric]
    return {
        "metric": metric,
        "unit": entry.unit,
        "days": asked,
        "n": len(points),
        "coverage": round(len(points) / asked, 3),
        "series": {p["day"]: p["value"] for p in points},
    }


def register(server: MCPServer) -> None:
    """Attach the metric tools to `server`."""

    @server.tool()
    def list_metrics() -> dict[str, Any]:
        """Every metric, derived series and logged event kind this server can answer about.

        Each entry has `key`, `kind` (series | derived | event), `unit`, a one-line
        `definition` and the `note_id` of the research note that defines it. Call this
        first; every other tool takes a `key` from here.
        """
        return catalogue_payload()

    @server.tool()
    async def metric_series(ctx: Context, metric: str, days: int = 30) -> dict[str, Any]:
        """The owner's daily values for one metric, as `{iso date: value}`.

        `n` is how many days have a reading and `coverage` is n over the days asked, so a
        sparse series says so. Days without a reading are absent, never zero-filled.
        """
        require_metric(metric)
        return await read_as_owner(ctx, lambda user: series_payload(user, metric, days))

    @server.tool()
    async def metric_stats(
        ctx: Context, metric: str, days: int = 30, stat: Stat = "avg"
    ) -> dict[str, Any]:
        """One statistic (avg, min, max, sum, latest, trend, series) over the last `days`."""
        require_metric(metric)
        if metric in _NO_STATS:
            return {"metric": metric, "note": "use metric_series for this metric"}
        window = bounded(days)
        return await read_as_owner(
            ctx,
            lambda user: coach_tools.query_metric(user.id, user.timezone, metric, window, stat),
        )

    @server.tool()
    async def compare_event(
        ctx: Context, event: str, metric: str, days: int = 60
    ) -> dict[str, Any]:
        """The metric on days the owner logged `event` versus days they did not.

        Observational and single-subject: a hint, not proof. `event` is a kind from
        `list_metrics` (alcohol, caffeine, ...) or a habit name the owner logged.
        """
        require_metric(metric)
        window = bounded(days, lo=7)
        return await read_as_owner(
            ctx,
            lambda user: coach_tools.compare_event(user.id, user.timezone, event, metric, window),
        )

    @server.tool(name="history")
    async def metric_history(ctx: Context, metric: str, days: int = 90) -> dict[str, Any]:
        """The `/api/history` payload for one metric: `{metric, series: [{day, value}]}`."""
        require_metric(metric)

        def read(user: RequestUser) -> dict:
            with tenant_transaction(user.id) as cur:
                return history(cur, user.id, user.timezone, metric, days)

        return await read_as_owner(ctx, read)
