"""The jobs half of the invariant: a free owner's nightly chain spends ZERO tokens.

This is #48 — the cost hole — measured end to end against a real database, the real
``run_chain``, and a stubbed model whose CALL COUNT is the assertion. ``PRICING.md``
§6.1: at 5 % conversion each premium user carries ~19 free ones, so a chain that
generated for everybody would put the free tier's marginal cost above the premium
tier's profit.

Why the call count and not the step statuses: an implementation that ran ``recs``,
``warm`` and ``briefing`` and threw their output away would report the same ``skipped``
outcomes while spending exactly the money this exists to save. ``tests/jobs/
test_chain_supervision.py`` pins the control flow with stubbed steps; this pins the
SPEND with real ones.
"""

from __future__ import annotations

import json
from collections.abc import Callable, Iterator

import pytest
from tests.conftest import entitle
from tests.contracts.seed import seed_all
from tests.insights._stub import StubLLM

from healthee.core.tenancy import SENTINEL_TZ, SENTINEL_USER_ID, user_today
from healthee.insights import coaching, grounded
from healthee.jobs import briefing, chain, coach_weekly

pytestmark = [
    pytest.mark.integration,
    # `seed_owner_b` provisions owner B and nothing removed it. `--user`-less ops
    # tooling walks every active owner it finds, so the stray is not free (#119).
    pytest.mark.usefixtures("owner_sweep"),
]


@pytest.fixture
def chain_bed(db: None, monkeypatch: pytest.MonkeyPatch) -> Iterator[StubLLM]:  # noqa: ARG001
    """A seeded owner, a counting LLM stub, and Telegram silenced."""
    client = StubLLM()
    monkeypatch.setattr(grounded, "get_client", lambda: client)
    monkeypatch.setattr(chain, "send_telegram", lambda *_a, **_kw: True)
    monkeypatch.setattr(briefing, "send_telegram", lambda *_a, **_kw: True)
    seed_all()
    yield client


def _llm_steps_due() -> set[str]:
    """The LLM steps this owner's chain runs today (the weekly review is Sunday-only)."""
    return {*chain._coach_names(user_today(SENTINEL_TZ)), "warm", "briefing"}


def _run(client: StubLLM) -> chain.ChainResult:
    """One forced chain for the seeded owner. ``force`` because ``seed_all`` may have
    left the day's dedup marker behind and the point here is what a RUN costs."""
    return chain.run_chain(SENTINEL_USER_ID, SENTINEL_TZ, client=client, force=True)


def test_a_free_owners_chain_spends_zero_llm_calls(chain_bed: StubLLM) -> None:
    """The whole point of 6.6a, asserted as a number."""
    entitle(SENTINEL_USER_ID, premium=False)

    result = _run(chain_bed)

    assert chain_bed.calls == 0, f"a free owner's chain made {chain_bed.calls} model calls"
    skipped = {s.name for s in result.steps if s.status == "skipped"}
    assert skipped == _llm_steps_due()


def test_a_premium_owners_chain_does_spend(chain_bed: StubLLM) -> None:
    """The control. Without it, "zero calls" would also pass against a broken chain."""
    entitle(SENTINEL_USER_ID, premium=True)

    result = _run(chain_bed)

    assert chain_bed.calls > 0, "a premium owner's chain generated nothing"
    ran = {s.name for s in result.steps if s.status == "ok"}
    assert _llm_steps_due() <= ran


def test_the_deterministic_steps_run_for_a_free_owner_against_a_real_db(
    chain_bed: StubLLM,
) -> None:
    """`correlate` is FREE tier and costs no tokens — skipping it would remove a feature.

    Asserted against the real engine rather than a stub: the reason `correlate` is not
    gated is that it is deterministic, and this is what shows it truly is (it completes
    with the model never called).
    """
    entitle(SENTINEL_USER_ID, premium=False)

    result = _run(chain_bed)

    statuses = {s.name: s.status for s in result.steps}
    assert statuses["correlate"] == "ok"
    assert statuses["challenges"] == "ok"
    assert chain_bed.calls == 0


def test_a_free_owner_gets_no_warmed_coaching_line_to_read_later(
    chain_bed: StubLLM,
) -> None:
    """§12.7's "read pre-generated AI content from another path" loophole, in the jobs.

    The endpoint gate is not the only thing standing between a free owner and an AI
    line: the line is never written in the first place, so there is nothing cached for
    any path to serve.
    """
    entitle(SENTINEL_USER_ID, premium=False)
    _run(chain_bed)

    assert coaching.cached_line(SENTINEL_USER_ID, SENTINEL_TZ, coaching.DAILY_ACTION_KEY) is None
    assert coaching.cached_line(SENTINEL_USER_ID, SENTINEL_TZ, coaching.SLEEP_TONIGHT_KEY) is None


def test_a_free_owner_gets_no_recommendation_rows(chain_bed: StubLLM) -> None:
    """The same, for the rows `/api/today` reads. Nothing stored ⇒ nothing to leak."""
    entitle(SENTINEL_USER_ID, premium=False)
    before = _rec_count()
    _run(chain_bed)
    assert _rec_count() == before


def _rec_count() -> int:
    from healthee.core.db import tenant_transaction

    with tenant_transaction(SENTINEL_USER_ID) as cur:
        cur.execute("SELECT count(*) FROM recommendation WHERE user_id = %s", (SENTINEL_USER_ID,))
        row = cur.fetchone()
    return int(row[0]) if row else 0


def test_two_owners_with_opposite_entitlement_do_not_leak_into_each_other(
    chain_bed: StubLLM,
    make_owner_b: Callable[[], None],
) -> None:
    """A's lock must not stop B's chain, and B's entitlement must not unlock A's.

    Two-sided by design (MULTI_USER.md §10): a one-sided check passes identically
    against an implementation that reads ONE owner's subscription for everybody.
    """
    make_owner_b()
    from tests.contracts.seed_owner_b import OWNER_B, OWNER_B_TZ

    entitle(SENTINEL_USER_ID, premium=False)
    entitle(OWNER_B, premium=True)

    free = chain.run_chain(SENTINEL_USER_ID, SENTINEL_TZ, client=chain_bed, force=True)
    after_free = chain_bed.calls
    paid = chain.run_chain(OWNER_B, OWNER_B_TZ, client=chain_bed, force=True)

    assert after_free == 0, "the FREE owner's chain spent tokens"
    assert chain_bed.calls > 0, "the PREMIUM owner's chain spent nothing"
    assert {s.name for s in free.steps if s.status == "skipped"} == _llm_steps_due()
    assert _llm_steps_due() <= {s.name for s in paid.steps if s.status == "ok"}


@pytest.fixture
def make_owner_b() -> Callable[[], None]:
    def seed() -> None:
        from tests.contracts.seed_owner_b import seed_owner_b

        seed_owner_b()

    return seed


def test_weekly_coach_generation_is_a_step_that_actually_costs(
    chain_bed: StubLLM, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Guards the premise of the skip: the weekly coach really is an LLM step.

    If `generate_week` ever stopped calling a model, gating it would be cost theatre —
    and this file's central assertion would keep passing while protecting nothing.
    """
    from tests.jobs._coach_fixtures import answer

    entitle(SENTINEL_USER_ID, premium=True)
    stub = StubLLM(json_text=json.dumps(answer(job={"target": 20})))
    monkeypatch.setattr(grounded, "get_client", lambda: stub)
    coach_weekly.generate_week(SENTINEL_USER_ID, SENTINEL_TZ, client=stub)
    assert stub.calls > 0
