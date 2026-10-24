/// How a reading is judged: one vocabulary for every chip, dot and bar.
///
/// The colour kit's rule 4: **each metric has a polarity, and the usual range
/// is the owner's own 30-day middle.** Inside the range is neutral, never
/// green; green is earned by being better than usual and red by being worse.
/// A metric with a best-inside-range polarity (blood oxygen, skin temperature)
/// is *watch* yellow on either side, because neither side is good or bad.
///
/// ```text
///   inside the range                 usual   ink, "Usual"
///   higher is better, above          better  "↑ Above usual"
///   higher is better, below          worse   "↓ Below usual"
///   lower is better,  below          better  "↓ Below usual"
///   lower is better,  above          worse   "↑ Above usual"
///   best inside the range, outside   watch   "↑ Outside usual"
///   no judgement, outside            usual   "↑ Above usual", in ink2
///   goal met / short of it           better / worse
///   no range yet                     usual   "No trend yet"
///   no reading                       noData  "No reading"
/// ```
///
/// The range is the server's (`median_30d` ± `sd_30d`); this file draws a
/// verdict from it and never defines a second one (`usual_range.dart` owns the
/// local quartile band the older cards still use).
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/data/models/metric_card.dart';
import 'package:healthee/shared/usual_range.dart';

/// Which way is better for a reading.
enum Polarity {
  /// HRV, recovery, VO₂max, regularity, efficiency, sleep health.
  higherBetter,

  /// Resting heart rate, breathing rate, sleep debt, biological age, stress.
  lowerBetter,

  /// Blood oxygen, skin temperature, weight, bedtime.
  insideRange,

  /// Steps, active minutes: judged against a goal, not a range.
  goal,

  /// Nothing to judge: the range is shown and no colour is spent.
  neutral,
}

/// The five things a dot, a chip or a ring can be.
enum ReadingState {
  /// Better than usual, a goal met.
  better,

  /// Worse than usual, a goal missed.
  worse,

  /// Outside the range with no good side.
  watch,

  /// Inside the range, or nothing to judge. Neutral.
  usual,

  /// Not recorded. Hatched grey and a dash, never coloured.
  noData,
}

/// Resolves a state to the theme's colour. Neutral states return `ink2`, the
/// text-secondary ink, so a chip in the usual range spends no colour.
extension ReadingStateColour on ReadingState {
  /// The colour of a dot or a chip's words in this state.
  Color colourIn(HealtheeColors colors) => switch (this) {
    ReadingState.better => colors.fav,
    ReadingState.worse => colors.alert,
    ReadingState.watch => colors.unf,
    ReadingState.usual => colors.ink2,
    ReadingState.noData => colors.ink3,
  };

  /// The newest dot's colour: like [colourIn], but a reading inside its range
  /// is the primary ink, not the secondary one.
  Color dotIn(HealtheeColors colors) =>
      this == ReadingState.usual ? colors.ink : colourIn(colors);

  /// The chip's fill, or null when the state draws no tinted chip.
  Color? fillIn(HealtheeColors colors) => switch (this) {
    ReadingState.better => colors.favSoft,
    ReadingState.worse => colors.alertSoft,
    ReadingState.watch => colors.unfSoft,
    ReadingState.usual || ReadingState.noData => null,
  };
}

/// The verdict on one reading.
@immutable
class Judgement {
  /// A verdict.
  const Judgement(this.state, this.words);

  /// Better, worse, watch, usual or no data.
  final ReadingState state;

  /// The chip's words, with its arrow.
  final String words;

  @override
  bool operator ==(Object other) =>
      other is Judgement && other.state == state && other.words == words;

  @override
  int get hashCode => Object.hash(state, words);

  @override
  String toString() => 'Judgement($state, $words)';
}

/// Judges [value] against [usual] by [polarity].
///
/// [value] null is "No reading"; [usual] null is "No trend yet". For
/// [Polarity.goal] pass [goal] and the verdict is `Goal met` or `N to go`
/// (the shortfall, in whole units).
Judgement judge({
  required double? value,
  required UsualRange? usual,
  required Polarity polarity,
  double? goal,
}) {
  if (value == null || !value.isFinite) {
    return const Judgement(ReadingState.noData, 'No reading');
  }
  if (polarity == Polarity.goal && goal != null) {
    return value >= goal
        ? const Judgement(ReadingState.better, 'Goal met')
        : Judgement(ReadingState.worse, '${(goal - value).ceil()} to go');
  }
  if (usual == null) {
    return const Judgement(ReadingState.usual, 'No trend yet');
  }
  final side = usual.sideOf(value);
  if (side == UsualSide.within) {
    return const Judgement(ReadingState.usual, 'Usual');
  }
  final above = side == UsualSide.above;
  final words = above ? '↑ Above usual' : '↓ Below usual';
  return switch (polarity) {
    Polarity.higherBetter => Judgement(
      above ? ReadingState.better : ReadingState.worse,
      words,
    ),
    Polarity.lowerBetter => Judgement(
      above ? ReadingState.worse : ReadingState.better,
      words,
    ),
    Polarity.insideRange => Judgement(
      ReadingState.watch,
      above ? '↑ Outside usual' : '↓ Outside usual',
    ),
    Polarity.goal || Polarity.neutral => Judgement(ReadingState.usual, words),
  };
}

/// The server's usual range for [card]: `median_30d` ± `sd_30d`. Null until
/// the server has a baseline for it.
UsualRange? usualOfCard(MetricCard card) {
  final median = card.median30d;
  final sd = card.sd30d;
  if (median == null || sd == null || sd <= 0) {
    return null;
  }
  return UsualRange(low: median - sd, high: median + sd, days: 30);
}

/// The polarity of a metric by id; anything unlisted is [Polarity.neutral].
Polarity polarityOf(String metric) => switch (metric) {
  'hrv_sleep_avg' ||
  'hrv' ||
  'recovery_score' ||
  'recovery' ||
  'vo2max_estimate' ||
  'sleep_regularity_index' ||
  'sleep_health_score_4dim' ||
  'tst_min' ||
  'sleep_efficiency' => Polarity.higherBetter,
  'rhr_daily' ||
  'resting_hr' ||
  'respiratory_rate_sleep' ||
  'sleep_debt_min' ||
  'biological_age' ||
  'stress' ||
  'stress_daily' => Polarity.lowerBetter,
  'spo2_overnight' ||
  'spo2_overnight_min' ||
  'temperature_c' ||
  'skin_temp_c' ||
  'weight_kg' => Polarity.insideRange,
  'mvpa_min' || 'steps_total' => Polarity.goal,
  _ => Polarity.neutral,
};
