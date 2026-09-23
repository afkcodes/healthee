#!/usr/bin/env bash
#
# Break each guard on purpose, and require a test to notice.
#
# A test that passes against broken code is not a test, and three of the guards
# in this app cannot be reached by using it:
#
#   * the 60-day horizon fires two months after a row is written;
#   * the `pushed_at_ms` retention guard fires a year after that;
#   * the daily-counter write is invisible until the day it was needed is over.
#
# `strap_store_test.dart` and `prune_safety_test.dart` name this file as their
# proof. It applies each mutation with an EXACT-STRING replacement that asserts
# it actually changed something — a patch that silently matched nothing runs the
# unmutated suite and reports a pass, which reads exactly like a working guard.
#
# Usage:  bash test/mutations.sh              (from apps/mobile — every mutation)
#         bash test/mutations.sh <substring>  (only the ones whose NAME matches)
#
# The filter is for iterating on a mutation you just wrote; CI runs the whole
# file. It skips by name only — a filtered run reports what it skipped, because a
# run that quietly did four of a hundred and forty-seven reads like a green suite.
#
# Exit 0  every mutation was caught.  Exit 1  at least one survived.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

ONLY="${1:-}"
PASS=0
FAIL=0
SKIPPED=0

# patch <file> <old> <new> — replaces exactly once, or aborts.
patch() {
  python3 - "$1" "$2" "$3" <<'PY'
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
src = open(path).read()
count = src.count(old)
assert count > 0, f'MUTATION DID NOT APPLY: no match in {path}'
open(path, 'w').write(src.replace(old, new))
print(f'  mutated {path} ({count} site(s))')
PY
}

# mutate <name> <test-target> <file> <old> <new> [<old2> <new2>]
# <test-target> may be more than one path, space-separated.
mutate() {
  local name="$1" target="$2" file="$3"
  shift 3
  if [ -n "$ONLY" ] && [[ "$name" != *"$ONLY"* ]]; then
    SKIPPED=$((SKIPPED + 1))
    return
  fi
  echo "── $name"
  cp "$file" "$file.orig"
  while [ "$#" -ge 2 ]; do
    if ! patch "$file" "$1" "$2"; then
      mv "$file.orig" "$file"
      echo "  ✗ PATCH FAILED — the mutation script is stale, not the code"
      FAIL=$((FAIL + 1))
      return
    fi
    shift 2
  done
  # shellcheck disable=SC2086 — $target is a space-separated list of paths.
  if flutter test $target >/dev/null 2>&1; then
    echo "  ✗ SURVIVED — $target passes against broken code"
    FAIL=$((FAIL + 1))
  else
    echo "  ✓ caught by $target"
    PASS=$((PASS + 1))
  fi
  mv "$file.orig" "$file"
}

PRUNE=lib/data/store/horizon_prune.dart
WRITER=lib/data/store/strap_writer.dart
SAFETY=test/store/prune_safety_test.dart
STORE=test/store/strap_store_test.dart

# ── the guard this whole file exists for ────────────────────────────────────
# Drop `pushed_at_ms IS NOT NULL` from the samples delete: an unsent
# measurement dies at 60 days again, silently. This IS the original defect.
mutate 'unsent samples are pruned at the horizon' "$SAFETY" "$PRUNE" \
  '    removed += await (delete(strapSamples)..where(
      (r) => r.day.isSmallerThanValue(horizon) & r.pushedAtMs.isNotNull(),
    )).go();' \
  '    removed += await (delete(strapSamples)..where(
      (r) => r.day.isSmallerThanValue(horizon),
    )).go();'

# The same guard on #121'"'"'s table — the since-midnight counter, which has no
# other home anywhere and cannot be re-read tomorrow.
mutate 'the unsent daily counter is pruned at the horizon' "$SAFETY" "$PRUNE" \
  '    removed += await (delete(deviceTotals)..where(
      (r) => r.day.isSmallerThanValue(horizon) & r.pushedAtMs.isNotNull(),
    )).go();' \
  '    removed += await (delete(deviceTotals)..where(
      (r) => r.day.isSmallerThanValue(horizon),
    )).go();'

# The other direction: the one-year bound stops distinguishing sent from unsent,
# so a row the server already has is destroyed AND reported as a loss.
mutate 'the one-year bound ignores pushed_at_ms' "$SAFETY" "$PRUNE" \
  '      ..where(
        strapSamples.day.isSmallerThanValue(floor) &
            strapSamples.pushedAtMs.isNull(),
      );' \
  '      ..where(strapSamples.day.isSmallerThanValue(floor));' \
  '    final rows = await (delete(strapSamples)..where(
      (r) => r.day.isSmallerThanValue(floor) & r.pushedAtMs.isNull(),
    )).go();' \
  '    final rows = await (delete(strapSamples)..where(
      (r) => r.day.isSmallerThanValue(floor),
    )).go();'

# A loss that is counted but not recorded: returned to one sync and gone by
# morning, which is how a data loss becomes a rumour.
mutate 'the loss is never written down' "$SAFETY" "$PRUNE" \
  '    await _recordLoss(rows, throughDay, at);' \
  ''

# ── the horizon itself ──────────────────────────────────────────────────────
# Off by one in the safe direction for storage and the wrong one for data: the
# boundary day goes too.
mutate 'the horizon eats its own boundary day' "$STORE" "$PRUNE" \
  'r.day.isSmallerThanValue(horizon) & r.pushedAtMs.isNotNull()' \
  'r.day.isSmallerOrEqualValue(horizon) & r.pushedAtMs.isNotNull()'

# ── #121, one layer up ──────────────────────────────────────────────────────
# The strap'"'"'s daily counter never reaches the store. On the server this cost
# 142 of 143 production days, permanently.
mutate 'the daily counter is never stored' "$STORE" "$WRITER" \
  '      if (result.dailyTotals case final totals?) {' \
  '      if (result.dailyTotals case final totals? when false) {'

# ── A1: the counter's READ INSTANT is the second measurement on that row ────
# The phone has always recorded WHEN it asked the strap, and never sent it. The
# server then substituted the ARRIVAL instant, so the partial-day caveat named
# the wrong moment — and suppressed itself entirely whenever a push crossed local
# midnight, which is the normal case. Two mutations, because there are two ways to
# get this wrong and only one of them looks wrong.
PUSH_BATCH=lib/data/push/push_batch.dart
PAYLOAD=test/push/push_payload_test.dart

# 1. The field goes back to not being sent at all — the defect itself.
mutate 'the read instant is dropped from the wire again' "$PAYLOAD" "$PUSH_BATCH" \
  "            'read_at': total.readAtMs," \
  ""

# 2. The subtler one: a plausible instant is sent that is not the reading. This is
# the failure to avoid — recreating the same lie with a new mechanism — and the
# payload still looks complete.
mutate 'the push time is sent as the read instant' "$PAYLOAD" "$PUSH_BATCH" \
  "            'read_at': total.readAtMs," \
  "            'read_at': DateTime.now().millisecondsSinceEpoch,"

# ── colour: the legacy hue set, and the mapping every sleep chart shares ────
HUES=lib/core/theme/instrument_hues.dart
PALETTE=lib/core/theme/palette.dart
STAGES=lib/core/theme/sleep_stage_palette.dart
HUES_TEST=test/theme/v02_tokens_test.dart
STAGE_TEST=test/theme/sleep_stage_test.dart
CONTRAST_TEST=test/theme/stage_contrast_test.dart
TOKEN_TEST=test/core/theme_test.dart

# The block this replaced mutated the five identity tags, whose whole invariant
# was that a tag could never be a verdict colour. Legacy makes two of its hues
# verdicts on purpose (cHrv IS the green, cHeart IS the alert), so that invariant
# is gone and mutating toward it would now be mutating toward CORRECT code.
#
# What is mutable now is the transcription itself, and the one mapping four
# charts share.

# A hue transcribed one digit wrong. Renders perfectly; is not legacy's app.
mutate 'a v02 family hue is transcribed wrong' "$HUES_TEST" "$PALETTE" \
  '  static const Color movement = Color(0xFF774000);' \
  '  static const Color movement = Color(0xFF774001);'

# The dark theme quietly wearing the light theme's value. Invisible by day.
mutate 'the dark hue set copies the light one' "$HUES_TEST" "$PALETTE" \
  '  static const Color sleep = Color(0xFFC5A8FF);' \
  '  static const Color sleep = LightFamilies.sleep;'

# The reverse of legacy's rule. Legacy FUSED identity and verdict (cHrv WAS the
# green); v02 separates them, so the regression is someone re-merging the two
# because "the fitness colour and the good colour should surely match".
mutate 'the fitness family is re-merged with the favourable verdict' "$HUES_TEST" "$PALETTE" \
  '  static const Color fav = Color(0xFF065F3D);' \
  '  static const Color fav = LightFamilies.fitness;'

# Two sleep stages collapsing onto one colour: a hypnogram that cannot be read.
mutate 'deep and light sleep share a colour' "$STAGE_TEST $CONTRAST_TEST" "$HUES" \
  "    'deep' => stageDeep," \
  "    'deep' => stageLight,"

# The pair swapped. Every night on every sleep screen is drawn inside out, and
# nothing about it looks broken.
mutate 'REM and awake are swapped' "$STAGE_TEST $CONTRAST_TEST" "$HUES" \
  "    'rem' => stageRem,
    'awake' => stageAwake," \
  "    'rem' => stageAwake,
    'awake' => stageRem,"

# `core` and `light` are one stage under two vocabularies. Giving them different
# colours draws a distinction that does not exist.
mutate 'core and light stop being the same stage' "$STAGE_TEST" "$HUES" \
  "    'core' || 'light' => stageLight," \
  "    'core' => stageRem,
    'light' => stageLight,"

# ── the shipped stage set is the prototype's ────────────────────────────────
# `design/mobile-preview/richer.css` ships four stage hues and those are what the
# app draws. They were once substituted for a derived luminance ramp on
# accessibility grounds; the owner restated the rule — the prototype IS the
# specification — so the substitution is reverted and the measurements are kept
# as recordings. Every mutation below is a way for a stage to drift off
# `richer.css` while still rendering perfectly.

# The whole dark set reverted to legacy's borrowed metric hues — the edit made by
# someone who reads the ramp's docstring and not the file header above it.
mutate "legacy's four dark stage values replace the prototype's" \
  "$CONTRAST_TEST $TOKEN_TEST" "$STAGES" \
  '  static const Color darkDeep = Color(0xFF7859E3);' \
  '  static const Color darkDeep = Color(0xFFD9A84E);' \
  '  static const Color darkLight = Color(0xFF9EBDFF);' \
  '  static const Color darkLight = Color(0xFF7DA3C4);' \
  '  static const Color darkRem = Color(0xFFDA7BDD);' \
  '  static const Color darkRem = Color(0xFF968EC9);' \
  '  static const Color darkAwake = Color(0xFFFFBD76);' \
  '  static const Color darkAwake = Color(0xFFE07A5F);'

# ONE value moved. A wholesale-revert test would not catch a single-line edit,
# and one wrong stage is a whole hypnogram lane painted in another stage's hue.
mutate "the dark REM value alone drifts off richer.css" \
  "$CONTRAST_TEST $TOKEN_TEST" "$STAGES" \
  '  static const Color darkRem = Color(0xFFDA7BDD);' \
  '  static const Color darkRem = Color(0xFF968EC9);'

# The same, in the theme the owner reads by day.
mutate "the light AWAKE value alone drifts off richer.css" \
  "$CONTRAST_TEST $TOKEN_TEST" "$STAGES" \
  '  static const Color lightAwake = Color(0xFFEDA253);' \
  '  static const Color lightAwake = Color(0xFFBF472E);'

# The superseded ramp put back where the prototype's set belongs — the exact
# revert this branch exists to undo, and it renders beautifully.
mutate 'the superseded ramp is restored over the prototype' \
  "$CONTRAST_TEST $TOKEN_TEST" "$HUES" \
  '      stageDeep = V02StagePrototype.darkDeep,' \
  '      stageDeep = DarkStagePalette.deep,'

# The split undone at the source: a stage pointed back at its metric hue. This is
# the edit that looks like a tidy-up — "these are the same colour, why two names".
mutate 'a stage colour is re-merged with its metric hue' \
  "$CONTRAST_TEST $TOKEN_TEST $STAGE_TEST" "$HUES" \
  '      stageDeep = V02StagePrototype.darkDeep,' \
  '      stageDeep = DarkFamilies.movement,'

# The kept record decaying into a story. The superseded ramp is retained so the
# trade stays legible, and its docstring claims it darkens monotonically by
# depth; scramble it and the claim is fiction nobody checks.
mutate 'the superseded ramp stops measuring what it claims' \
  "$CONTRAST_TEST" "$STAGES" \
  '  static const Color deep = Color(0xFFFECC73);
' \
  '  static const Color deep = Color(0xFF8A82BC);
' \
  '  static const Color rem = Color(0xFF8A82BC);
' \
  '  static const Color rem = Color(0xFFFECC73);
'

# The grey joining the ramp. "Unrecognised" is the absence of a stage identity;
# giving it chroma makes it a fifth stage nobody named.
mutate 'the unrecognised grey gains chroma' "$CONTRAST_TEST" "$STAGES" \
  '  static const Color unstaged = Color(0xFF797979);' \
  '  static const Color unstaged = Color(0xFF79885F);'

# `the stage bar stops naming its segments` lived here until the v02 redesign.
# It broke `h_stage_bar.dart`'s `Semantics` label, so colour became the only
# carrier on Today's 10 px sleep bar. v02 removed the grid that bar sat in and
# the file with it, so there is nothing left to break — the seven-night stack
# that replaced it carries a legend, which is a different claim with its own
# mutation ('the seven-night stack is drawn from no nights').

# ── the fifth row: an unrecognised stage ────────────────────────────────────
# The two halves of one defect, in two files, and each is enough on its own to
# put a byte nobody decoded on screen as a named stage. Fixing one and not the
# other looks fixed and is not: `normaliseStage` launders the code into `core`
# BEFORE the colour mapping ever sees it.
FORMAT=lib/features/sleep/sleep_format.dart

mutate 'an unrecognised code is painted as light sleep again' "$STAGE_TEST" "$HUES" \
  "    _ => unstaged," \
  "    _ => stageLight,"

mutate 'an unrecognised code is renamed to light sleep again' "$STAGE_TEST" "$FORMAT" \
  "  return kUnrecognisedStage;
}" \
  "  return 'core';
}"

# ── the two tiles that were withheld forever ────────────────────────────────
FACTS=lib/features/today/today_facts.dart
VITALS_TEST=test/features/today_overnight_vitals_test.dart

# Reverting the fallback restores the bug exactly: both surfaces go back to
# saying "the server did not say why" about numbers in the same payload.
mutate 'Resp and SpO2 go back to claiming no data' "$VITALS_TEST" "$FACTS" \
  "    return firstRefusal ??
        (overnight?.hasValue ?? false ? overnight! : _absent);" \
  "    return firstRefusal ?? _absent;"

# The honest bug replacing the dishonest one: the right number with its
# instrument unnamed, so a raw session average reads as today's derived figure.
mutate 'the overnight value loses its instrument caveat' "$VITALS_TEST" "$FACTS" \
  "    return Caveated<double>(value, <Disclosure>[" \
  "    return Present<double>(value); // ignore: dead_code
    return Caveated<double>(value, <Disclosure>["

# ── the insight rewrite ─────────────────────────────────────────────────────
FINDINGS=lib/shared/findings_section.dart
WORDING=test/features/findings_wording_test.dart

# The regression this change exists to undo: the server's debug string back on
# the surface as the headline.
mutate 'the raw Spearman string is the headline again' "$WORDING" "$FINDINGS" \
  '  if (a == null) {
    return '"'"'A pattern in your own data'"'"';
  }' \
  '  if (a == null || true) {
    return finding.description ?? '"'"'A pattern in your own data'"'"';
  }'

# The failure that would make the rewrite WORSE than what it replaced: readable,
# and causal about an observational n-of-1.
mutate 'the headline acquires a causal verb' "$WORDING" "$FINDINGS" \
  "    _ => 'moved with'," \
  "    _ => 'improves',"

# The caveat dropped from the disclosure, so opening the arithmetic means
# leaving the framing behind.
mutate 'the caveat is dropped from the disclosure' "$WORDING" "$FINDINGS" \
  "    'One person, one stretch of time, nothing controlled. It says the two moved '
        'together — not that either one caused the other.'," \
  "    ''," \

# ── the two resting heart rates ─────────────────────────────────────────────
STRAP_STRIP=lib/features/diagnostics/widgets/metric_strip.dart
SERVER_STRIP=lib/features/diagnostics/widgets/server_metric_strip.dart
TABS=test/features/tab_screens_test.dart

# The owner'"'"'s own bug report: two differently-defined numbers under one label,
# with nothing anywhere saying they are different instruments. The stream still
# CARRIES its instrument sentence here; the row just stops drawing it, which is
# exactly how an attribution is lost — nothing is deleted and nothing is shown.
mutate 'the strap row stops naming its instrument' "$TABS" "$STRAP_STRIP" \
  '        if (metric.stream.instrument case final String note)' \
  '        if (metric.stream.instrument case final String note when false)'

# The same failure from the other side: the canonical row stops saying it is the
# canonical one, so the two numbers are back to disagreeing in silence.
mutate 'the canonical row stops naming its method' "$TABS" "$SERVER_STRIP" \
  '        if (_instrumentNote(card.metric) case final String note)' \
  '        if (_instrumentNote(card.metric) case final String note when false)'

# ── Today is LEGACY'S screen, in legacy's order ─────────────────────────────
BODY=lib/features/today/today_body.dart
ORDER_TEST=test/features/today_order_test.dart

# A re-ordering. The v02 prototype reads night, then day, then the longer view,
# and the whole point of the rebuild is that the owner's screen matches it. A
# swap like this compiles, renders, and looks like a design decision somebody
# made.
mutate "the prototype's chapter order is swapped" "$ORDER_TEST" "$BODY" \
  '  _nightChapter(sections, facts, reveals, extras);
  todayDaySections(sections, facts, data, extras);' \
  '  todayDaySections(sections, facts, data, extras);
  _nightChapter(sections, facts, reveals, extras);'

# The bridge under the hero moves above it. It still reads as a sentence about
# the estimate, the chapters are untouched, and nothing looks wrong — the
# connective line has simply stopped connecting the two things it names.
mutate 'the context bridge is drawn before the hero' "$ORDER_TEST" "$BODY" \
  '  sections.add(
    TodaySummaryTiles(
      facts: facts,
      onOpenRecovery: extras.onOpenRecovery,
      onOpenSleep: extras.onOpenSleep,
      onOpenActivity: extras.onOpenActivity,
    ),
  );
  // No spacer: the bridge carries the gap itself so its rule can span it and
  // reach the tiles above. See `ContextBridge.leadIn`.
  sections.add(
    ContextBridge.link(
      kAgeBridge,
      label: '"'"'See the contributors'"'"',
      onOpen: extras.onOpenBody,
    ),
  );' \
  '  sections.add(
    ContextBridge.link(
      kAgeBridge,
      label: '"'"'See the contributors'"'"',
      onOpen: extras.onOpenBody,
    ),
  );
  sections.add(
    TodaySummaryTiles(
      facts: facts,
      onOpenRecovery: extras.onOpenRecovery,
      onOpenSleep: extras.onOpenSleep,
      onOpenActivity: extras.onOpenActivity,
    ),
  );
  sections.gap(PageSpacing.block);'

# A section quietly dropped. Legacy draws the week whenever it has two nights;
# a card that stops appearing is the failure mode a rendered-scroll test cannot
# see, because most of Today is never built at 800x600.
mutate 'a legacy section is dropped' "$ORDER_TEST" "$BODY" \
  '  if (snapshot.sleepHistory7d.length >= 2) {' \
  '  if (snapshot.sleepHistory7d.length >= 2 \&\& false) {'

# ── the connection surface may only be quiet when nothing is wrong ──────────
HEALTH=lib/data/sync/connection_health.dart
LINES=lib/data/sync/health_lines.dart
STRIP_TEST="test/features/today_connection_surface_test.dart test/features/connection_quiet_test.dart"

# The whole bargain of collapsing the strip to a dot. A quiet healthy state is
# honest ONLY if every unhealthy state is loud, so the mutation is the one that
# would be easy to write and impossible to see: the data-side faults stop
# reaching the surface and the dot keeps saying nothing is wrong.
mutate 'the data-side faults stop opening the strip' "$STRIP_TEST" "$HEALTH" \
  '      if (line.loud)
        ConnectionAlert(id: line.id, headline: line.headline!),' \
  '      if (false) ConnectionAlert(id: line.id, headline: line.headline!),'

# The link half, the same way round: an unreachable strap classified as fine.
mutate 'a failed link classifies as healthy' "$STRIP_TEST" "$HEALTH" \
  "  ConnectionFailed(:final failure) => <ConnectionAlert>[" \
  "  ConnectionFailed(:final failure) => failure.code.isNotEmpty ? null : <ConnectionAlert>["

# A phone that has never read its strap, reported as resting.
mutate 'never-synced classifies as healthy' "$STRIP_TEST" "$HEALTH" \
  '  Disconnected(:final lastCompleteSync) => lastCompleteSync == null' \
  '  Disconnected(:final lastCompleteSync) => lastCompleteSync != null'

# `quiet` is the ONE place the answer is computed. A widget that could decide it
# for itself could decide it while something is wrong.
mutate 'quiet stops accounting for the alerts' "$STRIP_TEST" "$HEALTH" \
  '  bool get quiet => !busy && alerts.isEmpty;' \
  '  bool get quiet => !busy;'

