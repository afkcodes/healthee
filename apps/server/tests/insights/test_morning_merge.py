"""#95 — the briefing and the daily action are ONE generation, rendered twice.

The whole point is a number: **one** LLM call where there were two. So the assertions
here are call counts against a counting stub, not step statuses — an implementation that
generated twice and threw one away would report identical statuses while spending exactly
the money this change exists to save (the same argument ``tests/premium/test_chain_spend``
makes for the free tier).

The second subject is the coupling, which is the risk the saving is bought with. Merging
two surfaces into one call means one failure could dark both, and a silent coupling that
halves availability to save money is not a win. So these tests pin the invariant the
design rests on: **the merged call is an optimisation, never a dependency** — when it
cannot ship, each surface still produces exactly what it produced before #95.
"""

from __future__ import annotations

import json
import sys
from collections.abc import Iterator
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from tests._auth import SECRET, auth_header
from tests.conftest import entitle
from tests.insights._ids import ESTABLISHED_ID
from tests.insights._stub import MORNING_JSON, VALID_TEXT, StubLLM

from healthee.api.app import create_app
from healthee.core.config import get_settings
from healthee.core.db import tenant_transaction
from healthee.core.tenancy import SENTINEL_TZ, SENTINEL_USER_ID, user_today
from healthee.db import migrate
from healthee.insights import coaching, grounded, morning, pipeline
from healthee.jobs import briefing as briefing_mod
from healthee.jobs import chain

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "analytics"))
import _seed_db as sd  # type: ignore[import-not-found]  # noqa: E402 — shared v2 seed helpers

pytestmark = pytest.mark.integration

_AUTH = auth_header(SENTINEL_USER_ID, SECRET)

_BRIEFING_BODY = (
    f"Recovery sits at your median. Steady load may support fitness [{ESTABLISHED_ID}]."
)
_ACTION_LINE = (
    f"Walk 20 minutes after lunch; regular movement may help recovery [{ESTABLISHED_ID}]."
)
_MERGED = json.dumps({"briefing": _BRIEFING_BODY, "action": _ACTION_LINE})


@pytest.fixture
def bed(db: None, monkeypatch: pytest.MonkeyPatch) -> Iterator[None]:  # noqa: ARG001
    """A seeded premium owner with Telegram silenced — the nightly bed, offline."""
    migrate.apply_migrations()
    days = sd.recent_days(30)
    sd.clean("kv")
    with tenant_transaction(SENTINEL_USER_ID) as cur:
        sd.seed_daily(cur, "recovery_score", {d: 70.0 for d in days})
        sd.seed_daily(cur, "sleep_regularity_index", {d: 74.0 for d in days})
    entitle(SENTINEL_USER_ID, premium=True)
    monkeypatch.setattr(briefing_mod, "send_telegram", lambda *_a, **_kw: True)
    monkeypatch.setattr(chain, "send_telegram", lambda *_a, **_kw: True)
    monkeypatch.setenv("SUPABASE_JWT_SECRET", SECRET)
    monkeypatch.delenv("SUPABASE_PROJECT_REF", raising=False)
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


def _stub(monkeypatch: pytest.MonkeyPatch, client: StubLLM) -> StubLLM:
    """Route every choke-point call through one counting stub (no network, no key)."""
    monkeypatch.setattr(grounded, "get_client", lambda: client)
    return client


# ── the saving: one call, two surfaces ───────────────────────────────────────


