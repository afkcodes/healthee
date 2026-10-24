# Healthee redesign build: architect + delegated builders

## ROLE (binding for this whole session)

You (Opus) are the **architect and reviewer**. You set scope, architecture, and quality bar. You do not write feature code or browse the codebase yourself.

- **All coding** is done by subagents. Use the Agent tool with `model: "sonnet"`, `effort: "medium"`, `subagent_type: "general-purpose"`.
- **All exploration** (finding files, reading code to answer a question) is also done by subagents. Use `model: "sonnet"`, `effort: "medium"`, `subagent_type: "Explore"`.
- **You only:**
  - read this prompt, the spec images and short excerpts subagents quote back to you;
  - write briefs;
  - review diffs;
  - run git commit and push.
- **Every brief is self-contained.** Include:
  - the goal and exact file paths;
  - the spec image path;
  - the rules from this prompt that apply;
  - the acceptance checks;
  - the reply format: "≤150 words: files changed, tests run + pass/fail, anything you could not do".
  - Subagents never paste whole files or full test logs back.
- **Review** with `git diff --stat`, then read only the hunks that matter. If a diff misses the spec, send a fix brief to the same agent (SendMessage). Don't rewrite it yourself.
- **Parallel agents** only when their file sets do not overlap (for example server vs mobile). Never run two agents on the same files.

## TOKEN AND SAFETY RULES

- Branch: `design/redesign-2026-10` (already pushed; check it out, never branch from main).
- **First action:** read `design/redesign-2026-10/STATUS.md`. It is the authority on which phases are done; skip those.
- **Before each phase**, run `git log --oneline -20`. If that phase's commit already exists, skip the phase.
- **After each phase:**
  - a subagent runs `flutter analyze` and the tests for the touched dirs (server: `uv run pytest <paths>`);
  - you review;
  - you commit with the message given and push immediately;
  - you update the status file (next item).