# A loud line whose short form goes missing renders as nothing on the strip.
# The constructor makes that impossible; this is the check that it stays so.
mutate 'a loud line ships with an empty headline' "$STRIP_TEST" "$LINES" \
  "  headline: 'Not signed in to a server'," \
  "  headline: '',"

# ── the ring, and the card that carries what a ring cannot say ──────────────
CARD=lib/features/today/widgets/data_health_section.dart
RING=lib/shared/connection/sync_ring.dart
SURFACE_TEST="test/features/today_connection_surface_test.dart test/features/connection_quiet_test.dart"
RING_TEST=test/features/sync_ring_test.dart

# THE mutation the strip's deletion is exposed to. The two RADIO faults have no
# `HealthLine` behind them, so the card is the only place their words exist —
# dropping the loop leaves them classified, loud, and drawn nowhere at all.
mutate 'the radio faults stop reaching the card' "$SURFACE_TEST" "$CARD" \
  '          for (final alert in link) ...[' \
  '          for (final alert in const <ConnectionAlert>[]) ...['

# The remedy dropped while the headline stays. "Bluetooth is off" with no
# "turn Bluetooth on" is a fault with no answer, and it looks fixed.
mutate 'a radio fault loses its remedy' "$SURFACE_TEST" "$CARD" \
  '            if (alert.detail case final String remedy) ...[' \
  '            if (alert.detail case final String remedy when false) ...['

# The ring deciding quietness for itself. It reads `quiet` — the ONE place the
# answer is computed — and a ring that consulted only the link would draw the
# resting state over a phone that cannot reach its server.
mutate 'the ring re-derives quiet from the link alone' "$RING_TEST" "$RING" \
  '  if (!health.quiet) {' \
  '  if (health.linkAlerts.isNotEmpty) {'

# An invented fraction. `strap_progress.dart` is explicit: a determinate bar that
# is really a guess is the interface version of a number nobody measured, and it
# makes a stalled sync indistinguishable from a working one in the other
# direction — the bar simply sits at whatever was invented.
mutate 'a phase with no progress fakes a fraction' "$RING_TEST" "$RING" \
  '        SyncRingState.syncing => health.progress?.fraction,' \
  '        SyncRingState.syncing => health.progress?.fraction ?? 0.5,'

# The fault ring wearing a verdict colour. `README.md`: there is one red and it
# is illness; `unf` is not a warning colour. A radio is not a fact about a body.
mutate 'the fault ring spends a verdict colour' "$RING_TEST" "$RING" \
  '    SyncRingState.needsAttention => colors.ink,' \
  '    SyncRingState.needsAttention => colors.unf,'

# The label collapsing to one sentence for every state: four colours and one
# word is what a screen reader gets from a ring nobody labelled.
mutate 'every ring state announces the same thing' "$RING_TEST" "$RING" \
  '    case SyncRingState.connected:
    case SyncRingState.idle:
      return health.report.headline;' \
  '    case SyncRingState.connected:
    case SyncRingState.idle:
      return '"'"'Syncing'"'"';'

# ── colour on Insights is a claim, and only where there is one ──────────────
POLARITY=lib/shared/format/metric_polarity.dart
TRENDS_TEST=test/features/insights_trends_test.dart

# The load-bearing case. Calories turning green or red is how the owner learns
# that every colour on the screen is decoration.
mutate 'a NEUTRAL metric acquires a verdict' "$TRENDS_TEST" "$POLARITY" \
  '    MetricPolarity.neutral || null => TrendVerdict.none,' \
  '    MetricPolarity.neutral ||
    null =>
      delta > 0 ? TrendVerdict.favourable : TrendVerdict.unfavourable,'

# The sign read as the verdict, which gets resting heart rate exactly backwards.
mutate 'polarity is ignored and the sign decides' "$TRENDS_TEST" "$POLARITY" \
  '    MetricPolarity.lowerIsBetter =>
      delta < 0 ? TrendVerdict.favourable : TrendVerdict.unfavourable,' \
  '    MetricPolarity.lowerIsBetter =>
      delta > 0 ? TrendVerdict.favourable : TrendVerdict.unfavourable,'

# ── an out-of-shell route reached with `go` is a one-way door ───────────────
SCREEN=lib/features/today/today_screen.dart
# The three rows moved onto the v02 settings index and the device screen when
# the supporting flows were rebuilt. The GUARD is unchanged — an out-of-shell
# route reached with `go` still has nothing beneath it — so the mutation follows
# the row rather than being retired with the widget that used to hold it.
SETTINGS_INDEX=lib/features/settings/settings_screen.dart
DEVICE_SCREEN=lib/features/settings/device_screen.dart
ROUTER=lib/core/router.dart
BACK_TEST="test/features/back_navigation_test.dart test/features/out_of_shell_navigation_test.dart"

# The defect exactly as it shipped, found on the device and not here. `go`
# REPLACES the location, so Settings has nothing beneath it: the shell's back
# rule finds an empty branch stack, correctly concludes "not on Today", and
# leaves the app — from a screen the owner tapped into two seconds earlier.
mutate 'the avatar reaches settings with go' "$BACK_TEST" "$SCREEN" \
  '          onOpenProfile: () => unawaited(context.push(Routes.settings)),' \
  '          onOpenProfile: () => context.go(Routes.settings),'

# Two levels out: back from diagnostics must land on the screen that opened it.
mutate 'diagnostics is reached with go' "$BACK_TEST" "$SETTINGS_INDEX" \
  '              onTap: () => unawaited(context.push(Routes.diagnostics)),' \
  '              onTap: () => context.go(Routes.diagnostics),'

mutate 'pairing is reached with go' "$BACK_TEST" "$DEVICE_SCREEN" \
  '              onTap: () => unawaited(context.push(Routes.pairing)),' \
  '              onTap: () => context.go(Routes.pairing),'

mutate 'the server screen is reached with go' "$BACK_TEST" "$SETTINGS_INDEX" \
  '              onTap: () => unawaited(context.push(Routes.serverSignIn)),' \
  '              onTap: () => context.go(Routes.serverSignIn),'

# "Done" on a PUSHED setup flow must return where it came from. Hard-coding the
# redirect'"'"'s answer throws away the screen underneath, which looks correct until
# somebody opens pairing from settings.
mutate 'leaving a setup flow always goes to Today' "$BACK_TEST" "$ROUTER" \
  '  if (context.canPop()) {
    context.pop();
  } else {
    context.go(Routes.today);
  }' \
  '  context.go(Routes.today);'

# ── the v02 supporting flows: settings, profile, account, pairing ───────────
APPEARANCE=lib/features/settings/appearance_screen.dart
PROFILE_FORM=lib/features/profile/widgets/profile_editor.dart
SESSION_CARD=lib/features/signin/widgets/server_session_card.dart
FRESHNESS=lib/features/settings/data_freshness_screen.dart
SETTINGS_TEST=test/features/settings_screen_test.dart
LAYOUT_TEST=test/features/settings_layout_test.dart
PROFILE_TEST=test/profile/profile_edit_test.dart

# Appearance must READ the one theme state, never hold a second copy. A control
# pinned to a literal renders one theme before the picker opens and another
# after — the exact drift the single source of truth exists to prevent.
mutate 'the appearance tiles stop reading the app state' "$SETTINGS_TEST" "$APPEARANCE" \
  '          selected: mode,' \
  '          selected: ThemeMode.light,'

# A prefilled weight that the owner taps Save on becomes a weight measured
# TODAY, and the freshness horizon that withholds a stale VO2max is then
# satisfied by a number nobody stepped on a scale for.
mutate 'the stored weight is prefilled as a new weigh-in' "$PROFILE_TEST" "$PROFILE_FORM" \
  '  final TextEditingController _weight = TextEditingController();' \
  '  late final TextEditingController _weight = TextEditingController(
    text: widget.profile.weightKg?.toString(),
  );'

# The card that overflowed by 110px on a 420px phone, restored. It went
# unnoticed because every suite pumped the 800px default.
mutate 'the session controls go back into a Row' "$LAYOUT_TEST" "$SESSION_CARD" \
  '          HButton(
            label: '"'"'Sign out'"'"',
            kind: HButtonKind.secondary,
            onPressed: enabled ? onSignOut : null,
          ),
          const SizedBox(height: stackGap),
          HButton(
            label: '"'"'Use a different server'"'"',
            kind: HButtonKind.soft,
            onPressed: enabled ? onReplace : null,
          ),' \
  '          Row(
            children: <Widget>[
              HButton(
                label: '"'"'Sign out'"'"',
                kind: HButtonKind.secondary,
                onPressed: enabled ? onSignOut : null,
              ),
              HButton(
                label: '"'"'Use a different server'"'"',
                kind: HButtonKind.soft,
                onPressed: enabled ? onReplace : null,
              ),
            ],
          ),'

# `disclosure.reason` is an operator'"'"'s filter key; `.message` is the sentence
# the owner reads. A row printing the key explains itself in our words.
mutate 'a withheld stream prints its filter key' "$SETTINGS_TEST" "$FRESHNESS" \
  '        disclosure.message,' \
  '        disclosure.reason,'

# ── Sleep: a panel that blanks a value without saying so ───────────────────
# The v02 Sleep screen's whole bargain is that a missing field renders as
# WITHHELD rather than as a bare dash. Half of that is the dash; the other half
# is the sentence naming what is missing and why. A dash with no sentence is a
# blank, and it is exactly what a "the panel still renders" test passes for —
# which is why each refusal line is deleted here on purpose.
WITHHELD_TEST=test/features/sleep_withheld_test.dart
CHECKS_TEST=test/features/sleep_checks_test.dart
CHARTS_TEST='test/features/sleep_charts_test.dart test/features/sleep_stage_charts_test.dart'
READING=lib/features/sleep/v02/sleep_reading.dart
VITALS=lib/shared/v02/vitals_table.dart
CHECKS=lib/features/sleep/v02/checks_panel.dart
BANDS=lib/features/sleep/v02/sleep_cutoffs.dart
TIMING_CHART=lib/shared/charts/v02/v02_timing_chart.dart
TIMING=lib/features/sleep/v02/timing_panel.dart
NIGHT=lib/features/sleep/v02/night_panels.dart
SHARES=lib/features/sleep/v02/stage_shares.dart

mutate 'the night reading blanks its refusals' "$WITHHELD_TEST" "$READING" \
  '    for (final field in <String, Reading<double>>{
      '"'"'Time asleep'"'"': night.tstMin,' \
  '    for (final field in <String, Reading<double>>{
      if (false) '"'"'Time asleep'"'"': night.tstMin,'

mutate 'the overnight table stops naming what it could not measure' \
  "$WITHHELD_TEST" "$VITALS" \
  '    for (final vital in rows)' \
  '    for (final vital in <Vital>[])'

# The legacy defect itself: a dimension the server never scored drawn as a
# PASSED check. A tick made out of nothing is worse than no tick at all.
mutate 'an unscored sleep check renders as a pass' "$CHECKS_TEST" "$CHECKS" \
  '      child: passed == true' \
  '      child: passed != false'

# CLAUDE.md's no-composite rule, at the one place it could be broken silently:
# the payload already carries the count, so drawing it is a one-line change that
# looks like a helpful summary in review.
mutate 'THE FOUR CHECKS ARE SUMMED INTO ONE NUMBER' "$CHECKS_TEST" "$CHECKS" \
  '          for (var i = 0; i < rows.length; i++)' \
  '          PanelValue(
            night.healthScore.valueOrNull?.round().toString() ?? '"'"'—'"'"',
            unit: '"'"'/ 4'"'"',
          ),
          for (var i = 0; i < rows.length; i++)'

# A published cutoff hard-coded back into the widget. The panel would keep
# printing 7–9 hours beside a check the server scored against 6–8.
mutate 'the duration cutoff comes out of the widget again' "$CHECKS_TEST" "$BANDS" \
  '  double get durationLowMin => (cutoffs?.durationHours?.first ?? 7) * 60;' \
  '  double get durationLowMin => 7 * 60;'

# ── Sleep: an interpolation that invents a reading ──────────────────────────
# Catmull-Rom overshoots. On two late nights either side of an early one it
# draws a bedtime earlier than any night measured — the same class of error as a
# spline through nightly minimums drawing a minimum lower than any night.
mutate 'the timing curve goes back to Catmull-Rom' "$CHARTS_TEST" "$TIMING_CHART" \
  '    final path = curvePath(points, SeriesCurve.monotone);' \
  '    final path = smoothPath(points);'

# ── Sleep: a chart that is present and draws nothing ────────────────────────
# Two charts on this screen once shipped at zero height because a suite only
# checked the widget existed.
mutate 'the stage timeline is handed no height' "$CHARTS_TEST" "$NIGHT" \
  '                progress: t,
                height: chartHeight,' \
  '                progress: t,
                height: 0,'

# One point is not a line. Below the floor the panel must draw nothing and keep
# its slot, not plot a single night as a trend.
mutate 'a one-night timing chart is plotted anyway' "$CHARTS_TEST" "$TIMING" \
  '          if (bedtime.length < 2)' \
  '          if (bedtime.length < 0)'

# The bar's LENGTH is the share. Flatten it and a stage the owner never entered
# is drawn as long as the one that took most of the night — the same lie the
# stacked strip could tell with a one-pixel sliver, in the mark that replaced it.
mutate 'the stage bars stop encoding the share' "$CHARTS_TEST" "$SHARES" \
  '        final fill = _minFill + share.clamp(0.0, 1.0) * (allowance - _minFill);' \
  '        final fill = allowance;'

# ── Today: a refusal must never come back as a number ───────────────────────
WITHHELD_TEST=test/features/today_withheld_test.dart

# Four mutations against `lib/features/today/widgets/metric_tile.dart` lived
# here — a withheld grid cell drawing a number, dropping its remedy, a caveated
# cell that stops marking itself, and the reserved disclosure line. The v02
# redesign replaced the six-cell grid with `summary_tile.dart` and the file
# became unreachable from `main.dart`, so all four are gone with it. The claim
# they guarded is not: a withheld reading still has to say why, and that is the
# next mutation down, against `reading_view.dart`, which is what every v02
# surface goes through.

# A withheld BLOCK silently vanishing is legacy's own behaviour and the one this
# port deliberately does not keep: an absent card and a broken screen look the
# same.
mutate 'a withheld block is dropped instead of explained' "$WITHHELD_TEST" \
  lib/shared/states/reading_view.dart \
  '      Withheld<T>(:final disclosure) =>
        withheldBuilder?.call(context, disclosure) ??
            WithheldCard(
              disclosure: disclosure,
              label: label,
              onExplain: onExplainWithheld,
            ),' \
  '      Withheld<T>() => const SizedBox.shrink(),'

# The v02 carrier drops the REASON and keeps the hole. A dash with nothing
# beside it is the state this whole layer exists to make impossible: it reads as
# "nothing happened" rather than as "the server would not say".
mutate 'the withheld panel drops its reason' "$WITHHELD_TEST" \
  lib/shared/v02/withheld_panel.dart \
  '                  child: Text(
                    disclosure.message,' \
  '                  child: Text(
                    '"'"''"'"',' 

# ── a compacted caveat must not become an invisible one ─────────────────────
# The disclosures moved off the card and into a sheet on 2026-08-06, because the
# server's are essays and four of them under one card is what the owner reported.
# Every mutation below is the SAME failure the compaction could have introduced:
# the prose is gone from the screen and nothing took its place. None of them look
# broken — that is the entire risk, and it is worse than the essay was.
VIEW=lib/shared/states/reading_view.dart
CAVEAT=lib/shared/states/caveat_disclosure.dart
MODULE=lib/shared/instrument_module.dart
CAVEAT_TEST="test/features/today_caveat_surface_test.dart test/shared/reading_view_test.dart test/shared/caveat_carriers_test.dart test/features/caveat_attribution_test.dart"

# THE mutation: a Caveated renders exactly like a Present. This is what "just
# stop printing the bullet points" would have been if nobody replaced them, and
# it is a one-line diff that makes the screen look better.
mutate 'a caveated value renders as if it were Present' "$CAVEAT_TEST" "$VIEW" \
  '      Caveated<T>(:final value, :final caveats) => switch (caveatCarrier) {' \
  '      Caveated<T>(:final value) => builder(context, value),
      // ignore: dead_code
      Caveated<T>(:final caveats) => switch (caveatCarrier) {'

# The module ignoring what it was handed — same outcome, one layer down, and it
# takes out the blood-oxygen module, the HRV module and every card a ReadingView
# hands its disclosures down to.
mutate 'the module drops the caveat note' "$CAVEAT_TEST" "$MODULE" \
  '                if (disclosed.isNotEmpty)
                  CaveatNote(caveats: disclosed, label: named),' \
  ''

# The module stops CLAIMING the scope. This is the 2026-08-06 orphan defect
# reintroduced: the disclosure is still drawn, by `ReadingView`, as a sibling
# beneath the whole card — in the gutter, naming neither card. Nothing looks
# missing, which is exactly why it needs a mutation.
mutate 'the card stops claiming its own caveats' "$CAVEAT_TEST" "$MODULE" \
  '    final scope = CaveatScope.of(context);
    final disclosed = <Disclosure>[...caveats, ...?scope?.caveats];' \
  '    final scope = CaveatScope.of(context);
    final disclosed = <Disclosure>[...caveats];'

# The sheet keeping only the first disclosure. The card still says "4 things
# tilt this number", so the count and the contents disagree and only the sheet
# knows. Biological age loses three paragraphs including the SRI exclusion.
mutate 'the sheet shows only the first disclosure' "$CAVEAT_TEST" "$CAVEAT" \
  '            for (final caveat in caveats) _CaveatBlock(caveat: caveat),' \
  '            _CaveatBlock(caveat: caveats.first),'

# The headline stops counting. It is the ONLY part of a compacted caveat a
# reader sees without tapping, so this is where a dropped disclosure has to
# become visible — a fixed sentence would hide it completely.
mutate 'the headline stops counting the disclosures' "$CAVEAT_TEST" "$CAVEAT" \
  "String caveatHeadline(int count) => count == 1
    ? 'Caveated — one thing tilts this number'
    : 'Caveated — \$count things tilt this number';" \
  "String caveatHeadline(int count) => 'Caveated';"

# ── the asterisk must not come back ─────────────────────────────────────────
# `the caveat goes back to a bare footnote mark` lived here — it put
# `caveatFootnote` back to the bare `*` the owner asked about on the installed
# build. Its only render site was `CaveatFoot`, the grid tile's carrier, and its
# only caller was `metric_tile.dart`. v02 has ONE carrier, the note inside the
# panel or the hero, so the foot, its footnote string and this mutation all went
# with the grid.
#
# The claim is still guarded, in the place a bare glyph could now come back:
# `caveat_attribution_test.dart::isBareMark` fails on any carrier that draws a
# lone `*`, `†` or `‡`, and `the headline stops counting the disclosures` above
# breaks the sentence that replaced it.

# ── the two quiet chart inks ────────────────────────────────────────────────
# The gridline defect exactly as it shipped: `withValues` REPLACES the alpha, so
# a 10% hairline is drawn at 70%. On dark that is the "almost white" the owner
# reported, and it looks like a deliberate emphasis in a diff.
CHART_INK=test/theme/chart_ink_test.dart

mutate 'a gridline derives itself from the hairline again' "$CHART_INK" \
  lib/shared/charts/h_stacked_sleep.dart \
  '      ..color = colors.grid' \
  '      ..color = colors.line.withValues(alpha: 0.7)'

# The reference line back at full ink3 — the same weight as the caption naming
# it, which is what the owner asked us to quieten.
mutate 'the reference line goes back to full-strength ink' "$CHART_INK" \
  lib/shared/charts/h_area.dart \
  '                referenceInk: colors.reference,' \
  '                referenceInk: colors.ink3,'

# Today'"'"'s picture of the night. `hypnogramSpans` was mutated here until
# 2026-08-06 — it guarded legacy'"'"'s fabricated one-minute light-sleep band for an
# unstaged night. The grid cell that drew it, and the `HStageBar` that replaced
# it, both went with the v02 redesign; the seven-night stack carries the guard
# now, in the same shape: no nights, no chart. Feeding it an empty list is the
# claim the deleted fallback made in reverse — a chart slot that says nothing
# about nights we DO have staged.
#
# `every sleep stage is drawn the same width` sat here too, against
# `h_stage_bar.dart`. That file is unreachable from `main.dart` now, so the
# mutation went with it.
SLEEP_CELL_TEST="test/features/grid_sleep_cell_test.dart test/features/today_charts_test.dart"

mutate 'the seven-night stack is drawn from no nights' "$SLEEP_CELL_TEST" \
  lib/features/today/v02/night_panels.dart \
  '            builder: (context, t) =>
                HStackedSleep(nights, progress: t, height: chartHeight),' \
  '            builder: (context, t) => HStackedSleep(
                  const <SleepNightSummary>[],
                  progress: t,
                  height: chartHeight,
                ),'

# A factor the model did not score, drawn as a factor scored zero. An empty
# track and a full-length zero-width fill are the same picture; the em dash in
# the reading column is the only thing that says which of the two this is.
mutate 'an unscored recovery factor reads as zero' \
  test/features/today_screen_test.dart \
  lib/shared/v02/meters.dart \
  '                          child: factor.fraction == null
                              ? const SizedBox.shrink()
                              : FractionallySizedBox(' \
  '                          child: factor.fraction == 999
                              ? const SizedBox.shrink()
                              : FractionallySizedBox('

# The factor rows print the payload's own keys. `rr` under a bar on a health
# screen is a log line where a name belongs.
mutate 'a recovery factor is labelled by its wire key' \
  test/features/today_screen_test.dart \
  lib/features/today/v02/recovery_panel.dart \
  '                  factorLabel(factor.name),' \
  '                  factor.name,'

# ── a modal sheet is over the APP, not over one tab ─────────────────────────
# The owner's report: "the info sheet comes beyond the navbar". Both halves are
# mutated here because each is enough on its own to put the tail of a sheet
# under an opaque bar, and each looks completely fine in review.
SHEET=lib/shared/sheets/app_sheet.dart
INFO=lib/shared/metric_info/metric_info_sheet.dart
LAYER_TEST=test/features/sheet_layering_test.dart

# The defect exactly as it shipped: the DEFAULT. `useRootNavigator: false`
# resolves the current tab's branch navigator, which lives inside
# `Scaffold.body`, so the sheet is laid out in one tab's content box and stops
# at the bar's top edge.
mutate 'the sheet goes back to the tab branch navigator' "$LAYER_TEST" "$SHEET" \
  '    useRootNavigator: true,' \
  '    useRootNavigator: false,'

# The other half: covering the bar means owning the inset the bar was absorbing.
# Dropping it puts the sources inside the gesture bar, which reads as fixed.
mutate 'the sheet foot stops leaving the gesture inset' "$LAYER_TEST" "$INFO" \
  '      padding: EdgeInsets.fromLTRB(22, 12, 22, 32 + sheetBottomInset(context)),' \
  '      padding: const EdgeInsets.fromLTRB(22, 12, 22, 32),'

# ── a reference line is a CLAIM ─────────────────────────────────────────────
# Owner report 2026-08-06: "can we change the heartrate, stress, hrv, blood
# oxygen graphs to be more meaningful ones, this graphs all look similar." The
# fix gave each chart a reference — and the SECOND report, on that build, was
# "stress is named as AROUSAL, heart rate is also looks wried, same as blood
# oxygen you just made it bad": three of the four captions had been painted on
# top of the data, the metric had been renamed out from under him, and two
# y-scales spent the plot on air.
#
# ## What the v02 redesign took, and what it did not
#
# Twelve mutations here were aimed at legacy's four vitals cards
# (`stress_card`, `blood_oxygen_card`, `hrv_trend_card`, `metric_note`) and at
# `h_deviation.dart` / `h_night_line.dart`. Every one of those files is
# unreachable from `main.dart` now and deleted, so those mutations are deleted
# too — including the three `wearable_stress_validity` D1–D4 ones, whose
# directives are still enforced where the coach can reach them
# (`insights/guard_directives.py`) rather than on a card nobody draws.
#
# The four below survive because their FILES survive: `chart_reference.dart` is
# drawn by five live v02 painters, and `h_area.dart` by the diagnostics metric
# strip. They lost their old test target with the cards, so they are retargeted
# at `chart_reference_test.dart`, which asserts the same geometry against the
# primitive instead of through a card that no longer exists.
REFERENCE=lib/shared/charts/chart_reference.dart
AREA=lib/shared/charts/h_area.dart
REFERENCE_TEST=test/shared/chart_reference_test.dart

# ── THE DEFECT THE OWNER PHOTOGRAPHED: a label lying on the data ────────────
# `YOUR 30-DAY NORMAL 53 MS` across the HRV trace, `RESTING 56` in the same
# pixels as the hour captions, a 55-character SpO2 sentence through the nights.
# It renders, and the label is drawn CORRECTLY — in the wrong place. Nothing
# short of geometry catches that, which is why it shipped.
mutate 'a reference caption is painted back into the plot' "$REFERENCE_TEST" "$REFERENCE" \
  '  } else {
    canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
  }
}' \
  '  } else {
    canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
  }
  final label = chartLabel(
    reference.label,
    TextStyle(fontSize: 8, color: color),
  );
  label.paint(canvas, Offset(0, (y - label.height - 1).clamp(0.0, size.height)));
}'

# The other half of "looks wried", and it is invisible to every assertion about
# WHAT was drawn: the reference painted first, so a grey hairline sits under a
# 32% clay wash and comes out as brown sludge. This is the code as it shipped.
mutate 'the reference goes back behind the fill' "$REFERENCE_TEST" "$AREA" \
  '    for (final reference in references) {
      paintChartReference(
        canvas,
        size,
        reference,
        scale: scale,
        color: referenceInk,
        progress: progress,
      );
    }
