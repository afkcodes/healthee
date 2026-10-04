"""FastAPI application wiring — construction only.

No business logic and no SQL live here (standards §2: "app.py (wiring only)").
It configures logging, opens/closes the DB pool around the app lifetime, and
mounts the routers. Domain routers are added as later work packages land.

Serve it with:

    uv run uvicorn healthee.api.app:app
"""

from __future__ import annotations

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from healthee.api.routers import (
    activity,
    auth,
    challenges,
    coach,
    daily_action,
    entitlement,
    generation,
    gps,
    health,
    history,
    ingest,
    insights,
    logs,
    map_tiles,
    programs,
    readiness,
    recommendations,
    sleep,
    today,
    workouts,
)
from healthee.core.bounds import MeasurementError
from healthee.core.db import close_pool
from healthee.core.dob import DobError
from healthee.core.entitlement import warn_if_self_host_unlocked
from healthee.core.logging import configure_logging, get_logger, silence_access_log_for
from healthee.core.map_tiles import TILE_PATH_PREFIX
from healthee.mcp.server import mcp_lifespan, mount_mcp

log = get_logger(__name__)


def _dob_error_is_a_client_error(_request: Request, exc: Exception) -> JSONResponse:
    """A rejected `dob` is a 422, wherever the rejection happened (#57).

    `ingest.models.ProfileIn` already 422s the values it can judge, but it runs before
    the owner's timezone is known and so carries a day of slack (`core.dob._TZ_SLACK`).
    A dob inside that slack is rejected later, by the canonical parse inside the upsert,
    and until now that surfaced as a **500** — measured, not inferred: a UTC-midnight
    "tomorrow" from an IST owner returned 500.

    500 is a lie about whose fault it is, and it is the kind of lie that gets a real
    incident mis-triaged. Handling `DobError` specifically — rather than `ValueError`
    around the ingest — is what keeps a genuine internal failure a 500.
    """
    log.info("rejected dob", extra={"error": str(exc)})
    return JSONResponse(status_code=422, content={"detail": str(exc)})


def _measurement_error_is_a_client_error(_request: Request, exc: Exception) -> JSONResponse:
    """A value no measurement can have is a 422, wherever the refusal happened.

    Same argument as `_dob_error_is_a_client_error` above, for the values that arrive
    every minute rather than once. `core.bounds` is called from pydantic validators
    (which already 422) AND from the upsert layer, which re-asserts the bound so a
    non-HTTP caller cannot skip it. The second of those had no handler, so the check
    that exists to stop a bad value would itself have produced a 500 blaming us for a
    client's number.
    """
    log.info("rejected an implausible measurement", extra={"error": str(exc)})
    return JSONResponse(status_code=422, content={"detail": str(exc)})


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    """Startup/shutdown: configure logging on the way up, close the pool on the
    way down. The pool itself opens lazily on first query."""
    configure_logging()
    # Before the first request, and here rather than in `configure_logging`
    # because uvicorn configures its own loggers after ours: a basemap tile path
    # in an access log is a location history, which is what proxying the tiles
    # exists to prevent (core/map_tiles).
    silence_access_log_for(TILE_PATH_PREFIX)
    log.info("healthee server starting")
    warn_if_self_host_unlocked()
    # The MCP session manager must run for the app's life (a mounted SDK app has no
    # lifespan of its own); a no-op when `mcp_enabled` is false.
    async with mcp_lifespan(app):
        yield
    close_pool()
    log.info("healthee server stopped")


