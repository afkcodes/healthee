/// `Beyond a single night` — efficiency, regularity and HRV over the fortnight.
///
/// `design/mobile-preview/sleep-history-view.js`:
///
/// ```js
/// ${H.chapter('sleep-trends','Beyond a single night','sleep','insights')}
/// ${['efficiency','regularity','hrv'].map(key => H.historyPanel(key)).join('')}
/// ```
///
/// Each of those is a panel with the latest reading, a full line chart with its
/// gridlines and its touch readout, and a line saying how many dated samples are
/// behind it.
///
/// ## Straight segments, never a spline
///
/// These are **nightly** readings — one number per night, not a dense continuous
/// trace — so the line joins them and does not curve between them. A monotone
/// curve would be defensible for a heart-rate trace sampled every minute; here
/// it would draw an efficiency at 03:00 on a night that has exactly one
/// efficiency, and the rule this project already learned the expensive way is
/// that an interpolation must never produce a value nobody measured.
///
/// ## A gap stays a gap
///
/// A night the strap did not measure enters the series as `null`.
/// `SeriesPainter` breaks the line there rather than joining across it, so a
/// missing night looks missing instead of looking like a straight run.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/data/honesty/reading.dart';
import 'package:healthee/data/honesty/sleep_gap.dart';
import 'package:healthee/data/models/sleep_night.dart';
import 'package:healthee/features/sleep/sleep_format.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:healthee/shared/v02/trend_card.dart';
import 'package:solar_icons/solar_icons.dart';

/// One of the three fortnight panels.
@immutable
class SleepTrend {
  /// What to draw, and where its numbers come from.
  const SleepTrend({
    required this.title,
    required this.tone,
    required this.unit,
    required this.metric,
    required this.read,
    this.digits = 0,
    this.infoKey,
    this.higherIsBetter = true,
    this.ceiling,
  });

  /// The prototype's panel title.
  final String title;

  /// Which family it belongs to.
  final Tone tone;

  /// The unit beside the figure and in the readout.
  final String unit;

  /// The metric this panel opens.
  final String metric;

  /// Pulls this trend's value off one night.
  final Reading<double> Function(SleepNight night) read;

  /// How many decimals the figure carries.
  final int digits;

  /// Which ⓘ entry belongs to it.
  final String? infoKey;

  /// Which way is better. All three are higher today.
  final bool higherIsBetter;

  /// A scale the reading cannot pass, 100 for a percentage.
  final double? ceiling;
}

/// The three, in the prototype's order.
const List<SleepTrend> kSleepTrends = <SleepTrend>[
  SleepTrend(
    title: 'Sleep efficiency',
    tone: Tone.sleep,
    unit: '%',
    metric: 'efficiency_pct',
    read: _efficiency,
    digits: 1,
    infoKey: 'sleep_health',
    ceiling: 100,
  ),
  SleepTrend(
    title: 'Sleep regularity',
    tone: Tone.sleep,
    unit: 'SRI',
    metric: 'sri',
    read: _sri,
    infoKey: 'sleep_consistency',
  ),
  SleepTrend(
    title: 'Heart-rate variability',
    tone: Tone.fitness,
    unit: 'ms',
    metric: 'hrv_sleep_avg',
    read: _hrv,
    infoKey: 'hrv',
  ),
];

Reading<double> _efficiency(SleepNight night) => night.efficiencyPct;
Reading<double> _sri(SleepNight night) => night.sri;
Reading<double> _hrv(SleepNight night) => night.hrvSleepAvg;

/// One trend card over the fortnight, read against the fortnight before
/// (`trend_card.dart` draws it; this picks the nights).
class SleepTrendPanel extends StatelessWidget {
  /// [recent] and [earlier] are newest first, the order `/api/sleep` sends.
  const SleepTrendPanel({
    required this.trend,
    required this.recent,
    required this.reveals,
    this.earlier = const <SleepNight>[],
    this.onDetails,
    super.key,
  });

  /// Which trend this card draws.
  final SleepTrend trend;

  /// The fortnight, newest first.
  final List<SleepNight> recent;

  /// The fortnight before it, newest first.
  final List<SleepNight> earlier;

  /// Where "already revealed" is remembered.
  final RevealRegistry reveals;

  /// Opens this metric's own history.
  final void Function(String metric)? onDetails;

  /// Oldest first, with an unmeasured night kept as a gap.
  List<double?> get series => <double?>[
    for (final night in recent.reversed) trend.read(night).valueOrNull,
  ];

  /// One short date per night, oldest first.
  List<String> get dates => <String>[
    for (final night in recent.reversed) shortDate(night.date),
  ];

  /// How many of those nights carry a reading.
  int get measured => series.where((value) => value != null).length;

  /// The line under the chart: how much data is behind it.
  String get note => measured == 0
      ? 'No night in the last fortnight carries this reading.'
      : '$measured ${measured == 1 ? 'night' : 'nights'} measured'
            '${dates.isEmpty ? '' : ' through ${dates.last}'}.';

  @override
  Widget build(BuildContext context) {
    final latest = recent.isEmpty
        ? Withheld<double>(SleepGap.noSession.disclosure)
        : trend.read(recent.first);
    return TrendCard(
      title: trend.title,
      tone: trend.tone,
      icon: SolarIconsOutline.chart_2,
      unit: trend.unit,
      values: series,
      earlier: <double>[
        for (final night in earlier)
          if (trend.read(night).valueOrNull case final double value) value,
      ],
      digits: trend.digits,
      higherIsBetter: trend.higherIsBetter,
      ceiling: trend.ceiling,
      captions: dates.isEmpty
          ? const <String>[]
          : <String>[dates.first, dates.last],
      infoKey: trend.infoKey,
      revealId: 'sleep.trend.${trend.metric}',
      reveals: reveals,
      onDetails: onDetails == null ? null : () => onDetails!(trend.metric),
      notes: <String>[
        note,
        if (latest case Withheld<double>(:final disclosure))
          'Latest reading: ${disclosure.message}',
      ],
    );
  }
}