' \
  '' \
  '    if (fill) {' \
  '    for (final reference in references) {
      paintChartReference(
        canvas,
        size,
        reference,
        scale: scale,
        color: referenceInk,
        progress: progress,
      );
    }

    if (fill) {'

# `include:` is what makes a reference honest rather than decorative. Dropped,
# the resting line still draws — on the floor of the box, where it reads as
# "you never went below your resting rate". A false claim made by layout alone.
mutate 'the heart-rate reference is left out of its own scale' "$REFERENCE_TEST" "$AREA" \
  '      include: <double>[for (final line in references) line.value],' \
  '      include: const <double>[],'

# The padding made symmetric again — "why would a reference pad differently from
# the data?" It is a tidy-up, it renders, and it is the owner'"'"'s flat trace: his
# day drops from 59% of its plot to 51%, and a reading in an empty box is what
# he was looking at when he said the chart looked wrong.
mutate 'the reference pad reverts to the data pad' "$REFERENCE_TEST" "$REFERENCE" \
  '  static const double referencePadFraction = 0.06;' \
  '  static const double referencePadFraction = padFraction;'

# ── v02 charts: the foundation and the series charts (phase 2a) ─────────────
V02_FOUNDATION="test/shared/v02_chart_foundation_test.dart"
V02_SERIES="test/shared/v02_charts_series_test.dart"
V02_COLUMNS="test/shared/v02_charts_columns_test.dart"
V02_TICKS="lib/shared/charts/v02/chart_ticks.dart"
V02_CURVE="lib/shared/charts/v02/chart_curve.dart"
V02_SCRUB="lib/shared/charts/v02/chart_scrub.dart"
V02_FRAME="lib/shared/charts/v02/chart_frame.dart"
V02_INK="lib/shared/charts/v02/chart_ink.dart"
V02_VOID="lib/shared/charts/v02/chart_void.dart"
V02_COLUMN_PAINTER="lib/shared/charts/v02/column_painter.dart"
V02_BARS="lib/shared/charts/v02/v02_bar_chart.dart"
V02_LINKED="lib/shared/charts/v02/v02_linked_chart.dart"
V02_LINKED_PAINTER="lib/shared/charts/v02/linked_painter.dart"

# The axis goes back to the prototype's [min, mid, max]: three rules at whatever
# the data reached, so every chart carries a different arbitrary scale.
mutate 'the tick step stops being a round number' "$V02_FOUNDATION" "$V02_TICKS" \
  '  return multiple * magnitude;' \
  '  return rough;'

# The Fritsch-Carlson limiter removed. The curve is still smooth and still
# passes through every sample -- and now draws values between them that the
# sensor never produced.
mutate 'the monotone limiter is dropped' "$V02_FOUNDATION" "$V02_CURVE" \
  '    if (radius > 9) {' \
  '    if (radius > 1e9) {'

# The turning-point rule removed, which is the half that stops a curve
# continuing downward past a local minimum.
mutate 'a local extremum stops flattening the tangent' "$V02_FOUNDATION" "$V02_CURVE" \
  '    tangent[i] = slope[i - 1] * slope[i] <= 0
        ? 0
        : (slope[i - 1] + slope[i]) / 2;' \
  '    tangent[i] = (slope[i - 1] + slope[i]) / 2;'

# One reading becomes a line. This is the shipped bug: HArea([0, 0]).
mutate 'one sample is enough to draw a trend' "$V02_SERIES" "$V02_VOID" \
  '      if (measured >= 2) {' \
  '      if (measured >= 1) {'

# The tick labels move back inside the plot -- the exact 2026-08-06 failure,
# where three charts shipped with words lying across the trace.
mutate 'the value labels move into the plot' "$V02_SERIES" "$V02_FRAME" \
  '  final left = math.max(
    box.values.left,
    box.values.right - _gutterPad - painter.width,
  );' \
  '  final left = box.plot.left;'

# A withheld chart collapses its slot, so every card below it jumps when the
# sync lands and an absence stops looking like an absence.
mutate 'the empty slot stops holding its height' "$V02_SERIES" "$V02_VOID" \
  '      SizedBox(height: height, width: double.infinity);' \
  '      const SizedBox.shrink();'

# withValues REPLACES alpha. This is the gridline-at-five-times bug, exactly.
mutate 'the gridline alpha is replaced instead of scaled' "$V02_SERIES" "$V02_INK" \
  '    ..color = revealed(grid, progress)' \
  '    ..color = grid.withValues(alpha: progress)'

# The finger is mapped across the whole widget instead of the plot inside it, so
# the scrubber reports a sample next to the one under the cursor -- and looks
# exactly right doing it.
mutate 'the scrubber maps the finger against the widget, not the plot' "$V02_SERIES" "$V02_SCRUB" \
  '    final box = widget.metrics.box(Size(_width, widget.height));
    final index = box.indexAt(dx, widget.sampleCount);' \
  '    final index = ((dx / _width).clamp(0.0, 1.0) * (widget.sampleCount - 1))
        .round();'

# A bar axis cut above zero: a 9,000-step day then draws twice the bar of an
# 8,000-step day, and nobody can see the arithmetic that did it.
mutate 'the bar axis stops standing on zero' "$V02_COLUMNS" "$V02_BARS" \
  '                zeroBased: true,' \
  '                zeroBased: false,'

# A measured zero and an unmeasured day become the same picture.
mutate 'a measured zero stops marking its baseline' "$V02_COLUMNS" "$V02_COLUMN_PAINTER" \
  '    final height = math.max(full.abs() * progress.clamp(0.0, 1.0), _floorMark);' \
  '    final height = full.abs() * progress.clamp(0.0, 1.0);'

# Both panes forced onto one axis: heart rate flattens into the bottom third and
# the crossing point of the two traces starts looking like it means something.
mutate 'the linked panes share one scale' "$V02_COLUMNS" "$V02_LINKED" \
  '          ticks: ChartTicks.nice(pane.values.whereType<double>(), target: 2),' \
  '          ticks: ChartTicks.nice(
            panes.first.values.whereType<double>(),
            target: 2,
          ),'

# The lanes abut, and the second pane title sits on the first pane fill.
mutate 'the linked lanes stop leaving air between them' "$V02_COLUMNS" "$V02_LINKED_PAINTER" \
  'const double _laneGap = 5;' \
  'const double _laneGap = 0;'

# ── the v02 hero instruments ────────────────────────────────────────────────
HALO=lib/shared/v02/instruments/bio_halo.dart
FIELD=lib/shared/v02/instruments/halo_field.dart
WATERFALL=lib/shared/v02/instruments/age_waterfall.dart
RULER=lib/shared/v02/instruments/age_scale.dart
RAIL=lib/shared/v02/instruments/vo2max_rail.dart
HALO_TEST=test/shared/instruments/halo_motion_test.dart
AGE_TEST=test/shared/instruments/age_instruments_test.dart
FITNESS_TEST=test/shared/instruments/fitness_instruments_test.dart

# THE failure the waterfall exists to prevent. A term that could not be computed
# is drawn as a minimum-height bar, which is pixel-identical to the sleep term
# that WAS computed and came out at zero. One says "we could not price this",
# the other says "we priced it and it was nothing".
mutate 'an excluded age term is drawn as a stub bar' "$AGE_TEST" "$WATERFALL" \
  '            from: running,
            to: null,' \
  '            from: running,
            to: running,'

# The ladder snapped onto the estimate. It looks tidier, and it draws a
# reconciliation that did not happen.
mutate 'the waterfall snaps its ladder onto the estimate' "$AGE_TEST" "$WATERFALL" \
  '    final anchor = column.from == null ? bottom : y(column.from!);' \
  '    final anchor = column.from == null ? bottom : y(column.to ?? running);'

# A value off the 28-44 ruler clamped to the end instead of drawing nothing.
mutate 'the age ruler clamps an off-scale estimate' "$AGE_TEST" "$RULER" \
  '    if (onScale(estimate, low: kAgeScaleLow, high: kAgeScaleHigh)) {' \
  '    if (estimate.isFinite) {'

# The three ways the halo must stop, broken one at a time: a halo that pauses
# two ways out of three still burns the battery the third way.
mutate 'the halo keeps animating in the background' "$HALO_TEST" "$HALO" \
  '    _foreground = state == AppLifecycleState.resumed;' \
  '    _foreground = true;'

mutate 'the halo ignores the system reduced-motion setting' "$HALO_TEST" "$HALO" \
  '    _reducedMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;' \
  '    _reducedMotion = false;'

mutate 'the halo keeps animating offscreen' "$HALO_TEST" "$HALO" \
  '    if (!_onScreen()) {
      _ticker.stop();
      return;
    }
' \
  ''

# The still centre stops being enforced, so particles drift across the figure.
mutate 'particles are allowed into the still centre' "$HALO_TEST" "$FIELD" \
  '    if ((at - centre).distance < stillRadius) {
      return null;
    }
' \
  ''

# The extent renamed. A wording mutation on purpose: the sentence is the honesty
# half of the instrument, and it is as breakable as the geometry.
mutate 'the error magnitude is called a confidence interval' "$FITNESS_TEST" "$RAIL" \
  'const String kErrorMagnitudeNote = '"'"'not a confidence interval'"'"';' \
  'const String kErrorMagnitudeNote = '"'"'a 95% confidence interval'"'"';'

# ── the v02 Today: what a panel may not stop saying ─────────────────────────
PANEL=lib/shared/v02/panel.dart
HERO=lib/shared/v02/bio_hero.dart
HERO_PARTS=lib/shared/v02/bio_hero_parts.dart
MINI=lib/features/today/v02/mini_trend_panel.dart
FITNESS=lib/features/today/v02/longer_panels.dart
HERO_TEST=test/features/today_hero_test.dart
V02_CAVEAT_TEST="test/features/today_caveat_surface_test.dart test/features/caveat_attribution_test.dart"

# The v02 carrier stops reading the scope it was handed. `ReadingView` draws
# nothing itself under `CaveatCarrier.insideCard`, so this is the disclosure
# vanishing in silence — the one failure worse than the essay it replaced.
mutate 'the v02 panel drops the caveats it was handed' "$V02_CAVEAT_TEST" "$PANEL" \
  '              caveats: disclosed,
              caveatsLabel: named,' \
  '              caveats: const <Disclosure>[],
              caveatsLabel: named,'

# The same, in the hero. It is not a `Panel`, so it needs its own block and its
# own mutation: the biological-age block carries FOUR disclosures on the
# committed payload and is the card the owner reported.
mutate 'the hero drops the caveats it was handed' "$V02_CAVEAT_TEST" "$HERO" \
  '        caveats: disclosed,' \
  '        caveats: const <Disclosure>[],'

# A half-width panel blanking on a refusal. It keeps its title, its slot and its
# chart void, and stops saying why the number is missing — which reads as a
# metric that simply has nothing today.
#
# The target moved with the v02 deletions: the assertion lived in
# `vitals_thresholds_test.dart`, which was the suite for legacy's four vitals
# cards, but this half of it was always about `MiniTrendPanel` and never about a
# card. It is in `today_screen_test.dart` now, on the real payload.
mutate 'a twin panel blanks instead of saying why' \
  test/features/today_screen_test.dart "$MINI" \
  '      withheldBuilder: (context, disclosure) =>
          _panel(value: '"'"'—'"'"', note: disclosure.message),' \
  '      withheldBuilder: (context, disclosure) =>
          _panel(value: '"'"'—'"'"', note: '"'"''"'"'),'

# The tier id printed raw. `gps_graded` under a VO₂max figure is an identifier
# where an instrument's name belongs, and it looks like a deliberate label.
mutate 'the VO2max method is printed as its wire id' \
  test/features/today_screen_test.dart "$FITNESS" \
  "      'Read by \${methodLabel(vo2max.method)}'," \
  '      vo2max.method,'

# The server's 300-character method prose back inline. This is the owner's
# *"raw text below the fitness card"* report, arriving by the shortest route.
mutate "the method essay is printed on the card again" \
  "test/features/today_caveat_surface_test.dart" "$FITNESS" \
  '          PanelNote(_qualifiers(vo2max)),' \
  '          PanelNote(vo2max.methodCaveat),'

# A meter drawn against a target the payload never sent. `/api/today` carries no
# step goal, so any fraction here is this app inventing the owner's target and
# then reporting progress against it.
mutate 'the movement tile invents a step target' "$HERO_TEST" \
  lib/features/today/v02/today_hero.dart \
  '      fraction: plateau == null ? null : steps / plateau,' \
  '      fraction: steps / 10000,'

# The halo placed outside the scroll it watches. It still animates, it still
# looks right on the first screen, and it never pauses again.
mutate 'the hero art is dropped from the card' "$HERO_TEST" \
  lib/features/today/v02/today_hero.dart \
  '      art: const BioHalo(),' \
  '      art: null,'

# ── the v02 Today fixes (withheld hero · provenance off the cards) ───────────
ENVELOPE=lib/data/honesty/envelope.dart
WITHHELD_HERO=lib/features/today/v02/today_hero_withheld.dart
HERO_PARTS=lib/shared/v02/bio_hero_parts.dart
SHEET=lib/shared/metric_info/metric_info_sheet.dart
NIGHT=lib/features/today/v02/night_panels.dart
RECOVERY=lib/features/today/v02/recovery_panel.dart
CHAPTER=lib/shared/v02/chapter.dart
EXCLUDED=lib/shared/states/withheld_card.dart
BODY=lib/features/today/today_body.dart
WITHHELD_HERO_TEST=test/features/today_withheld_hero_test.dart
PROVENANCE_TEST=test/features/card_provenance_test.dart
SWEEP_TEST=test/features/citation_sweep_test.dart
FINDINGS=lib/shared/findings_section.dart
ACTIVITY_LEVEL=lib/features/profile/widgets/activity_level_field.dart
CHAPTER_TEST=test/shared/chapter_heading_test.dart
READING_TEST=test/shared/reading_view_test.dart

# THE ORIGINAL DEFECT. The composite `withheld` block carries `consequence` +
# `terms` and no top-level `reason`, so the envelope read it as absent, the null
# value fell through to `Excluded`, and Today drew the 400-word regularity essay
# where the hero belongs. Put the blind spot back.
mutate 'the composite withheld block is unreadable again' \
  "$WITHHELD_HERO_TEST" "$ENVELOPE" \
  '    return _composite(raw);' \
  '    return null;'

# The essay back on the card's face, by the shortest route there is.
mutate 'the withheld hero prints the server prose inline' \
  "$WITHHELD_HERO_TEST" "$WITHHELD_HERO" \
  '      kWithheldPointer,
      if (left.isNotEmpty)' \
  '      withheld.message,
      for (final term in withheld.terms) term.message,
      for (final exclusion in exclusions) exclusion.message,
      kWithheldPointer,
      if (left.isNotEmpty)'

# A marker placed for a value that does not exist — the held figure fed to the
# ruler, which is exactly the stale-as-current step this design forbids.
mutate 'a held value is drawn on the age ruler' \
  "$WITHHELD_HERO_TEST" "$WITHHELD_HERO" \
  "import 'package:healthee/shared/v02/bio_hero.dart';" \
  "import 'package:healthee/shared/v02/bio_hero.dart';
import 'package:healthee/shared/v02/instruments/age_scale.dart';" \
  '      figure: BioWithheldFigure(' \
  '      instrument: held == null
          ? null
          : AgeScale(estimate: held.value, chronologicalAge: 36),
      figure: BioWithheldFigure('

# The date blanked. A held figure with no date IS the stale-as-current bug.
mutate 'the last-known date is blanked' \
  "$WITHHELD_HERO_TEST" "$HERO_PARTS" \
  "          '\$asOfPrefix\${plainDay(day)}'," \
  "          ''," 

# The refused hero collapsed back into a panel — the small dashed box the owner
# read as the card being missing.
mutate 'the refused hero collapses into a panel' \
  "$WITHHELD_HERO_TEST" "$BODY" \
  '      withheldBuilder: (context, disclosure) => TodayBioHeroWithheld(
        withheld: disclosure,
        exclusions: switch (snapshot.biologicalAge) {
          Withheld<BiologicalAge>(:final exclusions) => exclusions,
          _ => const <Disclosure>[],
        },
      ),' \
  '      withheldBuilder: (context, disclosure) => WithheldPanel(
        disclosure: disclosure,
        label: '"'"'Biological age · estimate'"'"',
      ),'

# The ⓘ sheet emptied of the sources the cards handed it. Every card would keep
# its ⓘ and lose its grounding — the one way this change can do harm.
mutate "the info sheet drops the card's citations" \
  "$PROVENANCE_TEST" "$SHEET" \
  '              noteIds: _notes,' \
  '              noteIds: const <String>[],'

# A reference pill back on a card's face.
mutate 'an unscored dimension prints its cutoff as a reading' \
  test/features/today_withheld_test.dart "$NIGHT" \
  '            dimension.reading ?? '"'"'—'"'"',' \
  '            dimension.reading ?? dimension.cutoff,'

# Clinical routing swept away with the method text. A symptom outranks the score
# above it, and that sentence is not clutter.
mutate 'the illness-priority sentence is tidied off the card' \
  "$PROVENANCE_TEST" "$RECOVERY" \
  '          const PanelNote(kRecoveryPriorityNote),' \
  ''

