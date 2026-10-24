/// Effort and stress: three readings and one linked chart in a surface card.
///
/// Heart rate is a Heart-coloured line, the resting heart rate a dashed
/// reference in the same colour, and stress Mind-coloured columns under it, on
/// ONE shared hour axis. The chart is `V02LinkedChart`; this file only decides
/// what goes into its two panes and what is written around them, so the one
/// chart implementation draws Today's version of the same signals too.
///
/// A coinciding change in the two is context, not proof: the chart carries that
/// sentence itself and this card adds no interpretation of its own.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/data/models/today_series.dart';
import 'package:healthee/features/insights/v02/effort_stress_stats.dart';
import 'package:healthee/shared/charts/v02/v02_linked_chart.dart';
import 'package:healthee/shared/format/time_labels.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:healthee/shared/v02/surface_panels.dart';

/// The card.
class EffortStressCard extends StatelessWidget {
  /// [heartRate] and [stress] are the payload's hourly series; [restingHr] the
  /// owner's resting heart rate, or null for no reference line.
  const EffortStressCard({
    required this.heartRate,
    required this.stress,
    required this.reveals,
    this.restingHr,
    super.key,
  });

  /// Whether either signal has enough to draw.
  ///
  /// **Both or neither.** A linked chart with one live pane is a different chart
  /// under a title promising a comparison the reader cannot make, and two hours
  /// is not a day.
  static bool hasSomethingToDraw(
    List<HourPoint> heartRate,
    List<HourPoint> stress,
  ) => heartRate.length > 2 && stress.length > 2;

  /// Today's heart rate, hour by hour.
  final List<HourPoint> heartRate;

  /// Today's stress, hour by hour.
  final List<HourPoint> stress;

  /// Where "already revealed" is remembered.
  final RevealRegistry reveals;

  /// The resting heart rate the dashed reference is drawn at.
  final double? restingHr;

  @override
  Widget build(BuildContext context) {
    final hours = heartRate.length < stress.length
        ? heartRate.length
        : stress.length;
    final stats = EffortStressStats(heartRate, stress);
    final resting = restingHr;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _Readings(stats: stats),
          const SizedBox(height: Insets.lg),
          RevealOnce(
            id: 'insights.effort-stress',
            registry: reveals,
            builder: (context, t) => V02LinkedChart(
              <LinkedPane>[
                LinkedPane(
                  tone: Tone.heart,
                  label: 'Heart rate',
                  unit: 'bpm',
                  reference: resting == null
                      ? null
                      : LaneReference(
                          value: resting,
                          label: 'resting ${resting.round()}',
                        ),
                  values: <double?>[
                    for (var i = 0; i < hours; i++) heartRate[i].average,
                  ],
                ),
                LinkedPane(
                  tone: Tone.stress,
                  label: 'Stress',
                  bars: true,
                  values: <double?>[
                    for (var i = 0; i < hours; i++) stress[i].average,
                  ],
                ),
              ],
              progress: t,
              // `shortClock`, as Today draws the same chart: one chart labelled
              // two ways on two screens is the drift `shared/format/` stops.
              captions: hours < 2
                  ? const <String>[]
                  : <String>[
                      shortClock(heartRate.first.hour),
                      shortClock(heartRate[hours - 1].hour),
                    ],
              sampleLabels: <String>[
                for (var i = 0; i < hours; i++) shortClock(heartRate[i].hour),
              ],
              semanticLabel:
                  'Heart rate and stress through today, on a shared hour axis',
            ),
          ),
        ],
      ),
    );
  }
}

class _Readings extends StatelessWidget {
  const _Readings({required this.stats});

  final EffortStressStats stats;

  @override
  Widget build(BuildContext context) {
    String whole(double? v) => v == null ? '—' : v.round().toString();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          flex: 5,
          child: _Reading(
            label: 'Heart rate',
            value: stats.heartRangeLabel ?? '—',
            unit: 'bpm',
          ),
        ),
        Expanded(
          flex: 4,
          child: _Reading(
            label: 'Peak-hour stress',
            value: whole(stats.peakStress),
            unit: '/100',
          ),
        ),
        Expanded(
          flex: 3,
          child: _Reading(
            label: 'Avg stress',
            value: whole(stats.averageStress),
            unit: '/100',
          ),
        ),
      ],
    );
  }
}

class _Reading extends StatelessWidget {
  const _Reading({required this.label, required this.value, this.unit});

  final String label;
  final String value;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label, style: TypeLadder.callout.copyWith(color: colors.ink2)),
        const SizedBox(height: Insets.xs),
        Text.rich(
          TextSpan(
            text: value,
            style: TypeLadder.title2.copyWith(color: colors.ink),
            children: <InlineSpan>[
              if (unit != null)
                TextSpan(
                  text: ' $unit',
                  style: TypeLadder.callout.copyWith(color: colors.ink2),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
