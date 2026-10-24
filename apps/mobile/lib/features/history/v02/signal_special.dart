/// The rows whose figure is not a card's: sleep health (four checks), sleep
/// debt (nights short), and the values the snapshot keeps in typed blocks.
///
/// Presentation only. Each judgement is a plain reading of a field the server
/// sent: a missed check is `passed == false`, debt is `debt_min > 0`, a goal is
/// `Mvpa.weekTarget` and nothing else.
library;

import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/data/models/today_snapshot.dart';
import 'package:healthee/features/history/v02/signal_row.dart';
import 'package:healthee/shared/format/duration.dart';
import 'package:healthee/shared/v02/reading_state.dart';

/// The week's minutes for the three MVPA rows. These are weekly figures, so
/// they come from the MVPA block ahead of any card that might carry a day's.
double? weekValue(String metric, TodaySnapshot? snapshot) {
  final mvpa = snapshot?.mvpa.valueOrNull;
  return switch (metric) {
    'mvpa_min' => mvpa?.weekMin.toDouble(),
    'vigorous_min' => mvpa?.weekVigorousMin?.toDouble(),
    'moderate_min' => mvpa?.weekModerateMin?.toDouble(),
    _ => null,
  };
}

/// The weekly goal, only where the server sent one.
double? weekGoal(String metric, TodaySnapshot? snapshot) => metric == 'mvpa_min'
    ? snapshot?.mvpa.valueOrNull?.weekTarget?.toDouble()
    : null;

/// The value a typed block holds for [metric], when no card carries it.
double? blockValue(String metric, TodaySnapshot? snapshot) => switch (metric) {
  'recovery_score' => snapshot?.recovery.valueOrNull?.recovery.toDouble(),
  'vo2max_estimate' => snapshot?.vo2max.valueOrNull?.estimate,
  'cardio_load' => snapshot?.cardioLoad.valueOrNull?.load,
  _ => null,
};

/// The sleep-health and sleep-debt rows, or null for any other metric.
SignalRow? specialRow(
  String metric,
  String title,
  Tone tone,
  TodaySnapshot? snapshot,
) => switch (metric) {
  'sleep_health_score_4dim' => _sleepHealth(title, tone, snapshot),
  'sleep_debt_min' => _sleepDebt(title, tone, snapshot),
  _ => null,
};

SignalRow _sleepHealth(String title, Tone tone, TodaySnapshot? snapshot) {
  final health = snapshot?.sleepHealth.valueOrNull;
  final dims = health?.dimensions ?? const [];
  final missed = dims.where((d) => d.passed == false).length;
  final unscored = dims.where((d) => d.passed == null).length;
  final scored = dims.isNotEmpty;
  return SignalRow(
    metric: 'sleep_health_score_4dim',
    title: title,
    tone: tone,
    caption: scored
        ? dims.map((d) => d.name.toLowerCase()).join(', ')
        : 'higher is better',
    judgement: !scored
        ? const Judgement(ReadingState.noData, 'No reading')
        : missed > 0
        ? Judgement(ReadingState.worse, '$missed missed')
        : unscored > 0
        ? Judgement(ReadingState.usual, '$unscored not scored')
        : const Judgement(ReadingState.better, 'All met'),
    figure: scored ? SignalFigure('${health!.met}', '/${dims.length}') : null,
    graphic: SignalGraphic.checks,
    checks: <bool?>[for (final d in dims) d.passed],
    spoken: scored ? '${health!.met} of ${dims.length} checks met' : '',
  );
}

SignalRow _sleepDebt(String title, Tone tone, TodaySnapshot? snapshot) {
  final debt = snapshot?.sleepDebt.valueOrNull;
  if (debt == null) {
    return SignalRow(
      metric: 'sleep_debt_min',
      title: title,
      tone: tone,
      caption: snapshot == null ? 'lower is better' : 'not enough nights yet',
      judgement: const Judgement(ReadingState.noData, 'No reading'),
      graphic: SignalGraphic.bar,
    );
  }
  final behind = debt.debtMin > 0;
  final share = debt.nights > 0 ? debt.nightsBelow / debt.nights : null;
  return SignalRow(
    metric: 'sleep_debt_min',
    title: title,
    tone: tone,
    caption: 'last ${debt.nights} nights · ${debt.nightsBelow} short',
    judgement: behind
        ? const Judgement(ReadingState.worse, 'Behind')
        : const Judgement(ReadingState.better, 'No debt'),
    figure: SignalFigure(durationText(debt.debtMin)),
    graphic: SignalGraphic.bar,
    progress: share?.clamp(0.0, 1.0),
    spoken: durationText(debt.debtMin),
  );
}
