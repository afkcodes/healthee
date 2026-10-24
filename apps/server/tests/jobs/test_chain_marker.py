"""The chain's dedup marker against a real database: one row per owner, forever.

`tests/jobs/test_chain_supervision.py` stubs the marker to keep the branching tests
pure control-flow, so nothing there can see the marker's actual SHAPE. That shape is
the subject here, and it is a correctness question twice over:

  * **idempotence** — the marker is the whole reason a five-minute tick is safe
    (`MULTI_USER.md` §6: "Idempotence is the marker's job, not the loop's"), so a
    change to how it is stored has to be re-proved per owner, per THEIR local day,
    and across a day boundary;
  * **growth** — the old encoding put the day in the KEY and left one row per owner
    per day in `kv` forever (16 of them live on prod, one per day since the cutover).
    The row COUNT is therefore an assertion, not a detail: it is the whole fix.

Auto-skips without a reachable TimescaleDB (same policy as the other integration
tests).
"""

from __future__ import annotations

from collections.abc import Iterator
from datetime import date, timedelta
from uuid import UUID

import pytest

from healthee.core.db import admin_connection, tenant_transaction
from healthee.core.tenancy import SENTINEL_USER_ID
from healthee.db import migrate
from healthee.jobs import chain

pytestmark = pytest.mark.integration

_DAY = date(2026, 7, 15)
_TZ = "Asia/Kolkata"

# A second owner, created here rather than reusing the contract seed: this file needs
# two tenants and NO data at all, so seeding a whole second person's health history
# would be a slower test asserting the same thing.
_OWNER_B = UUID("77777777-0000-4000-8000-000000000077")


@pytest.fixture
def two_owners(db: None) -> Iterator[None]:  # noqa: ARG001 — gates on DB reachability
    """The sentinel plus one more owner, both starting with an empty `kv`.

    ADMIN for the setup/teardown: `app_user` is not a tenant table, and the teardown
    must remove rows written under two different owners — which one RLS-scoped
    transaction cannot see, let alone delete.
    """
    migrate.apply_migrations()
    with admin_connection() as conn, conn.cursor() as cur:
        cur.execute(
            "INSERT INTO app_user (id, email, timezone) VALUES (%s, %s, %s) "
            "ON CONFLICT (id) DO NOTHING",
            (_OWNER_B, "marker-b@example.test", "America/Chicago"),
        )
        cur.execute("DELETE FROM kv WHERE user_id IN (%s, %s)", (SENTINEL_USER_ID, _OWNER_B))
    yield
    with admin_connection() as conn, conn.cursor() as cur:
        cur.execute("DELETE FROM kv WHERE user_id IN (%s, %s)", (SENTINEL_USER_ID, _OWNER_B))
        cur.execute("DELETE FROM app_user WHERE id = %s", (_OWNER_B,))


def _marker_rows(user_id: UUID) -> list[tuple[str, str]]:
    """Every `kv` row this owner holds for the chain marker — key and value."""
    with tenant_transaction(user_id) as cur:
        cur.execute(
            "SELECT key, value FROM kv WHERE user_id = %s AND key LIKE 'job:chain%%' ORDER BY key",
            (user_id,),
        )
        return [(row[0], row[1]) for row in cur.fetchall()]


# ── idempotence: unchanged by the new shape ───────────────────────────────────


def test_the_same_local_day_twice_is_a_dedup(two_owners: None) -> None:  # noqa: ARG001
    """The tick's safety property: mark it, and asking again for that day says done."""
    assert chain._chain_done(SENTINEL_USER_ID, _DAY) is False
    chain._mark_chain_done(SENTINEL_USER_ID, _DAY)
    assert chain._chain_done(SENTINEL_USER_ID, _DAY) is True
    chain._mark_chain_done(SENTINEL_USER_ID, _DAY)  # the upsert is itself idempotent
    assert chain._chain_done(SENTINEL_USER_ID, _DAY) is True


