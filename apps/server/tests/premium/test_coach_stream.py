"""POST /api/coach/stream over real HTTP — the streaming twin of /api/coach.

Lives beside ``test_premium_cap.py`` rather than under ``tests/insights`` because it
needs the same seeded, entitled, real-HTTP bed (``tests/premium/conftest.py``'s
``bed``/``stub``/``make_free``) that file already uses for the coach's refund
contract — this is that same contract, over SSE instead of one JSON body.

What is proven here and NOT in ``tests/insights/test_coach_progress.py`` (which
proves the event EMISSION with no DB): the wire framing, the documented event order
end-to-end, that the ``answer`` event is exactly what ``/api/coach`` itself returns
for an identical turn, the refund guarantee measured on the real ledger (the same way
``test_premium_cap.py`` does), the error/timeout classification and its logging, and
that a request which fails BEFORE any model call still gets a plain JSON 402 — the
completeness half (every route probed for a 402) already lives in
``tests/premium/test_ai_gate.py``.
"""

from __future__ import annotations

import json
import logging

import httpx
import httpx2
import openai
import pytest
from fastapi.testclient import TestClient
from tests.insights._coach_stub import (
    VALID_REPLY,
    CoachStub,
    claim_turn,
    tool_call,
    tool_turn,
    valid_turn,
)
from tests.insights._stub import StubLLM
from tests.premium.conftest import AUTH

from healthee.api import coach_stream
from healthee.core import allowance
from healthee.core.tenancy import SENTINEL_TZ, SENTINEL_USER_ID
from healthee.insights import coach as coach_module
from healthee.insights import coach_tools

pytestmark = pytest.mark.integration

_QUESTION = {"messages": [{"role": "user", "content": "how am I doing?"}]}
_STREAM_PATH = "/api/coach/stream"


def _coach_uses() -> int:
    from healthee.api import gate

    verdict = allowance.peek(
        SENTINEL_USER_ID,
        SENTINEL_TZ,
        gate.COACH,
        gate.PREMIUM_COACH_QUESTIONS,
        window_days=gate.PREMIUM_WINDOW_DAYS,
    )
    return verdict.used


def _parse_sse(text: str) -> list[tuple[str, dict]]:
    """Every real ``event: x\\ndata: y`` frame, in order; keepalive comments dropped."""
    events: list[tuple[str, dict]] = []
    for block in text.split("\n\n"):
        block = block.strip()
        if not block or block.startswith(":"):
            continue
        name = data = None
        for line in block.split("\n"):
            if line.startswith("event:"):
                name = line.removeprefix("event:").strip()
            elif line.startswith("data:"):
                data = line.removeprefix("data:").strip()
        if name is not None and data is not None:
            events.append((name, json.loads(data)))
    return events


def _stream(bed: TestClient, body: dict) -> httpx2.Response:
    return bed.post(_STREAM_PATH, json=body, headers=AUTH)


# ── the wire framing ──────────────────────────────────────────────────────────


def test_headers_say_sse_and_disable_proxy_buffering(bed: TestClient, stub: StubLLM) -> None:  # noqa: ARG001
    resp = _stream(bed, _QUESTION)
    assert resp.status_code == 200
    assert resp.headers["content-type"].startswith("text/event-stream")
    assert resp.headers["cache-control"] == "no-cache"
    assert resp.headers["x-accel-buffering"] == "no"


# ── the documented event order ─────────────────────────────────────────────────