# The exclusion essay back inline, under every value that has one.
mutate 'the exclusion prints its reasoning on the card again' \
  "$READING_TEST" "$EXCLUDED" \
  '                  child: Text(
                    headline(exclusions),' \
  '                  child: Text(
                    exclusions.first.message,'

# The equal-flex split restored: the title and the rule share the row, so every
# chapter heading is cut and the rule stops half way.
mutate 'the chapter title goes back to sharing the row' \
  "$CHAPTER_TEST" "$CHAPTER" \
  '              SizedBox(
                width: wanted < room ? wanted : (room < 0 ? 0 : room),
                child: Text(' \
  '              Flexible(
                child: Text('

# ── the prototype's own chrome: the pinned nav, the glint, the date control ──
# Four things had drifted from `design/mobile-preview/` on judgement calls that
# were not ours to make. Each mutation below is the drift coming back, and every
# one of them renders perfectly.
SHELL_SRC=lib/shared/instrument_screen.dart
BODY_SRC=lib/features/today/today_body.dart
REVEAL=lib/shared/reveal_once.dart
PINNED_TEST=test/features/chapter_nav_pinned_test.dart
REVEAL_TEST=test/shared/reveal_once_test.dart
HALO=lib/shared/v02/instruments/halo_painter.dart
HALO_TEST=test/shared/instruments/halo_ink_test.dart
PARTS=lib/shared/v02/panel_parts.dart
PARTS_TEST=test/shared/panel_value_width_test.dart
VIEW_DATE=lib/data/store/view_date.dart
DEVICE_REPO=lib/data/device/device_repository.dart
SECTIONS=lib/features/today/today_sections.dart
DATE_TEST=test/features/date_control_test.dart

# The nav un-pinned — the edit that reads as a simplification and silently gives
# back `position: sticky`.
mutate 'the chapter nav scrolls away again' "$PINNED_TEST" "$BODY_SRC" \
  '    sections.addPinned(
      TodayChapterNav(chapters: chapters),
      ChapterNav.extentOf,
    );' \
  '    sections.add(TodayChapterNav(chapters: chapters));'

# The pin kept but the shell told to ignore it. Same rendered result, different
# line, and a test that only watched the call site would miss it.
mutate 'the shell stops honouring a pinned section' "$PINNED_TEST" "$SHELL_SRC" \
  '      if (section.pinnedExtent case final SectionExtent extent) {' \
  '      if (section.pinnedExtent case final SectionExtent extent when false) {'

# `CLAUDE.md`'s hard rule, broken inside the restructured scroll: every chart
# replays its reveal on the way back, which is the known expensive legacy bug.
mutate 'a chart replays its reveal on scroll-back' \
  "$REVEAL_TEST $PINNED_TEST" "$REVEAL" \
  '  bool markSeen(Object id) => _seen.add(id);' \
  '  bool markSeen(Object id) {
    _seen.add(id);
    return true;
  }'

# The glint back to a brightness event: `--halo-warm` resolved and then not used.
mutate 'the halo glint stops being warm' "$HALO_TEST" "$HALO" \
  '      glint: colors.haloWarm,' \
  '      glint: colors.bioInk,'

# `--halo-warm` transcribed one digit wrong. Renders; is not the prototype.
mutate 'the halo warm is transcribed wrong' "$HALO_TEST" "$PALETTE" \
  '  static const Color haloWarm = Color(0xFFFED16B);' \
  '  static const Color haloWarm = Color(0xFFFED16C);'

# `.panel-summary` back to two equal halves, which clips every long figure on
# every phone width and looks fine on the 800 px test surface.
mutate 'the panel figure goes back to sharing the row' "$PARTS_TEST" "$PARTS" \
  '                    width: _figureWidth(
                      context,
                      constraints.maxWidth - gap,
                      context.compactPanel,
                    ),' \
  '                    width: (constraints.maxWidth - gap) / 2,'

# ⛔ STALE-AS-CURRENT, and note where it moved to. This used to break Today'"'"'s
# past-day REFUSAL. `/api/today` answers for a day now, so there is no refusal
# left to break — the guarantee is that a payload is drawn only under the day it
# answers for, which lives in `ScreenData.snapshot` and is mutated at the end of
# this file. What survives here is the LAYOUT decision, which must still follow
# the reader'"'"'s selection: force it and a past day is dressed as the current one.
mutate "the past-day layout stops following the selection" \
  "$DATE_TEST" "$SECTIONS" \
  '  final past = data.view.isPast;' \
  '  const past = false;'

# The window gone: the control can ask for tomorrow, or for a day the horizon
# already pruned, and both answer with a screen of withholds.
mutate 'the date control can leave its window' "$DATE_TEST" "$VIEW_DATE" \
  '  void select(String day) {
    if (isViewableDay(day, ref.read(todayProvider))) {
      state = day;
    }
  }' \
  '  void select(String day) {
    state = day;
  }'

# The selection stops reaching the data: the header moves and the screen does
# not, which is a date control that lies about what is under it.
mutate 'the measured half stops following the selection' \
  "$DATE_TEST" "$DEVICE_REPO" \
  '  return store.strapReader.day(ref.watch(viewDateProvider));' \
  '  return store.strapReader.day(ref.watch(todayProvider));'

HERO=lib/shared/v02/bio_hero.dart
HERO_PARTS=lib/shared/v02/bio_hero_parts.dart
GEOMETRY_TEST=test/features/today_hero_geometry_test.dart
FIELD_TEST=test/features/today_hero_field_test.dart

# ── the hero's geometry ─────────────────────────────────────────────────────
# THE DEFECT ITSELF: the field stops being a background layer and becomes a
# sized child of the stack, so the card is as tall as the FIELD and the
# contributions and the model label go off the bottom of the screen.
mutate 'the field drives the card height' "$GEOMETRY_TEST" "$HERO_PARTS" \
  '  return Positioned.fill(
    // The constraints here are the card'"'"'s finished size' \
  '  return SizedBox.fromSize(
    size: const Size(300, 900),
    // The constraints here are the card'"'"'s finished size'

# The clip goes soft: `overflow: clip` over a 28px radius becomes a square
# corner, and the field paints into the four corners the card does not have.
mutate 'the card stops clipping to its rounded corner' "$FIELD_TEST" "$HERO" \
  '      clipBehavior: Clip.antiAlias,' \
  '      clipBehavior: Clip.none,'

# The hole goes back to the middle of the CARD: the densest part of the field
# crosses the figure, and the still centre lands on the sentence and the ruler.
mutate 'the still centre leaves the figure' "$FIELD_TEST" "$HERO_PARTS" \
  '        stillCentre: centred
            ? bioStillCentre(constraints.biggest)
            : Alignment.center,' \
  '        stillCentre: Alignment.center,'

# `motion.css` resets `.age-value { margin: 0 }`; richer.css'"'"'s 20 comes back
# and the square no longer starts directly under the eyebrow.
mutate 'the centred display takes the inline layout gap' \
  "$GEOMETRY_TEST" "$HERO" \
  '    if (!centred) const SizedBox(height: valueGap),' \
  '    const SizedBox(height: valueGap),'

# The two margins stop being told apart: the divider'"'"'s own 16 is replaced by
# the collapsed 18, which is only right when the caption abuts the rule.
mutate 'the divider gap is always the collapsed one' "$GEOMETRY_TEST" "$HERO" \
  '        height: caption != null && instrument == null ? ruleGap : dividerGap,' \
  '        height: ruleGap,'

# The eyebrow row stops being the control'"'"'s 32: the still centre'"'"'s arithmetic
# is then wrong by the difference, and the square moves up.
mutate 'the eyebrow row loses its pinned extent' "$GEOMETRY_TEST" "$HERO" \
  '        minHeight: centred ? eyebrowExtent : 0,' \
  '        minHeight: 0,'

