"""The tools over real MCP, as a client would call them, against the seeded owner."""

from __future__ import annotations

from datetime import timedelta

import pytest
from mcp import Client
from tests.contracts.seed import today_local
from tests.mcp_server.conftest import (
    SPARSE_DAYS_AGO,
    SPARSE_METRIC,
    SPARSE_VALUE,
    McpBed,
    call,
    call_raw,
    run_client,
)

from healthee.mcp.catalogue import CATALOGUE

pytestmark = pytest.mark.integration

EXPECTED_TOOLS = {
    "list_metrics",
    "metric_series",
    "metric_stats",
    "compare_event",
    "today",
    "sleep",
    "sleep_health",
    "activity",
    "workouts",
    "workout",
    "recovery",
    "history",
    "recent_logs",
    "findings",
    "recommendations",
    "knowledge_search",
    "knowledge_note",
}


def test_a_valid_token_lists_every_tool(bed: McpBed) -> None:
    async def work(client: Client) -> set[str]:
        return {tool.name for tool in (await client.list_tools()).tools}

    assert run_client(bed.app, bed.token_a, work) == EXPECTED_TOOLS


def test_list_metrics_serves_the_whole_catalogue(bed: McpBed) -> None:
    payload = call(bed.app, bed.token_a, "list_metrics")
    assert [m["key"] for m in payload["metrics"]] == [e.key for e in CATALOGUE]
    rhr = next(m for m in payload["metrics"] if m["key"] == "rhr_daily")
    assert rhr["unit"] == "bpm" and rhr["note_id"] == "resting_heart_rate"


def test_metric_series_returns_the_seeded_values_and_coverage(bed: McpBed) -> None:
    payload = call(bed.app, bed.token_a, "metric_series", metric=SPARSE_METRIC, days=10)
    today = today_local()
    assert payload["series"] == {
        (today - timedelta(days=ago)).isoformat(): SPARSE_VALUE for ago in SPARSE_DAYS_AGO
    }
    assert payload["n"] == len(SPARSE_DAYS_AGO)
    assert payload["days"] == 10
    assert payload["coverage"] == pytest.approx(len(SPARSE_DAYS_AGO) / 10)
    assert payload["unit"] == "kcal"


def test_an_unknown_metric_is_refused_naming_the_catalogue(bed: McpBed) -> None:
    result = call_raw(bed.app, bed.token_a, "metric_series", metric="sleep_score")
    assert result.is_error
    assert "list_metrics" in result.content[0].text


def test_metric_stats_is_query_metric_shaped(bed: McpBed) -> None:
    payload = call(bed.app, bed.token_a, "metric_stats", metric="rhr_daily", days=14, stat="avg")
    assert payload["metric"] == "rhr_daily"
    assert payload["avg"] == 55.0
    assert payload["n"] >= 1


def test_compare_event_refuses_an_unknown_metric(bed: McpBed) -> None:
    result = call_raw(bed.app, bed.token_a, "compare_event", event="alcohol", metric="nope")
    assert result.is_error and "list_metrics" in result.content[0].text


def test_compare_event_returns_the_coach_shape(bed: McpBed) -> None:
    payload = call(bed.app, bed.token_a, "compare_event", event="alcohol", metric="hrv_sleep_avg")
    assert payload["event"] == "alcohol"
    assert "note" in payload or "delta" in payload


def test_history_is_the_api_payload(bed: McpBed) -> None:
    payload = call(bed.app, bed.token_a, "history", metric="rhr_daily", days=7)
    assert payload["metric"] == "rhr_daily"
    assert payload["series"] and set(payload["series"][0]) == {"day", "value"}


def test_today_carries_the_api_payload_with_its_gate(bed: McpBed) -> None:
    payload = call(bed.app, bed.token_a, "today")
    assert payload["as_of"]["is_today"] is True
    assert "locked" not in payload  # seeded owner is premium


@pytest.mark.parametrize(
    "tool", ["sleep", "sleep_health", "activity", "workouts", "recovery", "recent_logs", "findings"]
)
def test_the_page_reads_answer(bed: McpBed, tool: str) -> None:
    assert isinstance(call(bed.app, bed.token_a, tool), dict)


def test_a_future_day_is_refused_like_the_api_would(bed: McpBed) -> None:
    result = call_raw(bed.app, bed.token_a, "today", day="2999-01-01")
    assert result.is_error and "future" in result.content[0].text


def test_workout_detail_by_start_iso(bed: McpBed) -> None:
    listed = call(bed.app, bed.token_a, "workouts", days=30)
    assert listed["n"] >= 1
    start = listed["workouts"][0]["start_iso"]
    detail = call(bed.app, bed.token_a, "workout", id=start)
    assert isinstance(detail, dict) and detail


def test_recommendations_are_locked_for_a_free_owner(bed: McpBed) -> None:
    from tests.conftest import entitle

    entitle(bed.owner_a, premium=False)
    payload = call(bed.app, bed.token_a, "recommendations")
    assert payload["locked"] is True and "recommendations" not in payload


def test_recommendations_for_a_premium_owner(bed: McpBed) -> None:
    payload = call(bed.app, bed.token_a, "recommendations")
    assert payload["days"] == 30 and isinstance(payload["recommendations"], list)


def test_weight_stats_point_at_metric_series_instead_of_claiming_no_data(bed: McpBed) -> None:
    payload = call(bed.app, bed.token_a, "metric_stats", metric="weight_kg")
    assert "metric_series" in payload["note"]
    assert "n" not in payload


def test_windows_are_bounded(bed: McpBed) -> None:
    stats = call(bed.app, bed.token_a, "metric_stats", metric="rhr_daily", days=999999)
    assert stats["days"] == 365
    assert call(bed.app, bed.token_a, "workouts", days=999999)["days"] == 365
    series = call(bed.app, bed.token_a, "metric_series", metric="rhr_daily", days=999999)
    assert series["days"] == 1825
