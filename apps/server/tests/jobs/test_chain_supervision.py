"""The crux WP8 test: the supervised chain never swallows a step failure.

Pure control-flow (no DB, no LLM): the step functions and the kv dedup
marker are stubbed, so these prove the supervision contract exactly —
  * a step that RAISES is caught, reported to Telegram, and returned as `failed`
    (NOT silently passed, NOT crashing the process — the legacy swallow is dead);
  * `illness` runs FIRST — it is the only step anything below it reads, and
    `challenges` consults the flag it writes in the very next step;
  * `challenges` runs before correlate and depends on nothing — a correlate failure
    must not reach back and skip closing out a commitment that already ended;
  * a `correlate` failure ABORTS `coach_today` AND `warm` (both read its findings);
  * a `briefing` failure does not undo the coach_today that already ran;
  * a `warm` failure is non-fatal — it costs the coaching lines, not the briefing;
  * a second run for the same day is a deduped no-op;
  * a NON-PREMIUM owner's chain runs the three deterministic steps — `illness` among
    them, because safety is never paywalled — and calls none of the three that cost
    tokens (6.6a — the cost hole, MULTI_USER.md §12.3).

Entitlement is stubbed alongside the dedup marker so these stay pure control-flow: the
real `is_premium` reads the `subscription` table, and a DB lookup in here would make a
file whose whole subject is branching depend on a seeded database.
"""

from __future__ import annotations

from collections.abc import Iterator
from datetime import date
from uuid import UUID

import pytest

from healthee.jobs import chain

DAY = date(2026, 7, 15)

# An arbitrary owner: these tests are pure control-flow, so the id only has to be
# threaded consistently — the per-owner dedup marker is asserted in test_scheduler.
_OWNER = UUID("44444444-4444-4444-4444-444444444444")
_TZ = "Asia/Kolkata"


@pytest.fixture
def notices(monkeypatch: pytest.MonkeyPatch) -> Iterator[list[str]]:
    """Capture Telegram notifications, back the dedup marker + entitlement in memory."""
    sent: list[str] = []
    monkeypatch.setattr(chain, "send_telegram", lambda text, **_: sent.append(text) or True)
    monkeypatch.setattr(chain, "is_premium", lambda _user_id: True)
    marker: set[str] = set()
    monkeypatch.setattr(chain, "_chain_done", lambda _user_id, day: day.isoformat() in marker)
    monkeypatch.setattr(
        chain, "_mark_chain_done", lambda _user_id, day: marker.add(day.isoformat())
    )
    yield sent


def _stub_steps(monkeypatch: pytest.MonkeyPatch, **raisers: bool) -> dict[str, int]:
    """Stub every step; names in ``raisers`` raise. Returns a call counter.

    ALL of them are stubbed, including ``warm`` and ``challenges``: an unstubbed step
    would reach the real coaching module (DB + the choke point) or the real lifecycle
    (DB writes), so these control-flow tests would silently stop being control-flow
    tests. A step added to the chain and NOT added here is the exact way that decays.
    """
    calls = {
        "illness": 0,
        "challenges": 0,
        "correlate": 0,
        "coach_today": 0,
        "warm": 0,
        "briefing": 0,
    }

    def make(name: str):
        def step(_day: date, _user_id: UUID, _tz: str, *, client=None) -> dict:  # noqa: ARG001
            calls[name] += 1
            if raisers.get(name):
                raise RuntimeError(f"{name} boom")
            return {"ran": name}

        return step

    for name in calls:
        monkeypatch.setattr(chain, f"step_{name}", make(name))
    return calls


def test_a_raising_step_is_caught_reported_and_not_swallowed(
    monkeypatch: pytest.MonkeyPatch, notices: list[str]
) -> None:
    calls = _stub_steps(monkeypatch, coach_today=True)
    result = chain.run_chain(_OWNER, _TZ, DAY)  # must not raise

    coach_today = next(s for s in result.steps if s.name == "coach_today")
    assert coach_today.status == "failed"
    assert "coach_today boom" in (coach_today.error or "")
    # Reported to the health surface — the failure is visible, not hidden.
    assert any("chain step 'coach_today' failed" in n and "coach_today boom" in n for n in notices)
    # The other steps still ran; the process was not crashed.
    assert calls == {
        "illness": 1,
        "challenges": 1,
        "correlate": 1,
        "coach_today": 1,
        "warm": 1,
        "briefing": 1,
    }