# The rim's dust handed the stream heads' glow — one line, and 1,120 grains
# become solid balls six times too wide. This IS the defect the owner reported.
SCALE_TEST=test/shared/instruments/halo_scale_test.dart
mutate 'the rim dust wears the stream glow' \
  "$SCALE_TEST" lib/shared/v02/instruments/halo_painter.dart \
  '    dust.forEach(
      (dot) => canvas.drawPoints(
        ui.PointMode.points,
        dot.at,
        _dot(
          glint: dot.glint,
          width: dot.extent,' \
  '    dust.forEach(
      (dot) => canvas.drawPoints(
        ui.PointMode.points,
        dot.at,
        _dot(
          glint: dot.glint,
          width: dot.extent * 6,'

# ── Activity and Insights, rebuilt to v02 ──────────────────────────────────
ACT_SECTIONS=lib/features/activity/activity_sections.dart
ACT_TRAIN=lib/features/activity/v02/training_panels.dart
ACT_MOVE=lib/features/activity/v02/movement_panels.dart
INS_TRENDS=lib/features/insights/widgets/trends_section.dart
ACT_ORDER_TEST=test/features/activity_order_test.dart
INS_ORDER_TEST=test/features/insights_order_test.dart
SURFACE_TEST=test/features/activity_insights_surface_test.dart
EMPTY_TEST=test/features/today_empty_states_test.dart

# The refusal loses its carrier and the panel silently vanishes from the list —
# the failure `WithheldPanel` exists for, and the one a "does it render" test
# passes straight through.
mutate 'a refused Activity block draws nothing instead of saying why' \
  "$EMPTY_TEST" "$ACT_SECTIONS" \
  '        withheldBuilder: (context, disclosure) => WithheldPanel(
          disclosure: disclosure,
          label: '"'"'Active minutes · MVPA'"'"',
        ),' \
  '        withheldBuilder: (context, disclosure) => const SizedBox.shrink(),'

# The wire id reaches a health screen where the instrument'"'"'s NAME belongs.
# [[hr_reserve_vo2max]] D4 requires the method wherever the number is, and
# `gps_graded` is a log line, not a method.
mutate 'the VO2max method is printed as its wire id on Activity' \
  "$SURFACE_TEST" "$ACT_TRAIN" \
  "      'Read by \${methodLabel(vo2max.method)}'," \
  "      'Read by \${vo2max.method}',"

# The reference pill returns to the card face. The owner asked twice for these
# to live in the info sheet; the sources must stay reachable, not stay printed.
mutate 'the reference label returns to the intensity card' \
  "$SURFACE_TEST" "$ACT_MOVE" \
  "          PanelValue('\${mvpa.weekMin}', unit: 'equivalent min')," \
  "          PanelValue('\${mvpa.weekMin}', unit: 'equivalent min',
              context_: 'Reference \${mvpa.weekTarget} min/week'),"

# The prototype'"'"'s order breaks: the age bridge climbs above the panel whose
# number it is about, so a connective sentence arrives before the thing it
# connects to.
mutate "Activity's sections leave the prototype's order" \
  "$ACT_ORDER_TEST" "$ACT_SECTIONS" \
  '  if (!past) {
    sections
      ..add(const InsightCard(scope: '"'"'activity'"'"', title: '"'"'Activity analysis'"'"'))
      ..gap(PageSpacing.panel);
  }' \
  '  sections.gap(PageSpacing.block);
  sections.add(const DataFooter());
  if (!past) {
    sections
      ..add(const InsightCard(scope: '"'"'activity'"'"', title: '"'"'Activity analysis'"'"'))
      ..gap(PageSpacing.panel);
  }'

# A heading over nothing. `insights_sections.dart` drops the head with the
# panels precisely so an empty block reads as silence rather than as breakage.
mutate 'Insights keeps a trends heading with no trends under it' \
  "$INS_ORDER_TEST" lib/features/insights/insights_sections.dart \
  '  if (trends.isNotEmpty) {
    sections.gap(PageSpacing.block);' \
  '  if (true) {
    sections.gap(PageSpacing.block);'

# THE load-bearing case, in its v02 carrier: a metric with no known polarity —
# or a neutral one — acquires a verdict colour, after which every colour on the
# screen is decoration and the two that are claims stop meaning anything.
mutate 'a polarity-less trend panel acquires a verdict colour' \
  test/features/insights_trends_test.dart "$INS_TRENDS" \
  '      TrendVerdict.none => null,' \
  '      TrendVerdict.none => colors.fav,'

# The sparkline collapses to nothing. Two charts have shipped at zero height in
# this repo because a test only asked whether the widget existed.
mutate 'a trend sparkline is laid out at zero height' \
  "$SURFACE_TEST" "$INS_TRENDS" \
  '  static const double sparklineHeight = 30;' \
  '  static const double sparklineHeight = 0;'
# ── Actions · Journal · Coach, rebuilt to v02 ───────────────────────────────
# The honesty layer on these three screens is almost entirely a set of things
# that must NOT be drawn — a bar with no observation behind it, an input with no
# balance behind it, a prompt that spends a question the owner does not have.
# Every one of those is invisible when it is right, so each is broken here.
SUGGESTION=lib/features/actions/v02/suggestion_card.dart
DECK_ITEM=lib/features/actions/v02/deck_item.dart
CHALLENGE_CARD=lib/features/actions/v02/challenge_card.dart
ACTIONS_SCREEN=lib/features/actions/actions_screen.dart
OUTCOME_CARD=lib/shared/challenge_outcome_card.dart
CHOICES=lib/shared/v02/choices.dart
COACH_SCREEN=lib/features/coach/coach_screen.dart
COACH_CTRL=lib/features/coach/coach_controller.dart
COMPOSER=lib/features/coach/v02/coach_composer.dart
JOURNAL_GRID=lib/features/journal/v02/journal_grid.dart
LOG_SHEET=lib/features/journal/v02/log_sheet.dart
ACTIONS_TEST=test/features/actions_v02_test.dart
CARDS_TEST=test/features/actions_cards_test.dart
COACH_TEST=test/features/coach_screen_test.dart
COMPOSER_TEST=test/features/coach_composer_test.dart
JOURNAL_TEST=test/journal/journal_screen_test.dart

# A snake_case token on a health screen is a log line where a source belongs.
mutate 'a raw signal id reaches the suggestion card' "$ACTIONS_TEST" "$SUGGESTION" \
  "  if (!hasMetricName(id)) {
    return 'Raised by a reading with no name in this app';
  }" \
  "  if (false) {
    return 'Raised by a reading with no name in this app';
  }
  return 'Raised by \$signal';"

# Adoption records an INTENTION. Nothing in this app observes the doing.
mutate 'the adopted line starts claiming the action was done' \
  "$CARDS_TEST" "$SUGGESTION" \
  "const String kAdoptedNote = 'An intention, not a completed action.';" \
  "const String kAdoptedNote = 'Done for today.';"

# The family is the rec's own category. A card that picked one would be a hue
# that can disagree with what the card is about — and the hue is the control's
# ground now, which is where the owner asked the category to speak.
mutate 'the suggestion row ignores its category' "$ACTIONS_TEST" "$DECK_ITEM" \
  '    tone: toneForCategory(rec.category),' \
  '    tone: Tone.fitness,'

# The ranking is the server's claim about which suggestion matters most today.
# A client that re-sorted it would be overruling that silently.
mutate 'the client re-sorts the server’s ranking' "$ACTIONS_TEST" "$ACTIONS_SCREEN" \
  '        SuggestionList(recommendations: recommendations),' \
  '        SuggestionList(recommendations: recommendations.reversed.toList()),'

# The prototype's order, moved by one: the owner's own record climbs above the
# suggestions, which are the screen's subject and the whole of its top half.
mutate 'the Actions sections come out of order' "$ACTIONS_TEST" "$ACTIONS_SCREEN" \
  '    const PageSection(SectionHead(title: kRecordHeading), gap: 0),' \
  '' \
  '    if (snapshot != null)
      PageSection(' \
  '    const PageSection(SectionHead(title: kRecordHeading), gap: 0),
    if (snapshot != null)
      PageSection('

# "Nothing observed yet" and "you are at zero" are different days.
mutate 'a challenge with no progress draws a bar at zero' "$CARDS_TEST" "$CHALLENGE_CARD" \
  '  static double? fraction(ChallengeProgress? progress) {
    if (progress == null) {
      return null;
    }' \
  '  static double? fraction(ChallengeProgress? progress) {
    if (progress == null) {
      return 0;
    }'

# A 7-day window over something nobody started reads as a commitment.
mutate 'a suggested challenge is labelled as a running one' "$CARDS_TEST" "$CHALLENGE_CARD" \
  "    return challenge.status == 'active'
        ? '\$window challenge'
        : 'Suggested · \$window';" \
  "    return '\$window challenge';"

# `.check-action .checkbox { width: 24px; height: 24px }`.
mutate 'the adopt checkbox loses its box' "$CARDS_TEST" "$CHOICES" \
  '  static const double boxSize = 24;' \
  '  static const double boxSize = 20;'

# Half a comparison drawn as a whole one is the claim the card refuses.
mutate 'an outcome invents the half of the comparison it was not sent' \
  "$CARDS_TEST" "$OUTCOME_CARD" \
  '    if (before == null || during == null) {
      return null;
    }' \
  '    if (during == null) {
      return null;
    }
    final start = before ?? during;'

# The sentence that keeps an outcome an observation.
mutate 'the outcome drops its "not a proven effect" sentence' \
  "$CARDS_TEST" "$OUTCOME_CARD" \
  "const String kObservationNote =
    'These are the readings inside the window, beside the readings before it. '
    'That is an observation, not a proven effect of the challenge.';" \
  "const String kObservationNote =
    'The challenge raised your average over the window.';"

# ── the coach's meter, which is the only spend in the product ───────────────
# An input beside an unknown or empty balance is the silent spend the feature is
# not allowed to have.
mutate 'the coach composer appears with no balance behind it' \
  "$COACH_TEST" "$COACH_SCREEN" \
  '  return uncapped || (allowance?.hasRemaining ?? false);' \
  '  return true;'

# A prompt button asks a question, so it costs one — same gate as the input.
mutate 'the opening prompts stop being gated by the balance' \
  "$COMPOSER_TEST" "$COACH_SCREEN" \
  '              canAsk ? ask : null),' \
  '              ask),'
# (anchor re-cut TWICE now: once when `ask` grew a `topic:` argument, and again
#  when the openers moved out of `_tail` into `CoachPrompts` so the ask box could
#  come before them. A stale patch runs the UNMUTATED suite and reports a pass,
#  which reads exactly like a working guard — so every move of this call is a
#  re-cut, not a hope.)

# `routers/coach.py` refunds three of five outcomes, so a local subtraction is
# wrong — and wrong the flattering way round. THE METER IS RE-READ.
mutate 'the meter stops being re-read after an attempt' "$COACH_TEST" "$COACH_CTRL" \
  '      if (_isCurrent(generation)) {
        ref.invalidate(coachEntitlementProvider);
        state = state.copyWith(asking: false);
      }' \
  '      if (_isCurrent(generation)) {
        state = state.copyWith(asking: false);
      }'

# The cost is on the button, before the tap, in the number.
mutate 'the cost comes off the ask button' "$COACH_TEST" "$COMPOSER" \
  "    remaining == null ? 'Ask' : 'Ask — uses 1 of your \$remaining';" \
  "    remaining == null ? 'Ask' : 'Ask';"

# A cost label that squeezes the input off the page satisfies "the label is
# present" and makes the surface unusable.
# The width negotiation went with the full-width ask bar: the field is
# `Expanded` beside a fixed send control, so an input that can be typed in is
# structural rather than negotiated. What can still take the room away is the
# control beside it growing — `Expanded` yields whatever is left, however
# little that is.
mutate 'the composer stops making room for its input' "$COMPOSER_TEST" "$COMPOSER" \
  '  static const double sendSize = 44;' \
  '  static const double sendSize = 240;'

# ── the journal ────────────────────────────────────────────────────────────
# Current fasting state is FETCHED, never inferred.
mutate 'the fast tile guesses instead of reading the state' \
  "$JOURNAL_TEST" "$JOURNAL_GRID" \
  "    final label = tile.kind == null && fastOpen ? 'End fast' : tile.label;" \
  '    final label = tile.label;'

# `grid-template-columns: repeat(3, minmax(0, 1fr))`.
mutate 'the journal grid loses a column' "$JOURNAL_TEST" "$JOURNAL_GRID" \
  '  static const int columns = 3;' \
  '  static const int columns = 2;'

# `screens-actions.js::H.journalKinds`, in its order.
mutate 'the journal kinds are reordered' "$JOURNAL_TEST" "$JOURNAL_GRID" \
  "  JournalKindTile(SolarIconsOutline.waterdrop, 'Water', LogKind.water),
  JournalKindTile(SolarIconsOutline.smileCircle, 'Mood', LogKind.mood)," \
  "  JournalKindTile(SolarIconsOutline.smileCircle, 'Mood', LogKind.mood),
  JournalKindTile(SolarIconsOutline.waterdrop, 'Water', LogKind.water),"

# An entry nobody acknowledged must not clear the form — the owner types a
# weight once.
mutate 'a failed journal write clears the draft anyway' "$JOURNAL_TEST" "$LOG_SHEET" \
  "      AppLog.failure('journal', 'saving an observation', error, stack);
      if (mounted) {" \
  "      AppLog.failure('journal', 'saving an observation', error, stack);
      _value.clear();
      if (mounted) {"

# The phone and the endpoint agree about what a valid entry is.
mutate 'an invalid amount reaches the wire' "$JOURNAL_TEST" "$LOG_SHEET" \
  '    if (problem != null) {
      setState(() => _message = problem);
      return;
    }' \
  '    if (problem != null) {
      setState(() => _message = problem);
    }'

# ── the v02 history surfaces ────────────────────────────────────────────────
TILE=lib/features/history/v02/metric_tile.dart
PANEL=lib/features/history/v02/history_panel.dart
WINDOW=lib/data/history/history_window.dart
EXPLORER=lib/features/history/metric_explorer_screen.dart
EXPLORER_TEST=test/history/metric_explorer_test.dart
HISTORY_TEST=test/history/history_screen_test.dart
WINDOW_TEST=test/history/history_window_test.dart

# A refusal that is silently dropped leaves the tile reading as "no data", which
# is a different and much softer claim than the server's own sentence.
mutate 'a withheld reading loses its reason in the tile' "$EXPLORER_TEST" "$TILE" \
  '    final refusal = withheld is Withheld<double>
        ? withheld.disclosure.message
        : null;' \
  '    final refusal = withheld is Withheld<double> ? null : null;'

# THE ONE THAT MATTERS MOST. Colour by the sign of the delta and every metric
# gets a verdict — after which the colours that really ARE verdicts stop meaning
# anything, and calories rising reads as good news.
mutate 'a polarity-unknown metric is coloured by the sign of its delta' \
  "$HISTORY_TEST" "$PANEL" \
  '      TrendVerdict.none => null,' \
  '      TrendVerdict.none => delta > 0 ? colors.fav : colors.unf,'

# Squeeze the holes out and a fortnight with two missing nights draws twelve
# evenly-spaced points with every one of them joined up.
mutate 'a missing day is squeezed out instead of left as a hole' \
  "$WINDOW_TEST $HISTORY_TEST" "$WINDOW" \
  '      values.add(byDay[day]);' \
  '      if (byDay[day] != null) values.add(byDay[day]);'

# One metric quietly missing from the directory is a door nobody can find, and
# the screen looks entirely correct without it.
mutate 'the explorer drops a metric from the directory' "$EXPLORER_TEST" "$EXPLORER" \
  '    for (final metric in HistoryMetric.values)
      _entryFor(metric, cards[metric.id], snapshot),' \
  '    for (final metric in HistoryMetric.values.skip(1))
      _entryFor(metric, cards[metric.id], snapshot),'

# An id on a tile is a log line where a name belongs.
mutate 'a tile falls back to the raw metric id' "$EXPLORER_TEST" "$EXPLORER" \
  '    title: card?.label ?? metricTitle(metric.id),' \
  '    title: card?.label ?? metric.id,'

# The window must stop on the day the reader chose. Showing the newest reading
# under an older date is stale-as-current at one metric's scale.
mutate 'the window ignores the selected day' "$WINDOW_TEST" "$WINDOW" \
  '      if (point.date.compareTo(day) <= 0) point,' \
  '      point,'

# ── the citation sweep: chips off every card, and still reachable ────────────
# Both directions, because either one alone is satisfied by the wrong fix. A
# suite that only checked the chip was gone would pass on DELETING the evidence.

# The chip back on the findings card — the exact regression the owner reported
# twice, and the one that lands on two screens at once (Insights and Sleep).
mutate 'a source chip returns to the findings card' \
  "$SWEEP_TEST" "$FINDINGS" \
  '        Text(
          findingWindow(finding),
          style: text.bodySmall?.copyWith(color: colors.ink2),
        ),' \
  '        Text(
          findingWindow(finding),
          style: text.bodySmall?.copyWith(color: colors.ink2),
        ),
        CitationRow(noteIds: finding.researchNoteIds),'

# The other half: the chips come off and the ⓘ is handed nothing. The card looks
# exactly as the sweep intended and the grounding is gone from the device.
mutate "the findings ⓘ is emptied of the card's citations" \
  "$SWEEP_TEST" "$FINDINGS" \
  '              detail: MetricDetail(
                title: headline,
                notes: finding.researchNoteIds,' \
  '              detail: MetricDetail(
                title: headline,
                notes: const <String>[],'

# The same emptying on the profile field, where the note behind five verbatim
# science labels is the only thing licensing them.
mutate 'the activity-level ⓘ loses the note its labels come from' \
  "$SWEEP_TEST" "$ACTIVITY_LEVEL" \
  "          notes: <String>['non_exercise_vo2max']," \
  '          notes: <String>[],'

# ── server prose: the chips came off, and the ⓘ has to have them ─────────────
# `GroundedProse` and `GroundedMarkdown` used to draw a citation row under every
# sentence a model wrote — four screens at once. The chips are gone; these three
# are the ways the grounding could go with them, each invisible on the card.

PROSE_TEST=test/features/prose_grounding_test.dart
LOSS_TEST=test/features/prose_grounding_loss_test.dart
REASONING=lib/shared/states/reasoning_note.dart
DETAIL=lib/shared/metric_info/metric_detail.dart

# (a) The ⓘ handed an empty note list while the prose still parses ids. This is
# the whole defect the move can introduce: the card looks exactly as intended
# and the evidence is off the device.
mutate 'a prose surface hands its ⓘ no sources at all' \
  "$PROSE_TEST" "$DETAIL" \
  '    notes: grounding.noteIds,' \
  '    notes: const <String>[],'

# (b) The unresolved markers dropped on the way into `MetricDetail`. A citation
# that resolves to nothing is OUR failure, not a fact about the owner's body,
# and this is the one loss that leaves no trace anywhere on the screen.
mutate 'the unresolved markers are dropped on the way to the ⓘ' \
  "$LOSS_TEST" "$DETAIL" \
  '    unresolved: grounding.unresolved,' \
  '    unresolved: const <String>[],'

# (c) The personal findings merged into the note ids, so an n-of-1 correlation
# from this owner's own history is drawn as a research citation and loses
# `kSingleSubjectFraming` with it.
mutate 'a personal finding is dressed as a research note in the ⓘ' \
  "$LOSS_TEST" "$DETAIL" \
  '    notes: grounding.noteIds,
    personalFindings: grounding.personalFindings,' \
  '    notes: <String>[...grounding.noteIds, ...grounding.personalFindings],
    personalFindings: const <String>[],'

# The prose surface that keeps its own dot: a disclosure whose answer is server
# prose. Gating the dot on the wrong thing takes the grounding off every one.
mutate 'a disclosure filled with server prose draws no ⓘ' \
  "$PROSE_TEST" "$REASONING" \
  '                if (_detail case final MetricDetail detail
                    when detail.isNotEmpty)' \
  '                if (_detail case final MetricDetail detail when false)'

# ── Workouts: the payload that had NO honesty envelope ─────────────────────
# `/api/activity/workout` sent a bare nullable for every derived metric and no
# `withheld` block at all, so nothing on the wire forced this screen to explain
# an absence. It carries `metrics_withheld` now
# (`docs/BACKEND_GAPS_FROM_UI.md` B6) and `workout_readings.dart` prefers it —
# but the local reasons stay as the fallback, because an installed app meets
# servers it did not ship with. Both halves are mutated below: dropping either
# is a silent regression in review.

W_READINGS=lib/data/workouts/workout_readings.dart
W_EFFORT=lib/features/workouts/v02/effort_cards.dart
W_CARDS=lib/features/workouts/v02/session_cards.dart
W_REFUSED=lib/features/workouts/v02/refused_figures.dart
W_ROWS=lib/features/workouts/v02/session_rows.dart
W_LIST=lib/features/workouts/workout_history_screen.dart
W_LABELS=lib/shared/format/workout_labels.dart
W_ORDER_TEST=test/features/workouts_order_test.dart
W_SURFACE_TEST=test/features/workouts_surface_test.dart
W_LABELS_TEST=test/shared/workout_labels_test.dart

# Zone minutes drawn against a scale that does not exist. The server sends
# `[0,0,0,0,0]` with no HRmax, so this renders five confident empty bars — a
# picture of an easy session, on a session nothing was measured against.
mutate 'the zones are drawn without the HRmax they are cut against' \
  "$W_SURFACE_TEST" "$W_READINGS" \
  '    detail.hrmax == null || detail.zones.isEmpty ? null : detail.zones,' \
  '    detail.zones.isEmpty ? null : detail.zones,'

# The server's own reason is discarded and the local guess printed instead. It
# looks harmless — a sentence still appears — and it is the whole point of B6
# undone: the server can see the resting heart rate and the profile sex that
# this payload does not carry, so its reason names the input that actually
# failed while the local one lists all four and hopes.
mutate 'the wire says which input failed and the app ignores it' \
  "$W_SURFACE_TEST" "$W_READINGS" \
  '      if (detail.withheld[serverKey] case final Disclosure stated) {' \
  '      if (null case final Disclosure stated) {'

# And the fallback removed: a server with no envelope would then refuse mutely,
# trading one silence for another.
mutate 'a payload without the envelope refuses without a reason' \
  "$W_SURFACE_TEST" "$W_READINGS" \
  "    'A session load needs your HRmax, your resting heart rate and your sex on '" \
  "    ''
        '"

# The hole stays and the sentence goes. `withheld_panel.dart`: a hole that says
# why it is a hole is the whole design; without the why it is a dash.
mutate 'the zones refusal keeps the hole and drops the reason' \
  "$W_SURFACE_TEST" "$W_READINGS" \
  "    'Zone minutes are cut against an HRmax estimate, and the server sent none '" \
  "    'Zone minutes are unavailable. '"

# A stat cell that vanishes with nothing said about it — exactly what the
# pre-v02 screen did, and the reason this file's whole workouts section exists.
mutate 'a dropped figure leaves no cell and no explanation' \
  "$W_SURFACE_TEST" "$W_REFUSED" \
  '    if (missing.isEmpty) {' \
  '    if (missing.isNotEmpty) {'

# CLAUDE.md pins free-living energy to the MET-by-state model. This kcal figure
# is the STRAP's own count, and unnamed an owner reads it as the model's.
mutate "the energy figure stops naming the strap as its instrument" \
  "$W_ORDER_TEST" "$W_CARDS" \
  '          if (energy.hasValue) const PanelNote(kEnergyInstrument),' \
  '          if (false) const PanelNote(kEnergyInstrument),'

# A second-half heart-rate change presented as a finding rather than a number.
mutate 'heart-rate drift loses the line saying what it is not' \
  "$W_ORDER_TEST" "$W_CARDS" \
  '          if (drift.hasValue) const PanelNote(kDriftCaveat),' \
  '          if (false) const PanelNote(kDriftCaveat),'

# The wire is one entry per RECORDED minute, so carrying the last reading across
# a gap draws a heart rate this app never measured, as confidently as the ones
# it did. This is the whole reason the series is laid back on a minute axis.
mutate 'the trace carries the last reading across a gap' \
  "$W_SURFACE_TEST" "$W_EFFORT" \
  '    return <double?>[for (var i = 0; i <= last; i++) slots[i]];' \
  '    var carried = points.first.value;
    return <double?>[
      for (var i = 0; i <= last; i++) carried = slots[i] ?? carried,
    ];'

# The declared join. A minute-sampled signal is the one case a spline is allowed
# for, and which spline it is decides whether the curve can leave its samples.
mutate 'the trace is joined by something other than the safe spline' \
  "$W_SURFACE_TEST" "$W_EFFORT" \
  "        unit: 'bpm',
        curve: SeriesCurve.monotone," \
  "        unit: 'bpm',
        curve: SeriesCurve.straight,"

# Present and painting nothing. Two sleep charts shipped at zero height because
# a suite only checked the widget was in the tree.
mutate 'the workout trace is handed no height' \
  "$W_SURFACE_TEST" "$W_EFFORT" \
  "        unit: 'bpm',
        curve: SeriesCurve.monotone," \
  "        unit: 'bpm',
        height: 0,
        curve: SeriesCurve.monotone,"

# `7:8` per kilometre. A pace is read as a clock, and a clock without its
# padding is a different number.
mutate 'a pace loses the padding that makes it a clock' \
  "$W_LABELS_TEST" "$W_LABELS" \
  "  return '\${minutes + (carried ? 1 : 0)}:\${shown.toString().padLeft(2, '0')}';" \
  "  return '\${minutes + (carried ? 1 : 0)}:\$shown';"

# A run of sessions with no day over it. The list then reads as "your workouts",
# undated — and the newest and the oldest look the same.
mutate 'the session list stops captioning its days' \
  "$W_ORDER_TEST" "$W_ROWS" \
  '      TinyLabel(prettyDate(date)),' \
  '      const SizedBox.shrink(),'

# The list is bounded by the server at 100 sessions of ten minutes. Without the
# sentence it reads as every session the owner has ever recorded.
mutate 'the list stops saying what it leaves out' \
  "$W_ORDER_TEST" "$W_LIST" \
  '        const SmallProse(kHistoryBounds),' \
  '        const SizedBox.shrink(),'


# ---------------------------------------------------------------------------
# The finding detail — the screen the owner tapped for and did not get.
# ---------------------------------------------------------------------------

PATTERNS=lib/features/insights/v02/pattern_panels.dart
DETAIL_PARTS=lib/features/insights/v02/finding_detail_parts.dart
DETAIL_SCREEN=lib/features/insights/v02/finding_detail_screen.dart
ROUTE_TEST=test/features/finding_detail_route_test.dart
WORDING_TEST=test/features/finding_detail_wording_test.dart
NAMES=lib/shared/format/metric_names.dart
NAMES_TEST=test/shared/metric_names_coverage_test.dart

# The original defect, restored: the card keeps its look and loses its
# destination. This is exactly the state the owner reported.
mutate 'the relationship card goes inert again' \
  "$ROUTE_TEST" "$PATTERNS" \
  "      actionLabel: 'Explore'," \
  '      actionLabel: null,'

# The finding stops travelling, so the screen must re-derive numbers it was
# already handed — a second source of truth for one figure.
mutate 'the finding no longer rides along with the tap' \
  "$ROUTE_TEST" "$PATTERNS" \
  '          extra: finding,' \
  '          extra: null,'

# The route key drops its lag, so two findings on the same pair collide and the
# wrong one opens.
mutate 'the route key stops distinguishing two lags of one pair' \
  "$WORDING_TEST" "$DETAIL_SCREEN" \
  "'\${finding.metricA ?? ''}~\${finding.metricB ?? ''}~\${finding.lagDays ?? 0}'" \
  "'\${finding.metricA ?? ''}~\${finding.metricB ?? ''}'"

# q = 3.15e-27 rendered as "0.000" — an exact zero the data does not support.
mutate 'a vanishing q-value is rounded to an exact zero' \
  "$WORDING_TEST" "$DETAIL_PARTS" \
  "  return q < 0.001
      ? 'Adjusted q-value < 0.001'
      : 'Adjusted q-value \${q.toStringAsFixed(3)}';" \
  "  return 'Adjusted q-value \${q.toStringAsFixed(3)}';"

# The screen agrees with itself no longer: a negative correlation is announced
# as having moved together, contradicting the card that opened it.
mutate 'the observation ignores the sign of the coefficient' \
  "$WORDING_TEST" "$DETAIL_PARTS" \
  '  final opposite = effect != null && effect < 0;' \
  '  const opposite = false;'

# The second line is the one that does the work. Drop it and the screen states
# a co-movement with nothing qualifying it.
mutate 'the observation loses "That doesn’t tell us why."' \
  "$WORDING_TEST" "$DETAIL_PARTS" \
  "'They moved in opposite directions.\nThat doesn’t tell us why.'" \
  "'They moved in opposite directions.'"

# The arrow acquires a direction the statistic does not have.
mutate 'the pair arrow becomes single-headed' \
  "$NAMES_TEST" "$NAMES" \
  "const String kPairArrow = '↔';" \
  "const String kPairArrow = '→';"

# The BUNDLED fallback is dropped from the chain. Figtree has no U+2194, so
# without a bundled face that does, Android reaches NotoColorEmoji and puts a
# blue box in a sentence — measured on the device, twice, with the platform
# symbol faces named the whole time.
mutate 'the bundled glyph fallback is dropped' \
  "test/core/typography_test.dart" "lib/core/theme/typography.dart" \
  "  // Bundled. Complete. Load-bearing — see above.
  'HealtheeSymbols'," \
  ""

# It stays named, but behind a platform face — which is the arrangement that
# demonstrably did not work.
mutate 'the bundled fallback stops being first' \
  "test/core/typography_test.dart" "lib/core/theme/typography.dart" \
  "  'HealtheeSymbols',
  // Platform text faces, for the case where the bundled asset fails entirely.
  'SF Pro Text', // iOS" \
  "  'SF Pro Text', // iOS
  'HealtheeSymbols',"

# ── The four v02 detail screens ────────────────────────────────────────────────
#
# Each of these breaks a REFUSAL or a qualification — the sentences that make a
# number safe to read. A screen that draws the figure and drops the sentence
# looks finished, which is exactly why none of them can be left to review.

BODY_TEST=test/features/body_screen_test.dart
FITNESS_TEST=test/features/fitness_screen_test.dart
RECOVERY_TEST=test/features/recovery_screen_test.dart
HISTORY_TEST=test/features/sleep_history_screen_test.dart
BODY_SCREEN=lib/features/today/body_screen.dart
BODY_LIMITS=lib/features/today/v02/body_limits_panels.dart
BODY_PANELS=lib/features/today/v02/body_panels.dart
FITNESS_PANELS=lib/features/activity/v02/fitness_panels.dart
RECOVERY_PANELS=lib/features/today/v02/recovery_detail_panels.dart
SIGNAL=lib/shared/v02/signal_chart.dart
HISTORY_PANELS=lib/features/sleep/v02/history_panels.dart

# The exclusion stops being an exclusion: the term is named and the server's
# reasoning — the whole reason it cannot be priced — is dropped.
mutate 'the excluded term loses the server’s reasoning' \
  "$BODY_TEST" "$BODY_LIMITS" \
  '            PanelNote(exclusions[i].message),' \
  "            const PanelNote(''),"

# The exclusion is counted as a caveat as well, so the screen states it twice —
# once as "not a lever" and once as a tilt on a number it is not in.
mutate 'the exclusion is repeated as a caveat' \
  "$BODY_TEST" "$BODY_SCREEN" \
  '      if (!exclusions.contains(caveat)) caveat,' \
  '      caveat,'

# The equation stops being the payload's arithmetic and becomes a fixed
# sentence, which cannot follow a model that reweights or drops a term.
mutate 'the age equation stops reading its own terms' \
  "$BODY_TEST" "$BODY_PANELS" \
  '    for (final term in age.contributions) {' \
  '    for (final term in <AgeContribution>[]) {'

# The line every reader needs and no reader asks for: without it a published
# model error reads as an interval computed for this owner.
mutate 'the VO₂max band stops saying it is not a confidence interval' \
  "$FITNESS_TEST" "$FITNESS_PANELS" \
  "ml/kg/min\$derived. The band is not a confidence interval.'" \
  "ml/kg/min\$derived.'"

# The stored series is written by three instruments and now names which one read
# each point (`docs/BACKEND_GAPS_FROM_UI.md` B2). Collapsing the three endings
# into one is the regression: a window nobody labelled would then read as a
# window read one way throughout, which is the caveat vanishing rather than
# being answered.
mutate 'an unlabelled window reads as a single-instrument one' \
  "$FITNESS_TEST" "$FITNESS_PANELS" \
  "      0 => kStoredHistoryNote," \
  "      0 => kSingleMethodNote,"

# And the other direction: a window that really did cross two instruments says
# nothing about it, so a step that is a change of ruler reads as the owner.
mutate 'a mixed-instrument window stops saying it is mixed' \
  "$FITNESS_TEST" "$FITNESS_PANELS" \
  "      _ => kMixedMethodNote," \
  "      _ => kSingleMethodNote,"

# A signal with no baseline gets drawn at dead centre, which asserts it is
# exactly normal — the one claim `recovery_signals.dart` says we cannot make.
mutate 'a signal with no baseline is drawn at the centre line' \
  "$RECOVERY_TEST" "$SIGNAL" \
  '    if (z == null || !z.isFinite) {
      return null;
    }' \
  '    if (z == null || !z.isFinite) {
      return 0.5;
    }'

# The bridge states a share the payload never sent.
mutate 'the sleep share is asserted rather than read' \
  "$RECOVERY_TEST" "$RECOVERY_PANELS" \
  "String sleepShareBridge(double? weight) => weight == null
    ? kNightBridge" \
  "String sleepShareBridge(double? weight) => weight == null
    ? 'Sleep contributes 40% of the model. \$kNightBridge'"

# A night the strap did not record is given a duration out of thin air.
mutate 'an unrecorded night is drawn as a measured one' \
  "$HISTORY_TEST" "$HISTORY_PANELS" \
  "    return minutes == null ? '—' : hoursMinutes(minutes);" \
  "    return hoursMinutes(minutes ?? 0);"

# The same night's session times are invented rather than left absent.
mutate 'an unrecorded night invents its bedtime and wake' \
  "$HISTORY_TEST" "$HISTORY_PANELS" \
  "    return '\${start == null ? '—' : clock(start)} → '
        '\${end == null ? '—' : clock(end)}';" \
  "    return '23:00 → 06:30';"

# ── the way OFF a screen, and the subject a link carries ONTO one ───────────
# Both are silent. A back control that lands on the wrong tab looks like a back
# control, and a topic that never reaches the input looks like a coach that was
# simply opened.
DETAIL_PAGE=lib/shared/v02/detail_page.dart
PARENTS=lib/core/parent_tabs.dart
NAV_TEST=test/features/out_of_shell_navigation_test.dart
PARENTS_TEST=test/core/parent_tabs_test.dart
TOPIC_TEST=test/features/coach_topic_test.dart
# `coachLocation` lives with the path table, not with the wiring — `routes.dart`
# was split out of `router.dart` at the 400-line gate and is re-exported from it.
ROUTES=lib/core/routes.dart
COACH_TOPICS=lib/features/coach/coach_topics.dart

# THE ORIGINAL DEFECT: no stack, no control, no way off the screen. It is
# invisible until something opens a detail screen without pushing it.
mutate 'a stranded detail screen draws no back control' "$NAV_TEST" "$DETAIL_PAGE" \
  '    final bool canLeave = stacked || GoRouter.maybeOf(context) != null;' \
  '    final bool canLeave = stacked;'

# The fallback fires but goes nowhere useful — Today from every screen looks
# right on the one screen Today is the answer for.
mutate 'every stranded screen falls back to Today' "$PARENTS_TEST" "$PARENTS" \
  '  return kParentTabs[head] ?? Routes.today;' \
  '  return Routes.today;'

# `/history?metric=hrv` is the metric detail. Splitting on `?` is what makes it
# resolve at all; without it the whole metric surface falls through to Today.
mutate 'a query string sends the metric detail to the wrong tab' \
  "$PARENTS_TEST" "$PARENTS" \
  "  final String path = location.split('?').first;" \
  '  final String path = location;'

# The map is the FALLBACK. A pop that stopped outranking it would send an owner
# who pushed into `body` from Today to Activity instead of back to Today.
mutate 'the back-map outranks a real stack' "$NAV_TEST" "$DETAIL_PAGE" \
  '  final NavigatorState navigator = Navigator.of(context);
  if (navigator.canPop()) {
    navigator.pop();
    return;
  }' \
  '  final NavigatorState navigator = Navigator.of(context);
  if (navigator.canPop() && false) {
    navigator.pop();
    return;
  }'

# The gesture and the affordance went missing together last time. Restoring only
# the glyph leaves the system back button dead on exactly these screens.
mutate 'the system back gesture stops taking the same door' \
  "$NAV_TEST" "$DETAIL_PAGE" \
  '        if (!didPop) {
          leaveDetail(context);
        }' \
  '        if (!didPop) {
          return;
        }'

# The subject is the whole reason the coach became a route. A dropped topic
# leaves `Discuss this workout` opening a coach that knows nothing about it —
# which is what the sheet did, and it looked fine.
mutate 'the coach topic never reaches the location' "$TOPIC_TEST" "$ROUTES" \
  "  return subject.isEmpty
      ? Routes.coach
      : '\${Routes.coach}?topic=\${Uri.encodeQueryComponent(subject)}';" \
  '  return Routes.coach;'

# ...or reaches the location and is dropped reading it back off the route.
mutate 'the route drops the topic it was given' "$TOPIC_TEST" "$ROUTES" \
  "  final String subject = uri.queryParameters['topic']?.trim() ?? '';
  return subject.isEmpty ? null : subject;" \
  '  return null;'

# ...or reaches it and is dropped on the way into the input.
mutate 'the seeded topic never reaches the input' "$TOPIC_TEST" \
  lib/features/coach/coach_screen.dart \
  '            initialQuestion: conversation.isEmpty ? topic : null,' \
  '            initialQuestion: null,'

# A blank topic from a caller that had no label would open the coach with an
# empty box claiming to hold a question.
mutate 'a blank topic is carried into the route as one' "$TOPIC_TEST" "$ROUTES" \
  "  final String subject = topic?.trim() ?? '';" \
  "  final String subject = topic ?? ' ';"

# THE SPEND. Asking on arrival charges one of twenty for a navigation, and the
# owner never sees the sentence before it is sent.
mutate 'arriving with a topic asks it immediately' "$TOPIC_TEST" \
  lib/features/coach/coach_body.dart \
  '    void ask(String question) => unawaited(
      ref.read(coachControllerProvider.notifier).ask(question, topic: topic),
    );' \
  '    void ask(String question) => unawaited(
      ref.read(coachControllerProvider.notifier).ask(question, topic: topic),
    );
    if (topic != null && conversation.isEmpty && !conversation.asking) {
      WidgetsBinding.instance.addPostFrameCallback((_) => ask(topic!));
    }'

