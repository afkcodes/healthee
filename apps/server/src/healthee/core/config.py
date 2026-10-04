"""Application settings — the ONE place environment variables are read.

There are TWO env templates, one per deployment context, and every var must be
present in the one(s) that need it — they are not copies of each other:
  * `infra/.env.example` — the compose/prod template (consumed by
    docker-compose.prod.yml, deploy.sh, backup/). Its Postgres host is the `db`
    service name, and it carries the deploy/backup vars the container never sees.
  * `apps/server/.env.example` — the local-dev template for `apps/server/.env`
    (Postgres on localhost; what the test suite and `scripts/model_eval.py` read).
Adding a setting below means adding it to BOTH unless it is genuinely
context-specific — a var that exists in only one silently defaults in the other,
which is how a blank model id reaches OpenRouter as a 400 in prod.

No other module in the codebase may touch `os.environ` — they call
`get_settings()` instead (standards §2: "config (pydantic-settings ONLY)").

The accessor is import-safe: nothing is constructed at import time, so importing
this module never fails even when required vars are unset. `get_settings()`
constructs (and caches) the singleton on first call, where a misconfiguration
fails loudly instead of silently defaulting.
"""

from __future__ import annotations

from functools import lru_cache
from typing import Literal, Self

from pydantic import field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

from healthee.core import config_guards as guards