def test_one_call_produces_both_the_briefing_body_and_the_daily_action(
    bed: None,  # noqa: ARG001
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """THE assertion of #95: both surfaces are filled and the client ran exactly once."""
    stub = _stub(monkeypatch, StubLLM(json_text=_MERGED))

    warmed = coaching.warm_morning(SENTINEL_USER_ID, SENTINEL_TZ)

    assert stub.calls == 1, f"the merged generation cost {stub.calls} calls, not one"
    assert set(warmed) == {coaching.MORNING_BRIEFING_KEY, coaching.DAILY_ACTION_KEY}
    assert coaching.cached_line(SENTINEL_USER_ID, SENTINEL_TZ, coaching.DAILY_ACTION_KEY) == (
        _ACTION_LINE
    )
    body = coaching.cached_line(SENTINEL_USER_ID, SENTINEL_TZ, coaching.MORNING_BRIEFING_KEY)
    assert body is not None
    # ONE canonical action: the Telegram body renders the same sentence `/api/today`
    # serves, rather than a second one generated from the same data.
    assert _BRIEFING_BODY in body
    assert _ACTION_LINE in body


def test_the_cached_action_is_what_api_today_serves(
    bed: None,  # noqa: ARG001
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The read path is unchanged: cache-only, and it holds the merged answer's action."""
    stub = _stub(monkeypatch, StubLLM(json_text=_MERGED))
    api = TestClient(create_app())
    assert api.get("/api/today", headers=_AUTH).json()["action"] is None  # cold
    assert stub.calls == 0

    coaching.warm_morning(SENTINEL_USER_ID, SENTINEL_TZ)

    assert api.get("/api/today", headers=_AUTH).json()["action"] == _ACTION_LINE
    assert stub.calls == 1  # the read served cache: no generation on a read path


def test_the_briefing_step_sends_the_warmed_body_and_spends_nothing(
    bed: None,  # noqa: ARG001
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The other half of the saving: with a warmed body the briefing costs zero calls."""
    stub = _stub(monkeypatch, StubLLM(json_text=_MERGED))
    sent: list[str] = []
    monkeypatch.setattr(briefing_mod, "send_telegram", lambda msg: bool(sent.append(msg)) or True)
    coaching.warm_morning(SENTINEL_USER_ID, SENTINEL_TZ)

    status = briefing_mod.send_briefing(SENTINEL_USER_ID, SENTINEL_TZ)

    assert stub.calls == 1, "the briefing generated a second time instead of sending the warm body"
    assert status["source"] == "warm"
    assert status["validated"] is True
    assert len(sent) == 1
    assert _BRIEFING_BODY in sent[0]
    assert _ACTION_LINE in sent[0]
    assert "healthee briefing — " in sent[0]  # still date-stamped, never presented undated


# ── the coupling: a failure darks neither surface ────────────────────────────


def test_an_ungrounded_action_line_withholds_the_whole_merged_answer(
    bed: None,  # noqa: ARG001
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Validation binds BOTH fields: they are one candidate, so there is no partial pass.

    A perfectly grounded briefing does not ship beside an uncited action — which is the
    coupling, stated honestly, and the reason the fallback below exists.
    """
    bad = json.dumps({"briefing": _BRIEFING_BODY, "action": "This suggests your fitness is low."})
    _stub(monkeypatch, StubLLM(json_text=bad))

    assert morning.generate_morning(SENTINEL_USER_ID, SENTINEL_TZ) is None
    briefing_key = coaching.MORNING_BRIEFING_KEY
    assert coaching.cached_line(SENTINEL_USER_ID, SENTINEL_TZ, briefing_key) is None


def test_a_missing_field_does_not_ship_a_briefing_around_nothing(
    bed: None,  # noqa: ARG001
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The structural check the validator cannot make: no `action` key at all.

    `validate_json` finds no ungrounded sentence in a field that is absent, so it passes —
    which is exactly why `morning._fields` exists and is asserted here.
    """
    _stub(monkeypatch, StubLLM(json_text=json.dumps({"briefing": _BRIEFING_BODY})))

    assert morning.generate_morning(SENTINEL_USER_ID, SENTINEL_TZ) is None


def test_a_merged_call_that_cannot_ship_darks_neither_surface(
    bed: None,  # noqa: ARG001
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The invariant the whole saving is bought with (#95's stated risk).

    The merged JSON is unshippable; the prose script is fine. Both surfaces must still
    produce exactly what they produced before the merge — the action from its own
    generation, the briefing from its own — so availability is unchanged and only the
    COST moved.
    """
    bad = json.dumps({"briefing": _BRIEFING_BODY, "action": "This suggests your fitness is low."})
    stub = _stub(monkeypatch, StubLLM([VALID_TEXT], json_text=bad))
    sent: list[str] = []
    monkeypatch.setattr(briefing_mod, "send_telegram", lambda msg: bool(sent.append(msg)) or True)

    warm = coaching.warm_lines(SENTINEL_USER_ID, SENTINEL_TZ)
    status = briefing_mod.send_briefing(SENTINEL_USER_ID, SENTINEL_TZ)

    # The job health surface says which path ran, so "the briefing body is not cached" is
    # not read as "the owner got no briefing" — it is a call more expensive, not a card
    # short.
    assert warm["morning"] == "fallback"
    assert coaching.MORNING_BRIEFING_KEY not in warm["warmed"]
    # The action survived the merged failure on its own independent call.
    assert coaching.cached_line(SENTINEL_USER_ID, SENTINEL_TZ, coaching.DAILY_ACTION_KEY) == (
        VALID_TEXT
    )
    # So did the briefing, on its own.
    assert status["source"] == "standalone"
    assert len(sent) == 1
    assert VALID_TEXT in sent[0]
    # What a night costs when the merged answer cannot be grounded: the merged candidate
    # and each nudged rewrite the retry budget allows, then the action's own generation,
    # the sleep line and the briefing's own — three independent calls that all succeed
    # here. Written off `validation_retries()` because that number is configuration now
    # (#128) and this test is about the FALLBACK PATH, not about the budget.
    assert stub.calls == pipeline.validation_retries() + 1 + 3


def test_the_briefing_still_generates_when_warm_never_ran(
    bed: None,  # noqa: ARG001
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """A `correlate` failure skips `warm` entirely — the briefing must not go silent.

    Nothing was warmed, so there is no body to send and this step does what it always did.
    """
    stub = _stub(monkeypatch, StubLLM([VALID_TEXT]))
    sent: list[str] = []
    monkeypatch.setattr(briefing_mod, "send_telegram", lambda msg: bool(sent.append(msg)) or True)

    status = briefing_mod.send_briefing(SENTINEL_USER_ID, SENTINEL_TZ)

    assert status["source"] == "standalone"
    assert status["sent"] is True
    assert stub.calls == 1
    assert VALID_TEXT in sent[0]


# ── the chain: same steps, same order, one call fewer ────────────────────────


def test_the_chain_sequences_unchanged_and_the_morning_costs_one_call(
    bed: None,  # noqa: ARG001
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Two steps became one CALL, not one step: the chain is untouched below the money.

    ``correlate`` is stubbed to a no-op (its own dependency logic is pinned in
    ``tests/jobs/test_chain_supervision.py``); everything else runs for real. The call
    budget is the assertion: the merged morning + sleep-tonight = 2 (the coach steps are
    stubbed or, with no active job, make no call), where the same chain spent 4 before #95,
    and the briefing step now spends none of them.
    """
    stub = _stub(monkeypatch, StubLLM(json_text=MORNING_JSON))
    monkeypatch.setattr(chain, "step_correlate", lambda *a, **kw: {"ok": True})  # noqa: ARG005
    monkeypatch.setattr(chain, "step_coach_weekly", lambda *a, **kw: {"ok": True})  # noqa: ARG005
    day = user_today(SENTINEL_TZ)

    result = chain.run_chain(SENTINEL_USER_ID, SENTINEL_TZ, day, client=stub, force=True)

    assert [step.name for step in result.steps] == [
        "illness",
        "challenges",
        "correlate",
        *chain._coach_names(day),
        "warm",
        "briefing",
    ]
    assert {step.status for step in result.steps} == {"ok"}
    warm = next(step for step in result.steps if step.name == "warm")
    assert warm.detail is not None
    assert warm.detail["warmed"] == sorted(
        [coaching.MORNING_BRIEFING_KEY, coaching.DAILY_ACTION_KEY, coaching.SLEEP_TONIGHT_KEY]
    )
    briefing_step = next(step for step in result.steps if step.name == "briefing")
    assert briefing_step.detail is not None
    assert briefing_step.detail["source"] == "warm"
    assert stub.calls == 2, f"the nightly chain made {stub.calls} calls, not 2"


def test_a_second_warm_for_the_same_day_regenerates_nothing(
    bed: None,  # noqa: ARG001
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The per-day cache still bounds the spend on the merged call as it did on two.

    Asserted on ``warm_lines`` rather than a second ``run_chain``: the coach steps have no per-day
    cache and may pay again on a forced re-run, which is true before and after #95 and would
    make a chain-level count read as a regression it is not.
    """
    stub = _stub(monkeypatch, StubLLM(json_text=MORNING_JSON))
    coaching.warm_lines(SENTINEL_USER_ID, SENTINEL_TZ, client=stub)
    spent = stub.calls

    again = coaching.warm_lines(SENTINEL_USER_ID, SENTINEL_TZ, client=stub)

    assert spent == 2, "the shipping path should be the merged call plus the sleep line"
    assert stub.calls == spent, "a re-run of an already-warmed day paid for it again"
    assert again["degraded"] == []
    assert again["morning"] == "merged"