# These sentences are read as the owner's own. A verdict in one is this product
# asserting something in their voice, before the coach has looked at anything.
mutate 'an opening question characterises what it names' "$TOPIC_TEST" \
  "$COACH_TOPICS" \
  "    'What should I notice in my \${metricName(metric)} trend?';" \
  "    'Why has my \${metricName(metric)} been getting worse?';"

# ── the GPS screens, ported off the legacy frame ────────────────────────────
ROUTE_MAP=lib/features/gps/route_map.dart
ROUTE_SECTIONS=lib/features/gps/route_detail_sections.dart
GPS_TEST=test/gps/route_screens_test.dart
# The drawing's own suite. Split out of `route_screens_test.dart` when that file
# passed the 400-line gate — and this line is the reason the split is worth a
# comment: the mutation below kept naming the old file, applied cleanly, and
# SURVIVED, because the test that catches it had moved. A mutation whose target
# no longer holds its test reports a pass it did not earn.
MAP_TEST=test/gps/route_map_test.dart

# One fix is a dot. A box with a dot in it is a picture of a journey nobody
# recorded, and it looks like a map that simply did not load.
mutate 'a single GPS fix is drawn as a route' "$MAP_TEST" "$ROUTE_MAP" \
  '    if (widget.points.length < 2) {' \
  '    if (widget.points.length < 1) {'

# A session VO2max with no method beside it is the shape #108 shipped in: a
# number nobody can trace to the tier that produced it.
mutate 'a session VO2max loses the instrument that produced it' \
  "$GPS_TEST" "$ROUTE_SECTIONS" \
  "                ? 'Method not named by the server for this session'" \
  "                ? ''"

# The withheld estimate stops saying why, and the screen just has less on it.
mutate 'a withheld fitness estimate stops giving its reason' \
  "$GPS_TEST" "$ROUTE_SECTIONS" \
  '  final double? vo2max = route.vo2max;
  if (vo2max == null) {' \
  '  final double? vo2max = route.vo2max;
  if (false) {'

# A track with no altitudes is drawn as level ground no barometer measured.
mutate 'a track with no altitudes gets a flat elevation profile' \
  "$GPS_TEST" "$ROUTE_SECTIONS" \
  '  if (values.nonNulls.length < 2) {
    return const <Widget>[];
  }' \
  '  if (false) {
    return const <Widget>[];
  }'

# ── the links section 2 found undrawn, and the ones drawn at a neighbour ────
# A link that lands on the wrong screen is the hard one: the control is there,
# the tap does something, and a screen appears.
LINKS_TEST=test/features/panel_links_test.dart
TODAY_SCREEN=lib/features/today/today_screen.dart
TODAY_BODY=lib/features/today/today_body.dart
TODAY_DAY=lib/features/today/today_day_sections.dart
EXPLORER=lib/features/history/metric_explorer_screen.dart

# The device strip answers "is my strap current?". The settings index is a
# screen about the app, and it opens, so nothing looks broken.
# The device strip is gone: `Data & sync` is a row INSIDE Settings now, so the
# separate door was a second way to the same room. What has to hold is that the
# room is still there, one tap on from the owner mark — `panel_links_test.dart`
# taps through both. Pointed back at the index it is a screen about the app
# rather than an answer to "is my strap current?".
mutate 'the sync row opens the settings index again' \
  "$LINKS_TEST" lib/features/settings/settings_screen.dart \
  '              onTap: () => unawaited(context.push(Routes.dataFreshness)),' \
  '              onTap: () => unawaited(context.push(Routes.settings)),'

# A panel pointed at a metric other than the one it draws.
mutate 'a panel Details opens a neighbouring metric' "$LINKS_TEST" "$TODAY_BODY" \
  '        onDetails: _metric(extras, TodayMetricIds.heartRateVariability),' \
  '        onDetails: _metric(extras, TodayMetricIds.restingHeartRate),'

# `.context-bridge` is one thought that ends in a link. Dropping the link is
# the state this screen shipped in, and it reads as prose rather than as a gap.
mutate 'the sleep bridge loses the link that ends it' "$LINKS_TEST" "$TODAY_BODY" \
  '    ContextBridge.link(
      kSleepBridge,
      label: '"'"'Open your night'"'"',
      onOpen: extras.onOpenSleep,
    ),' \
  '    ContextBridge.text(kSleepBridge),'

mutate 'the movement bridge loses the link that ends it' \
  "$LINKS_TEST" "$TODAY_DAY" \
  '    ContextBridge.link(
      kMovementBridge,
      label: '"'"'See the relationship'"'"',
      onOpen: extras.onOpenRecovery,
    ),' \
  '    ContextBridge.text(kMovementBridge),'

# The directory row promising "duration, stages and regularity" opens last
# night instead of the thirty nights it names — two screens, one subject.
mutate 'the metric directory sends Sleep history to the Sleep tab' \
  "$LINKS_TEST" "$EXPLORER" \
  '              onOpen: () => unawaited(context.push(Routes.sleepHistory)),' \
  '              onOpen: () => context.go(Routes.sleep),'

mutate 'the metric directory sends Fitness estimates to the Activity tab' \
  "$LINKS_TEST" "$EXPLORER" \
  '              onOpen: () => unawaited(context.push(Routes.fitness)),' \
  '              onOpen: () => context.go(Routes.activity),'

# The coach stops carrying its history, so every question arrives contextless.
# The other half of the same rule: `ask` sends the WHOLE thread, which is why
# the thread must be endable — see `CoachController.newThread`.
mutate 'the coach forgets the conversation it is in' \
  "test/features/coach_thread_test.dart" "lib/features/coach/coach_conversation.dart" \
  "    final wire = <CoachTurn>[];
    for (final entry in entries) {" \
  "    final wire = <CoachTurn>[];
    for (final entry in <CoachEntry>[]) {"

# The refusal notes start reaching the model as conversation.
mutate 'a coach trouble note becomes a turn' \
  "test/features/coach_thread_test.dart" "lib/features/coach/coach_conversation.dart" \
  "        case CoachTrouble():
          break;" \
  "        case CoachTrouble(:final message):
          wire.add(CoachTurn(role: 'user', content: message));"

# ── the selected day, carried in the route ─────────────────────────────────
# Four failures that are all silent: the screen still draws, the header still
# says a date, and nothing throws. `view_date_route_test.dart` and
# `past_day_screens_test.dart` are the proof.
DATE_ROUTE=lib/core/view_date_route.dart
DATE_ROUTE_TEST=test/features/view_date_route_test.dart
PAST_TEST=test/features/past_day_screens_test.dart

# The day reaches Today and is dropped by every other route, which is exactly
# what a tab switch looks like: the header on Activity quietly says today.
mutate 'the day is dropped on a tab switch' \
  "$DATE_ROUTE_TEST" "$DATE_ROUTE" \
  '  if (!isDateAwareRoute(state.uri.path)) {
    return null;
  }' \
  '  if (state.uri.path != Routes.today) {
    return null;
  }'

# The retention bound comes off the link's day. A bookmark kept past the
# 60-day horizon then leaves a date in the URL the screen is not showing.
mutate 'the route accepts a day outside the retention window' \
  "$DATE_ROUTE_TEST" "$DATE_ROUTE" \
  '  if (requested != null &&
      requested != selected &&
      isViewableDay(requested, latest)) {' \
  '  if (requested != null &&
      requested != selected) {'

# Sleep'"'"'s window stops following the reader and slices from the newest night
# again — the seam `sleep_history_screen.dart` used to record, reopened.
mutate 'a chart ignores the selected day and windows on the newest sample' \
  "$PAST_TEST" lib/features/sleep/sleep_windows.dart \
  '    final nights = <SleepNight>[
      for (final night in page.nights)
        if (night.date.compareTo(day) <= 0) night,
    ];' \
  '    final nights = <SleepNight>[
      for (final night in page.nights) night,
    ];'

# ── the dated history a past day now draws ──────────────────────────────────
DATED=lib/shared/v02/dated_history.dart
DATED_PANEL=lib/shared/v02/dated_panel.dart
DATED_DATA=lib/data/history/dated_history.dart
DATED_TEST=test/features/dated_panel_test.dart
DATED_DATA_TEST=test/history/dated_history_test.dart
DATE_TEST=test/features/date_control_test.dart

# THE LINE, and it MOVED when the server learned to answer for a day. It used to
# be "a past day may gain charts of measurements, never a judgement", because
# `/api/today` took no day and the only payload there was described the current
# one. It is now "a day wears only the judgements computed FOR it" — the same
# rule, applied where the failure can still get in.
#
# The frame between the tap and the response: Riverpod keeps the previous value
# through a refresh, so let a payload about another day through and one day's
# recovery, debt and biological age draw under another day's date for the length
# of a round trip.
mutate 'a payload about another day is drawn as this day’s answer' \
  "$DATE_TEST $PAST_TEST" lib/shared/screen_data.dart \
  '      final bool answersThisDay = view.isPast
          ? answered.day == view.day
          : answered.isToday;' \
  '      final bool answersThisDay = true;'

# The other half of that guard, and the one a "same date" test cannot see: on the
# CURRENT day the question is the server's own `is_today`, so a payload that
# says it is about an older day must not be drawn as today's.
mutate 'a payload that says it is not today is drawn as today' \
  "$DATE_TEST $PAST_TEST" lib/shared/screen_data.dart \
  '          : answered.isToday;' \
  '          : true;'

# The request must CARRY the day, or every screen asks for the current one and
# the whole feature is a header that lies about which day is on screen.
mutate 'the day is dropped from the request' \
  "test/data/today_cache_test.dart" lib/data/today_repository.dart \
  '      queryParameters: day == null ? null : <String, Object?>{'"'"'day'"'"': day},' \
  '      queryParameters: null,'

# Offline on a past day, fall back to the NEWEST cached payload and the client
# commits the exact lie the server refuses to: today's judgements under an older
# date, reached through the cache instead of through the endpoint.
mutate 'an offline past day falls back to the newest cached payload' \
  "test/data/today_cache_test.dart" lib/data/today_repository.dart \
  '    final row = day == null
        ? await _store.readLatest(kTodayPayload, scope: session.scope)
        : await _store.read(kTodayPayload, day, scope: session.scope);' \
  '    final row = await _store.readLatest(kTodayPayload, scope: session.scope);'

# The live-feed trust card is an age measured against right now. Draw it on a
# past day and the screen reports an observation made after that day as one of
# its facts.
mutate 'the live trust card is drawn on a past day' \
  "$DATE_TEST" lib/features/today/today_sections.dart \
  '  if (!past) {
    sections.add(_dataHealth(data, extras));
  }' \
  '  sections.add(_dataHealth(data, extras));'

# The same failure a chart at a time: window on today and every dated panel
# draws the newest fortnight there is, captioned with the day the reader chose.
mutate 'a dated series is windowed on today rather than the chosen day' \
  "$PAST_TEST $DATED_TEST" "$DATED" \
  '          window: HistoryWindow.endingOn(
            series[metric.id],
            day,
            kDatedPanelDays,
          ),' \
  '          window: HistoryWindow(series[metric.id]),'

# Fill the holes from the neighbour on the left and the chart draws a line
# through days nobody measured — a measurement nobody took.
mutate 'a missing day is interpolated across instead of left as a gap' \
  "test/history/history_window_test.dart $DATED_TEST" \
  lib/data/history/history_window.dart \
  '      final value = byDay[iso];
      values.add(value);' \
  '      final value = byDay[iso] ?? (values.isEmpty ? null : values.last);
      values.add(value);' \

# A batched read that drops what it does not recognise hands back eight series
# where nine were asked for, and the missing one reads as "you have no data".
mutate 'the batched parse drops a malformed point instead of refusing' \
  "$DATED_DATA_TEST" "$DATED_DATA" \
  '    if (points.isNotEmpty && points.last.date.compareTo(day) >= 0) {
      throw FormatException('"'"'History dates must increase for $metric'"'"');
    }' \
  '    if (points.isNotEmpty && points.last.date.compareTo(day) >= 0) {
      continue;
    }'

# ── what the server started sending, and what the app stopped apologising for ─
# `docs/BACKEND_GAPS_FROM_UI.md` sections A and B. Every guard here sits at the
# seam where a payload that got RICHER could quietly go back to being read as
# though it had not — the failure mode that leaves a true-sounding sentence on
# screen beside data contradicting it.

H_SLEEP_MODEL=lib/data/models/sleep_page.dart
H_NAPS=lib/features/sleep/v02/naps_panel.dart
H_SLEEP_TEST=test/features/sleep_surface_test.dart
H_FINDING_MODEL=lib/data/models/finding.dart
H_SCATTER=lib/shared/charts/h_scatter.dart
H_SCATTER_TEST=test/shared/scatter_test.dart
H_TODAY_BODY=lib/features/today/today_body.dart
H_GOLDEN_TEST=test/data/today_snapshot_golden_test.dart

# A1. The nap's stage TOTALS read as an empty split — the defect the server just
# fixed, arriving from the other side. The panel would go back to saying the
# strap staged nothing, on a nap it staged.
mutate 'a nap ignores the stage minutes the server now sends' \
  "$H_SLEEP_TEST" "$H_SLEEP_MODEL" \
  "      stages: StageMinutes.maybe(json['stages'])," \
  "      stages: StageMinutes.maybe(const <String, Object?>{}),"

# A1. The sentence blaming the server comes back unconditionally — true once,
# false now, and the worst kind of copy because it reads as an explanation.
mutate 'the nap panel blames the wire for a breakdown it received' \
  "$H_SLEEP_TEST" "$H_NAPS" \
  '            if (noneStaged) const PanelNote(kNapsUnstagedNote),' \
  '            const PanelNote(kNapsUnstagedNote),'

# B1. A pair with one half missing becomes a dot at zero — a day sitting on the
# axis that nobody measured, inside the one chart whose job is to let the owner
# check the number above it against their own days.
mutate 'half a pair is plotted at zero instead of dropped' \
  "$H_SCATTER_TEST" "$H_FINDING_MODEL" \
  '    if (a == null || b == null) {' \
  '    if (a == null && b == null) {' \
  "    return FindingPoint(date: json['date'] as String?, a: a, b: b);" \
  "    return FindingPoint(date: json['date'] as String?, a: a ?? 0, b: b ?? 0);"

# B1. Two points make a perfect line whatever the data is: a picture of
# arithmetic offered as a picture of the owner.
mutate 'a scatter is drawn from too few pairs to be a shape' \
  "$H_SCATTER_TEST" "$H_SCATTER" \
  '    if (points.length < Finding.minPlottablePoints) {' \
  '    if (points.isEmpty) {'

# B4. The centre ships and the spread is dropped, so "baseline 44" is a bare
# point again and a reading of 50 could be an ordinary night or a remarkable one.
mutate 'the baseline loses the spread it is only meaningful with' \
  "$H_GOLDEN_TEST test/features/today_screen_test.dart" "$H_TODAY_BODY" \
  "  final spread = sd == null ? '' : ' ± \${sd.round()}';" \
  "  final spread = '';"

# ── the recorded track, and the basemap under it ────────────────────────────
GPS_RUN=lib/data/gps/gps_run.dart
ROUTE_PAINTER=lib/features/gps/route_painter.dart
GPS_RUN_TEST=test/gps/gps_run_test.dart

# THE original defect, restored: the state keeps only the newest fix, so the
# count still climbs, the distance still climbs, and the map has one dot to
# draw. The recorder screen had no map for exactly this reason — not a missing
# painter, a missing measurement.
mutate 'the recording state drops the coordinates it recorded' \
  "$GPS_RUN_TEST" "$GPS_RUN" \
  '      track: <RoutePoint>[...value.track, _asRoutePoint(fix)],' \
  '      track: <RoutePoint>[_asRoutePoint(fix)],'

# The tiles are thrown away whenever the view moves. On the recorder the view
# moves on every accepted fix, so this is a basemap that blanks once a second
# and re-asks for the squares it is already holding, for as long as somebody
# keeps running.
mutate 'a new view throws away the tiles it could have kept' \
  "$MAP_TEST" "$ROUTE_MAP" \
  '    final List<MapTileRef> missing = <MapTileRef>[
      for (final MapTileRef tile in view.tiles())
        if (!_tiles.containsKey(tile)) tile,
    ];' \
  '    _tiles = const <MapTileRef, ui.Image>{};
    final List<MapTileRef> missing = view.tiles();'

# A cache miss withholds the track instead of drawing it on the plain ground.
# Offline is the day the owner most needs to see what they recorded, and this
# failure looks exactly like a screen that has not finished loading.
mutate 'a cache miss blanks the route instead of falling back to the ground' \
  "$MAP_TEST" "$ROUTE_PAINTER" \
  '  bool get drawsTrack => points.length >= 2;' \
  '  bool get drawsTrack => points.length >= 2 && tiles.isNotEmpty;'

# ── BACKEND_AUDIT.md section A — the client half ─────────────────────────────
#
# Three of the thirteen were defects on THIS side of the wire, and each has the
# same shape: the server did the honest work and the app undid it. Each mutation
# below puts the SHIPPED defect back rather than a plausible near miss.

SEVERITY_A=test/data/honesty_severity_a_test.dart
VO2MAX_MODEL=lib/data/models/vo2max.dart
STAGE_CHART=lib/shared/charts/h_stacked_sleep.dart
ACTIVITY_MODEL=lib/data/models/activity_today.dart

# A4. The measurement date is printed whether or not it differs from the day the
# estimate speaks for. The card fills with a second date that says nothing, which
# is how the line that matters on the fortnight-old day stops being read.
mutate 'the measurement date is printed even when it is the same day' \
  "$SEVERITY_A" "$VO2MAX_MODEL" \
  '  String? get measuredEarlier =>
      measuredAsOf != null && measuredAsOf != asOfDate ? measuredAsOf : null;' \
  '  String? get measuredEarlier => measuredAsOf;'

# A4, the live half. The field stops being parsed at all — which is exactly the
# state the audit found: `measured_as_of` on the wire, and no client field for
# it, so a card read "as of today" over a run recorded a fortnight ago.
mutate 'the measurement date goes back to being unparsed' \
  "$SEVERITY_A" "$VO2MAX_MODEL" \
  "      measuredAsOf: json['measured_as_of'] as String?," \
  '      measuredAsOf: null,'

# A5. The chart stacks an unmeasured night's stages anyway. All four are null so
# every segment is zero-height — pixel-identical to a night of literal zero
# sleep, which is what this drew and what the owner saw.
mutate 'an unmeasured night is stacked as four zero-height stages' \
  "$SEVERITY_A" "$STAGE_CHART" \
  '      if (!night.hasBreakdown) {' \
  '      if (false) {'

# NOT here: a second A5 mutation on the axis. It was written — "an unmeasured
# night contributes a zero to the axis" — and it SURVIVED, because `_totalOf`
# already answers 0 for a night with no stages, so the `hasBreakdown` branch it
# broke changed nothing. The branch was deleted rather than the mutation being
# quietly dropped: a survivor that reveals a guard guarding nothing is the
# harness doing its job (`HOW_WE_VERIFY.md` section 2, "the mutation with no
# test" inverted — here the test was fine and the guard was decoration).

