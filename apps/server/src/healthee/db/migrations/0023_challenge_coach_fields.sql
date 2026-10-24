-- 0023_challenge_coach_fields — the human-readable half of a weekly coach job.
--
-- The weekly coach hands the owner ONE job a week, and the screen that shows it needs
-- words the metric rule cannot supply: the one-line action, when in the day it happens,
-- what the owner may fall back to on a bad day, what counts, and how many days of the
-- week the job asks for. All of it is presentation of a rule that already lives in
-- `metric`/`comparator`/`target_value`; none of it changes how the rule is scored.
--
-- Every column is NULLABLE with no default: a challenge created before this migration,
-- or by the standalone generator, has no such text and must say so rather than carry
-- an invented sentence. A NULL is "not authored", never an empty string.
--
-- `floor_value` is the bad-day threshold: reaching it (but not the target) is a
-- `partial` day in `challenges.day_verdicts`, never a `done` one.
--
-- Replay-safe; `migrate._apply_one` runs the file plus its ledger row in ONE transaction.

ALTER TABLE challenge ADD COLUMN IF NOT EXISTS action_text TEXT;
ALTER TABLE challenge ADD COLUMN IF NOT EXISTS slot_text TEXT;
ALTER TABLE challenge ADD COLUMN IF NOT EXISTS floor_value DOUBLE PRECISION;
ALTER TABLE challenge ADD COLUMN IF NOT EXISTS floor_text TEXT;
ALTER TABLE challenge ADD COLUMN IF NOT EXISTS counts_when TEXT;
ALTER TABLE challenge ADD COLUMN IF NOT EXISTS days_required SMALLINT;
