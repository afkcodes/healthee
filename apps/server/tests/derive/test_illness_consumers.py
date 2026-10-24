"""The four dormant consumers, driven by a flag the PRODUCER wrote.

Every one of these read paths shipped, was reviewed, and has never once seen a real
row — the table only ever held rows a test put there by hand. So each assertion here is
of the form "run the producer, then ask the consumer", never "insert a flag, then ask
the consumer": a fixture that writes the row itself cannot tell you the producer's
output has the shape the consumer expects.

The four:
  * ``read/health_metrics.illness_flag_payload`` — the Today pill and its deterministic
    framing sentence;
  * ``read/recovery.recovery_score_payload`` — the guidance override (C3's fix);
  * ``challenges/levers.analyse`` — [[recovery_readiness]] D7's hard training override;
  * ``challenges/confounds.illness_days`` — the outcome ledger's illness-day count.

Plus the one that is not a consumer but a policy: an UNENTITLED owner's chain must still
run the step (6.6a's gate is live, ``PRICING.md`` §1a never paywalls safety).

Anchored on the owner's REAL local today, because three of these five read the wall
clock — an active flag is one within ``_ILLNESS_ACTIVE_DAYS`` of *now*, and a fixed date
would make them assert nothing.
"""

from __future__ import annotations

from collections.abc import Iterator
from datetime import date, timedelta

import pytest
from tests.conftest import entitle
from tests.derive import _illness_seed as seed

from healthee.challenges import confounds, levers
from healthee.challenges.gen_context import owner_calibrations
from healthee.core.db import tenant_transaction
from healthee.core.tenancy import user_today
from healthee.derive.illness import derive_illness_flag
from healthee.jobs import chain
from healthee.read.health_metrics import active_illness_severity, illness_flag_payload
from healthee.read.recovery import recovery_score_payload
from healthee.read.today import today_snapshot

pytestmark = [
    pytest.mark.integration,
    # This module provisions owners — explicitly, JIT on the first authenticated
    # request, or via `seed_owner_b` — and removed none of them. `--user`-less ops
    # tooling walks every active owner it finds, so the strays are not free (#119).
    pytest.mark.usefixtures("owner_sweep"),
]

TODAY = user_today(seed.TZ)

# The push-style phrasings `read/recovery_guidance.py` must never emit under a flag —
# the same list `tests/read/test_illness_override.py` guards the seeded case with.
_PUSH_PHRASES = ("good day to push", "a harder session", "intervals")


@pytest.fixture
def flagged_owner(db: None) -> Iterator[None]:  # noqa: ARG001 — gates on DB reachability
    """Sixteen steady nights, then two ill ones — a REAL `high` flag for today.

    Two ill nights rather than one so the flag is `sustained`, which is the shape that
    exercises the framing sentence's Smarr/Quer suffix as well as the tier.
    """
    seed.reset()
    entitle(seed.OWNER, premium=True)
    _seed_and_produce(TODAY, ill_nights=2)
    yield
    seed.reset()


def _seed_and_produce(today: date, *, ill_nights: int) -> dict:
    """Seed a history ending at ``today`` and run the producer over it."""
    with tenant_transaction(seed.OWNER) as cur:
        seed.steady_history(cur, seed.OWNER, last_night=today)
        for back in range(ill_nights):
            seed.write_night(
                cur, seed.OWNER, today - timedelta(days=back), rr=seed.ILL_RR, temp_c=seed.ILL_TEMP
            )
    with tenant_transaction(seed.OWNER) as cur:
        return derive_illness_flag(cur, seed.OWNER, seed.TZ, today)


# ── consumer 1: the Today pill ───────────────────────────────────────────────


def test_the_today_pill_renders_from_a_produced_flag(flagged_owner: None) -> None:  # noqa: ARG001
    """The pill that has never appeared in production.

    The framing sentence is asserted on its content, not merely on being non-empty: it
    is the honesty contract in one string — a possibility, never a diagnosis, with the
    two deltas quoted against the window they were actually measured over.
    """
    with tenant_transaction(seed.OWNER) as cur:
        payload = illness_flag_payload(cur, seed.OWNER, seed.TZ)

    assert payload is not None
    assert payload["severity"] == "high"
    assert payload["sustained"] is True
    assert payload["date"] == TODAY.isoformat()
    assert payload["rr_delta_bpm"] == pytest.approx(2.5)
    assert payload["temp_delta_c"] == pytest.approx(0.75)
    assert payload["research_note_ids"] == ["respiratory_rate_normal", "skin_temp_signals"]

    framing = payload["framing"]
    assert framing.startswith("Possible early signal — consider lighter activity today.")
    assert "+2.5 bpm vs your 14-day baseline" in framing
    assert "+0.75°C" in framing
    assert "Smarr 2020 / Quer 2021 pattern" in framing
    assert framing.endswith("Not a diagnosis.")
    for banned in ("rest today", "you're sick", "you are sick", "fever"):
        assert banned not in framing.lower(), f"framing said {banned!r} — it is not a diagnosis"


def test_the_flag_reaches_the_assembled_today_payload(flagged_owner: None) -> None:  # noqa: ARG001
    """The pill is only real if it survives the aggregator that actually serves it."""
    with tenant_transaction(seed.OWNER) as cur:
        snapshot = today_snapshot(cur, seed.OWNER, seed.TZ)
    assert snapshot["illness_flag"] is not None
    assert snapshot["illness_flag"]["severity"] == "high"


