"""What the dedup marker means when a step fails — one case per step (B1).

The marker used to advance on ``correlate`` alone, under a comment describing "the
generating steps" that silently annexed the two steps above it and the one below. So:

* a failed ``illness`` was recorded as done and never retried — and
  ``derive_illness_flag`` is not part of ``derive_batch``, so ``db/rederive.py`` cannot
  rebuild what that lost. The day's answer was gone permanently;
* a failed ``challenges`` was likewise marked done and simply skipped;
* ``briefing`` ran AFTER the mark was written, so a briefing failure could never be
  retried however the rule above was written.

``tests/jobs/test_chain_supervision.py`` proves each step's failure is *reported*;
this file proves it is *not forgotten*. They are separate files because they answer
different questions and because the supervision file is already at the size gate.

Same pure control-flow bed as its sibling: every step and the marker are stubbed, so
these assert branching and nothing else.
"""

from __future__ import annotations

from collections.abc import Iterator
from datetime import date
from uuid import UUID

import pytest

from healthee.jobs import chain

DAY = date(2026, 7, 15)
_OWNER = UUID("55555555-5555-5555-5555-555555555555")
_TZ = "Asia/Kolkata"

# Every step, so a seventh added to the chain has to be added here too.
_STEPS: tuple[str, ...] = ("illness", "challenges", "correlate", "coach_today", "warm", "briefing")


@pytest.fixture
def marker(monkeypatch: pytest.MonkeyPatch) -> Iterator[set[str]]:
    """Back the dedup marker in memory and swallow the Telegram alerts."""
    monkeypatch.setattr(chain, "send_telegram", lambda *_args, **_kw: True)
    monkeypatch.setattr(chain, "is_premium", lambda _user_id: True)
    marked: set[str] = set()
    monkeypatch.setattr(chain, "_chain_done", lambda _user_id, day: day.isoformat() in marked)
    monkeypatch.setattr(
        chain, "_mark_chain_done", lambda _user_id, day: marked.add(day.isoformat())
    )
    yield marked


def _stub_steps(monkeypatch: pytest.MonkeyPatch, **raisers: bool) -> dict[str, int]:
    """Stub every step; names in ``raisers`` raise. Returns a per-step call counter."""
    calls = dict.fromkeys(_STEPS, 0)

    def make(name: str):
        def step(_day: date, _user_id: UUID, _tz: str, *, client=None) -> dict:  # noqa: ARG001
            calls[name] += 1
            if raisers.get(name):
                raise RuntimeError(f"{name} boom")
            return {"ran": name}

        return step

    for name in _STEPS:
        monkeypatch.setattr(chain, f"step_{name}", make(name))
    return calls


@pytest.mark.parametrize("failing", _STEPS)
def test_a_failed_step_leaves_the_day_unmarked_and_the_next_tick_retries(
    monkeypatch: pytest.MonkeyPatch, marker: set[str], failing: str
) -> None:
    """One case per step, because *which* steps gate the mark is exactly what was wrong.

    Asserted through ``run_chain`` twice as well as on the marker: the property that
    matters to the owner is that the day is RE-RUN, and a marker written under a key
    nothing reads would satisfy an internals assertion while still costing them the day.
    """
    calls = _stub_steps(monkeypatch, **{failing: True})

    first = chain.run_chain(_OWNER, _TZ, DAY)
    assert first.deduped is False
    assert {s.name: s.status for s in first.steps}[failing] == "failed"
    assert marker == set(), f"a failed '{failing}' marked the day done"

    second = chain.run_chain(_OWNER, _TZ, DAY)
    assert second.deduped is False, f"a failed '{failing}' was never retried"
    assert calls[failing] == 2


def test_a_failed_warm_still_does_not_abort_the_run(
    monkeypatch: pytest.MonkeyPatch,
    marker: set[str],  # noqa: ARG001
) -> None:
    """Non-fatal is about the RUN, not about the mark, and both halves have to hold.

    ``warm`` failing must not cost the owner their briefing on this tick — that is what
    "non-fatal" has always meant here — and it must not be recorded as a completed day
    either, or the dead coaching line stays null until tomorrow with nobody retrying it.
    """
    calls = _stub_steps(monkeypatch, warm=True)
    result = chain.run_chain(_OWNER, _TZ, DAY)

    statuses = {s.name: s.status for s in result.steps}
    assert (statuses["warm"], statuses["briefing"]) == ("failed", "ok")
    assert calls["briefing"] == 1
    assert chain.run_chain(_OWNER, _TZ, DAY).deduped is False


def test_a_clean_run_marks_the_day_exactly_once(
    monkeypatch: pytest.MonkeyPatch, marker: set[str]
) -> None:
    """The other half of the rule: nothing failed, so the day is done and stays done."""
    calls = _stub_steps(monkeypatch)

    assert chain.run_chain(_OWNER, _TZ, DAY).deduped is False
    assert marker == {DAY.isoformat()}
    assert chain.run_chain(_OWNER, _TZ, DAY).deduped is True
    assert calls["briefing"] == 1


def test_a_skipped_step_is_not_a_failure_and_still_marks(
    monkeypatch: pytest.MonkeyPatch, marker: set[str]
) -> None:
    """A free owner's three LLM steps are ``skipped``, which is entitlement, not a fault.

    Reading a skip as a failure would re-enter their chain every five minutes for the
    rest of their local day, burning the scheduler's attempt budget on a chain that
    succeeded at everything it was allowed to do.
    """
    monkeypatch.setattr(chain, "is_premium", lambda _user_id: False)
    _stub_steps(monkeypatch)

    result = chain.run_chain(_OWNER, _TZ, DAY)

    assert {s.status for s in result.steps} == {"ok", "skipped"}
    assert marker == {DAY.isoformat()}


def test_the_mark_is_written_after_the_last_step(
    monkeypatch: pytest.MonkeyPatch,
    marker: set[str],  # noqa: ARG001
) -> None:
    """Ordering, asserted rather than trusted.

    The mark used to sit ABOVE ``briefing``, which made a briefing failure unretryable
    *by construction* — no rule about which steps gate the mark could have saved it.
    Recording when ``_mark_chain_done`` fires relative to the last step is the only
    thing that catches a future edit moving it back up.
    """
    order: list[str] = []
    calls = _stub_steps(monkeypatch)
    stubbed_briefing = chain.step_briefing

    def watched(day: date, user_id: UUID, tz: str, *, client=None) -> dict:
        order.append("briefing")
        return stubbed_briefing(day, user_id, tz, client=client)

    monkeypatch.setattr(chain, "step_briefing", watched)
    monkeypatch.setattr(chain, "_mark_chain_done", lambda *_args: order.append("mark"))

    chain.run_chain(_OWNER, _TZ, DAY)

    assert calls["briefing"] == 1
    assert order == ["briefing", "mark"]