def test_the_next_local_day_fires(two_owners: None) -> None:  # noqa: ARG001
    """The day boundary: yesterday's marker must not dedup today away.

    This is the failure that would be invisible until an owner silently stopped
    getting a briefing, so it is asserted in both directions — the new day is not
    deduped, and marking it does not un-dedup the old one.
    """
    chain._mark_chain_done(SENTINEL_USER_ID, _DAY)
    assert chain._chain_done(SENTINEL_USER_ID, _DAY + timedelta(days=1)) is False
    chain._mark_chain_done(SENTINEL_USER_ID, _DAY + timedelta(days=1))
    assert chain._chain_done(SENTINEL_USER_ID, _DAY + timedelta(days=1)) is True
    assert chain._chain_done(SENTINEL_USER_ID, _DAY) is True


def test_two_owners_dedup_independently(two_owners: None) -> None:  # noqa: ARG001
    """One owner's completed chain must never dedup another's away (the folded kv PK).

    With the day gone from the key, the OWNER is the only thing separating the two
    rows — so this stops being a property of the key string and becomes a property of
    the primary key, and it is worth re-proving on the real table.
    """
    chain._mark_chain_done(SENTINEL_USER_ID, _DAY)
    assert chain._chain_done(_OWNER_B, _DAY) is False
    chain._mark_chain_done(_OWNER_B, _DAY)
    assert [key for key, _ in _marker_rows(_OWNER_B)] == ["job:chain_done"]
    assert chain._chain_done(SENTINEL_USER_ID, _DAY) is True


# ── growth: the whole point ───────────────────────────────────────────────────


def test_a_year_of_days_leaves_one_row_per_owner(two_owners: None) -> None:  # noqa: ARG001
    """400 local days, two owners, two rows. The old shape would leave 800.

    The count IS the fix (`0012` folded prod's 16 accumulated rows into one). A marker
    that still deduped correctly while growing a row a day would pass every test above
    and be exactly the bug this file was written for.
    """
    for offset in range(400):
        day = _DAY + timedelta(days=offset)
        chain._mark_chain_done(SENTINEL_USER_ID, day)
        chain._mark_chain_done(_OWNER_B, day)

    last = (_DAY + timedelta(days=399)).isoformat()
    assert _marker_rows(SENTINEL_USER_ID) == [("job:chain_done", last)]
    assert _marker_rows(_OWNER_B) == [("job:chain_done", last)]


def test_the_marker_never_moves_backwards(two_owners: None) -> None:  # noqa: ARG001
    """A forced re-run of an OLD day must not un-dedup the newest one.

    `run_chain(..., day=<past>, force=True)` is a legitimate call (the only thing that
    ever wants an earlier day), and with a plain overwrite it would drop the mark back
    to that date — so the next tick would re-run today's chain, re-spending its LLM
    calls and re-sending a briefing that had already gone out.
    """
    newest = _DAY + timedelta(days=10)
    chain._mark_chain_done(SENTINEL_USER_ID, newest)
    chain._mark_chain_done(SENTINEL_USER_ID, _DAY)

    assert _marker_rows(SENTINEL_USER_ID) == [("job:chain_done", newest.isoformat())]
    assert chain._chain_done(SENTINEL_USER_ID, newest) is True
    # And an earlier day reads as covered: the marker is a high-water mark, so the
    # chain "has run through" it — re-generating a past day is `force`'s job, not a
    # thing the tick should ever decide to do on its own.
    assert chain._chain_done(SENTINEL_USER_ID, _DAY) is True


# ── end to end: the real marker, through `run_chain` ──────────────────────────


def _stub_steps(monkeypatch: pytest.MonkeyPatch) -> dict[str, int]:
    """Stub every step (and entitlement); the MARKER stays real — it is the subject."""
    calls = {"challenges": 0, "correlate": 0, "coach_today": 0, "warm": 0, "briefing": 0}
    monkeypatch.setattr(chain, "is_premium", lambda _user_id: True)

    def make(name: str):
        def step(_day: date, _user_id: UUID, _tz: str, *, client=None) -> dict:  # noqa: ARG001
            calls[name] += 1
            return {"ran": name}

        return step

    for name in calls:
        monkeypatch.setattr(chain, f"step_{name}", make(name))
    return calls


