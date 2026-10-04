"""Tenant isolation over MCP: two owners, two tokens, each sees only their own numbers.

The critical test. B's rows sit at the SAME natural keys as A's with impossible values
(B resting HR 88 against A's 55), so a tool that read across owners — or trusted anything
but the authenticated token — returns an absurd figure rather than the right one.
"""

from __future__ import annotations

import pytest
from tests.contracts.seed_owner_b import B_RECOVERY, B_RHR, B_STEPS
from tests.mcp_server.conftest import SPARSE_METRIC, McpBed, call, run_client

pytestmark = pytest.mark.integration


def _values(payload: dict) -> set[float]:
    return set(payload["series"].values())


def test_each_token_sees_only_its_own_series(bed: McpBed) -> None:
    a = call(bed.app, bed.token_a, "metric_series", metric="rhr_daily", days=14)
    b = call(bed.app, bed.token_b, "metric_series", metric="rhr_daily", days=14)
    assert _values(a) == {55.0}
    assert _values(b) == {B_RHR}


def test_the_sparse_series_exists_for_a_only(bed: McpBed) -> None:
    a = call(bed.app, bed.token_a, "metric_series", metric=SPARSE_METRIC, days=10)
    b = call(bed.app, bed.token_b, "metric_series", metric=SPARSE_METRIC, days=10)
    assert a["n"] == 4 and b["n"] == 0 and b["coverage"] == 0


@pytest.mark.parametrize(
    ("metric", "b_value"), [("steps_total", B_STEPS), ("recovery_score", B_RECOVERY)]
)
def test_stats_and_history_are_owner_scoped(bed: McpBed, metric: str, b_value: float) -> None:
    stats = call(bed.app, bed.token_b, "metric_stats", metric=metric, days=14, stat="avg")
    assert stats["avg"] == b_value
    history = call(bed.app, bed.token_b, "history", metric=metric, days=14)
    assert {p["value"] for p in history["series"]} == {b_value}


def test_page_reads_do_not_leak_across_owners(bed: McpBed) -> None:
    for token, own, other in ((bed.token_a, 55.0, B_RHR), (bed.token_b, B_RHR, 55.0)):
        history = call(bed.app, token, "history", metric="rhr_daily", days=14)
        assert {p["value"] for p in history["series"]} == {own}
        assert other not in {p["value"] for p in history["series"]}


def test_a_tool_cannot_name_another_owner(bed: McpBed) -> None:
    """No tool takes an owner argument, so identity can only come from the token."""

    async def work(client):
        return (await client.list_tools()).tools

    for tool in run_client(bed.app, bed.token_a, work):
        arguments = set(tool.input_schema.get("properties", {}))
        assert not arguments & {"user", "user_id", "owner", "owner_id", "tenant"}, tool.name