def test_illness_runs_before_challenges_which_reads_what_it_writes(
    monkeypatch: pytest.MonkeyPatch,
    notices: list[str],  # noqa: ARG001
) -> None:
    """Order is load-bearing, not cosmetic — it is the whole reason `illness` is first.

    `challenges` reads the illness flag twice in the step immediately after: the ladder
    adapter asks `recovery_guard` whether an adopted training target may be RAISED, and
    `lifecycle` asks `confounds` whether the owner was ill inside a closing outcome's
    window. Produce the flag after them and today's flag reaches neither — the adapter
    ratchets a target on the morning the owner got sick, and the ledger records that
    day as unconfounded. A test on the ORDER is the only thing that keeps that true
    when a seventh step is appended.
    """
    _stub_steps(monkeypatch)
    result = chain.run_chain(_OWNER, _TZ, DAY)

    names = [s.name for s in result.steps]
    assert names.index("illness") < names.index("challenges")
    assert names[0] == "illness"


def test_challenges_runs_before_correlate_and_depends_on_nothing(
    monkeypatch: pytest.MonkeyPatch, notices: list[str]
) -> None:
    """Closing out a finished commitment is not downstream of any computation.

    A correlate failure — which legitimately aborts coach_today and warm — must not reach back
    and skip it: an owner whose findings broke still deserves an honest outcome for the
    challenge that ended last night.
    """
    calls = _stub_steps(monkeypatch, correlate=True)
    result = chain.run_chain(_OWNER, _TZ, DAY)

    assert [s.name for s in result.steps][:2] == ["illness", "challenges"]
    assert {s.name: s.status for s in result.steps}["challenges"] == "ok"
    assert calls["challenges"] == 1
    assert not any("challenges" in n for n in notices), "it ran clean; nothing to report"


def test_a_challenges_failure_is_reported_and_the_chain_continues(
    monkeypatch: pytest.MonkeyPatch, notices: list[str]
) -> None:
    """Nothing below it reads its result, so it must not abort — but must be visible.

    "Non-fatal" decaying into "swallowed" is the legacy failure this whole module
    exists to prevent: a challenge that silently stops closing out would show the
    owner a commitment that ended weeks ago, with nobody told.
    """
    calls = _stub_steps(monkeypatch, challenges=True)
    result = chain.run_chain(_OWNER, _TZ, DAY)  # must not raise

    statuses = {s.name: s.status for s in result.steps}
    assert statuses["challenges"] == "failed"
    assert (statuses["correlate"], statuses["coach_today"], statuses["briefing"]) == (
        "ok",
        "ok",
        "ok",
    )
    assert calls["correlate"] == 1
    assert any("chain step 'challenges' failed" in n and "challenges boom" in n for n in notices)


def test_correlate_failure_aborts_recs(monkeypatch: pytest.MonkeyPatch, notices: list[str]) -> None:
    calls = _stub_steps(monkeypatch, correlate=True)
    result = chain.run_chain(_OWNER, _TZ, DAY)

    statuses = {s.name: s.status for s in result.steps}
    assert statuses["correlate"] == "failed"
    assert statuses["coach_today"] == "skipped"  # dependency abort
    assert statuses["warm"] == "skipped"  # ditto: warming reads correlate's findings too
    assert calls["coach_today"] == 0  # coach_today was NOT executed on stale inputs
    assert calls["warm"] == 0
    assert any("chain step 'correlate' failed" in n for n in notices)


def test_briefing_failure_does_not_undo_recs(
    monkeypatch: pytest.MonkeyPatch, notices: list[str]
) -> None:
    calls = _stub_steps(monkeypatch, briefing=True)
    result = chain.run_chain(_OWNER, _TZ, DAY)

    statuses = {s.name: s.status for s in result.steps}
    assert statuses["coach_today"] == "ok"  # coach_today completed and its result stands
    assert calls["coach_today"] == 1
    assert statuses["briefing"] == "failed"
    assert any("chain step 'briefing' failed" in n for n in notices)


def test_warm_failure_is_non_fatal_and_still_reported(
    monkeypatch: pytest.MonkeyPatch, notices: list[str]
) -> None:
    """A dead coaching line must not cost the owner their briefing — but must be visible.

    The two halves matter equally. Non-fatal: `warm` is the newest step and the least
    important one (a null action is a degraded card), so it must not abort the chain.
    Reported: "non-fatal" must not decay into "swallowed" — the whole reason the lines
    were null for months is that nobody was told anything was wrong.
    """
    calls = _stub_steps(monkeypatch, warm=True)
    result = chain.run_chain(_OWNER, _TZ, DAY)  # must not raise

    statuses = {s.name: s.status for s in result.steps}
    assert statuses["warm"] == "failed"
    assert statuses["coach_today"] == "ok"  # the coach_today already persisted stand
    assert statuses["briefing"] == "ok"  # the chain continued past the dead line
    assert calls["briefing"] == 1
    assert any("chain step 'warm' failed" in n and "warm boom" in n for n in notices)