def test_a_repeating_tick_runs_the_chain_once_per_owner_per_local_day(
    two_owners: None,  # noqa: ARG001
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The scheduler's contract, end to end on the real `kv`: tick, tick, tick — once.

    Then the owner's next local day fires, and B's day is untouched by A's. The row
    count is asserted at the end because that is the invariant a future marker change
    is most likely to break silently.
    """
    calls = _stub_steps(monkeypatch)

    assert chain.run_chain(SENTINEL_USER_ID, _TZ, _DAY).deduped is False
    assert chain.run_chain(SENTINEL_USER_ID, _TZ, _DAY).deduped is True
    assert chain.run_chain(SENTINEL_USER_ID, _TZ, _DAY).deduped is True
    assert calls["briefing"] == 1, "the chain re-ran inside one local day"

    tomorrow = _DAY + timedelta(days=1)
    assert chain.run_chain(SENTINEL_USER_ID, _TZ, tomorrow).deduped is False
    assert calls["briefing"] == 2

    assert chain.run_chain(_OWNER_B, "America/Chicago", _DAY).deduped is False
    assert calls["briefing"] == 3

    assert _marker_rows(SENTINEL_USER_ID) == [("job:chain_done", tomorrow.isoformat())]
    assert _marker_rows(_OWNER_B) == [("job:chain_done", _DAY.isoformat())]


# ── `0012`: what happens to the rows prod has already accumulated ─────────────
#
# In THIS file rather than a schema-test module of its own, because it needs exactly
# the same two-owner-with-empty-kv bed as everything above and the fold is the other
# half of the same fix. The statements are read from the migration file and replayed
# on an admin connection: the runner has already recorded `0012` as applied, so
# `apply_migrations()` would (correctly) do nothing here.


def _apply_0012() -> None:
    """Replay `0012`'s statements — the migration's own SQL, not a copy of it."""
    path = next(p for p in migrate._migration_files() if p.stem == "0012_chain_marker_one_row")
    with admin_connection() as conn, conn.cursor() as cur:
        for statement in migrate._split_statements(path.read_text()):
            cur.execute(statement)  # type: ignore[arg-type] — trusted, from the repo


def test_0012_folds_the_accumulated_rows_into_one_per_owner(
    two_owners: None,  # noqa: ARG001
) -> None:
    """Prod's 16 dated rows (per owner) become one, carrying the LATEST day.

    The latest, not any of them: the new marker means "the chain has run THROUGH this
    day", so folding to an older date would re-run — and re-send the briefing for —
    days that had already completed.
    """
    with admin_connection() as conn, conn.cursor() as cur:
        for owner, days in ((SENTINEL_USER_ID, (17, 18, 19)), (_OWNER_B, (18, 30))):
            for offset in days:
                stamp = (_DAY + timedelta(days=offset)).isoformat()
                cur.execute(
                    "INSERT INTO kv (user_id, key, value) VALUES (%s, %s, %s)",
                    (owner, f"job:chain_done:{stamp}", stamp),
                )

    _apply_0012()

    assert _marker_rows(SENTINEL_USER_ID) == [
        ("job:chain_done", (_DAY + timedelta(days=19)).isoformat())
    ]
    assert _marker_rows(_OWNER_B) == [("job:chain_done", (_DAY + timedelta(days=30)).isoformat())]


def test_0012_is_replay_safe_and_never_lowers_a_marker(two_owners: None) -> None:  # noqa: ARG001
    """Running it twice, and running it over a marker the new code has already advanced.

    Both are the same hazard: `deploy.sh` migrates with api+scheduler STOPPED, but a
    re-run (or a half-finished deploy someone repeats) must not drag the mark back to
    the last dated row and hand the owner a second chain for a day already done.
    """
    stale = (_DAY - timedelta(days=5)).isoformat()
    with admin_connection() as conn, conn.cursor() as cur:
        cur.execute(
            "INSERT INTO kv (user_id, key, value) VALUES (%s, %s, %s)",
            (SENTINEL_USER_ID, f"job:chain_done:{stale}", stale),
        )
    chain._mark_chain_done(SENTINEL_USER_ID, _DAY)  # the new code, already running

    _apply_0012()
    _apply_0012()

    assert _marker_rows(SENTINEL_USER_ID) == [("job:chain_done", _DAY.isoformat())]
