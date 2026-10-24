/// One trend card, the redesign's single grammar for a metric over a period
/// (`design/mobile-preview/proposal.js::trendCard`).
///
/// The period's average as the figure; its change against the period before,
/// in words and coloured by which way is better; every reading as a dot on the
/// owner's usual band ([TrendDots]); and one sentence counting how many sat
/// inside it.
///
/// The band is `usual_range.dart`'s middle half of the PERIOD BEFORE, so a
/// period is read against the one before it and never against itself. With
/// fewer than seven earlier readings there is no band and no change, and the
/// card says it is still learning.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/core/theme/type_scale_keys.dart';
import 'package:healthee/shared/charts/v02/trend_dots.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:healthee/shared/usual_range.dart';
import 'package:healthee/shared/v02/key_number_card.dart';
import 'package:healthee/shared/v02/panel.dart';
import 'package:healthee/shared/v02/panel_head.dart';
import 'package:healthee/shared/v02/panel_parts.dart';

/// What the band, the line and a hollow dot mean, said once per card.
const String kTrendLegend =
    'Shaded: the middle half of the period before. Dashed: this average. '
    'Hollow: a reading outside the shaded part.';

/// The card.
class TrendCard extends StatelessWidget {
  /// [values] is oldest first, null for an unmeasured slot; [earlier] is the
  /// period before, in any order.
  const TrendCard({
    required this.title,
    required this.tone,
    required this.icon,
    required this.unit,
    required this.values,
    required this.revealId,
    required this.reveals,
    this.earlier = const <double>[],
    this.digits = 0,
    this.higherIsBetter = true,
    this.ceiling,
    this.captions = const <String>[],
    this.readings = 'nights',
    this.before = 'the fortnight before',
    this.infoKey,
    this.onDetails,
    this.notes = const <String>[],
    super.key,
  });

  /// Between the figure and the chart, and around the sentence.
  static const double gap = 10;

  /// A change under one unit is said as none.
  static const double flat = 1;

  final String title;
  final Tone tone;
  final IconData icon;
  final String unit;
  final List<double?> values;
  final String revealId;
  final RevealRegistry reveals;
  final List<double> earlier;
  final int digits;

  /// Null: neither way is better, and a change is said without colour.
  final bool? higherIsBetter;
  final double? ceiling;

  /// The first and last date under the chart.
  final List<String> captions;

  /// What one reading is: `nights`, `days`, `weeks`.
  final String readings;

  /// What the change is against: `the fortnight before`, `the week before`.
  final String before;
  final String? infoKey;
  final VoidCallback? onDetails;

  /// Extra lines under the card, in order.
  final List<String> notes;

  int get measured => values.where((v) => v != null).length;

  UsualRange? get band => usualRangeOf(earlier);

  static double? _mean(Iterable<double> values) =>
      values.isEmpty ? null : values.reduce((a, b) => a + b) / values.length;

  String _say(double value) => value.toStringAsFixed(digits);

  Verdict? _change(double? mean) {
    final then = _mean(earlier);
    if (mean == null || then == null || earlier.length < kUsualMinDays) {
      return null;
    }
    final change = mean - then;
    if (change.abs() < flat) {
      return Verdict('No change vs $before', VerdictTone.neutral);
    }
    final better = higherIsBetter;
    return Verdict(
      '${change > 0 ? '↑' : '↓'} ${change.abs().round()} vs $before',
      better == null
          ? VerdictTone.neutral
          : (change > 0) == better
          ? VerdictTone.better
          : VerdictTone.worse,
    );
  }

  @override
  Widget build(BuildContext context) {
    final mean = _mean(<double>[for (final v in values) ?v]);
    final usual = band;
    final change = _change(mean);
    return Panel(
      tone: tone,
      label: title,
      head: PanelHead(
        title: title,
        icon: icon,
        infoKey: infoKey,
        actionLabel: onDetails == null ? null : 'Details',
        onAction: onDetails,
      ),
      child: Builder(
        builder: (context) {
          final colors = context.colors;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              PanelValue(
                mean == null ? '—' : _say(mean),
                unit: unit,
                context_: measured == 0
                    ? null
                    : 'average over $measured $readings',
              ),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  if (change case final Verdict said) VerdictChip(said),
                  Text(switch (higherIsBetter) {
                    true => 'Higher is better.',
                    false => 'Lower is better.',
                    null => 'Steadier is better.',
                  }, style: KeyType.line.copyWith(color: colors.ink2)),
                ],
              ),
              const SizedBox(height: gap),
              RevealOnce(
                id: revealId,
                registry: reveals,
                builder: (context, t) => TrendDots(
                  values: values,
                  progress: t,
                  band: usual,
                  average: mean,
                  digits: digits,
                  ceiling: ceiling,
                  captions: captions,
                  semanticLabel: '$title over the period',
                ),
              ),
              const SizedBox(height: gap),
              _sentence(colors, usual),
              if (usual != null) const PanelNote(kTrendLegend),
              for (final line in notes) PanelNote(line),
            ],
          );
        },
      ),
    );
  }

  Widget _sentence(HealtheeColors colors, UsualRange? usual) {
    final style = KeyType.line.copyWith(color: colors.ink2);
    if (usual == null) {
      return Text(
        'Your usual range needs $kUsualMinDays measured $readings before '
        'these. It is still being learned.',
        style: style,
      );
    }
    final inside = values
        .where((v) => v != null && usual.sideOf(v) == UsualSide.within)
        .length;
    return Text.rich(
      TextSpan(
        style: style,
        children: <InlineSpan>[
          TextSpan(
            text: '$inside of $measured $readings',
            style: TypeLadder.calloutStrong.copyWith(color: colors.ink),
          ),
          // A no-break space before the unit, so a wrap never strands `%.`.
          TextSpan(
            text:
                ' were inside your usual of ${_say(usual.low)} to '
                '${_say(usual.high)}\u00a0$unit.',
          ),
        ],
      ),
    );
  }
}
