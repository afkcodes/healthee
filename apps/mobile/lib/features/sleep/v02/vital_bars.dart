/// `Your body overnight` as the approved redesign draws it: each vital on a
/// range bar against the owner's own usual (`proposal-sleep.js`, `#p-sleep`).
///
/// Per row: the vital's name and reading, a [RangeBar] whose band is the
/// middle half of the owner's last 14 nights (`sleep_usual.dart`), the verdict
/// in words and which way is better. The direction is the physiology's, said
/// plainly, and it decides only the verdict's colour:
///
///   * resting heart: lower is better, so above the band is the worse side;
///   * HRV and blood oxygen: higher is better;
///   * breathing and skin temperature: close to the owner's usual is better,
///     so either side outside the band is the worse side.
///
/// A vital with no reading draws its name and a dash, and the panel's note
/// carries the server's reason (`VitalsTable.refusals`).
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/sleep_type_scale.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/core/theme/type_scale_keys.dart';
import 'package:healthee/data/models/sleep_night.dart';
import 'package:healthee/features/sleep/v02/sleep_usual.dart';
import 'package:healthee/shared/instrument/h_tap.dart';
import 'package:healthee/shared/usual_range.dart';
import 'package:healthee/shared/v02/key_number_card.dart';
import 'package:healthee/shared/v02/range_bar.dart';
import 'package:healthee/shared/v02/vitals_table.dart';

/// Which way is better for a vital.
enum VitalDirection {
  /// Resting heart.
  lower('Lower is better.'),

  /// HRV, blood oxygen.
  higher('Higher is better.'),

  /// Breathing, skin temperature.
  usual('Close to your usual is better.');

  const VitalDirection(this.words);

  /// Said beside the verdict.
  final String words;
}

/// The direction for a vital, by its metric id. Unknown ids get `usual`.
VitalDirection directionOf(String metric) => switch (metric) {
  'rhr' => VitalDirection.lower,
  'hrv_sleep_avg' || 'spo2_avg' => VitalDirection.higher,
  _ => VitalDirection.usual,
};

/// The rows, each read against [nights] before [day].
class VitalBars extends StatelessWidget {
  /// [read] picks each vital's value off a night, by metric id.
  const VitalBars({
    required this.vitals,
    required this.nights,
    required this.day,
    required this.read,
    this.onOpenMetric,
    super.key,
  });

  /// Between two rows.
  static const double rowPad = 14;

  final List<Vital> vitals;
  final List<SleepNight> nights;
  final String day;
  final double? Function(SleepNight night, String metric) read;
  final void Function(String metric)? onOpenMetric;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var i = 0; i < vitals.length; i++)
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: colors.line, width: hairline),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: rowPad),
              child: _row(vitals[i]),
            ),
          ),
      ],
    );
  }

  Widget _row(Vital vital) => ToneScope(
    tone: vital.tone,
    child: Builder(
      builder: (context) {
        final colors = context.colors;
        final value = vital.reading.valueOrNull;
        final band = usualOfNights(nights, day, (n) => read(n, vital.metric));
        final direction = directionOf(vital.metric);
        final reading = value == null
            ? '—'
            : value.toStringAsFixed(vital.digits);
        return HTap(
          onTap: onOpenMetric == null
              ? null
              : () => onOpenMetric!(vital.metric),
          semanticLabel: '${vital.label} $reading ${vital.unit}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(vital.icon, size: 16, color: colors.ink2),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      vital.label,
                      style: SleepType.checkName.copyWith(color: colors.ink),
                    ),
                  ),
                  Text.rich(
                    TextSpan(
                      children: <InlineSpan>[
                        TextSpan(
                          text: reading,
                          style: SleepType.checkValue.copyWith(
                            color: value == null ? colors.ink2 : colors.ink,
                          ),
                        ),
                        TextSpan(
                          text: '\u00A0${vital.unit}',
                          style: SleepType.vitalUnit.copyWith(
                            color: colors.ink2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (value != null) ...<Widget>[
                const SizedBox(height: 10),
                _bar(vital, value, band),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    if (band?.sideOf(value) case final UsualSide side)
                      VerdictChip(Verdict(side.words, _tone(side, direction))),
                    Text(
                      direction.words,
                      style: KeyType.line.copyWith(color: colors.ink2),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    ),
  );

  static Widget _bar(Vital vital, double value, UsualRange? band) {
    final low = band?.low ?? value;
    final high = band?.high ?? value;
    final span = (high - low).abs() < 1 ? 2.0 : high - low;
    var min = (([low, value].reduce((a, b) => a < b ? a : b)) - span)
        .floorToDouble();
    var max = (([high, value].reduce((a, b) => a > b ? a : b)) + span)
        .ceilToDouble();
    if (vital.metric == 'spo2_avg' && max > 100) {
      max = 100;
      min = min > 90 ? 90 : min;
    }
    String say(double v) => v.toStringAsFixed(vital.digits);
    return RangeBar(
      value: value,
      min: min,
      max: max,
      band: band,
      startLabel: say(min),
      endLabel: say(max),
      usualLabel: band == null
          ? null
          : say(band.low) == say(band.high)
          ? 'usual about ${say(band.low)}'
          : 'usual ${say(band.low)} to ${say(band.high)}',
      pendingLabel: 'learning your usual',
      semanticLabel: band == null
          ? '${vital.label} ${say(value)}. Your usual is still being learned.'
          : '${vital.label} ${say(value)}. Your usual is ${say(band.low)} '
                'to ${say(band.high)}.',
    );
  }

  static VerdictTone _tone(UsualSide side, VitalDirection direction) =>
      switch ((side, direction)) {
        (UsualSide.within, _) => VerdictTone.neutral,
        (UsualSide.below, VitalDirection.higher) ||
        (UsualSide.above, VitalDirection.lower) ||
        (_, VitalDirection.usual) => VerdictTone.worse,
        _ => VerdictTone.better,
      };
}
