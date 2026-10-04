"""Knowledge search and the two resources."""

from __future__ import annotations

import json

import pytest
from mcp import Client
from mcp_types import TextResourceContents
from tests.mcp_server.conftest import McpBed, call, call_raw, run_client

from healthee.insights import manifest

pytestmark = pytest.mark.integration


def _text(contents: list) -> str:
    assert isinstance(contents[0], TextResourceContents)
    return contents[0].text


GRADES = {"Established", "Probable", "Emerging", "Contested", "Myth", "Refuted"}


def test_knowledge_search_returns_graded_passages(bed: McpBed) -> None:
    payload = call(bed.app, bed.token_a, "knowledge_search", query="resting heart rate", k=5)
    assert payload["mode"] == "passages"
    assert 0 < len(payload["results"]) <= 5
    for hit in payload["results"]:
        assert hit["grade"] in GRADES, hit
        assert manifest.by_id(hit["note_id"]) is not None
        assert hit["ref"].startswith(hit["note_id"] + "#p")
        assert hit["text"] and hit["section"] is not None


def test_knowledge_search_refuses_an_empty_query(bed: McpBed) -> None:
    assert call_raw(bed.app, bed.token_a, "knowledge_search", query="  ").is_error


def test_knowledge_note_returns_body_and_grade(bed: McpBed) -> None:
    payload = call(bed.app, bed.token_a, "knowledge_note", note_id="resting_heart_rate")
    assert payload["note_id"] == "resting_heart_rate"
    assert payload["grade"] == manifest.grade_of("resting_heart_rate")
    assert payload["body"]


def test_the_metrics_resource_is_the_catalogue(bed: McpBed) -> None:
    async def work(client: Client) -> str:
        result = await client.read_resource("healthee://metrics")
        return _text(result.contents)

    keys = {m["key"] for m in json.loads(run_client(bed.app, bed.token_a, work))["metrics"]}
    assert {"rhr_daily", "alcohol", "weight_kg"} <= keys


def test_the_knowledge_template_resolves_a_note(bed: McpBed) -> None:
    async def work(client: Client) -> tuple[list[str], str]:
        templates = await client.list_resource_templates()
        read = await client.read_resource("healthee://knowledge/resting_heart_rate")
        return [t.uri_template for t in templates.resource_templates], _text(read.contents)

    uris, text = run_client(bed.app, bed.token_a, work)
    assert "healthee://knowledge/{note_id}" in uris
    assert text == manifest.prompt_body("resting_heart_rate")