def test_a_tool_using_turn_emits_the_documented_order(
    bed: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(coach_tools, "execute_tool", lambda name, args, uid, tz: {"avg": 42.0})
    script = CoachStub(
        [tool_turn(tool_call("c1", "query_metric", '{"metric": "hrv_sleep_avg"}')), valid_turn()]
    )
    monkeypatch.setattr(coach_module, "get_client", lambda: script)
    events = _parse_sse(_stream(bed, _QUESTION).text)
    stages = [data["stage"] for name, data in events if name == "stage"]
    assert stages == ["context", "thinking", "tool", "thinking", "checking"]
    tool_event = next(data for name, data in events if name == "stage" and data["stage"] == "tool")
    assert tool_event["detail"] == "query_metric"
    assert events[-1][0] == "answer"


def test_a_rejected_then_accepted_candidate_shows_revising(
    bed: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    bad = claim_turn("This is great", ["not_a_real_note"])
    monkeypatch.setattr(coach_module, "get_client", lambda: CoachStub([bad, valid_turn()]))
    events = _parse_sse(_stream(bed, _QUESTION).text)
    stages = [data["stage"] for name, data in events if name == "stage"]
    assert stages == ["context", "thinking", "checking", "revising", "thinking", "checking"]
    assert events[-1][0] == "answer"
    assert events[-1][1]["reply"] == VALID_REPLY
    assert events[-1][1]["validated"] is True


# ── the answer event is exactly /api/coach's own payload ─────────────────────


def test_the_answer_event_equals_post_coach_for_the_same_turn(
    bed: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(coach_module, "get_client", lambda: CoachStub([valid_turn()]))
    plain = bed.post("/api/coach", json=_QUESTION, headers=AUTH)
    assert plain.status_code == 200

    monkeypatch.setattr(coach_module, "get_client", lambda: CoachStub([valid_turn()]))
    events = _parse_sse(_stream(bed, _QUESTION).text)
    name, data = events[-1]
    assert name == "answer"
    assert data == plain.json()
    assert data["reply"] == VALID_REPLY


# ── the live draft (the owner's 2026-09-19 call) ──────────────────────────────


def test_draft_frames_arrive_before_the_answer_event(bed: TestClient, stub: StubLLM) -> None:  # noqa: ARG001
    """Real SSE framing, end to end: a ``draft`` event ships (the round's own final
    flush, `coach_loop.ToolLoop`) strictly before the terminal ``answer`` event, and
    it carries the shape ``packages/contracts/snapshots/coach_stream_events.json``
    documents (``{"round", "text"}``)."""
    events = _parse_sse(_stream(bed, _QUESTION).text)
    names = [name for name, _ in events]
    assert "draft" in names
    assert names.index("draft") < names.index("answer")
    draft_data = next(data for name, data in events if name == "draft")
    assert draft_data == {"round": 1, "text": VALID_REPLY}


# ── the refund contract, measured on the real ledger ──────────────────────────


def test_a_refused_question_is_refunded(bed: TestClient, stub: StubLLM) -> None:
    resp = _stream(bed, {"messages": [{"role": "user", "content": "do I have diabetes?"}]})
    events = _parse_sse(resp.text)
    assert events[-1][0] == "answer"
    assert events[-1][1]["refused"] is True
    assert stub.calls == 0
    assert _coach_uses() == 0


def test_an_unvalidatable_answer_is_refunded(
    bed: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    from tests.insights._coach_stub import answer_payload

    claim = ("Your recovery suggests overtraining", ["not_a_real_note"], "Probable")
    broken = StubLLM(coach_text=json.dumps(answer_payload(claims=[claim])))
    monkeypatch.setattr(coach_module, "get_client", lambda: broken)
    events = _parse_sse(_stream(bed, _QUESTION).text)
    assert events[-1][0] == "answer"
    assert events[-1][1]["validated"] is False
    assert _coach_uses() == 0


def test_a_turn_with_no_question_is_refunded(bed: TestClient, stub: StubLLM) -> None:  # noqa: ARG001
    events = _parse_sse(_stream(bed, {"messages": []}).text)
    assert events[-1][0] == "answer"
    assert _coach_uses() == 0


def test_a_worker_exception_is_refunded_reported_as_a_500_and_logged(
    bed: TestClient, monkeypatch: pytest.MonkeyPatch, caplog: pytest.LogCaptureFixture
) -> None:
    def explode(*_a: object, **_k: object) -> None:
        raise RuntimeError("the provider hung up")

    monkeypatch.setattr(coach_stream, "run_coach", explode)
    with caplog.at_level(logging.ERROR):
        events = _parse_sse(_stream(bed, _QUESTION).text)
    assert events == [("error", {"status": 500, "message": "the coach turn failed"})]
    assert _coach_uses() == 0
    assert any("coach stream worker failed" in r.message for r in caplog.records)


def test_a_stdlib_timeout_is_reported_as_a_504(
    bed: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    def timed_out(*_a: object, **_k: object) -> None:
        raise TimeoutError("gathering deadline exceeded")

    monkeypatch.setattr(coach_stream, "run_coach", timed_out)
    events = _parse_sse(_stream(bed, _QUESTION).text)
    assert events == [("error", {"status": 504, "message": "the coach timed out"})]
    assert _coach_uses() == 0


def test_an_openai_api_timeout_error_is_also_reported_as_a_504(
    bed: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    """``openai.APITimeoutError`` is NOT a stdlib ``TimeoutError`` — named by class instead."""
    exc = openai.APITimeoutError(request=httpx.Request("POST", "https://example.invalid"))

    def timed_out(*_a: object, **_k: object) -> None:
        raise exc

    monkeypatch.setattr(coach_stream, "run_coach", timed_out)
    events = _parse_sse(_stream(bed, _QUESTION).text)
    assert events == [("error", {"status": 504, "message": "the coach timed out"})]


def test_a_delivered_answer_is_not_refunded(bed: TestClient, stub: StubLLM) -> None:  # noqa: ARG001
    events = _parse_sse(_stream(bed, _QUESTION).text)
    assert events[-1][1]["validated"] is True
    assert _coach_uses() == 1


# ── the gate runs before any byte of the stream ───────────────────────────────


def test_a_free_owner_gets_a_plain_json_402_never_a_stream(
    bed: TestClient,
    make_free,
    stub: StubLLM,  # noqa: ANN001, ARG001
) -> None:
    make_free()
    resp = _stream(bed, _QUESTION)
    assert resp.status_code == 402
    assert resp.headers["content-type"].startswith("application/json")
    detail = resp.json()["detail"]
    assert detail["locked"] is True
    assert stub.calls == 0
    assert _coach_uses() == 0