# A13(c). The weekly MVPA target is hard-coded back to 150, so a payload that
# carries none still draws a confident percentage of a number the server never
# sent — with no `Reading` wrapper and no withheld path.
mutate 'the app invents a weekly mvpa target again' \
  "$SEVERITY_A" "$ACTIVITY_MODEL" \
  "      weekTarget: (json['week_target'] as num?)?.toInt()," \
  "      weekTarget: (json['week_target'] as num?)?.toInt() ?? 150,"

# A13(a), client side. A day with no intensity breakdown is read as a day of no
# moderate and no vigorous minutes, so the week's split understates itself by
# exactly the days nobody measured.
mutate 'a missing intensity breakdown is read as measured zeros' \
  "$SEVERITY_A" "$ACTIVITY_MODEL" \
  "      weekModerateMin: (json['week_moderate_min'] as num?)?.toInt()," \
  "      weekModerateMin: (json['week_moderate_min'] as num?)?.toInt() ?? 0," \
  "      weekVigorousMin: (json['week_vigorous_min'] as num?)?.toInt()," \
  "      weekVigorousMin: (json['week_vigorous_min'] as num?)?.toInt() ?? 0,"

# ── BACKEND_AUDIT.md sections B and C — the client half ──────────────────────
#
# C3 is the one CLAUDE.md's first hard rule names: the client computed its own,
# age-blind sleep need while the server computed the real one. B4 and C2 are the
# wire-shape halves of two server fixes.

B_AND_C=test/data/honesty_b_c_test.dart
SLEEP_DEBT_MODEL=lib/data/models/sleep_debt.dart
NEED_PANEL=lib/features/sleep/v02/need_panel.dart
BUCKET_MODEL=lib/data/models/today_series.dart
NAP_MODEL=lib/data/models/sleep_page.dart

# C3. The parser coalesces a missing need to a flat eight hours again — a
# personal target invented for somebody we could not compute one for, and then
# published back as theirs. The server's need is age-selected (450 at 65+).
mutate 'the client invents a sleep need again' \
  "$B_AND_C" "$SLEEP_DEBT_MODEL" \
  "      needMin: (json['need_min'] as num?)?.toInt()," \
  "      needMin: (json['need_min'] as num?)?.toInt() ?? 480,"

# C3, one layer up. The Sleep tab measures against its own constant rather than
# the need it was handed, so the two tabs disagree about the same nights again.
mutate 'the sleep panel measures against its own constant again' \
  "$B_AND_C" "$NEED_PANEL" \
  '    final need = needMin?.toDouble();' \
  '    final need = 480.0;'

# C3, the withhold. With no need the panel draws its figures anyway, against
# nothing — the "optimistic guess" the honesty contract is defined against.
mutate 'the panel stops withholding when there is no need' \
  "$B_AND_C" "$NEED_PANEL" \
  '    final hasNeed = need != null && need > 0;' \
  '    final hasNeed = true;'

# C2. The nap reads its time in bed off the key a NIGHT uses for total sleep
# time, so one name means two quantities in one payload again.
mutate 'a nap reads time in bed off the night is sleep-time key' \
  "$B_AND_C" "$NAP_MODEL" \
  "      tibMin: (json['tib_min'] as num?)?.toDouble()," \
  "      tibMin: (json['duration_min'] as num?)?.toDouble(),"

# B4. The bucket parses a distance again — and the only distance it could parse
# is the population-stride one the server stopped computing, so the field is a
# measurement in name and nothing behind it.
mutate 'a step bucket parses a distance nobody measured' \
  "$B_AND_C" "$BUCKET_MODEL" \
  "      steps: (json['steps'] as num?)?.toDouble() ?? 0," \
  "      steps: (json['distance_m'] as num?)?.toDouble() ??
          (json['steps'] as num?)?.toDouble() ??
          0,"

# ── the LLM audit ────────────────────────────────────────────────────────────
#
# Four of these protect a SENTENCE about the owner's money or the owner's data
# rather than a number, which is the class this app has the least other cover
# for: none of them fails loudly, and all four read as working code.

COACH_CLIENT=lib/data/coach/coach_client.dart
COACH_THREAD_W=lib/features/coach/widgets/coach_thread.dart
COACH_CTRL=lib/features/coach/coach_controller.dart
COACH_SCREEN=lib/features/coach/coach_screen.dart
REC_MODEL=lib/data/models/recommendation.dart
SHARED_OTHER_DAY=lib/shared/format/other_day.dart
GEN_INSIGHT=lib/data/insights/generated_insight.dart
BUDGET_TEST=test/data/coach_ask_budget_test.dart
CHARGE_TEST=test/features/coach_charge_honesty_test.dart
DATING_TEST=test/features/actions_dating_test.dart
FALLBACK_TEST=test/features/insight_fallback_test.dart
TOPIC_TEST=test/features/coach_topic_test.dart

# ── A1 ───────────────────────────────────────────────────────────────────────
# The ask goes back to the app's 10-second READ default while one coach turn is
# budgeted at up to 22 model calls. The server charges the slot before the
# handler starts, so this is a charge for an answer nobody receives.
mutate 'the coach ask goes back to the read timeout' \
  "$BUDGET_TEST" "$COACH_CLIENT" \
  '        options: Options(
          receiveTimeout: Env.coachTimeout,
          sendTimeout: Env.coachTimeout,
        ),' \
  '        options: Options(
          receiveTimeout: Env.requestTimeout,
          sendTimeout: Env.requestTimeout,
        ),'

# The timeout stays and the SENTENCE goes back to denying the charge — the half
# a fix is most likely to stop at, and the half the owner actually reads.
mutate 'a receive timeout claims nothing was charged again' \
  "$BUDGET_TEST" "$COACH_CLIENT" \
  '      DioExceptionType.badCertificate => CoachCharge.notCharged,
      _ => CoachCharge.unknown,' \
  '      DioExceptionType.badCertificate => CoachCharge.notCharged,
      _ => CoachCharge.notCharged,'

# The thread prints the denial for an unknown charge — the exact sentence that
# shipped, over a meter showing one fewer.
mutate 'the thread denies a charge it cannot see' \
  "$CHARGE_TEST" "$COACH_THREAD_W" \
  "            CoachCharge.unknown =>
              'We could not confirm whether this was counted. The number '
                  'above is the server’s own, re-read just now.'," \
  "            CoachCharge.unknown =>
              'Nothing was counted for this. The number above is the '
                  'server’s own, re-read just now.',"

# The controller flattens the client's verdict back to "not charged", which is
# where the false sentence was actually produced.
mutate 'the controller overrides what the client worked out' \
  "$CHARGE_TEST" "$COACH_CTRL" \
  '        _trouble(failure.message, charge: failure.charge);' \
  '        _trouble(failure.message, charge: CoachCharge.notCharged);'

# ── A3 ───────────────────────────────────────────────────────────────────────
# The row's own date is dropped again, so a two-day-old action is drawn as the
# day's own with nothing able to say otherwise.
mutate 'a recommendation drops the day it was written for' \
  "$DATING_TEST" "$REC_MODEL" \
  "      date: json['date'] as String?," \
  '      date: null,'

# The date is parsed and not drawn — a field that exists and changes nothing,
# which reads exactly like a working fix.
#
# ⚠ The decision moved to `shared/format/other_day.dart` when the v02 Actions screen
# and the illness banner turned out to need the same comparison (audit C5), so these
# two now break the SHARED function and require the TODAY card's test to notice. That
# pairing is the point: it is what proves the Today card really runs on the shared
# rule rather than on a copy of it that happens to agree.
mutate 'the actions block stops naming the day it is showing' \
  "$DATING_TEST" "$SHARED_OTHER_DAY" \
  '  if (contentDay == null || viewedDay == null || contentDay == viewedDay) {
    return null;
  }
  return contentDay;' \
  '  return null;'

# The other direction, and the one that speaks: the block names a day whenever it
# has one, so TODAY's own actions are announced as written for another day. A line
# that appears on every day stops carrying the meaning it was added for.
mutate 'the day is announced even when it is the day on screen' \
  "$DATING_TEST" "$SHARED_OTHER_DAY" \
  '  if (contentDay == null || viewedDay == null || contentDay == viewedDay) {' \
  '  if (contentDay == null) {'

# ── C2 ───────────────────────────────────────────────────────────────────────
# The honest fallback is suppressed again and the card renders blank — the one
# answer the whole honesty layer exists to be able to give, deleted.
mutate 'the honest fallback is blanked again' \
  "$FALLBACK_TEST" "$GEN_INSIGHT" \
  '      text: parsed.text,' \
  "      text: json['validated'] == true || json['refused'] == true
          ? parsed.text
          : '',"

# The fallback is shown but not FRAMED, so "we could not ground this" reads as
# an interpretation of the owner's data.
mutate 'the fallback is shown as though it were a finding' \
  "$FALLBACK_TEST" "$GEN_INSIGHT" \
  "      validated: json['validated'] == true," \
  '      validated: true,'

# ── the coach topic ──────────────────────────────────────────────────────────
# The subject stops reaching the server, so grounding is back to whatever the
# model infers from prose — the gap the field was added to close.
mutate 'the topic never leaves the phone' \
  "$TOPIC_TEST" "$COACH_SCREEN" \
  '      ref.read(coachControllerProvider.notifier).ask(question, topic: topic),' \
  '      ref.read(coachControllerProvider.notifier).ask(question),'

# The topic is sent on the first turn only, so a thread opened about a workout
# stops being about it as soon as the owner asks a follow-up.
mutate 'the topic is dropped after the first turn' \
  "$BUDGET_TEST" "$COACH_CLIENT" \
  "          if (subject.isNotEmpty) 'topic': subject," \
  "          if (subject.isNotEmpty && messages.length == 1) 'topic': subject,"

# ── the redirect policy (AUTH_AUDIT.md A1) ───────────────────────────────────
API_CLIENT=lib/data/api/api_client.dart
PROBE=lib/data/api/server_probe.dart
REDIRECT_TEST=test/data/redirect_policy_test.dart

# The exact defect the audit found: the ONE client that carries the bearer token
# follows a 3xx again, and `dart:io` replays the Authorization header at whatever
# host the `Location` names. It is the only credential-egress path in the audit.
mutate 'the app client follows redirects while carrying the token' \
  "$REDIRECT_TEST" "$API_CLIENT" \
  '      followRedirects: false,
      maxRedirects: 0,' \
  '      maxRedirects: 5,'

# One client forgets and the other two remember — which is precisely the state the
# audit found, and precisely what a per-instance check cannot notice. The source
# scan is what makes the rule structural rather than remembered.
mutate 'the sign-in probe forgets the rule the app client keeps' \
  "$REDIRECT_TEST" "$PROBE" \
  '        followRedirects: false,' \
  '        maxRedirects: 5,'

# ── The knowledge audit's screen findings (2026-09-08) ───────────────────────
# The ⓘ explainers are the one interpretive channel in this app with no grade
# gate on the way out: `insights/validator._grade_issue` calibrates the MODEL's
# sentences against their cited notes' grades and cannot see a Dart string. So
# these are the only claims in the product nothing checked, and the mutations
# below are what now checks them.

# The per-claim sentences; `UNCITED_TEST` holds the structural half of the same
# grounding pass (what a citation row implies, and what `uncited` means).
GROUNDING_TEST=test/shared/metric_info_claims_test.dart
UNCITED_TEST=test/shared/metric_info_grounding_test.dart
MERGED_GRADE_TEST=test/shared/metric_info_merged_grade_test.dart
EXPLAINERS_BODY=lib/shared/metric_info/explainers_body.dart
EXPLAINERS_SLEEP=lib/shared/metric_info/explainers_sleep.dart
INFO_SHEET=lib/shared/metric_info/metric_info_sheet.dart

# The MVPA card prints a mortality percentage again. Three of its four cited
# notes forbid the sentence outright — `mvpa_minutes_mortality` D4 and its Safety
# bounds, `exercise_mortality` D1, `mvpa_weekly_plan`'s Safety bounds — and
# `output_guard.personal_death_risk_number` blocks the MODEL from writing it,
# citing those same notes. The Dart string was the unguarded half of one claim.
mutate 'the MVPA card prints a death-risk percentage again' \
  "$GROUNDING_TEST" "$EXPLAINERS_BODY" \
  "        'more moderate-to-vigorous activity tracks with lower all-cause mortality — '" \
  "        'reaching it tracks with roughly 22–31% lower all-cause mortality versus none — '"

# The VO₂max card does the same, against `non_exercise_vo2max` D4 — the directive
# governing the Jurca tier this card actually shows for this owner.
mutate 'the VO₂max card launders the estimate into a death-risk number' \
  "$GROUNDING_TEST" "$EXPLAINERS_BODY" \
  "        'treadmill tests, low fitness carried a greater hazard than current smoking, '" \
  "        'treadmill tests, the fittest had about 80% lower all-cause mortality, '"

# The comparator goes back to the splice: `vo2max.md:209-210` says the hazard of
# low CRF exceeded smoking, diabetes and END-STAGE RENAL DISEASE in Mandsager's
# modelled cohort. Hypertension belongs to the separate, non-cohort sentence.
# This is the audit's clearest case of a citation that exists and does not
# support the claim — the one shape worse than an absent citation.
mutate 'Mandsager 2018 is credited with a comparator it does not make' \
  "$GROUNDING_TEST" "$EXPLAINERS_BODY" \
  "        'diabetes or end-stage renal disease modelled in that same population '" \
  "        'diabetes or high blood pressure modelled in that same population '"

# The sleep-health card glosses the MIDPOINT dimension as a bedtime again. Read
# as a bedtime, 2–4 am is the window `sleep_timing_chronotype.md:54-57` scores
# WORST — so the ⓘ told the owner the app wants him in bed between 2 and 4 am.
mutate 'the sleep card calls a midpoint a bedtime' \
  "$GROUNDING_TEST" "$EXPLAINERS_SLEEP" \
  "        'Four qualities of a good night: enough hours, efficient sleep, sleep timing, '" \
  "        'Four qualities of a good night: enough hours, efficient sleep, a healthy bedtime, '"

# `sleep_regularity_index` D6: "Never convert an SRI into risk, years, or a
# biological-age contribution — the published hazard figures belong to the
# software that scored the SRI; ours is a third pipeline." The card printed one
# three lines above its own disclaimer saying it could not.
mutate 'the SRI card converts a regularity score into a risk figure' \
  "$GROUNDING_TEST" "$EXPLAINERS_SLEEP" \
  "        'improve it, and the steadiest sleepers carried the lower risk (Windred '" \
  "        'improve it, and the steadiest sleepers sat around 30% lower risk (Windred '"

# The grade stamp goes back to the explainer's STATIC notes, so a Contested id
# the server sent is listed as a source under a Probable stamp. No amount of
# prose care catches this one — it is the merge, not a sentence.
mutate 'the grade stamp stops covering the sources beside it' \
  "$MERGED_GRADE_TEST" "$INFO_SHEET" \
  '              fallbackGrade: explainer == null ? null : weakestGrade(_notes),' \
  '              fallbackGrade: explainer == null ? null : weakestGrade(explainer.notes),'

# `uncited` renders as "Not covered by those sources: …". Putting a sourced claim
# under it — this one is `energy_expenditure_derivation.md:132-133` verbatim —
# teaches the reader that the label carries no information, which is worse than
# having no label at all.
mutate 'a sourced claim goes back under the not-covered disclaimer' \
  "$UNCITED_TEST" "$EXPLAINERS_BODY" \
  "    notes: <String>['energy_expenditure_derivation', 'weight_bmi_body_composition']," \
  "    notes: <String>['energy_expenditure_derivation', 'weight_bmi_body_composition'],
    uncited: 'If your logged weight is old, the BMR under this number is old too — about 0.6% per kilogram out of date.',"
# ── the four on the today.json wire (final audit A1-A4, C4-C6) ───────────────
# The prose moved out of `insights_section.dart` at the 400-line gate; the
# sentences these four mutations are about live in `finding_prose.dart` now.
INSIGHTS=lib/features/today/widgets/finding_prose.dart
WORDING_BOTH=test/features/findings_wording_test.dart
EFFECT_TEST=test/features/finding_effect_metric_test.dart

# A2. THE defect, and the exact code that shipped: the one-metric branch falls
# back to the server's raw debug string as the headline of the home screen.
#
# ⚠ The target is the wording test, and that is the point of this mutation. The
# same test named only `shared/findings_section.dart` while THIS function went on
# printing `description_raw`, so it went green against the live defect. If it is
# ever re-aimed at one composer again, this survives.
mutate 'the raw string is the home-screen headline again' "$WORDING_BOTH" "$INSIGHTS" \
  '    return (
      headline: _oneMetricHeadline(a, finding.eventKind),
      context: context,
    );' \
  '    return (
      headline: finding.description ?? '"'"'Pattern found in your data.'"'"',
      context: context,
    );'

# A2, the other half: the event kind is ignored, so an event finding loses the
# one structured field that says what it was compared against.
mutate 'the event kind stops reaching the sentence' "$WORDING_BOTH" "$INSIGHTS" \
  "  return eventKind == null" \
  "  return true || eventKind == null"

# A1. The letter goes back to being the client's, whatever statistic it is — a
# Spearman rho drawn under the symbol for Pearson'"'"'s r.
mutate 'every effect is labelled r again' "$EFFECT_TEST" "$INSIGHTS" \
  "  final figure = metric == null ? effect : '\$metric \$effect';" \
  "  final figure = 'r \$effect';"

# A1, the withholding half: an absent metric name is filled in rather than left
# out, so a number we cannot name is named anyway.
mutate 'an unnamed effect is given a name anyway' "$EFFECT_TEST" "$INSIGHTS" \
  "  final metric = finding.effectMetric;" \
  "  final metric = finding.effectMetric ?? 'r';"

# ── A4 · C4 — the illness banner ─────────────────────────────────────────────
BANNER=lib/features/today/widgets/illness_banner.dart
ILLNESS_TEST=test/features/illness_dating_test.dart

# A4. The date is parsed and not drawn again, so a flag raised two days ago reads
# as today'"'"'s under a present-tense sentence.
mutate 'the illness flag stops naming the day it was raised' \
  "$ILLNESS_TEST" "$BANNER" \
  '          if (otherDay(flag.date, viewedDay) case final String day) ...[' \
  '          if (null case final String day) ...['

# A4, the other edge: every flag is captioned with a date, including today'"'"'s —
# a caption that always fires says nothing, and contradicts a sentence that is
# not wrong.
mutate 'the banner captions every flag, including this day’s' \
  "$ILLNESS_TEST" "$BANNER" \
  '          if (otherDay(flag.date, viewedDay) case final String day) ...[' \
  '          if (flag.date case final String day) ...['

# C4. The client-side delta line comes back — the same numbers a second time,
# with the 14-day window dropped, breaking the directive the server sentence
# above it exists to satisfy.
mutate 'the banner restates the deltas without their window' \
  "$ILLNESS_TEST" "$BANNER" \
  '          // The day the signal was RAISED, whenever that is not the day on screen.' \
  '          if (flag.respiratoryRateDeltaBpm case final double rr) ...[
            const SizedBox(height: Insets.sm),
            Text(
              '"'"'breathing rate +${rr.toStringAsFixed(1)} bpm vs your baseline.'"'"',
              style: text.bodySmall?.copyWith(color: colors.ink2),
            ),
          ],
          // The day the signal was RAISED, whenever that is not the day on screen.'

# ── A3 — the recovery ladder’s three honesty fields ──────────────────────────
RECOVERY_MODEL=lib/data/models/recovery_signals.dart
RECOVERY_PANEL=lib/features/today/v02/recovery_detail_panels.dart
HONESTY_TEST=test/features/recovery_honesty_fields_test.dart

# The field is dropped at the boundary again — the state the audit found, where
# the server did the honest work and the client filed it under a key nothing
# reads.
mutate 'direction_basis is dropped at the client boundary again' \
  "$HONESTY_TEST" "$RECOVERY_MODEL" \
  "      directionBasis: json['direction_basis'] as String?," \
  "      directionBasis: null,"

mutate 'the baseline count is dropped at the client boundary again' \
  "$HONESTY_TEST" "$RECOVERY_MODEL" \
  "      n: (json['n'] as num?)?.toInt()," \
  "      n: null,"

# The floor is parsed and not named, so "the population floor decided this" is a
# claim the reader cannot weigh.
mutate 'the population floor stops being named' "$HONESTY_TEST" "$RECOVERY_PANEL" \
  "  final floor = signal.populationFloorMin;" \
  "  final double? floor = null;"

# The verdict'"'"'s limb stops reaching the surface: the note is composed and never
# returned, which is precisely the shape the whole finding is about.
mutate 'the limb sentence is composed and never shown' \
  "$HONESTY_TEST" "$RECOVERY_PANEL" \
  "  return lines.isEmpty ? null : lines.join(' ');" \
  "  return null;"

# The counts collapse into a range, which cannot say WHICH verdict to discount.
mutate 'the baseline depths collapse into one number' \
  "$HONESTY_TEST" "$RECOVERY_PANEL" \
  "      if (signal.n case final int n) '\${signal.name} \$n'," \
  "      if (signal.n case final int _) signal.name,"

# ── C5 — one “from another day” decision, two surfaces ───────────────────────
OTHER_DAY=lib/shared/format/other_day.dart
ACTIONS_V02=test/features/actions_v02_test.dart
SHARED_DAY_TEST=test/features/other_day_shared_test.dart

# The v02 Actions screen goes back to relabelling a two-day-stale set as today'"'"'s.
mutate 'the v02 actions set is relabelled as this day’s' "$ACTIONS_V02" \
  lib/features/actions/actions_screen.dart \
  '    if (recommendationsFromDay(recommendations, snapshot?.asOf?.day)
        case final String day)' \
  '    if (null case final String day)'

