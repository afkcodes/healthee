/// `Your trends` — the owner's main readings over a week, a month or six
/// months, each against the same length of time before it
/// (`design/mobile-preview/proposal.js`, `#p-trends`).
///
/// Every card is `trend_card.dart`'s, fed by `/api/history` one metric at a
/// time, so a metric that fails to load fails on its own card and says so.
///
/// Not here yet, though the preview drew them: time asleep, bed and wake, and
/// deep sleep by day. `/api/history` has no daily sleep-duration or stage
/// series (`history_metric.dart`), and a card that computed one on the phone
/// would be a second definition of a sleep metric. They live on Sleep.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/data/history/history_metric.dart';
import 'package:healthee/data/history/history_repository.dart';
import 'package:healthee/features/trends/trends_period.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:healthee/shared/states/state_scaffold.dart';
import 'package:healthee/shared/v02/choices.dart';
import 'package:healthee/shared/v02/data_footer.dart';
import 'package:healthee/shared/v02/detail_page.dart';
import 'package:healthee/shared/v02/panel_parts.dart';
import 'package:healthee/shared/v02/trend_card.dart';
import 'package:healthee/shared/v02/view_day.dart';
import 'package:solar_icons/solar_icons.dart';

/// What one card shows.
typedef TrendSpec = ({
  HistoryMetric metric,
  String title,
  Tone tone,
  IconData icon,
  int digits,
  bool? higherIsBetter,
});

/// The cards, in order.
const List<TrendSpec> kTrendSpecs = <TrendSpec>[
  (
    metric: HistoryMetric.hrv,
    title: 'Overnight HRV',
    tone: Tone.fitness,
    icon: SolarIconsOutline.pulse,
    digits: 0,
    higherIsBetter: true,
  ),
  (
    metric: HistoryMetric.restingHr,
    title: 'Resting heart rate',
    tone: Tone.heart,
    icon: SolarIconsOutline.heartPulse,
    digits: 0,
    higherIsBetter: false,
  ),
  (
    metric: HistoryMetric.recovery,
    title: 'Recovery',
    tone: Tone.recovery,
    icon: SolarIconsOutline.heartPulse,
    digits: 0,
    higherIsBetter: true,
  ),
  (
    metric: HistoryMetric.steps,
    title: 'Steps',
    tone: Tone.movement,
    icon: SolarIconsOutline.walking,
    digits: 0,
    higherIsBetter: true,
  ),
  (
    metric: HistoryMetric.sleepRegularity,
    title: 'Sleep regularity',
    tone: Tone.sleep,
    icon: SolarIconsOutline.moonSleep,
    digits: 0,
    higherIsBetter: true,
  ),
];

/// The screen.
class TrendsScreen extends ConsumerStatefulWidget {
  const TrendsScreen({super.key});

  /// `proposal.js`'s legend over the cards.
  static const String legend =
      'On every chart the shaded band is your usual range, from the same '
      'length of time before; the dashed line is this period\'s average; a '
      'hollow dot is a reading outside your range.';

  @override
  ConsumerState<TrendsScreen> createState() => _TrendsScreenState();
}

class _TrendsScreenState extends ConsumerState<TrendsScreen> {
  final RevealRegistry _reveals = RevealRegistry();
  TrendPeriod _period = TrendPeriod.week;

  @override
  Widget build(BuildContext context) {
    final end = watchViewDay(ref).day;
    return DetailPage(
      title: 'Your trends',
      eyebrow: _period.label,
      children: <Widget>[
        Segment<TrendPeriod>(
          options: <(TrendPeriod, String)>[
            for (final p in TrendPeriod.values) (p, p.label),
          ],
          selected: _period,
          onSelect: (p) => setState(() => _period = p),
        ),
        const SizedBox(height: Insets.cardGap),
        const PanelNote(TrendsScreen.legend),
        for (final spec in kTrendSpecs) ...<Widget>[
          const SizedBox(height: Insets.cardGap),
          _card(spec, end),
        ],
        const SizedBox(height: Insets.section),
        const DataFooter(),
      ],
    );
  }

  Widget _card(TrendSpec spec, String end) => ref
      .watch(metricHistoryProvider(spec.metric, _period.fetchDays))
      .when(
        skipLoadingOnRefresh: true,
        loading: () => LoadingState(label: 'Reading ${spec.title}'),
        error: (error, stackTrace) => ErrorState(
          message: "Couldn't load ${spec.title}",
          onRetry: () => ref.invalidate(
            metricHistoryProvider(spec.metric, _period.fetchDays),
          ),
        ),
        data: (points) {
          final cut = cutPeriod(points, end, _period);
          return TrendCard(
            title: spec.title,
            tone: spec.tone,
            icon: spec.icon,
            unit: spec.metric.unit,
            values: cut.values,
            earlier: cut.earlier,
            digits: spec.digits,
            higherIsBetter: spec.higherIsBetter,
            captions: cut.captions,
            readings: _period.readings,
            before: _period.before,
            revealId: 'trends.${spec.metric.id}.${_period.name}',
            reveals: _reveals,
          );
        },
      );
}