- **Status file:** `design/redesign-2026-10/STATUS.md`. Keep it under 15 lines: phases done, what's next, open issues. A fresh session must be able to resume from it alone.
- **Pushed work must build.** If a phase can't be finished, commit only what builds, write the gap in STATUS.md, and move on.
- **No new packages, fonts or assets** unless a phase says so.
- **Commits:** Conventional Commits only (the repo's commit-msg hook rejects anything else), split into smaller thematic commits if a phase is large. Never add a `Co-Authored-By: Claude` trailer; the hook rejects it.
- **Read the repo rules once, at the start:**
  - Have one Explore agent summarise for you, in ≤200 words, the MUST rules from `docs/ENGINEERING_STANDARDS.md` §2–3 and `CLAUDE.md`.
  - Paste that summary into every coding brief.
  - Rules you already know: 400-line max per file, tests in the same commit, no swallowed errors, science code untouched unless a phase says so.
- **Flutter not installed?** Phase 0's agent installs it: a shallow clone of the stable channel into ~/flutter, PATH updated, `flutter --version` once.

## SPEC

- **Images:** `design/redesign-2026-10/*.png` (if missing, the owner attached them to this chat). Each image shows dark on the left and light on the right.
  - 01 colour system
  - 02 health signals
  - 03 insights
  - 04 coach home
  - 05 review open
  - 06 every yes checked
  - 07 back to 150
  - 08 breathing plan
  - 09 breathing player
- **Images vs `design/mobile-preview`:** for these screens, the images replace `design/mobile-preview`.
- **Numbers in the images** are the owner's real data on 18 Oct. Build against live providers, never hardcode them.
- **Coach prompt:** `design/redesign-2026-10/COACH_TASK.md`.

## COLOUR RULES (apply everywhere)

**Domain hue** says WHAT a number is. **State colour** says HOW it's going. Chrome stays neutral.

Domain hues (dark / light):

| Domain | Dark | Light | Existing Tone |
|---|---|---|---|
| Heart | #FF375F | #E8304F | heart |
| Sleep | #7D7AFF | #5856D6 | sleep |
| Activity | #FF9F0A | #E58600 | movement / activity |
| Strain | #0A84FF | #0071E3 | load (give it its own family) |
| Breathing | #64D2FF | #0098C9 | oxygen |
| Body | #BF5AF2 | #9F45D6 | fitness (also water) |
| Mind | #63E6BE | #0FA37F | stress (also breathing exercises, meditation) |

State colours (dark / light):

| State | Dark | Light | Existing token |
|---|---|---|---|
| Better | #30D158 | #24A148 | fav |
| Worse | #FF453A | #E5342B | alert |
| Watch | #FFD60A | #C79A00 | unf |

- **No data:** hatched #55555B / #AEAEB2 plus a dash.
- **Neutrals:**
  - bg: #000 / #F2F2F7
  - card: #0F1012, top-lit to #16171A / #FFF
  - well: #1C1D21 / #F2F2F7
  - ink: #F5F5F7 · #8E8E93 · #55555B (dark); #111113 · #6E6E73 · #AEAEB2 (light)
  - band: white 7% / black 5%
  - primary button: ink fill, no hue.
- **Recovery zones:** 67–100 Better, 34–66 Watch, 0–33 Worse.
- **Sleep stages:** Awake #FF7A59, REM #64D2FF, Core #0A84FF, Deep #5E5CE6.
- **Charts:**
  - Lines and fills are always the domain colour.
  - The personal band (median ± 1.4826·MAD over 30 days) sits behind every trend.
  - Only the last dot, a chip or a zone carries state colour.
  - Inside the band is neutral, never green.
  - Gaps are never interpolated.

## HONESTY RULES (reviewer rejects violations)

- Every number comes from a provider. Missing data shows the no-data state.
- Evidence chips cite only real note ids from `packages/knowledge/notes`.
- **Breathing:**
  - Only "Steady 5·5" and "Long exhale 4·6" cite `slow_breathing_hrv_acute` (Established).
  - The claim is limited to "raises HRV during the session". Never claim a baseline shift.
  - Box and 4-7-8 are labelled "Not in our base".
- **Water:**
  - The target is user-set. The app never prescribes a litre target (`hydration_everyday` directive 2).
  - "8 glasses" is only a default that the user can change. It is never a recommendation.
- No mortality or risk numbers projected onto the owner.

## PHASES (one commit each, in order)

**P0 Setup**
- Create the branch.
- Save the spec images and COACH_TASK.md into `design/redesign-2026-10/` if they aren't there.
- Create STATUS.md.
- Commit: `docs: add the 2026-10 redesign spec and build status`

**P1 Tokens** (`apps/mobile/lib/core/theme`: palette, instrument_hues, tone, metric_hue, stage_colors, sleep_stage_palette)
- Apply COLOUR RULES through the existing `Tone` / `toneFor()`; keep them as the single source.
- Move HRV, RHR and VO2max to heart; sri and sleep_health to sleep; cardio_load to load; skin temp, weight, BMR and bio age to fitness (Body); stress to Mind.
- Recovery uses zones, not a hue.
- Fix any colour-asserting tests.
- Commit: `style(mobile): unified domain and state colour system`

**P2 Chart grammar** (`shared/charts/v02`, `shared/v02/signal_chart.dart`, `v02_sparkline.dart`)
- Add the band, the state-coloured last dot and goal bars:
  - domain fill;
  - below goal at 32%;
  - today hatched while counting.
- Add diverging correlation bars: together = Strain, opposite = Activity.
- Commit: `feat(mobile): chart grammar with the usual band and state dot`

**P3 Health signals** (`features/history/metric_explorer_screen.dart`; split it if it passes 400 lines). Match image 02:
- Summary strip.
- Domain groups: Heart, Breathing & oxygen, Sleep, Activity, Body.
- Rows: name, polarity and usual range, sparkline over band, value, state chip.
- Goal rows use a progress bar; sleep health uses 4 check pills.
- Commit: `feat(mobile): Health signals grouped by body system`

**P4 Insights** (`features/insights/*`, `widgets/trends_section.dart`, `v02/pattern_panels.dart`). Match image 03:
- Two hero tiles.
- Effort & stress on one clipped time axis.
- 2×3 pattern tiles, 14-day average vs the prior 14.
- Diverging correlations.
- Links.
- Commit: `feat(mobile): Insights with band tiles and diverging correlations`

**P5 Coach server** (`apps/server/src/healthee`). Two agents may run in parallel: (a) review + job; (b) ledger.
- **a. Weekly review:**
  - `POST /api/coach/review` generates the weekly review on first call per ISO week, then returns the cached one.
  - It uses the COACH_TASK task text through the existing grounded-ask choke point, gated like `/api/coach`.
  - The prompt gets the new inputs listed in COACH_TASK.md (`jobs/recs_context.py`).
- **a. Weekly job:**
  - Replace the daily 1–3 recs in `jobs/recs.py` with a weekly job created as a challenge through the existing challenge/program engine (`challenges/` ladder, rung, evaluate).
  - The daily line is at most 2 sentences.
  - Keep the recs table readable for history.
- **b. Ledger:** `GET /api/coach/ledger?window=week|month|all` returns every yes with a verdict: done / partial / missed / no_data / uncheckable.
  - Each verdict carries the measured value that decided it.
  - Challenge days come from `challenges/evaluate` + `ledger`.
  - Legacy adopted recs get best-effort rules. A rec is never "done" without a measured value; if nothing measures it, it is "uncheckable".
- Tests for verdicts and the weekly cache.
- Commit: `feat(server): weekly coach review on demand, weekly job, verified ledger`

**P6 Coach mobile** (`features/actions/*` becomes the Coach screen; reuse `v02/challenge_card.dart`, `working_on.dart`, `data/challenges/*`, `data/recommendations/*`). Match images 04–07:
- Collapsed review row: calls `/api/coach/review` only on expand, with a streaming or skeleton state.
- This week's job: 7 day dots verified by the strap, plus a counts / when / bad-day list.
- Your record: week / month toggle.
- Every yes, checked: screen 06, from the ledger.
- Back to 150: screen 07, from the program feed.
- Remove the old suggestion deck, the intentions screen and the "What changed?" screen.
- **No "Did anything move" section.**
- Commit: `feat(mobile): Coach screen with an accountable weekly job and ledger`

**P7 Basics: water + breathing** (mobile only, no AI). Match images 04, 08, 09:
- **Water:**
  - Tapping the next glass logs `LogKind.water` 250 ml through `journal_repository`; tapping a full glass deletes the last entry.
  - The target is user-set; default 8. Colour is Body.
- **Breathing plan:** computed on device from the 60-day store.

  | Slot | When | Session |
  |---|---|---|
  | Morning | median wake over 14 nights, rounded to :15 | Steady 5 min |
  | Midday | 14:00 | Box 4 min |
  | Night | a user-set "free from" time, default 22:15 | Long exhale 10 min |
  | On demand | only if night stress ≥ 30 between 00:00–06:00 in the last 7 days | Long exhale 5 min |

  - Each row's reason text is built from real values.
  - Toggles plus "Accept all".
  - Reminders through `data/notifications`.
- **Player:**
  - Reuse `shared/v02/instruments/bio_halo.dart` / `halo_field.dart` with a Mind-tone colour and a scale driven by breath phase. Add a phase parameter; don't fork the painter.
  - Preset chips, an in/out phase bar, breath x of n, pause and end.
  - Respect reduced motion.
  - Finishing or ending logs `LogKind.meditation` with the actual minutes.
- Commit: `feat(mobile): water and breathing basics on the Coach screen`

**DONE**
- Final `flutter analyze` and the full mobile and server test runs, via a subagent.
- Push.
- STATUS.md says complete.
- Reply to the owner in 5 lines: what shipped, what was skipped and why, what needs his device to verify.
