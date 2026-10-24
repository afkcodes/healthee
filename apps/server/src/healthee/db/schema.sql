-- Healthee schema — current-state reference (Rails-schema.rb style).
--
-- This file is the at-a-glance picture of the whole database. It is NOT applied
-- directly: the migration runner (healthee.db.migrate) builds the DB from the
-- numbered files in db/migrations/. Keep this in sync when you add a migration;
-- a test (tests/test_schema_files.py) asserts the table/index set here matches
-- what the migrations declare, so the two can never silently drift.
--
-- Cutover note (Phase 6): definitions are a superset-compatible match of legacy
-- PROD (schema_v2.sql + all applied migrations), so a pg_dump of prod restores
-- into this schema. The v1 compat VIEWs (metric_sample, session) and v1-only
-- tables (sync_run) are intentionally gone — the rebuild reads v2-native.

CREATE EXTENSION IF NOT EXISTS timescaledb;
CREATE EXTENSION IF NOT EXISTS pgcrypto;  -- gen_random_uuid() on older PG; core on PG13+
CREATE EXTENSION IF NOT EXISTS citext;    -- case-insensitive email (0002_identity)

-- ── sample ───────────────────────────────────────────────────────────────
-- Raw time-series hypertable: one row per (metric, ts). Re-ingest is idempotent.
CREATE TABLE IF NOT EXISTS sample (
  ts      TIMESTAMPTZ       NOT NULL,
  metric  TEXT              NOT NULL,
  value   DOUBLE PRECISION  NOT NULL,
  user_id UUID              NOT NULL  -- tenant (0003; DEFAULT dropped 0007)
            REFERENCES app_user(id) ON UPDATE CASCADE ON DELETE CASCADE,
  PRIMARY KEY (user_id, metric, ts)  -- owner folded into the key (0004)
);
SELECT create_hypertable('sample', 'ts',
  chunk_time_interval => INTERVAL '7 days', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS sample_metric_ts_idx ON sample (metric, ts DESC);
CREATE INDEX IF NOT EXISTS sample_user_idx ON sample (user_id, metric, ts DESC);

-- ── sleep_session ─────────────────────────────────────────────────────────
-- One typed sleep session (night or nap); stages is the [[startMs,endMs,type],…] hypnogram.
CREATE TABLE IF NOT EXISTS sleep_session (
  start_ts    TIMESTAMPTZ  NOT NULL,
  end_ts      TIMESTAMPTZ  NOT NULL,
  kind        TEXT         NOT NULL DEFAULT 'main',  -- 'main' night sleep | 'nap'
  score       INTEGER,
  avg_hr      INTEGER,
  -- NULLABLE since 0018: NULL means the strap staged nothing for this session, which is
  -- a different fact from a measured zero minutes in a stage. `NOT NULL DEFAULT 0` gave
  -- storage no way to say the first, so an unstaged night was served as a night of zero
  -- sleep. Rows written before 0018 cannot be told apart retroactively — see that file.
  rem_min     INTEGER,
  light_min   INTEGER,
  deep_min    INTEGER,
  wake_min    INTEGER,
  stages      JSONB        NOT NULL DEFAULT '[]'::jsonb,
  user_id     UUID         NOT NULL  -- tenant (0003; DEFAULT dropped 0007)
                REFERENCES app_user(id) ON UPDATE CASCADE ON DELETE CASCADE,
  PRIMARY KEY (user_id, start_ts)  -- owner folded into the key (0004)
);
CREATE INDEX IF NOT EXISTS sleep_session_start_idx ON sleep_session (start_ts DESC);
CREATE INDEX IF NOT EXISTS sleep_session_user_idx ON sleep_session (user_id, start_ts DESC);

-- ── workout ───────────────────────────────────────────────────────────────
-- One typed workout with device-measured calories/distance/HR.
CREATE TABLE IF NOT EXISTS workout (
  start_ts    TIMESTAMPTZ  NOT NULL,
  sport       INTEGER      NOT NULL DEFAULT 0,
  duration_s  INTEGER      NOT NULL DEFAULT 0,
  calories    INTEGER,
  distance_m  REAL,
  avg_hr      INTEGER,
  max_hr      INTEGER,
  min_hr      INTEGER,
  user_id     UUID         NOT NULL  -- tenant (0003; DEFAULT dropped 0007)
                REFERENCES app_user(id) ON UPDATE CASCADE ON DELETE CASCADE,
  PRIMARY KEY (user_id, start_ts)  -- owner folded into the key (0004)
);
CREATE INDEX IF NOT EXISTS workout_start_idx ON workout (start_ts DESC);
CREATE INDEX IF NOT EXISTS workout_user_idx ON workout (user_id, start_ts DESC);

-- ── derived_daily ─────────────────────────────────────────────────────────
-- Materialized per-day derived metrics for O(1) dashboard reads (filled on ingest).
CREATE TABLE IF NOT EXISTS derived_daily (
  day     DATE              NOT NULL,
  metric  TEXT              NOT NULL,
  value   DOUBLE PRECISION  NOT NULL,
  flags   JSONB             NOT NULL DEFAULT '{}'::jsonb,
  user_id UUID              NOT NULL  -- tenant (0003; DEFAULT dropped 0007)
            REFERENCES app_user(id) ON UPDATE CASCADE ON DELETE CASCADE,
  -- When this cell was last COMPUTED (0016). Set by the table's ONE writer
  -- (`derive/_common._upsert_daily`) on insert AND on conflict, so it means "a derive
  -- pass wrote this", not "the value changed". Ingest had a second writer until 0017
  -- (it wrote the strap's daily counter straight into `steps_total`); that write is now
  -- a raw row in `device_daily_total` that the derive pass reads.
  -- It is what lets a re-derive tell the rows it just produced apart from the rows a
  -- NARROWED derivation declined to produce — see `db/stale_derived.py`.
  derived_at TIMESTAMPTZ    NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, day, metric)  -- owner folded into the key (0004)
);
CREATE INDEX IF NOT EXISTS derived_daily_metric_day_idx ON derived_daily (metric, day DESC);
CREATE INDEX IF NOT EXISTS derived_daily_user_idx ON derived_daily (user_id, metric, day DESC);

-- ── device_daily_total (0017_device_daily_total) ──────────────────────────
-- The strap's OWN since-midnight totals (BLE 0x0016), one row per owner-local day —
-- the raw home this measurement did not have (#121). `derive/activity.py` prefers
-- `steps` here over the per-minute `steps_per_minute` sum when writing
-- `derived_daily.steps_total`, so a re-derive can no longer destroy it: before 0017
-- the counter WAS the derived cell, and any derive pass over the day overwrote it
-- with nothing to restore from (142 of 143 production days lost that way, and NOT
-- recovered by 0017 — see the migration, it starts empty and is forward-only).
-- `calories` is stored for completeness of the raw report and derives nothing:
-- free-living energy is the MET-by-state model, never a device number.
CREATE TABLE IF NOT EXISTS device_daily_total (
  day         DATE              NOT NULL,
  steps       INTEGER,
  distance_m  DOUBLE PRECISION,
  calories    DOUBLE PRECISION,
  source      TEXT              NOT NULL DEFAULT 'strap_0x16',  -- the reporting instrument
  reported_at TIMESTAMPTZ       NOT NULL DEFAULT now(),         -- when this reading ARRIVED
  -- When the phone ASKED the strap for this counter (0019). NULLABLE and staying that
  -- way: "we do not know when this was read" is the true state of every row written
  -- before 0019 and of every row an older client writes, and `now()` in its place is the
  -- lie 0019 exists to end. `partial_day_caveats` reads this one, never `reported_at`.
  read_at     TIMESTAMPTZ,
  user_id     UUID              NOT NULL
                REFERENCES app_user(id) ON UPDATE CASCADE ON DELETE CASCADE,
  PRIMARY KEY (user_id, day)  -- also the only index: every read is (user_id, day)
);

-- ── profile ───────────────────────────────────────────────────────────────
-- One profile per owner; inputs for energy/distance/VO₂max/bio-age derivation.
CREATE TABLE IF NOT EXISTS profile (
  name        TEXT,
  height_cm   REAL,
  sex         TEXT CHECK (sex IN ('male', 'female')),
  dob         DATE,
  -- Jurca 2005's five-level SELF-REPORTED physical-activity category (0014, #108).
  -- NULL means "never answered", and `derive/vo2max.py` withholds the estimate rather
  -- than assuming a level — it used to synthesise one from step cadence, which cannot
  -- tell deliberate exercise from getting around and was worth years of biological age.
  srpa        SMALLINT CHECK (srpa BETWEEN 0 AND 4),
  updated_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
  -- The owner IS the key (0005): the old `id INTEGER PK DEFAULT 1 CHECK (id = 1)`
  -- allowed exactly one row globally, so a second owner could not hold a profile
  -- and an upsert for one owner overwrote another's demographics.
  user_id     UUID         NOT NULL  -- tenant (0003; DEFAULT dropped 0007)
                REFERENCES app_user(id) ON UPDATE CASCADE ON DELETE CASCADE,
  PRIMARY KEY (user_id)  -- owner folded into the key (0005)
);
CREATE INDEX IF NOT EXISTS profile_user_idx ON profile (user_id);

-- ── weight_log ────────────────────────────────────────────────────────────
-- Body-weight measurements, one row per timestamp (deduped to one per local day).
CREATE TABLE IF NOT EXISTS weight_log (
  ts       TIMESTAMPTZ  NOT NULL,
  kg       REAL         NOT NULL,
  user_id  UUID         NOT NULL  -- tenant (0003; DEFAULT dropped 0007)
             REFERENCES app_user(id) ON UPDATE CASCADE ON DELETE CASCADE,
  PRIMARY KEY (user_id, ts)  -- owner folded into the key (0004)
);
CREATE INDEX IF NOT EXISTS weight_log_user_idx ON weight_log (user_id, ts DESC);

-- ── kv ────────────────────────────────────────────────────────────────────
-- Small key/value store (per-day markers, cached generated text).
CREATE TABLE IF NOT EXISTS kv (
  key      TEXT  NOT NULL,
  value    TEXT  NOT NULL,
  user_id  UUID  NOT NULL  -- tenant (0003; DEFAULT dropped 0007)
             REFERENCES app_user(id) ON UPDATE CASCADE ON DELETE CASCADE,
  PRIMARY KEY (user_id, key)  -- owner folded into the key (0004)
);
CREATE INDEX IF NOT EXISTS kv_user_idx ON kv (user_id, key);

-- ── manual_entry ──────────────────────────────────────────────────────────
-- User-logged events: caffeine/alcohol/meditation/exercise/fasting/habit/etc.
CREATE TABLE IF NOT EXISTS manual_entry (
  id         UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  kind       TEXT         NOT NULL,
  ts         TIMESTAMPTZ  NOT NULL,
  end_ts     TIMESTAMPTZ,
  name       TEXT,
  amount     DOUBLE PRECISION,
  unit       TEXT,
  severity   INTEGER,
  notes      TEXT,
  flags      JSONB        NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
  user_id    UUID         NOT NULL  -- tenant (0003; DEFAULT dropped 0007)
               REFERENCES app_user(id) ON UPDATE CASCADE ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS manual_entry_ts_idx ON manual_entry (ts DESC, kind);
CREATE INDEX IF NOT EXISTS manual_entry_user_idx ON manual_entry (user_id, ts DESC);

-- ── illness_flag ──────────────────────────────────────────────────────────
-- Early-warning flag: one row per wake-date when skin-temp/RR/HRV deviate enough.
CREATE TABLE IF NOT EXISTS illness_flag (
  date              DATE NOT NULL,
  severity          TEXT NOT NULL CHECK (severity IN ('moderate', 'high')),
  rr_delta_bpm      REAL,
  temp_delta_c      REAL,
  hrv_delta_z       REAL,
  rhr_delta_z       REAL,
  sustained         BOOLEAN NOT NULL DEFAULT FALSE,
  research_note_ids TEXT[] NOT NULL,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  user_id           UUID    NOT NULL  -- tenant (0003; DEFAULT dropped 0007)
                      REFERENCES app_user(id) ON UPDATE CASCADE ON DELETE CASCADE,
  PRIMARY KEY (user_id, date)  -- owner folded into the key (0004)
);
CREATE INDEX IF NOT EXISTS illness_flag_date_idx ON illness_flag (date DESC);
CREATE INDEX IF NOT EXISTS illness_flag_user_idx ON illness_flag (user_id, date DESC);

-- ── recommendation ────────────────────────────────────────────────────────
-- AI-synthesized daily recommendations (1–3 ranked actions per date, cite-or-drop).
CREATE TABLE IF NOT EXISTS recommendation (
  id                BIGSERIAL PRIMARY KEY,
  date              DATE NOT NULL,
  rank              INTEGER NOT NULL,
  action            TEXT NOT NULL,
  rationale         TEXT NOT NULL,
  expected_effect   TEXT,
  category          TEXT NOT NULL,
  evidence_grade    INTEGER NOT NULL CHECK (evidence_grade IN (2, 3)),
  research_note_ids TEXT[]  NOT NULL,
  signal_source     TEXT    NOT NULL,
  raw_llm_prompt    TEXT,   -- audit trail (legacy INSERTed these; v2 schema lacked them)
  raw_llm_response  TEXT,   -- audit trail
  adopted           BOOLEAN,
  adopted_at        TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  user_id           UUID    NOT NULL  -- tenant (0003; DEFAULT dropped 0007)
                      REFERENCES app_user(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT recommendation_user_key UNIQUE (user_id, date, rank)  -- owner folded in (0004)
);
CREATE INDEX IF NOT EXISTS recommendation_date_idx ON recommendation (date DESC);
CREATE INDEX IF NOT EXISTS recommendation_user_idx ON recommendation (user_id, date DESC);

-- ── finding ───────────────────────────────────────────────────────────────
-- Discovered patterns: pairwise metric correlations, event-effects, personal cutoffs.
CREATE TABLE IF NOT EXISTS finding (
  id            UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  computed_at   TIMESTAMPTZ  NOT NULL DEFAULT now(),
  kind          TEXT         NOT NULL,
  description   TEXT         NOT NULL,
  metric_a      TEXT         NOT NULL,
  metric_b      TEXT         NOT NULL DEFAULT '',
  event_kind    TEXT         NOT NULL DEFAULT '',
  lag_days      INTEGER      NOT NULL DEFAULT 0,
  effect_size   DOUBLE PRECISION NOT NULL,
  effect_metric TEXT         NOT NULL,
  p_value       DOUBLE PRECISION NOT NULL,
  q_value       DOUBLE PRECISION,
  n_samples     INTEGER      NOT NULL,
  significant   BOOLEAN      NOT NULL DEFAULT FALSE,
  research_note_ids TEXT[]   NOT NULL DEFAULT ARRAY[]::TEXT[],
  details       JSONB        NOT NULL DEFAULT '{}'::jsonb,
  user_id       UUID         NOT NULL  -- tenant (0003; DEFAULT dropped 0007)
                  REFERENCES app_user(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT finding_user_key                                      -- owner folded in (0004)
    UNIQUE (user_id, kind, metric_a, metric_b, event_kind, lag_days)
);
CREATE INDEX IF NOT EXISTS finding_kind_idx ON finding (kind, significant DESC, ABS(effect_size) DESC);
CREATE INDEX IF NOT EXISTS finding_metric_idx ON finding (metric_a, lag_days);
CREATE INDEX IF NOT EXISTS finding_user_idx ON finding (user_id, kind);

-- ── challenge ─────────────────────────────────────────────────────────────
-- Adoptable, auto-tracked health commitments; a program rung when program_id set.
CREATE TABLE IF NOT EXISTS challenge (
  id                BIGSERIAL PRIMARY KEY,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  gen_date          DATE,
  title             TEXT NOT NULL,
  why               TEXT NOT NULL,
  category          TEXT NOT NULL,
  difficulty        TEXT NOT NULL DEFAULT 'standard',
  metric            TEXT NOT NULL,
  comparator        TEXT NOT NULL,
  target_value      DOUBLE PRECISION NOT NULL,
  cadence           TEXT NOT NULL,
  window_days       INTEGER NOT NULL,
  expected_outcome  TEXT,
  how_to            TEXT,
  research_note_ids TEXT[],
  -- 0009: `expired` = the window ran out UNMET. Legacy called that "completed",
  -- which is the one thing a ledger must not do (CHALLENGES.md §2.3).
  -- 0010: `locked` = a designed program rung nobody has reached yet. It is a status
  -- rather than a flag so `lifecycle.adopt`'s "must be suggested" rule already
  -- refuses to snap rung 3 out of a ladder and run it on its own.
  status            TEXT NOT NULL DEFAULT 'suggested'
                      CHECK (status IN ('locked', 'suggested', 'active', 'completed',
                                        'expired', 'abandoned')),
  adopted_at        TIMESTAMPTZ,
  ends_at           TIMESTAMPTZ,
  completed_at      TIMESTAMPTZ,
  abandoned_at      TIMESTAMPTZ,
  baseline_value    DOUBLE PRECISION,   -- frozen at adopt — the before/after anchor
  -- 0013 gives this its FK to program(id) — stated after `program` below, since a
  -- rung's table is declared before its ladder's.
  program_id        BIGINT,
  rung_index        INTEGER,
  -- 0010: a `deload` rung is INSERTED after one timed out unmet, at an eased target.
  -- Never a repeat of the failed row — `challenge_outcome` is keyed on challenge_id
  -- and written DO NOTHING, so a second attempt on one row cannot be recorded.
  kind              TEXT NOT NULL DEFAULT 'standard'
                      CHECK (kind IN ('standard', 'deload')),
  -- 0023: the words a weekly coach job needs. All nullable — NULL is "not authored".
  action_text       TEXT,
  slot_text         TEXT,
  floor_value       DOUBLE PRECISION,   -- bad-day threshold: met (target not) => partial
  floor_text        TEXT,
  counts_when       TEXT,
  days_required     SMALLINT,
  user_id           UUID    NOT NULL  -- tenant (0003; DEFAULT dropped 0007)
                      REFERENCES app_user(id) ON UPDATE CASCADE ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS challenge_status_idx ON challenge (status, created_at DESC);
CREATE INDEX IF NOT EXISTS challenge_user_idx ON challenge (user_id, status);
CREATE INDEX IF NOT EXISTS challenge_program_rung_idx
  ON challenge (user_id, program_id, rung_index);

-- ── program ───────────────────────────────────────────────────────────────
-- Multi-week ladder of challenge "rungs" toward a goal (CHALLENGES.md §2.3).
-- Advancement is deterministic and recovery-aware: a rung that times out unmet is
-- recorded `expired`, never completed, and the ladder deloads or gives up rather
-- than pushing the owner up a staircase they are falling off.
CREATE TABLE IF NOT EXISTS program (
  id            BIGSERIAL PRIMARY KEY,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  title         TEXT NOT NULL,
  why           TEXT NOT NULL,
  goal          TEXT,
  goal_metric   TEXT,
  category      TEXT,
  weeks         INTEGER,
  -- 0010: `stalled` is the give-up condition — the ladder ran out of room to ease.
  -- Deliberately not `abandoned`: the owner did not quit, the system stopped.
  status        TEXT NOT NULL DEFAULT 'suggested'
                  CHECK (status IN ('suggested', 'active', 'completed',
                                    'stalled', 'abandoned')),
  adopted_at    TIMESTAMPTZ,
  completed_at  TIMESTAMPTZ,       -- `completed` only, mirroring challenge
  ended_at      TIMESTAMPTZ,       -- 0010: any terminal state
  ended_reason  TEXT,              -- 0010: why a stalled/abandoned ladder ended
  hold_reason   TEXT,              -- 0010: transient — why the next rung is paused
  -- `current_rung` was DROPPED in 0010: the rung rows already say where the owner
  -- is, and a pointer maintained beside them is a second definition that can drift.
  user_id       UUID    NOT NULL  -- tenant (0003; DEFAULT dropped 0007)
                  REFERENCES app_user(id) ON UPDATE CASCADE ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS program_user_idx ON program (user_id, status);

-- 0013: a rung belongs to its ladder in the DATABASE, not only in the code that
-- deletes them together. CASCADE on delete because an orphaned rung is invisible
-- (`locked`, unadoptable, indexed inside a ladder that no longer exists), and the only
-- program ever deleted is an un-adopted suggestion whose rungs never ran. CASCADE on
-- update because a FK without one ERRORS on a re-key rather than skipping it (0006).
ALTER TABLE challenge ADD CONSTRAINT challenge_program_id_fkey FOREIGN KEY (program_id)
  REFERENCES program(id) ON UPDATE CASCADE ON DELETE CASCADE;

-- ── challenge_outcome ─────────────────────────────────────────────────────
-- Frozen learning-loop ledger: a snapshot written when a challenge ends.
-- 0009 reshaped it so the honesty is structural rather than prose
-- (CHALLENGES.md §2.1/§2.6/§7.1) — the four columns below carry the argument.
CREATE TABLE IF NOT EXISTS challenge_outcome (
  challenge_id     BIGINT PRIMARY KEY REFERENCES challenge(id) ON DELETE CASCADE,
  metric           TEXT,
  category         TEXT,
  difficulty       TEXT,
  cadence          TEXT,
  target           DOUBLE PRECISION,
  baseline         DOUBLE PRECISION,   -- the frozen adopt-time value
  final            DOUBLE PRECISION,   -- the same metric at the end
  -- 0009 (was delta_pct): the metric move, baseline -> final, SIGNED so positive
  -- always means "the direction this challenge wanted". A raw delta cannot say
  -- that for a good="down" metric.
  improvement_pct  DOUBLE PRECISION,
  improved         BOOLEAN,            -- exactly improvement_pct > 0, nothing more
  -- 0009 REDEFINED: the BEHAVIOUR rate (days met / days elapsed). Legacy used one
  -- number for this AND for the metric move; improvement_pct now carries the latter.
  adherence        DOUBLE PRECISION,
  days_active      INTEGER,
  status           TEXT,               -- met | unmet_timed_out | abandoned
  -- 0009 (was downstream, TEXT): deltas on OTHER metrics — co-occurring and
  -- UNATTRIBUTED. Read with confounds.concurrent_challenges, never alone.
  co_occurring     JSONB,
  -- 0009: illness days in-window · concurrent challenges · regression-to-mean risk.
  confounds        JSONB       NOT NULL DEFAULT '{}'::jsonb,
  -- 0009: a thin baseline is LABELLED, never a silent NULL outcome that vanishes.
  data_confidence  TEXT        NOT NULL DEFAULT 'ok'
                     CHECK (data_confidence IN ('ok', 'insufficient_data')),
  ended_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  user_id          UUID        NOT NULL  -- tenant (0003; DEFAULT dropped 0007)
                     REFERENCES app_user(id) ON UPDATE CASCADE ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS challenge_outcome_user_idx ON challenge_outcome (user_id);
CREATE INDEX IF NOT EXISTS challenge_outcome_user_ended_idx
  ON challenge_outcome (user_id, ended_at DESC);

-- ── gps_track ─────────────────────────────────────────────────────────────
-- One phone-recorded outdoor workout track; denormalised summary cols for cheap lists.
CREATE TABLE IF NOT EXISTS gps_track (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  start_ts       TIMESTAMPTZ NOT NULL,
  end_ts         TIMESTAMPTZ NOT NULL,
  source         TEXT NOT NULL DEFAULT 'phone',
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  distance_m     DOUBLE PRECISION,
  duration_s     INTEGER,
  avg_hr         INTEGER,
  ele_gain_m     INTEGER,
  vo2max_submax  DOUBLE PRECISION,
  r2             DOUBLE PRECISION,
  user_id        UUID        NOT NULL  -- tenant (0003; DEFAULT dropped 0007)
                   REFERENCES app_user(id) ON UPDATE CASCADE ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS gps_track_time_idx ON gps_track (start_ts, end_ts);
CREATE INDEX IF NOT EXISTS gps_track_user_idx ON gps_track (user_id, start_ts);

-- ── gps_point ─────────────────────────────────────────────────────────────
-- One lat/lng/elevation fix within a gps_track.
CREATE TABLE IF NOT EXISTS gps_point (
  track_id  UUID NOT NULL REFERENCES gps_track(id) ON DELETE CASCADE,
  ts        TIMESTAMPTZ NOT NULL,
  lat       DOUBLE PRECISION NOT NULL,
  lng       DOUBLE PRECISION NOT NULL,
  ele_m     DOUBLE PRECISION,
  user_id   UUID NOT NULL  -- tenant (0003; DEFAULT dropped 0007)
              REFERENCES app_user(id) ON UPDATE CASCADE ON DELETE CASCADE,
  PRIMARY KEY (user_id, track_id, ts)  -- owner folded into the key (0004)
);
CREATE INDEX IF NOT EXISTS gps_point_user_idx ON gps_point (user_id, ts);

-- ── app_user (0002_identity) ───────────────────────────────────────────────
-- Local mirror of the Supabase user; the tenant key everywhere is this UUID.
-- No passwords here — Supabase owns credentials/sessions. JIT-provisioned on the
-- first authenticated request (MULTI_USER.md §4.4). 0003 seeds the sentinel owner
-- 00000000-0000-0000-0000-000000000000 (tz Asia/Kolkata) that owns all pre-auth
-- single-tenant data; it is re-keyed to the real Supabase UUID in 6.4.
CREATE TABLE IF NOT EXISTS app_user (
  id          UUID         PRIMARY KEY,               -- = Supabase auth.users.id (sub)
  email       CITEXT,                                 -- mirrored for convenience/joins
  status      TEXT         NOT NULL DEFAULT 'active',
  timezone    TEXT         NOT NULL DEFAULT 'UTC',    -- IANA name, per-user
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- ── device_token (0002_identity, FK widened in 0006) ───────────────────────
-- Per-strap/app long-lived ingest credential; only the SHA-256 hash is stored.
-- ON UPDATE CASCADE (0006) so the sentinel → real-owner re-key moves tokens with
-- everything else — it is the one FK to app_user 0003's sweep did not cover.
CREATE TABLE IF NOT EXISTS device_token (
  id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID         NOT NULL REFERENCES app_user(id)
                             ON UPDATE CASCADE ON DELETE CASCADE,
  token_hash  TEXT         NOT NULL,                  -- SHA-256 hex of the raw token
  label       TEXT,
  last_seen   TIMESTAMPTZ,
  -- NULL means live (0020). A revoked token keeps its row so `last_seen` can
  -- answer "was it used after I revoked it?" — see the migration.
  revoked_at  TIMESTAMPTZ,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);
-- Whole-table on purpose: uniqueness here is about SECRETS, not live credentials.
-- Narrowed to un-revoked rows it would let a revoked hash be re-minted.
CREATE UNIQUE INDEX IF NOT EXISTS device_token_hash_idx ON device_token (token_hash);

-- ── coach_commitment (0021) ────────────────────────────────────────────────
-- What the owner told the coach they would do, so the next conversation is not a
-- cold start. One row per agreement; the transcript is never stored. `metric` is
-- NULLABLE on purpose — "I'll get to bed earlier" names none, and inventing one
-- would invent an attribution. See the migration for the whole argument.
CREATE TABLE IF NOT EXISTS coach_commitment (
  id           BIGSERIAL    PRIMARY KEY,
  user_id      UUID         NOT NULL REFERENCES app_user(id)
                              ON UPDATE CASCADE ON DELETE CASCADE,
  stated       TEXT         NOT NULL,
  metric       TEXT,
  check_in_on  DATE         NOT NULL,
  status       TEXT         NOT NULL DEFAULT 'open',
  created_at   TIMESTAMPTZ  NOT NULL DEFAULT now(),
  resolved_at  TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS coach_commitment_open_idx
  ON coach_commitment (user_id, status, check_in_on);

-- ── subscription (0011_subscription) ───────────────────────────────────────
-- The entitlement row (MULTI_USER.md §12.2): one per owner, the SOLE source of
-- truth for premium access. `core/entitlement.py` is the only reader and the ops
-- module `db/grant_premium.py` (plus 6.6b's webhook) the only writers — the app
-- role holds SELECT and nothing else here, which is what makes "a request path
-- cannot mint entitlement" a privilege rather than a promise.
--
-- ON UPDATE CASCADE like every other FK to app_user: without it the sentinel
-- re-key ERRORS for any owner who has a row (the 0006 lesson, not repeated).
CREATE TABLE IF NOT EXISTS subscription (
  user_id            UUID PRIMARY KEY REFERENCES app_user(id)
                       ON UPDATE CASCADE ON DELETE CASCADE,
  status             TEXT NOT NULL DEFAULT 'none',    -- CHECK: none|trialing|active|
                                                      --   past_due|canceled|expired
  plan               TEXT,                            -- monthly|annual|comp_<n>mo|…
  provider           TEXT,                            -- stripe|polar|… (6.6b)
  provider_ref       TEXT,                            -- customer/subscription id (6.6b)
  trial_end          TIMESTAMPTZ,
  current_period_end TIMESTAMPTZ,                     -- premium requires now() < this
  granted_by         TEXT,                            -- hand-made grants: who
  note               TEXT,                            -- …and why
  coach_questions    INTEGER,                         -- NULL = deployment default,
                                                      --   0 = unlimited (0022)
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── Row-Level Security (0008_row_level_security, extended by 0011) ─────────
-- The isolation backstop (MULTI_USER.md §3.3): every TENANT table below carries
-- `ENABLE ROW LEVEL SECURITY` plus exactly ONE policy named `<table>_tenant`, of
-- this exact shape — `core.db.tenant_transaction()` sets the GUC it reads:
--
--   ALTER TABLE <t> ENABLE ROW LEVEL SECURITY;
--   CREATE POLICY <t>_tenant ON <t> FOR ALL
--     USING      (user_id = NULLIF(current_setting('healthee.user_id', true), '')::uuid)
--     WITH CHECK (user_id = NULLIF(current_setting('healthee.user_id', true), '')::uuid);
--
-- Why each part (all three were probed before being written — see 0008's header):
--   * FOR ALL + WITH CHECK — a USING-only policy leaves INSERT ungoverned, which
--     would break every upsert and let a write land under any owner.
--   * NULLIF(…, '') — a touched-then-reset GUC reads back as the EMPTY STRING, not
--     NULL, and a bare ''::uuid ERRORS instead of failing closed.
--   * no FORCE — FORCE only binds the table's OWNER. The app role owns nothing, so
--     plain ENABLE already binds it; the admin stays unbound on purpose (migrate,
--     claim_sentinel and the test reset must all see across owners).
--
-- The 19 tenant tables, each with `<table>_tenant`:
--   sample · sleep_session · workout · derived_daily · weight_log · kv ·
--   manual_entry · illness_flag · recommendation · finding · challenge · program ·
--   challenge_outcome · gps_track · gps_point · profile · subscription ·
--   device_daily_total · coach_commitment
--
-- `device_daily_total` (0017) and `coach_commitment` (0021) declare their own policies
-- in their own migrations, of exactly the shape above — a tenant table added later is
-- policied where it is created, not by editing 0008, which has already been applied
-- everywhere.
--
-- `subscription` (0011) is policied like the rest, and additionally carries a
-- privilege the others do not need: the app role may only SELECT it, so a request
-- path cannot write entitlement even where RLS would have allowed its own row.
--
-- `sample`'s chunks inherit the parent hypertable's policy — nothing extra needed.
--
-- NOT policied, deliberately: `app_user` and `device_token` (identity — the app has
-- to resolve WHO you are before it knows an owner to scope to, and the scheduler's
-- active_users() sweep must see every owner), and `schema_migrations` (admin-only,
-- not even granted to the app role).