# ── consumer 2: the recovery-guidance override ───────────────────────────────


def test_a_produced_flag_overrides_push_style_recovery_guidance(
    flagged_owner: None,  # noqa: ARG001
) -> None:
    """C3's fix, with a real row behind it for the first time.

    `recovery_score` is seeded HIGH deliberately: the contradiction this guards against
    is "you're well recovered, go push" printed on the same screen as an illness pill.
    """
    with tenant_transaction(seed.OWNER) as cur:
        cur.execute(
            "INSERT INTO derived_daily (user_id, day, metric, value, flags) "
            "VALUES (%s, %s, 'recovery_score', 82, '{}'::jsonb) "
            "ON CONFLICT (user_id, day, metric) DO UPDATE SET value = EXCLUDED.value",
            (seed.OWNER, TODAY),
        )
        payload = recovery_score_payload(cur, seed.OWNER, seed.TZ)

    assert payload is not None
    guidance = payload["guidance"]
    assert "illness signal is active" in guidance
    for phrase in _PUSH_PHRASES:
        assert phrase not in guidance, f"push guidance survived a produced flag: {guidance!r}"


# ── consumer 3: the hard training override ([[recovery_readiness]] D7) ───────


def test_a_produced_flag_blocks_a_hard_training_lever(flagged_owner: None) -> None:  # noqa: ARG001
    """The safety rule that could never fire, firing.

    ``mvpa_min`` is a hard training lever: offering it asserts "you can absorb more
    load", which is the one claim an active illness signal contradicts. The refusal must
    also SAY which rule produced it — a silent withhold is not an answer (standards
    §Errors), and it is what the generation prompt shows the owner.
    """
    with tenant_transaction(seed.OWNER) as cur:
        assert active_illness_severity(cur, seed.OWNER, seed.TZ, TODAY) == "high"
        calibrations = owner_calibrations(cur, seed.OWNER, seed.TZ, TODAY)
        analysis = levers.analyse(cur, seed.OWNER, seed.TZ, TODAY, calibrations, set())

    assert analysis.illness == "high"
    blocked = analysis.blocked_metrics()
    for metric in ("mvpa_min", "cardio_load", "workouts_week"):
        assert "an illness signal is active" in blocked.get(metric, "")
    # Movement and recovery-SUPPORTING levers are untouched — the rule eases intensity,
    # it does not withhold the things that help someone recover.
    assert "illness" not in blocked.get("steps_total", "")
    assert "illness" not in blocked.get("tst_min", "")


# ── consumer 4: the outcome ledger's confound ────────────────────────────────


def test_the_outcome_ledger_counts_a_produced_illness_day(flagged_owner: None) -> None:  # noqa: ARG001
    """`illness_days` has always returned 0 in production, because the table was empty.

    Both ill nights are produced, so a window covering them counts TWO — a count, not a
    boolean, because "one bad day inside a fortnight" and "ill throughout" are different
    reasons to distrust an outcome.
    """
    _seed_and_produce(TODAY - timedelta(days=1), ill_nights=1)  # yesterday's flag too
    with tenant_transaction(seed.OWNER) as cur:
        inside = confounds.illness_days(cur, seed.OWNER, TODAY - timedelta(days=13), TODAY)
        outside = confounds.illness_days(
            cur, seed.OWNER, TODAY - timedelta(days=40), TODAY - timedelta(days=20)
        )

    assert inside == 2
    assert outside == 0


# ── the policy: safety is never paywalled ────────────────────────────────────


def test_a_free_owners_chain_still_produces_the_flag(
    db: None,  # noqa: ARG001 — gates on DB reachability
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """6.6a's entitlement gate is LIVE, and this step must sit outside it.

    The gate is the real one — ``entitle(premium=False)`` writes the row ``is_premium``
    reads — so this fails the moment someone adds ``illness`` to ``LLM_STEPS`` or moves
    it below the entitlement branch. Only the OTHER steps are stubbed, and only because
    they would need a whole seeded history and a model; the illness step runs for real
    and its row is asserted in the database.
    """
    seed.reset()
    entitle(seed.OWNER, premium=False)
    _seed_and_produce(TODAY, ill_nights=2)
    with tenant_transaction(seed.OWNER) as cur:  # start from no flag, so the row is the chain's
        cur.execute("DELETE FROM illness_flag WHERE user_id = %s", (seed.OWNER,))
    for name in ("challenges", "correlate", "coach_today", "warm", "briefing"):
        monkeypatch.setattr(chain, f"step_{name}", lambda *a, **k: {})  # noqa: ARG005

    result = chain.run_chain(seed.OWNER, seed.TZ, TODAY)

    statuses = {step.name: step.status for step in result.steps}
    assert statuses["illness"] == "ok"
    assert statuses["coach_today"] == "skipped"  # the owner really is unentitled
    with tenant_transaction(seed.OWNER) as cur:
        assert seed.stored_flag(cur, seed.OWNER, TODAY) is not None
        assert active_illness_severity(cur, seed.OWNER, seed.TZ, TODAY) == "high"
    seed.reset()
