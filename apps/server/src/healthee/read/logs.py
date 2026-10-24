"""Manual logging — write (``POST /api/log``) and read (``GET /api/log/recent``).

v2-native writes to ``manual_entry`` / ``weight_log`` (the schema's own tables — no
v1 ``session`` view). Ported from legacy ``_record_log`` / ``log_recent`` with the
swallowed try/except removed: business-rule outcomes return an explicit
``{"ok": False, ...}``; a genuine DB failure propagates (standards §Errors).
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator

from healthee.core.bounds import MAX_MAGNITUDE, assert_plausible_weight_kg, event_instant
from healthee.derive._common import Cur

# The furthest back the log feed will look, whoever asks. Five years, matching
# `/api/history`'s own `Query(ge=1, le=1825)` — the two are the same question ("how much
# of this owner's past may one request reach for") and a second answer to it would be a
# second definition (`PERF_AUDIT.md` B4). The client asks for 7.
MAX_LOG_DAYS = 1825

# Instant kinds (a point event with an amount) vs the two duration kinds.
_INSTANT_KINDS = frozenset(
    {"caffeine", "alcohol", "water", "food", "med", "symptom", "mood", "habit"}
)
_DURATION_KINDS = frozenset({"meditation", "exercise"})

# ── The bounds on owner-authored free text, and why they are HERE ─────────────
#
# ``name``, ``kind``, ``unit`` and ``notes`` are written straight to ``manual_entry``
# and then rendered verbatim into EVERY prompt the product builds
# (``insights/context_sessions.manual_entries_section`` → ``insights/context.build_context``
# → both ``grounded_ask`` and the coach). Standards section 2: "Request bodies are ALWAYS
# pydantic models — validation at the boundary is what keeps a bad value out of the
# science layer." These fields had no bound of any kind, so 200 rows of arbitrarily long
# notes was the whole prompt budget — a denial-of-wallet against a $0.179-a-question
# surface, and the budget the corpus is competing for (``insights/retrieval``: the
# evidence block is "65–83 % of every prompt", and it is the part that gets squeezed).
#
# ⛔ A bound is the ONLY thing done to this text. It is not filtered, rewritten,
# stripped or refused for its content — it is the owner's own journal and their own
# record. What an instruction inside it can and cannot reach is handled where the
# prompt is BUILT (the data fence in ``manual_entries_section``), never in storage.
#
# The numbers are chosen to be invisible to a person writing a journal and fatal to a
# prompt-sized paste: 4,000 characters is roughly 700 words on one entry.
_NOTES_MAX = 4000
_NAME_MAX = 200
_UNIT_MAX = 32

# A logged duration is a person doing something, so a week is already absurd and it is
# still four hundred times the longest meditation anyone records. The bound is here
# because ``record_log`` computes ``ts - timedelta(minutes=mins)``, which raises
# ``OverflowError`` — a 500 for a client's number — on a large enough value.
_MINUTES_MAX = 7 * 24 * 60


class LogRequest(BaseModel):
    """Body of ``POST /api/log`` (mirrors the legacy ``_LogRequest``).

    ## Every number here is bounded, and one of them is a weight

    This model had ``max_length`` on its four strings (see the block above) and NOTHING
    on its four numbers, while ``read/gps_request.py`` — a phone upload of the same
    trust level, one directory over — bounds its payload to the millimetre. The sharp
    one is ``type: "weight"``, which writes ``amount`` into ``weight_log.kg``: a
    ``numeric(5,2)`` column, so an unbounded float was a database error before it was
    anything else, and the value feeds BMI, VO2max and biological age. A NaN or a 1e308
    weight was accepted by this endpoint.

    The bounds come from ``core.bounds``, the same module ``ingest/models.py`` uses, so
    the two routers that write ``weight_log`` cannot disagree about what a weight is.
    """

    model_config = ConfigDict(allow_inf_nan=False)

    type: str = Field(max_length=_NAME_MAX)
    amount: float | None = Field(default=None, ge=-MAX_MAGNITUDE, le=MAX_MAGNITUDE)
    name: str | None = Field(default=None, max_length=_NAME_MAX)
    unit: str | None = Field(default=None, max_length=_UNIT_MAX)
    minutes: int | None = Field(default=None, ge=0, le=_MINUTES_MAX)
    kind: str | None = Field(default=None, max_length=_NAME_MAX)
    at: int | None = None  # epoch ms; None = now
    notes: str | None = Field(default=None, max_length=_NOTES_MAX)

    @field_validator("at")
    @classmethod
    def _at_is_a_plausible_event_instant(cls, at: int | None) -> int | None:
        if at is not None:
            event_instant(at)  # raises MeasurementError (a ValueError) → pydantic 422
        return at


def record_log(cur: Cur, user_id: UUID, req: LogRequest) -> dict:
    """Write one manual log owned by ``user_id``. Returns ``{"ok": True}`` (with
    optional ``discarded``) or an explicit ``{"ok": False, "error": ...}`` for a
    rule outcome."""
    # ``event_instant`` is the ONE conversion, shared with the ingest path: it carries
    # the ms/seconds rule and the range check, so an out-of-range ``at`` is a 422 naming
    # the field rather than an ``OverflowError`` out of a handler.
    ts = event_instant(req.at) if req.at else datetime.now(tz=UTC)
    t = req.type
    if t == "weight":
        # A weight of "nothing given" is not a weight of zero. ``float(req.amount or 0)``
        # stored 0 kg for a body-mass log that forgot its number, which then dated the
        # owner's weight to now and fed BMI, VO2max and biological age an impossible
        # value; the freshness gate cannot help, because the row IS fresh.
        if req.amount is None:
            return {"ok": False, "error": "a weight log needs an amount in kilograms"}
        cur.execute(
            "INSERT INTO weight_log (user_id, ts, kg) VALUES (%s, %s, %s) "
            "ON CONFLICT (user_id, ts) DO UPDATE SET kg = EXCLUDED.kg",
            (user_id, ts, assert_plausible_weight_kg(float(req.amount))),
        )
    elif t in _INSTANT_KINDS:
        cur.execute(
            "INSERT INTO manual_entry (user_id, kind, ts, name, amount, unit, notes) "
            "VALUES (%s,%s,%s,%s,%s,%s,%s)",
            (user_id, t, ts, req.name, req.amount, req.unit, req.notes),
        )
    elif t in _DURATION_KINDS:
        mins = int(req.minutes or 0)
        cur.execute(
            "INSERT INTO manual_entry (user_id, kind, ts, end_ts, name, amount, unit, notes) "
            "VALUES (%s,%s,%s,%s,%s,%s,'min',%s)",
            (user_id, t, ts - timedelta(minutes=mins), ts, req.kind, mins, req.notes),
        )
    elif t in ("fast_start", "fast_end"):
        return _record_fast(cur, user_id, t, ts, req.notes)
    else:
        return {"ok": False, "error": f"unknown log type {t}"}
    return {"ok": True}


def _record_fast(cur: Cur, user_id: UUID, t: str, ts: datetime, notes: str | None) -> dict:
    """Open/close a fasting entry (one open fast at a time; discard <5-min accidents)."""
    if t == "fast_start":
        cur.execute(
            "SELECT 1 FROM manual_entry WHERE user_id=%s AND kind='fasting' "
            "AND end_ts IS NULL LIMIT 1",
            (user_id,),
        )
        if cur.fetchone():
            return {"ok": False, "error": "a fast is already open"}
        cur.execute(
            "INSERT INTO manual_entry (user_id, kind, ts, notes) VALUES (%s, 'fasting', %s, %s)",
            (user_id, ts, notes),
        )
        return {"ok": True}
    cur.execute(
        "SELECT ts FROM manual_entry WHERE user_id=%s AND kind='fasting' AND end_ts IS NULL "
        "ORDER BY ts DESC LIMIT 1",
        (user_id,),
    )
    open_row = cur.fetchone()
    if open_row and (ts - open_row[0]).total_seconds() < 300:
        cur.execute(
            "DELETE FROM manual_entry WHERE user_id=%s AND kind='fasting' AND end_ts IS NULL",
            (user_id,),
        )
        return {"ok": True, "discarded": "fast under 5 minutes — not recorded"}
    cur.execute(
        "UPDATE manual_entry SET end_ts=%s WHERE user_id=%s AND kind='fasting' AND end_ts IS NULL",
        (ts, user_id),
    )
    return {"ok": True}


def log_recent(cur: Cur, user_id: UUID, days: int = 7) -> dict:
    """Recent manual logs + current fasting status (the log feed).

    ``days`` is CLAMPED: it reached the SQL interval straight off the query string
    (`PERF_AUDIT.md` B4). The `LIMIT 80` below already bounded the ANSWER, which is why
    this was never a correctness problem — but it did not bound the SCAN, so a large
    enough `days` widened the range this reads without widening what it returns. Bounding
    the answer and bounding the work are different guarantees and the standards ask for
    the second ("every chart query has a range").
    """
    entries: list[dict] = []
    cur.execute(
        "SELECT id, kind, ts, name, amount, unit, notes FROM manual_entry "
        "WHERE user_id = %s AND kind <> 'fasting' AND ts >= now() - (%s || ' days')::interval "
        "ORDER BY ts DESC LIMIT 80",
        (user_id, max(1, min(days, MAX_LOG_DAYS))),
    )
    for entry_id, k, ts, name, amount, unit, notes in cur.fetchall():
        entries.append(
            {
                # The handle `DELETE /api/log/{id}` takes. Weight rows carry none: they
                # live in `weight_log`, keyed by (user, ts), and the feed shows only the
                # latest — there is nothing to delete by id.
                "id": str(entry_id),
                "type": k,
                "ts": int(ts.timestamp() * 1000),
                "name": name,
                "amount": float(amount) if amount is not None else None,
                "unit": unit,
                "notes": notes,
            }
        )
    cur.execute(
        "SELECT ts, kg FROM weight_log WHERE user_id = %s ORDER BY ts DESC LIMIT 1", (user_id,)
    )
    wr = cur.fetchone()
    if wr:
        entries.append(
            {
                "type": "weight",
                "ts": int(wr[0].timestamp() * 1000),
                "amount": float(wr[1]),
                "unit": "kg",
            }
        )
    entries.sort(key=lambda e: e["ts"], reverse=True)
    return {"entries": entries, "fast": _fast_status(cur, user_id)}


def delete_entry(cur: Cur, user_id: UUID, entry_id: UUID) -> bool:
    """Delete ONE of ``user_id``'s manual log entries. False means no such entry.

    False covers "never existed" and "belongs to someone else" alike, so the caller
    cannot tell which. Fasting rows are excluded: they are not in the feed, so no
    client can hold their id, and an open fast has its own start/end protocol.
    """
    cur.execute(
        "DELETE FROM manual_entry WHERE user_id = %s AND id = %s AND kind <> 'fasting'",
        (user_id, entry_id),
    )
    return cur.rowcount == 1


def _fast_status(cur: Cur, user_id: UUID) -> dict:
    cur.execute(
        "SELECT ts FROM manual_entry WHERE user_id = %s AND kind='fasting' AND end_ts IS NULL "
        "ORDER BY ts DESC LIMIT 1",
        (user_id,),
    )
    r = cur.fetchone()
    if not r:
        return {"open": False}
    mins = int((datetime.now(tz=UTC) - r[0]).total_seconds() // 60)
    return {"open": True, "current": {"duration_min": mins}}