# An undated block is filled in from the day on screen — "we do not know this
# block'"'"'s day" quietly becomes "it is this day'"'"'s", which is the one claim
# `other_day.dart` exists to refuse. It takes BOTH halves: dropping the null check
# alone is a no-op (the function returns that null anyway) and adding the fallback
# alone is unreachable behind the check — the first version of this mutation did one
# of the two and survived.
mutate 'an undated block is filled in from the day on screen' \
  "$SHARED_DAY_TEST" "$OTHER_DAY" \
  '  if (contentDay == null || viewedDay == null || contentDay == viewedDay) {
    return null;
  }
  return contentDay;' \
  '  if (viewedDay == null || contentDay == viewedDay) {
    return null;
  }
  return contentDay ?? viewedDay;'

# The two wordings merge, so a measured signal is described as authored advice
# that a nightly job failed to write.
mutate 'a raised signal is described as unwritten advice' \
  "$SHARED_DAY_TEST" "$OTHER_DAY" \
  "String raisedOnDay(String isoDay) => 'Raised on \${shortDate(isoDay)}, not on this day.';" \
  "String raisedOnDay(String isoDay) => writtenForDay(isoDay);"

# ── C6 — the journal panel follows the wire ──────────────────────────────────
ROUTINE=lib/data/models/routine.dart
JOURNAL_TEST=test/features/journal_logs_summary_test.dart

# `logs_summary` stops reaching `isEmpty`, so a caffeine-only day renders no
# journal panel while the payload reports the entry.
mutate 'a caffeine-only day is empty again' "$JOURNAL_TEST" "$ROUTINE" \
  '      openFast == null &&
      otherLogs.isEmpty;' \
  '      openFast == null;'

# Meditation is drawn twice — once from its own field and once from the roll-up
# that also counts it.
mutate 'meditation is drawn from both of its carriers' "$JOURNAL_TEST" "$ROUTINE" \
  "  static const Set<String> _ownBlock = <String>{'meditation', 'fasting'};" \
  "  static const Set<String> _ownBlock = <String>{};"

# ── C7 — the route counts describe the RUN, not the response ────────────────
#
# The server thins a long track for the map (`read/gps.py::MAX_MAP_POINTS`), so
# `points` is a sample of the recording rather than all of it. Every count this
# screen shows the owner has to come off the summary, which still counts the
# whole track. The first two mutations put a count back on the array: nothing
# throws, every number stays plausible, and a 28,800-fix run is described to the
# person who ran it as a 2,000-fix one.
ROUTE_SECTIONS=lib/features/gps/route_detail_sections.dart
ROUTE_TEST=test/gps/route_screens_test.dart

mutate 'the fix count is taken off the drawn points' "$ROUTE_TEST" "$ROUTE_SECTIONS" \
  "  final String recorded = 'Phone GPS · \${route.recordedPoints} fixes';" \
  "  final String recorded = 'Phone GPS · \${route.points.length} fixes';"

mutate 'the matched-HR count is taken off the drawn points' "$ROUTE_TEST" "$ROUTE_SECTIONS" \
  'body: noFitnessBody(route.matchedHrPoints)' \
  'body: noFitnessBody(
        route.points.where((RoutePoint point) => point.hr != null).length,
      )'

# The server said it thinned and the caption stops saying so, so a sampled
# drawing is presented as the whole track.
mutate 'a thinned drawing stops saying it was thinned' "$ROUTE_TEST" "$ROUTE_SECTIONS" \
  '  if (!route.pointsDecimated) {' \
  '  if (true) {'

# ── the two credentials, and the 401 that ends a session ────────────────────
#
# The server accepts each of these on exactly ONE path — a Supabase JWT on
# `/api/*`, a device token on `/ingest/*` — so a mis-route is not a style
# question. Sending the device token to `/api/*` is a 401 the app would replay
# with a credential that cannot work; sending the hour-long JWT to `/ingest/*`
# is a background sync that stops overnight and blames the network.
INTERCEPTORS=lib/data/api/interceptors.dart
STORED_SESSION=lib/data/api/stored_server_session.dart
IDENTITY_SESSION=lib/data/api/server_session.dart
ROUTING_TEST=test/signin/credential_routing_test.dart
GUARD_TEST=test/signin/session_guard_test.dart
IDENTITY_TEST=test/signin/identity_signin_test.dart

mutate 'the ingest push starts carrying the JWT' "$ROUTING_TEST" "$INTERCEPTORS" \
  '    if (path.startsWith(ingestPrefix)) {
      return session.token;
    }' \
  ''

mutate 'a device token is sent to /api/*' "$ROUTING_TEST" "$INTERCEPTORS" \
  '    return _identity?.accessToken();' \
  '    return await _identity?.accessToken() ?? session.token;'

# The transitional shape, dropped: an owner mid-migration is signed out of
# `/api/*` by an upgrade, with nothing on screen saying why.
mutate 'the shared token stops being accepted on /api/*' "$ROUTING_TEST" "$INTERCEPTORS" \
  '    if (session.kind == StoredCredentialKind.shared) {
      return session.token;
    }' \
  ''

# A record written before `kind` existed can only hold the shared token — the
# mint did not exist then. Read as a device token, those phones stop sending the
# one credential they have.
mutate 'a legacy stored session is read as a device token' \
  "$ROUTING_TEST" "$STORED_SESSION" \
  "      kind: data['kind'] == 'device'
          ? StoredCredentialKind.device
          : StoredCredentialKind.shared," \
  '      kind: StoredCredentialKind.device,'

mutate 'a minted device token is filed as the shared one' \
  "$ROUTING_TEST" "$IDENTITY_SESSION" \
  '      kind: StoredCredentialKind.device,' \
  '      kind: StoredCredentialKind.shared,'

# C4. A 401 that does not end the session is a dead credential replayed on every
# screen load and every background sync, for ever, with no prompt to sign in.
mutate 'a 401 stops ending the session' "$GUARD_TEST" "$INTERCEPTORS" \
  '    if (status == 401 && !path.startsWith(ServerSessionInterceptor.ingestPrefix)) {' \
  '    if (false) {'

# 403 is an ANSWER — a suspension, or a paywall. Signing the owner out over it
# replaces an accurate message with a login screen that changes nothing.
mutate 'a 403 signs the owner out too' "$GUARD_TEST" "$INTERCEPTORS" \
  '    if (status == 401 && !path.startsWith(ServerSessionInterceptor.ingestPrefix)) {' \
  '    if ((status == 401 || status == 403) &&
        !path.startsWith(ServerSessionInterceptor.ingestPrefix)) {'

# A push runs headless in a background isolate: there is nobody to prompt, and a
# revoked INGEST token must not sign the owner out of the app on that phone.
mutate 'a rejected push signs the owner out of the app' "$GUARD_TEST" "$INTERCEPTORS" \
  '    if (status == 401 && !path.startsWith(ServerSessionInterceptor.ingestPrefix)) {' \
  '    if (status == 401) {'

# The order is the design: the identity provider answers a wrong password
# without the owner's server ever being told there was an attempt.
mutate 'the server is asked before the password is proved' \
  "$IDENTITY_TEST" "$IDENTITY_SESSION" \
  '    final trimmed = email.trim();' \
  '    await probe.verify(url: address, token: '"'"'unproven'"'"');
    final trimmed = email.trim();'

# A session held only in memory is an owner signed out by every restart.
mutate 'the Supabase session is never persisted' "$IDENTITY_TEST" \
  lib/data/auth/identity_client.dart \
  '    await _secrets.write(
      key: kIdentitySessionKey,
      value: jsonEncode(session.toJson()),
    );' \
  ''


# Signing in with an email that has no account, and creating one for an email
# that already has one, are OPPOSITE mistakes with opposite remedies. One call
# apart, and the wrong one leaves the owner retrying a create that can never
# succeed instead of switching to sign in.
mutate 'creating an account signs in instead' "$IDENTITY_TEST" "$IDENTITY_SESSION" \
  '    if (create) {
      await auth.signUp(email: trimmed, password: password);
    } else {
      await auth.signIn(email: trimmed, password: password);
    }' \
  '    await auth.signIn(email: trimmed, password: password);'

# A project with email confirmation on returns a user and NO session. Treated as
# success, the app stores nothing and claims to be signed in; treated as a
# refusal, the owner resets a password that was just accepted.
mutate 'an unconfirmed signup is reported as success' "$IDENTITY_TEST" \
  lib/data/auth/identity_client.dart \
  '    if (response.session == null) {
      throw const ServerSignInException(IdentityNeedsConfirmation());
    }' \
  ''

# ⛔ The Zepp password must never become the Healthee one. Two services, two
# passwords — reuse means one breach opens both, which is what makes credential
# stuffing work. The email is a convenience; the password is not offered at all.
mutate 'the sign-in form is handed a password to prefill' \
  test/signin/zepp_prefill_test.dart \
  lib/features/signin/server_signin_screen.dart \
  '    final email = await ref.read(credentialsProvider).zeppEmail();' \
  '    final email = await ref.read(credentialsProvider).zeppPassword();'


# ⛔ The 44 px is decoration without this line, and NOTHING about that is visible
# — the box is the right size, the screenshot is right, and a widget test that
# taps `find.text(...)` passes because tapping the text is what still worked. It
# shipped four times before the owner reported the links as hard to press.
mutate 'a link defers hit-testing to its painted pixels' \
  test/core/tap_target_gate_test.dart lib/shared/v02/buttons.dart \
  '        behavior: HitTestBehavior.opaque,
        child: Opacity(' \
  '        child: Opacity('

# And the constraint itself, which is the other half: opaque over a 17 px box is
# an honest tap target for a control that is too small.
mutate 'the 44 px link constraint is dropped' \
  test/core/tap_target_gate_test.dart lib/shared/v02/buttons.dart \
  '  /// `.text-button { min-height: 44px }`.
  static const double minHeight = 44;' \
  '  /// `.text-button { min-height: 44px }`.
  static const double minHeight = 0;'


# ⛔⛔ THE ONE THAT COST A DAY. `AuthRetryableFetchException extends AuthException`,
# so folding the two clauses together makes an unreachable server indistinguishable
# from a refused credential — and the handler DELETES the session. One flaky app
# start signs the owner out permanently, silently, with a spinner on screen.
mutate 'an unreachable sign-in service deletes the session' \
  test/signin/session_survives_offline_test.dart \
  lib/data/auth/identity_client.dart \
  '    } on AuthRetryableFetchException catch (error) {
      // Kept, and deliberately not memoised: the session is probably fine and we
      // could not reach the one server that can say otherwise.
      _ready = null;
      AppLog.info('"'"'identity'"'"', '"'"'could not reach the sign-in service (${error.code})'"'"');
    } on AuthException catch (error) {' \
  '    } on AuthException catch (error) {'

# The memoisation half: keeping the session but caching the failure would make the
# rest of the process behave as signed out even after the network came back.
mutate 'a failed recovery is memoised as if it had answered' \
  test/signin/session_survives_offline_test.dart \
  lib/data/auth/identity_client.dart \
  '      _ready = null;
      AppLog.info('"'"'identity'"'"', '"'"'could not reach the sign-in service (${error.code})'"'"');' \
  '      AppLog.info('"'"'identity'"'"', '"'"'could not reach the sign-in service (${error.code})'"'"');'


# The retry storm. Announcing every 401 instead of the first closes a loop:
# invalidate -> the screens rebuild -> they request -> 401. 1,280 requests in four
# minutes in production, and every screen pinned in LOADING because no request
# survived long enough to become an error.
mutate 'every 401 re-announces the rejection' \
  test/signin/session_guard_test.dart lib/data/api/server_session.dart \
  '    if (rejected) {
      return false;
    }
    rejected = true;
    return true;' \
  '    rejected = true;
    return true;'

# And the other end of it: a sign-in that left the flag set would swallow the
# owner'"'"'s next real rejection, so the screens would never hear about it.
mutate 'signing in leaves the rejected flag set' \
  test/signin/session_guard_test.dart lib/data/api/server_session.dart \
  '    rejected = false;
    AppLog.info('"'"'signin'"'"', '"'"'signed in to ${address.host} with a pasted token'"'"');' \
  '    AppLog.info('"'"'signin'"'"', '"'"'signed in to ${address.host} with a pasted token'"'"');'


# ⛔ The release check asks a THIRD PARTY a question that needs no identity. Reusing
# the app's own client would attach the owner's credential to every one of those
# requests — quietly, on every app open, forever.
mutate 'the release check is given a credential-carrying client' \
  test/updates/release_client_test.dart lib/data/updates/release_client.dart \
  '      responseType: ResponseType.json,
      validateStatus: (_) => true,
      headers: const <String, String>{' \
  '      responseType: ResponseType.json,
      validateStatus: (_) => true,
      headers: const <String, String>{
        '"'"'Authorization'"'"': '"'"'Bearer leaked-owner-token'"'"',';

# "Up to date" is a CLAIM. An offline phone, a rate limit and a repo with no
# releases are not evidence for it, and collapsing them into it is the app
# reassuring somebody about something it never established.
mutate 'an unestablished check reports up to date' \
  test/updates/update_check_test.dart lib/data/updates/update_check.dart \
  '  if (current == null || release == null) {
    return const UpdateUnknown();
  }' \
  '  if (current == null || release == null) {
    return const UpToDate();
  }'

# The installer'"'"'s own rule. Comparing version NAMES instead would offer a download
# that Android then refuses as a downgrade — a 72 MB wait ending in an error the
# owner cannot act on.
mutate 'the update comparison uses the version name' \
  test/updates/app_release_test.dart lib/data/updates/app_release.dart \
  '  bool isNewerThan(int current) => versionCode > current;' \
  '  bool isNewerThan(int current) => versionCode >= current;'

# A release whose notes carry no versionCode cannot be compared at all. Treating it
# as comparable is how the updater starts guessing.
mutate 'a release with no versionCode is used anyway' \
  test/updates/app_release_test.dart lib/data/updates/app_release.dart \
  '    if (versionCode == null) {
      return null;
    }' \
  ''


# Shipped, and seen on a real phone: Sleep read "…sleep debt of 1,793 minutes ``."
# The model backticks its citations because the system prompt's examples do, so
# stripping the bracket left the ticks as punctuation noise on the one sentence
# whose job is to carry a claim and show its evidence.
mutate 'a stripped citation leaves its backticks behind' \
  test/data/citations_test.dart lib/data/honesty/citations.dart \
  "    .replaceAll(RegExp(r'\`[ \\t]*\`'), '')
" \
  ''


# ⛔ The discovery call decides where the next two lines send a PASSWORD. Skipping
# it puts the app back to signing in against whatever was compiled in — which is
# the whole thing auth-config exists to end.
mutate 'sign-in skips asking the server who it trusts' \
  test/auth/discovery_test.dart lib/data/api/server_session.dart \
  '    await _discoverIdentity(address);
' \
  ''

# A remembered provider from a server that could not serve one would point the
# NEXT sign-in at it. Storing before the answer is checked is how that happens.
mutate 'a server with no provider is remembered anyway' \
  test/auth/discovery_test.dart lib/data/api/server_session.dart \
  '      case AuthConfigNone():
        throw const ServerSignInException(ServerHasNoIdentityProvider());' \
  '      case AuthConfigNone():
        return;'

# "Configure this server" and "update this server" are different jobs for
# different people. The 404 is how the server tells us which.
mutate 'a too-old server is reported as an unconfigured one' \
  test/auth/discovery_test.dart lib/data/api/server_session.dart \
  '      case AuthConfigUnsupported():
        throw const ServerSignInException(ServerTooOldForSignIn());' \
  '      case AuthConfigUnsupported():
        throw const ServerSignInException(ServerHasNoIdentityProvider());'

# The stored provider is what makes a published APK point at the OWNER's project.
# Preferring the compiled-in one would quietly restore the old behaviour.
mutate 'the compiled-in provider wins over the discovered one' \
  test/auth/discovery_test.dart lib/data/auth/identity_providers.dart \
  'Future<AuthConfig?> resolveAuthConfig(Credentials credentials) async =>
    await credentials.authConfig() ??' \
  'Future<AuthConfig?> resolveAuthConfig(Credentials credentials) async =>
    null ??'


# ⛔ THE UPGRADE PATH. Without it every existing install signs itself out: a phone
# that signed in before auth-config existed has a session and an address but no
# provider, so on a defines-free build the client is never built, the session
# cannot be recovered, and every call is a 401 with no token in it. Silently.
mutate 'an upgrading install never asks the server it is signed in to' \
  test/auth/discovery_test.dart lib/data/auth/identity_providers.dart \
  '  return _fromTheServerWeAreSignedInTo(credentials, discover);' \
  '  return null;'

# And a bad moment must not become a permanent signed-out state.
mutate 'an unreachable server is cached as having no provider' \
  test/auth/discovery_test.dart lib/data/auth/identity_providers.dart \
  '  if (result is! AuthConfigFound) {
    AppLog.info('"'"'identity'"'"', '"'"'the signed-in server named no provider yet'"'"');
    return null;
  }
  await credentials.setAuthConfig(result.config);' \
  '  if (result is! AuthConfigFound) {
    await credentials.setAuthConfig(
      const AuthConfig(supabaseUrl: '"'"'x'"'"', anonKey: '"'"'y'"'"'),
    );
    return null;
  }
  await credentials.setAuthConfig(result.config);'


# ⛔ The SECOND time this shape bit. `restore()` memoises, so returning here with
# `_ready` completed means the provider is never resolved again for the life of the
# process — `accessToken()` returns null forever and every /api/* call is a 401
# with no token in it. Observed on a real phone against a server answering fine.
mutate 'a failed provider resolution is memoised as complete' \
  test/auth/discovery_test.dart lib/data/auth/identity_client.dart \
  '      _ready = null;
      return;
    }
    _watch ??= auth.onAuthStateChange.listen(_persist, onError: _noteStreamError);' \
  '      return;
    }
    _watch ??= auth.onAuthStateChange.listen(_persist, onError: _noteStreamError);'


# Reported from a real install: "i need to add server address its set as 127".
# A published APK is aimed at nobody, so `Env.apiBaseUrl` falls back to loopback —
# and prefilling that shows the reader an answer we do not have: a real-looking
# address, wrong for everyone who did not build the app, above a button.
mutate 'the loopback fallback is prefilled as if it were an answer' \
  test/features/server_signin_screen_test.dart \
  lib/features/signin/server_signin_screen.dart \
  "String get _suggestedAddress => Env.isUsingFallbackApi ? '' : Env.apiBaseUrl;" \
  'String get _suggestedAddress => Env.apiBaseUrl;'


# ⛔ A program the coach designed reached NO screen. `create_program` wrote a
# ladder in `suggested`, the feed served it with every field the client parses, and
# the deck knew about two of the three feeds. Found on a real install: the owner
# went looking for a six-week ladder and it was nowhere — which is also why it was
# still `suggested` with no adopted_at. There was never a button.
mutate 'suggested programs are dropped from the deck again' \
  test/features/program_in_deck_test.dart \
  lib/features/actions/v02/suggestion_list.dart \
  '      if (repository != null)
        for (final program in programs?.suggested ?? const <HealthProgram>[])
          DeckItem.program(program, repository, ref),' \
  ''

# A ladder commits you to an ORDER, not a number. Quoting the first rung's target
# reads as the whole commitment when it is only the first step, and the point of a
# ladder is that the target moves.
mutate 'a program quotes its first rung as the commitment' \
  test/features/program_in_deck_test.dart \
  lib/features/actions/v02/deck_item.dart \
  "        '\${program.rungs.length} rungs, one at a time'" \
  "        '\${program.rungs.first.target.round()} steps'"

# The preflight scan answered from the PREVIOUS scan's results, stopped the
# new scan before Android registered it, and left a LOW_LATENCY scan running.
mutate 'the strap scan listens to the replaying scanResults stream again' \
  test/ble/strap_scan_test.dart lib/ble/bluetooth_strap_scanner.dart \
  '  final subscription = FlutterBluePlus.onScanResults.listen((results) {' \
  '  final subscription = FlutterBluePlus.scanResults.listen((results) {'
# Back destroys the engine but not the process; the next UI isolate must
# reclaim a lease the replaced one never released, and must not rob anyone else.
mutate 'a replaced UI isolate keeps the strap until expiry again' \
  test/background/device_lease_ui_isolate_test.dart lib/data/sync/device_lease.dart \
  '    if (!legacy && !replacedUi && (owner == _pid || _isRunning(owner))) {' \
  '    if (!legacy && (owner == _pid || _isRunning(owner))) {'
mutate 'a UI isolate robs another lease inside itself' \
  test/background/device_lease_ui_isolate_test.dart lib/data/sync/device_lease.dart \
  '        holderUi != _uiIsolate;' \
  '        true;'
mutate 'a background isolate reclaims a live UI isolate lease' \
  test/background/device_lease_test.dart lib/data/sync/device_lease.dart \
  '        _uiIsolate != null &&' \
  ''
mutate 'the UI isolate stops stamping its lease rows' \
  test/background/device_lease_ui_isolate_test.dart lib/data/sync/device_lease.dart \
  "      '\${_uiIsolate == null ? '' : ':\$_uiIsolate'}';" \
  "      '';"
mutate 'a link refused the lease goes silent again' \
  test/sync/foreground_link_lease_test.dart lib/data/sync/foreground_link.dart \
  '        onState(Disconnected(lastCompleteSync: await lastCompleteSync()));' \
  ''

echo
echo "caught $PASS, survived $FAIL"
[ "$SKIPPED" -eq 0 ] || echo "SKIPPED $SKIPPED — this was a FILTERED run, not the gate"
[ "$FAIL" -eq 0 ]
