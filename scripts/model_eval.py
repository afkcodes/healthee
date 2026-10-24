#!/usr/bin/env python3
"""Compare LLM models across the WHOLE grounded pipeline, side by side.

For every model given, each representative prompt runs through the real path —
context build -> manifest retrieval -> the LLM -> the BLOCKING validator — and a
recs generation runs through the ``response_format="json"`` seam. Reports, per
model: latency, refused/validated, the citations it used, and the answer text.
This is how we decide whether a cheaper/pricier model earns its place (the
validator enforces the honesty contract independently of the model, so a weaker
model simply fails + falls back — it can't lower the bar).

Makes REAL, paid OpenRouter calls and seeds a throwaway dataset into a reachable
TimescaleDB — a dev tool, never run in CI.

Usage (run under the server venv so ``healthee`` + deps resolve):

    cd apps/server && \\
      POSTGRES_HOST=localhost POSTGRES_PORT=5544 POSTGRES_DB=healthee \\
      POSTGRES_USER=healthee POSTGRES_PASSWORD=<pw> REALTIME_INGEST_TOKEN=x \\
      uv run python ../../scripts/model_eval.py \\
        <provider>/<model-a> <provider>/<model-b>

``OPENROUTER_API_KEY`` (+ the POSTGRES_* vars) may instead live in
``apps/server/.env``. With no model args it runs the env-configured DEFAULT_MODEL.
"""

from __future__ import annotations

import sys
import time
from pathlib import Path

# Make apps/server importable (the seed helpers live under tests/) when this is
# run via `uv run` from apps/server. `healthee` itself resolves via the venv.
_APPS_SERVER = Path(__file__).resolve().parents[1] / "apps" / "server"
if str(_APPS_SERVER) not in sys.path:
    sys.path.insert(0, str(_APPS_SERVER))

from healthee.core import db as db_module
from healthee.core.config import get_settings
from healthee.core.tenancy import (
    SENTINEL_TZ,
    SENTINEL_USER_ID,
    user_today,
)
from healthee.insights.grounded import grounded_ask
from healthee.jobs.coach_inputs import read_inputs
from healthee.jobs.coach_llm import propose
from healthee.jobs.coach_task import WEEKLY_TASK
from tests.contracts.seed import seed_all

# (question, metrics-in-play) — a trend read, and a "train or rest?" that should
# trigger honest-when-uncertain behaviour.
QUESTIONS: list[tuple[str, list[str]]] = [
    (
        (
            "How are my recovery and sleep trending over the last two weeks, and what is "
            "the single most important thing I should focus on? Be specific to my numbers."
        ),
        ["recovery_score", "hrv_sleep_avg", "sleep_health_score_4dim", "rhr_daily"],
    ),
    (
        (
            "Should I train hard today or take it easy? Base it strictly on my recovery "
            "and readiness, and say plainly if the data doesn't support a confident call."
        ),
        ["recovery_score", "cardio_load", "hrv_sleep_avg"],
    ),
]


def _rule(char: str = "=") -> str:
    return char * 78


def _run_prose(question: str, metrics: list[str], models: list[str]) -> None:
    print("\n" + _rule())
    print("Q:", question)
    print(_rule())
    for model in models:
        t0 = time.perf_counter()
        try:
            r = grounded_ask(question, metrics=metrics, context_days=14, model=model)
        except Exception as exc:  # noqa: BLE001 — report per-model failure, keep the run going
            print(f"\n> {model}   ERROR: {type(exc).__name__}: {exc}")
            continue
        ms = (time.perf_counter() - t0) * 1000
        print(f"\n> {model}   ({ms:.0f} ms)")
        print(
            f"  refused={r.refused}  validated={r.validated}  "
            f"grade_floor={r.grade_floor}  citations={r.citations}"
        )
        print("  " + "\n  ".join(r.text.strip().splitlines()))


def _run_coach(models: list[str]) -> None:
    print("\n" + _rule())
    print("COACH (JSON seam) — the weekly answer per model (nothing is stored)")
    print(_rule())
    inputs = read_inputs(SENTINEL_USER_ID, SENTINEL_TZ, user_today(SENTINEL_TZ))
    question = f"{WEEKLY_TASK}\n# SIGNALS\n\n{inputs.text}"
    for model in models:
        t0 = time.perf_counter()
        try:
            week = propose(
                question, SENTINEL_USER_ID, SENTINEL_TZ, weekly=True, model=model
            )
        except Exception as exc:  # noqa: BLE001 — report per-model failure, keep going
            print(f"\n> {model}   ERROR: {type(exc).__name__}: {exc}")
            continue
        ms = (time.perf_counter() - t0) * 1000
        print(f"\n> {model}   ({ms:.0f} ms)  usable={week is not None}")


def main(argv: list[str]) -> None:
    models = argv or [get_settings().default_model]
    print(f"models: {models}\nseeding local DB...")
    db_module.close_pool()
    seed_all()
    for question, metrics in QUESTIONS:
        _run_prose(question, metrics, models)
    _run_coach(models)
    db_module.close_pool()
    print("\ndone.")


if __name__ == "__main__":
    main(sys.argv[1:])