class Settings(BaseSettings):
    """Typed view of the process environment. Field names map case-insensitively
    to the env vars in `infra/.env.example`."""

    model_config = SettingsConfigDict(
        env_file=".env",  # optional local override; env vars still win
        env_file_encoding="utf-8",
        extra="ignore",
        case_sensitive=False,
    )

    # ── Postgres / TimescaleDB ────────────────────────────────────────────
    postgres_host: str = "localhost"
    postgres_port: int = 5432
    postgres_db: str = "healthee"
    # The OWNER/ADMIN identity: owns the tables, runs migrations (DDL),
    # `db.claim_sentinel`, `db.provision_app_role`, and the test reset. It is NOT
    # the identity that serves requests — see the app role below. Prod already has
    # these set and their meaning is unchanged.
    postgres_user: str = "healthee"
    # Effectively required — a blank DB password is a misconfiguration, not a
    # default. The validator below turns "unset/empty" into a loud failure while
    # keeping the field constructible from the environment.
    postgres_password: str = ""

    # ── Postgres application role (least privilege — MULTI_USER.md §3.3) ──
    # The identity the request/job pool connects as. It is deliberately NOT a
    # superuser and NOT the table owner, because a superuser BYPASSES Row-Level
    # Security unconditionally (`rolbypassrls`) — RLS policies added on top of a
    # superuser connection are decoration, not isolation.
    #
    # Blank ⇒ the pool would fall back to the admin creds above. That fallback is a
    # documented, deliberately-transitional step of the two-deploy bootstrap
    # (`infra/DEPLOY.md` B2) — and it is also the state in which RLS isolates nothing,
    # so since the auth audit it has to be ASKED FOR (`allow_admin_db_fallback` below)
    # rather than reached by leaving a variable blank. Provision the role with
    # `python -m healthee.db.provision_app_role` (run as the admin), then set these.
    postgres_app_user: str = ""
    postgres_app_password: str = ""
    # The opt-out that keeps the bootstrap deploy bootable. See
    # `_refuse_an_unasked_for_rls_bypass` below for the whole argument.
    allow_admin_db_fallback: bool = False

    # ── FastAPI bind (inside the container) ───────────────────────────────
    api_host: str = "0.0.0.0"  # noqa: S104 — LAN-reachable by design (mobile app)
    api_port: int = 8765

    # ── Supabase auth (Phase 6 identity — verify JWTs, never issue) ───────
    # Supabase is the managed auth provider; the API is a resource server that
    # VERIFIES the access JWT (never mints one). The legacy HS256 shared secret
    # signs the token — we verify with the same secret. Blank ⇒ auth fails closed.
    supabase_jwt_secret: str = ""
    # Service-role key for later admin/webhook work (delete-user cascade, §4.5).
    supabase_service_role_key: str = ""
    # Project ref builds the expected issuer https://<ref>.supabase.co/auth/v1;
    # blank ⇒ the `iss` check is skipped (dev / self-signed test tokens).
    supabase_project_ref: str = ""
    # Expected `aud` claim on a Supabase access token (default for its auth server).
    supabase_jwt_aud: str = "authenticated"

    # ── What this deployment tells its APP to sign in against ───────────────
    #
    # Served unauthenticated by `GET /api/auth-config` (which argues why), because a
    # client needs this BEFORE it can authenticate. Both are public by construction:
    # the URL names a project and the **anon** key is the one Supabase documents as
    # shipping inside clients. ⛔ NEVER `service_role`, which bypasses every policy
    # and lives in `supabase_service_role_key`.
    #
    # `supabase_url` is optional — blank derives `https://<ref>.supabase.co` from
    # `supabase_project_ref`. Set it only for a self-hosted GoTrue, which has no ref.
    supabase_url: str = ""
    supabase_anon_key: str = ""
    # ── Signup gating (MULTI_USER.md §4, §13 [D1]) ────────────────────────
    # Invite-gated by config now, self-serve flippable later. The SERVER is the
    # trust boundary (§12.7), so this is enforced here — in `supabase_auth.
    # _provision_user` — and not merely as a Supabase dashboard toggle. It gates
    # the creation of a NEW `app_user` row only; an owner who already has a row is
    # always let through (gating accounts, not access).
    #   signups_open=True                  ⇒ anyone Supabase authenticates.
    #   signups_open=False + allowlist     ⇒ only those verified emails.
    #   signups_open=False + no allowlist  ⇒ nobody new (the default).
    signups_open: bool = False
    # Comma-separated invite allowlist, e.g. "a@b.com, c@d.com". A plain str (not
    # list[str]) because pydantic-settings parses complex types as JSON, and an
    # operator setting one env var should not have to write a JSON array. Read it
    # via `signup_allowlist_emails`, never raw.
    signup_allowlist: str = ""

    # ── Entitlement (Phase 6.6a, MULTI_USER.md §12) ───────────────────────
    # Declares that this deployment is somebody's OWN box, so every owner on it gets
    # the AI layer without a `subscription` row. Default false: the hosted service
    # must never be unlocked by forgetting to set something.
    #
    # It exists because the paywall's whole justification is OUR LLM bill on OUR
    # hosted service (PRICING.md §6.1) — an argument that does not survive contact
    # with a self-hoster running their own OpenRouter key, which is the product's
    # stated brand. The server cannot tell the two deployments apart, so the operator
    # says which one it is; that is server-owned config, not a client claim, and it is
    # exactly §12.6 step (a)'s "admin/config flag". It is logged at startup by both
    # the API and the scheduler, so a hosted box that sets it by accident says so on
    # every boot rather than quietly giving the AI layer away.
    self_host_unlocked: bool = False
    # How many coach questions a PREMIUM owner gets per rolling 30 days.
    #
    # 20 is not a round number, it is a measured one: a coach question costs $0.179
    # (#105 measured it and failed to make it cheaper), so 20 is $3.58 against a
    # $6.99 price and 30 would be $5.37 — PRICING.md §1 does that arithmetic.
    #
    # **Zero means UNLIMITED**, and that is the honest setting for a self-hoster:
    # the cap's whole justification is OUR LLM bill on OUR hosted service, an
    # argument that does not survive contact with somebody paying their own
    # OpenRouter key — the same argument `self_host_unlocked` above already makes.
    # It is a separate switch because the two are separable: a box can be somebody's
    # own and still want a bound on spend.
    # The DEFAULT only: `subscription.coach_questions` (0022) overrides it per owner.
    premium_coach_questions: int = 20
    mcp_enabled: bool = True  # read-only /mcp for AI tools (docs/MCP.md); false = plain 404
    # Where a locked card sends someone. Carried in the 402 body and by
    # `/api/entitlement` so the upgrade destination is deployment config rather than a
    # URL compiled into the app — a self-hoster has no checkout page to point at, and
    # the hosted one's moves when [D4] is decided.
    upgrade_url: str = ""

    # ── OpenRouter (optional — grounded LLM insights, wired in a later WP) ─
    openrouter_api_key: str = ""
    # LLM model ids — kept in env (DEFAULT_MODEL / COACH_MODEL), NOT hardcoded, so the
    # source never reveals which models we run. Blank here (nothing leaked to git);
    # real values live in the deploy env / a local .env. default_model = the cheap
    # high-volume tier; coach_model = the stronger tier for the interactive coach.
    # Blank is legal ONLY while the key above is blank too — `_require_model_ids_when_
    # ai_key_is_set` below refuses the half-configured state, which is a dead AI layer
    # behind a green /healthz.
    default_model: str = ""
    coach_model: str = ""
    # Where the coach spends THINKING (decode-time output, measured 2.7–3.7k tokens per
    # question; two of three rounds only pick a tool): "on" every round (as shipped),
    # "off" none, "answer_only" = off while tools are in play, on for the answer.
    # `insights/coach_loop.reasoning_for_round` applies it; lowercase, or boot refuses.
    coach_reasoning: Literal["on", "off", "answer_only"] = "on"
    # How long ONE LLM HTTP call may take before it is abandoned, and how many times
    # the SDK may retry it. Both are explicit because the SDK's defaults are
    # catastrophic here: `openai` defaults to a 600 s read timeout with 2 retries, so
    # a single stuck call can hang for 3 × 600 s = 30 MINUTES. Since 6.4c the
    # scheduler is a single-threaded tick loop iterating `active_users()`, so that one
    # call blocks EVERY later owner's chain for half an hour — silently, because the
    # tick that would have run them is simply still waiting.
    #
    # 60 s: ~10× a Flash-class call's expected worst case (PRICING.md section 3.1) —
    # generous enough that a slow-but-fine call still returns, short enough that a hang is a hang.
    # 1 retry: retries MULTIPLY the timeout, which is what turns a bad call into an
    # outage — the SDK's 2 keep the worst case at 3 × 60 s = 3 min, one keeps it at
    # 2 min while preserving recovery from a transient 429/5xx. The scheduler's own
    # `_ATTEMPT_BUDGET` and tomorrow's tick are the outer retries.
    llm_timeout_s: float = 60.0

    # The WALL-CLOCK cap on ONE completion, streamed or not — a different failure mode
    # than the read timeout above, which only fires when the socket goes silent.
    # OpenRouter's keepalive bytes during a long generation mean it often never is:
    # measured, one coach question ran 594 s across 3 calls under the 60 s "cap" above.
    llm_deadline_s: float = 120.0

    # ── How long one grounded run may spend GATHERING before it must answer ──
    #
    # ⛔ The bound that was missing. `insights/coach.py` allows 20 tool rounds and
    # nothing bounded how long they take, so a slow model turned a generous ceiling
    # into a run longer than any caller waits. Production, 2026-09-10: ~103 s a
    # round meant a worst case over half an hour against the app's own 360 s, and
    # ZERO coach requests had ever completed — the server answered a closed socket
    # every time.
    #
    # The number is arithmetic, not a round figure. The app waits 360 s
    # (`core/env.dart`'s `coachTimeout`). After gathering stops, the run still has
    # to ANSWER, and that is up to `validation_retries() + 1` more model calls —
    # two, at the same ~100 s a round was measured taking. 360 − 200 = 160, so 150
    # leaves the answer inside the caller's wait with a little room.
    #
    # ⚠ It is a safety net and not a fix. At ~100 s a round it buys ONE gathering
    # round, which is thin for a question like "design me a training programme".
    # The real lever is the ~30,000 tokens re-sent every round — 74% of it the
    # evidence block — and that is measured work, not a constant to nudge.
    gathering_deadline_s: float = 150.0
    llm_max_retries: int = 1
    # Dollars remaining on the OpenRouter account below which the scheduler's watcher
    # warns (`jobs.llm_watch`, read through `insights.credits.balance_state`). It is a
    # WARNING line, never a refusal — nothing in the app declines to spend because of
    # it, because a health companion going quiet on its own is the failure mode this
    # product exists to avoid.
    #
    # 20 is roughly a fortnight of the measured spend at one owner (PRICING.md §3.1's
    # box: ~$22 on the day the eval harness and production shared a key). Set it to a
    # multiple of YOUR daily spend, not of the balance: the number that matters is how
    # many days of warning it buys. 0 disables the warning and leaves only the
    # `exhausted` alert, which is the one that fires when it is already too late.
    llm_low_balance_usd: float = 20.0
    # How many NUDGED REWRITES one generated answer gets before the honest fallback ships
    # (`insights.pipeline.validation_retries`). It was hardcoded to 1, chosen when a retry
    # cost real money on the tier we ran then; on a flash tier three attempts cost a
    # fraction of one attempt on the tier above, and the failures a retry fixes are
    # citation/format wording, which is what a nudge naming the exact issue repairs.
    #
    # Deliberately ONE number rather than a per-model table. A price-scaled budget would
    # need model ids in git to key on, and `insights/client` keeps them out of git on
    # purpose (they resolve from DEFAULT_MODEL / COACH_MODEL); a table that must be edited
    # every time the env changes is a second, staler statement of which model we run. An
    # operator who switches to an expensive tier turns this down; that is honest and it is
    # one line.
    #
    # 0 is legal and means "one attempt, then the fallback". It cannot weaken the floor:
    # unvalidated text never ships at any value.
    llm_validation_retries: int = 2
    # COACH-TIER provider routing (enforced in `insights/client`; the default tier is a
    # different model most of these providers do not host, so a blanket rule would take
    # the nightly chain down). Fallbacks stay ON — a preference, never a restriction.
    #   llm_provider_order: comma-separated provider tags from
    #     `/api/v1/models/{id}/endpoints` (`baidu/fp8`, `fireworks`), walked in order.
    #   llm_provider_sort: what OpenRouter sorts by when no order is given —
    #     "throughput" | "latency" | "price" | "" (its default, PRICE-weighted).
    # Measured 2026-09-19: our coach model has 21 providers at 10–164 tok/s, the two
    # cheapest are the two slowest, and price-weighted routing put 6 of 65 questions
    # under 15 tok/s (the 594 s worst case). Throughput-first is the shipped default;
    # an order, when set, wins over the sort.
    llm_provider_order: str = ""
    llm_provider_sort: Literal["throughput", "latency", "price", ""] = "throughput"

    # ── On-disk caches for public geodata (SRTM elevation + basemap tiles) ─
    # Both hold PUBLIC data this server fetched, never an owner's coordinates.
    # Config, not constants: an unpersisted cache re-downloads on every restart
    # (SRTM once sat under `/tmp`) and `map_tile_cache_mb` bounds tile eviction.
    srtm_cache_dir: str = "/var/cache/healthee/srtm"
    map_tile_cache_dir: str = "/var/cache/healthee/tiles"
    map_tile_cache_mb: int = 512

    # Local text embedding (embedding_index.py, Step 2a) — same volume/reasoning as SRTM
    # above: a torch-free ONNX model whose ~69 MB file must persist across restarts.
    embedding_model: str = "BAAI/bge-small-en-v1.5"
    embedding_cache_dir: str = "/var/cache/healthee/embeddings"

    # Per-note passage budget for the COACH's evidence block only (Step 2b) — other
    # grounded surfaces still embed whole notes; insights/evidence.py's docstring has
    # the full argument. Approx tokens = chars / 4.
    evidence_token_budget: int = 8000
    # The cross-encoder rerank stage (Xenova/ms-marco-MiniLM-L-6-v2, ONNX/CPU). OFF by
    # default: measured 1.6 s for 60 pairs on four fast cores (3.5 s on one), against a
    # 43 ms fused hybrid order — the cost of a whole model round for a reorder.
    evidence_rerank: bool = False

    # ── Basemap (the tile proxy — core/map_tiles.py) ───────────────────────
    # Repointable to a commercial provider or your own tile stack with no app
    # rebuild — the app only ever talks to this server. http(s), must carry
    # {z}/{x}/{y}. Default is OSM's own server, whose policy permits one cached
    # server with a real User-Agent (this module) rather than the app itself.
    map_tile_url: str = "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
    # Travels WITH the url (`GET /api/map` serves both) — repointing one without
    # the other credits the wrong project, and the app cannot tell.
    map_tile_attribution: str = "© OpenStreetMap contributors"
    # Outside this range a request is refused here, never forwarded.
    map_tile_min_zoom: int = 1
    map_tile_max_zoom: int = 17

    # ── Telegram notifications (optional — job status + failures) ─────────
    telegram_bot_token: str = ""
    telegram_chat_id: str = ""

    # ── Logging ───────────────────────────────────────────────────────────
    log_level: str = "INFO"

    # ── The refusals ─────────────────────────────────────────────────────
    #
    # Each body — and the argument for it — lives in `core.config_guards`. They are
    # thin here on purpose: this file answers "what does the environment hold", and
    # that one answers "what combinations are not a deployment". The list below is
    # meant to read as an inventory of the ambiguities this codebase refuses rather
    # than interprets.

    @field_validator("postgres_password")
    @classmethod
    def _require_password(cls, value: str) -> str:
        return guards.require_password(value)

    @field_validator("map_tile_url")
    @classmethod
    def _require_a_usable_tile_template(cls, value: str) -> str:
        return guards.require_a_usable_tile_template(value)

    @model_validator(mode="after")
    def _require_app_creds_together(self) -> Self:
        guards.require_app_creds_together(self.postgres_app_user, self.postgres_app_password)
        return self

    @model_validator(mode="after")
    def _refuse_an_unasked_for_rls_bypass(self) -> Self:
        guards.refuse_an_unasked_for_rls_bypass(
            self.app_role_configured, self.allow_admin_db_fallback
        )
        return self

    @model_validator(mode="after")
    def _require_model_ids_when_ai_key_is_set(self) -> Self:
        guards.require_model_ids_when_ai_key_is_set(
            self.openrouter_api_key, self.default_model, self.coach_model
        )
        return self

    @model_validator(mode="after")
    def _require_an_ordered_zoom_range(self) -> Self:
        guards.require_an_ordered_zoom_range(self.map_tile_min_zoom, self.map_tile_max_zoom)
        return self

    @property
    def signup_allowlist_emails(self) -> frozenset[str]:
        """The invite allowlist as lowercased emails — the ONE parse of that var.

        Lowercased (not casefolded) to match `app_user.email`'s CITEXT semantics,
        which compare via `lower()`: an allowlist entry and the mirrored row must
        agree about what "the same email" means. Blank entries are dropped, so a
        trailing comma or an empty var can never allow anyone.
        """
        return frozenset(
            entry.strip().lower() for entry in self.signup_allowlist.split(",") if entry.strip()
        )

    @property
    def app_role_configured(self) -> bool:
        """True when a dedicated least-privilege app role is configured.

        False ⇒ the pool falls back to the admin creds (`core/db` warns).
        """
        return bool(self.postgres_app_user)

    def _conninfo(self, user: str, password: str) -> str:
        """libpq connection string for one identity — the ONE place it is formatted."""
        return (
            f"host={self.postgres_host} port={self.postgres_port} "
            f"dbname={self.postgres_db} user={user} password={password}"
        )

    @property
    def app_db_url(self) -> str:
        """Conninfo for the APPLICATION pool (`core/db.get_pool`).

        The least-privilege role when configured, else the admin creds — the
        transitional fallback, which now requires `ALLOW_ADMIN_DB_FALLBACK=true`
        (`_refuse_an_unasked_for_rls_bypass`) and which `core/db` announces with a
        WARNING at pool open.
        """
        if self.app_role_configured:
            return self._conninfo(self.postgres_app_user, self.postgres_app_password)
        return self.admin_db_url

    @property
    def admin_db_url(self) -> str:
        """Conninfo for the OWNER/ADMIN identity — DDL, TRUNCATE, re-keying.

        Only `core/db.admin_connection()` may use this; see its docstring for who
        is allowed to call it and why.
        """
        return self._conninfo(self.postgres_user, self.postgres_password)


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """Return the process-wide Settings singleton, constructing it on first call.

    Cached so every caller shares one instance. `get_settings.cache_clear()` in a
    test fixture forces a re-read after patching the environment.
    """
    return Settings()