def create_app() -> FastAPI:
    """Build the FastAPI app and mount routers. A factory so tests can construct
    isolated instances."""
    app = FastAPI(
        title="Healthee",
        version="0.1.0",
        lifespan=lifespan,
        # ── The interactive docs are OFF, and that is a decision, not a default ──
        #
        # nginx proxies `/` wholesale, so with these left at their defaults a full
        # machine-readable map of a health API — every route, every parameter, every
        # model — was served to anybody who asked, unauthenticated. That was never
        # argued for; it was FastAPI's default surviving into production, and two
        # security reviews raised it.
        #
        # What is lost is a browsable page on the box. `create_app().openapi()` still
        # builds the whole schema in-process, which is what the contract tests actually
        # use, so nothing that verifies the API loses anything. An operator who wants
        # the page runs the app locally.
        #
        # `tests/premium/test_ai_gate.py` used to exclude these four paths from its
        # route walk BY NAME — the only route-walking guard in the repo, with a
        # hard-coded blind spot at exactly the routes that were open by default. With
        # the routes gone the exclusion is gone too, and the blind spot closes with it.
        docs_url=None,
        redoc_url=None,
        openapi_url=None,
    )
    app.add_exception_handler(DobError, _dob_error_is_a_client_error)
    app.add_exception_handler(MeasurementError, _measurement_error_is_a_client_error)
    app.include_router(health.router)
    # …and the dependency-readiness probe beside it. Deliberately NOT the container
    # healthcheck: /healthz is what an orchestrator restarts on, /readyz reports the
    # things (a dead AI layer, an empty balance) that a restart cannot fix.
    app.include_router(readiness.router)
    # WP8 note: the daily chain runs on the scheduler timer (jobs.scheduler).
    # An optional future one-line wire — call jobs.chain.run_chain(day) after a
    # successful ingest push — would make recs refresh event-driven too; the
    # frozen ingest/ router is intentionally left untouched for now.
    app.include_router(ingest.router)
    # WP7 read routers (today / sleep / activity / workouts / history+profile / logs / gps).
    for read_router in (today, sleep, activity, workouts, history, logs, gps):
        app.include_router(read_router.router)
    # WP5 grounded insight surfaces (sleep/activity/metric/workout/notable) + coach.
    app.include_router(insights.router)
    app.include_router(coach.router)
    # WP-C2 challenges: the feed, the lifecycle writes, and the outcome ledger.
    # Deterministic only — generation (WP-C3) and the coach tools (WP-C5) are later.
    # Premium in full since 6.6a: every handler takes a gated identity (api.gate).
    app.include_router(recommendations.router)
    app.include_router(challenges.router)
    # WP-C4 programs: the multi-week ladder over those challenges. Mounted beside
    # them rather than inside them because a rung's own lifecycle is the challenges
    # router's (adapt, abandon), while the ladder's is this one's.
    app.include_router(programs.router)
    # WP-C3b/C4b generation: the ONE place a challenge or a ladder can be authored, and
    # the only endpoints in this app that call a model on the request path. Mounted after
    # the two feeds because it is a different concern (spend, not lifecycle) — its own
    # router says why at length.
    app.include_router(generation.router)
    # Phase 6.1 identity — Supabase-JWT-authed /api/me + /api/device. Additive:
    # existing routers keep their shared-token guard until the 6.4 flip.
    app.include_router(auth.router)
    # 6.6a entitlement — the one endpoint whose subject is the paywall, deliberately
    # ungated (a locked-out owner is exactly who needs to read it).
    app.include_router(entitlement.router)
    # 6.6a-2 the metered free allowance — the ONE surface it needed: a free owner's daily
    # action line is never generated by the chain, so revealing it means generating it,
    # which is a POST and not a read. Mounted after `today` because it is a different
    # concern (spend, not read) on the same subject.
    app.include_router(daily_action.router)
    # The basemap proxy. Mounted last because it is the only router that serves
    # bytes rather than JSON, and the only one whose request PATH is personal —
    # `api/routers/map_tiles.py` says what follows from that.
    app.include_router(map_tiles.router)
    # The MCP endpoint, last: its own bearer check (device token) runs inside the mount,
    # and it is absent entirely when `mcp_enabled` is false. See `healthee.mcp.server`.
    mount_mcp(app)
    return app


app = create_app()
