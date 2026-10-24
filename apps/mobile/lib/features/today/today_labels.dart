/// The small pure helpers legacy's Today screen keeps at file scope.
///
/// **Ported from** `healthee-legacy/app/lib/ui/today_screen.dart` — `_comma`
/// (429), `_sleepNightLabel` (506), `_noSleepLastNight` (521), `_stageFoot`
/// (421), `_hypnoFromTotals` (406), `_GreetingHeader._prettyDate` (491) and the
/// `medFoot` / `highGood` / `good` closures inside `_Content.build` (159–170).
///
/// They live in one file because they are the screen's *vocabulary* — every one
/// of them turns a number into the exact words legacy prints, and a second copy
/// of any of them is a second wording. Nothing here draws.
///
/// ## The one deliberate signature change
///
/// [sleepNightLabel] and [noSleepLastNight] take `now` rather than calling
/// `DateTime.now()` as legacy does. Both decide a *sentence about staleness*, and
/// a test that cannot fix the clock cannot assert the sentence. Every caller on
/// this screen already has an injected instant (`ScreenData.now`).
library;

/// `prettyDate` moved to `shared/format/` when Activity and Insights grew the
/// same header (Standards §1, second use; §3, no cross-feature imports). It is
/// re-exported rather than copied, so there is still one definition and every
/// call site that reads it from here is unchanged.
export 'package:healthee/shared/format/date_labels.dart'
    show dayTitle, prettyDate;

/// `shortClock` moved to `shared/format/time_labels.dart` when Insights grew
/// the same hour axis. Same reason, same re-export: one definition, and two
/// screens drawing one chart cannot label it two ways.
export 'package:healthee/shared/format/time_labels.dart' show shortClock;

/// `9264` → `9,264`. Legacy's `_comma`, regex and all.
String commaGrouped(int value) => value.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
  (match) => '${match[1]},',
);

/// Honest name for the sleep session on screen. Legacy's `_sleepNightLabel`.
///
/// "Last night" is a claim, and it is false when the owner was travelling and
/// did not sleep. The label counts **calendar days between waking and today**,
/// not hours, so a nap that ended at 02:00 this morning is still last night.
String sleepNightLabel(String? endIso, DateTime now) {
  if (endIso == null) {
    return 'Last night';
  }
  final end = DateTime.tryParse(endIso)?.toLocal();
  if (end == null) {
    return 'Last night';
  }
  final wake = DateTime(end.year, end.month, end.day);
  final today = DateTime(now.year, now.month, now.day);
  final daysAgo = today.difference(wake).inDays;
  if (daysAgo <= 0) {
    return 'Last night';
  }
  if (daysAgo == 1) {
    return 'Night before last';
  }
  return '$daysAgo nights ago';
}

/// True when the most recent sleep ended 24 h ago or more.
///
/// Legacy's `_noSleepLastNight`: when it is true, every overnight reading below
/// — sleep, HRV, SpO₂, breathing and their charts — is from an older night, and
/// the section gets a banner saying so.
bool noSleepLastNight(String? endIso, DateTime now) {
  final end = DateTime.tryParse(endIso ?? '')?.toLocal();
  if (end == null) {
    return false;
  }
  return now.difference(end).inHours >= 24;
}

/// `DEEP 24% · REM 24%` under the Sleep tile. Legacy's `_stageFoot`.
///
/// The denominator is light + deep + REM and deliberately **excludes awake** —
/// the percentages are of time asleep, not of time in bed. With no totals at all
/// legacy prints the em-dash form rather than `DEEP 0% · REM 0%`, because a zero
/// is a measurement and this is the absence of one.
String stageFoot(Map<String, int> totals) {
  double minutes(String key) => (totals[key] ?? 0).toDouble();
  final asleep = minutes('light') + minutes('deep') + minutes('rem');
  if (asleep == 0) {
    return 'DEEP — · REM —';
  }
  return 'DEEP ${(minutes('deep') / asleep * 100).round()}% · '
      'REM ${(minutes('rem') / asleep * 100).round()}%';
}

// `hypnogramSpans` lived here — legacy's `_hypnoFromTotals`, with legacy's
// fabricated one-minute light-sleep band for an unstaged night removed. It went
// with the Sleep tile's hypnogram on 2026-08-06 (see `today_tiles.dart`, the
// owner-delegated departure): the tile draws `HStageBar` now and nothing else
// consumed it. The guard did not go with it — `HStageBar` drops zero-minute
// stages itself and draws NOTHING for a night with no staged minutes, which
// `test/features/grid_sleep_cell_test.dart` asserts. Standards §1: delete dead
// code, git has it.

/// `MED 55`, or `14-DAY TREND` when there is no median yet. Legacy's `medFoot`.
///
/// Four-figure medians are comma-grouped and smaller ones are not, which is
/// legacy's `m >= 1000` branch verbatim.
String medianFoot(double? median30d) {
  if (median30d == null) {
    return '14-DAY TREND';
  }
  final rounded = median30d.round();
  return 'MED ${median30d >= 1000 ? commaGrouped(rounded) : rounded}';
}

/// The metrics where a HIGHER reading is the favourable one. Legacy's `highGood`.
///
/// It decides the colour of a delta badge and nothing else. Kept as legacy's own
/// set rather than derived from `shared/format/metric_polarity.dart`: that table
/// is this rebuild's and is keyed differently, and two tables that must agree
/// about "is up good" are exactly the second definition CLAUDE.md forbids. The
/// divergence is reported rather than merged here.
const Set<String> highIsFavorable = <String>{
  'hrv_sleep_avg',
  'steps_total',
  'total_calories',
  'active_calories',
  'sleep_health_score_4dim',
  'sleep_regularity_index',
  'mvpa_min',
  'vo2max_estimate',
  'spo2_overnight',
};

/// Whether a z-score is the good direction for [metric]. Legacy's `good`.
///
/// Null for a missing z **and for exactly zero**, which is legacy's own
/// `z == 0 ? null` — a reading sitting on its own median has no direction, and
/// painting it green would be a verdict invented out of no movement.
bool? favorableDirection(String metric, double? z) {
  if (z == null || z == 0) {
    return null;
  }
  return highIsFavorable.contains(metric) ? z > 0 : z < 0;
}

/// `6:20` from minutes — the Sleep tile's figure. Legacy's inline expression at
/// `today_screen.dart:175`.
String clockDuration(int minutes) =>
    '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}';