def test_second_run_same_day_is_a_deduped_no_op(
    monkeypatch: pytest.MonkeyPatch,
    notices: list[str],  # noqa: ARG001
) -> None:
    calls = _stub_steps(monkeypatch)
    first = chain.run_chain(_OWNER, _TZ, DAY)
    assert first.deduped is False
    assert calls == {
        "illness": 1,
        "challenges": 1,
        "correlate": 1,
        "coach_today": 1,
        "warm": 1,
        "briefing": 1,
    }

    second = chain.run_chain(_OWNER, _TZ, DAY)  # already ran today
    assert second.deduped is True
    assert second.steps == []
    assert calls == {
        "illness": 1,
        "challenges": 1,
        "correlate": 1,
        "coach_today": 1,
        "warm": 1,
        "briefing": 1,
    }  # nothing re-fired

    forced = chain.run_chain(_OWNER, _TZ, DAY, force=True)  # force overrides dedup
    assert forced.deduped is False
    assert calls == {
        "illness": 2,
        "challenges": 2,
        "correlate": 2,
        "coach_today": 2,
        "warm": 2,
        "briefing": 2,
    }


# ── entitlement: the free owner's chain must not reach a model (6.6a, #48) ─────


def test_a_free_owners_chain_calls_none_of_the_three_llm_steps(
    monkeypatch: pytest.MonkeyPatch, notices: list[str]
) -> None:
    """The cost hole, closed: coach_today / warm / briefing are never even CALLED.

    Asserted on the call counter, not on the outcome list — an implementation that ran
    the steps and threw their output away would produce identical `skipped` statuses
    while spending exactly the tokens this exists to save.
    """
    monkeypatch.setattr(chain, "is_premium", lambda _user_id: False)
    calls = _stub_steps(monkeypatch)

    result = chain.run_chain(_OWNER, _TZ, DAY)

    assert calls == {
        "illness": 1,
        "challenges": 1,
        "correlate": 1,
        "coach_today": 0,
        "warm": 0,
        "briefing": 0,
    }
    statuses = {s.name: s.status for s in result.steps}
    assert statuses == {
        "illness": "ok",
        "challenges": "ok",
        "correlate": "ok",
        "coach_today": "skipped",
        "warm": "skipped",
        "briefing": "skipped",
    }
    # Named, not silently absent: the health surface must be able to tell "this owner is
    # not entitled" from "coach_today broke again" (standards §Errors).
    skipped = [s for s in result.steps if s.status == "skipped"]
    assert all("not premium" in (s.error or "") for s in skipped)
    assert notices == []  # a skip is not a failure — nothing is alerted


def test_the_deterministic_steps_still_run_for_a_free_owner(
    monkeypatch: pytest.MonkeyPatch,
    notices: list[str],  # noqa: ARG001
) -> None:
    """`illness` is the SAFETY step and can never be gated (PRICING.md §1a: "never
    paywall data or safety"). `correlate` is FREE-tier and spends nothing — gating it
    would have taken a free feature away to save money it does not cost. `challenges`
    closes out commitments that already exist, which a lapse must not freeze forever."""
    monkeypatch.setattr(chain, "is_premium", lambda _user_id: False)
    calls = _stub_steps(monkeypatch)

    chain.run_chain(_OWNER, _TZ, DAY)

    assert calls["correlate"] == 1
    assert calls["challenges"] == 1
    # The safety step above all: PRICING.md §1a never paywalls safety, and an illness
    # flag that only paying owners got would be a guardrail sold as a feature.
    assert calls["illness"] == 1


def test_a_free_owners_day_is_still_marked_done(
    monkeypatch: pytest.MonkeyPatch,
    notices: list[str],  # noqa: ARG001
) -> None:
    """Dedup is about the day having run, not about what it generated.

    Without this the tick loop would re-enter a free owner's chain every five minutes
    for the rest of their day — cheap, but it would re-run correlate ~150 times and
    burn the scheduler's attempt budget on a chain that succeeded.
    """
    monkeypatch.setattr(chain, "is_premium", lambda _user_id: False)
    _stub_steps(monkeypatch)

    chain.run_chain(_OWNER, _TZ, DAY)
    assert chain.run_chain(_OWNER, _TZ, DAY).deduped is True
