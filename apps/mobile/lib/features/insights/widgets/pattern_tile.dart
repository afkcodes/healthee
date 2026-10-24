/// One Longer-patterns tile: label, window mean, usual-band line and change chip.
///
/// The label and the line are the metric's domain colour and never a verdict.
/// Only two things on the tile take a state colour: the newest dot (the latest
/// reading against the owner's usual range, by `judge`) and the chip (the
/// window's change, by the metric's polarity). Inside the usual range the dot
/// is the primary ink, and a metric the polarity table cannot judge draws its
/// chip on the neutral well.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/instrument_hues.dart';
import 'package:healthee/core/theme/shapes.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/features/insights/widgets/metric_trend.dart';
import 'package:healthee/shared/charts/v02/signal_spark.dart';
import 'package:healthee/shared/format/metric_polarity.dart' show TrendVerdict;
import 'package:healthee/shared/format/number_labels.dart';
import 'package:healthee/shared/instrument/h_tap.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:healthee/shared/usual_range.dart';
import 'package:healthee/shared/v02/reading_chip.dart';
import 'package:healthee/shared/v02/reading_state.dart' as rs;

/// The spec that names and draws [metric], or null for one with no tile.
PatternSpec? patternSpecOf(String metric) {
  for (final spec in kPatternSpecs) {
    if (spec.metric == metric) {
      return spec;
    }
  }
  return null;
}

/// The owner's usual range over a window: the middle half of its days before
/// the newest, by the one definition in `usual_range.dart`.
UsualRange? usualOfTrend(MetricTrend trend) =>
    usualRangeOf(windowBefore(trend.series, trend.series.last.date));

/// The state of the newest dot: the latest reading judged against [usualOfTrend].
rs.ReadingState dotStateOf(MetricTrend trend) => rs
    .judge(
      value: trend.latest,
      usual: usualOfTrend(trend),
      polarity: rs.polarityOf(trend.metric),
    )
    .state;

/// The state of the change chip: better or worse where the polarity table has a
/// claim, and the neutral state everywhere else.
rs.ReadingState changeStateOf(MetricTrend trend) => switch (trend.verdict) {
  TrendVerdict.favourable => rs.ReadingState.better,
  TrendVerdict.unfavourable => rs.ReadingState.worse,
  TrendVerdict.none => rs.ReadingState.usual,
};

/// `↑ 0.5 over 14d`, or `No change over 14d` for a window that did not move.
String changeLabel(MetricTrend trend, int decimals) {
  final size = _figure(trend.delta.abs(), decimals);
  if (double.parse(size.replaceAll(',', '')) == 0) {
    return 'No change over ${trend.days}d';
  }
  return '${trend.delta > 0 ? '↑' : '↓'} $size over ${trend.days}d';
}

String _figure(double value, int decimals) =>
    decimals == 0 ? groupedInt(value.round()) : value.toStringAsFixed(decimals);

/// The tile.
class PatternTile extends StatelessWidget {
  /// Draws [trend], or nothing for a metric with no [PatternSpec].
  const PatternTile({
    required this.trend,
    required this.reveals,
    this.onOpen,
    super.key,
  });

  /// The strip's height.
  static const double sparkHeight = 32;

  /// The window being drawn.
  final MetricTrend trend;

  /// The screen's reveal registry.
  final RevealRegistry reveals;

  /// Opens the metric's own history. Null draws a tile that does not tap.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final spec = patternSpecOf(trend.metric);
    if (spec == null) {
      return const SizedBox.shrink();
    }
    final colors = context.colors;
    final family = spec.tone.family(context.hues);
    final usual = usualOfTrend(trend);
    final tile = Container(
      padding: const EdgeInsets.all(Insets.md),
      decoration: ShapeDecoration(
        color: colors.surface,
        shape: hSquircle(Radii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Expanded(
                child: Text(
                  spec.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TypeLadder.calloutStrong.copyWith(color: family),
                ),
              ),
              const SizedBox(width: Insets.xs),
              Text(
                '${trend.days}d avg',
                style: TypeLadder.caption.copyWith(color: colors.ink2),
              ),
            ],
          ),
          const SizedBox(height: Insets.sm),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(
              TextSpan(
                text: _figure(trend.mean, spec.decimals),
                style: TypeLadder.title1.copyWith(color: colors.ink),
                children: <InlineSpan>[
                  if (spec.unit != null)
                    TextSpan(
                      text: ' ${spec.unit}',
                      style: TypeLadder.callout.copyWith(color: colors.ink2),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Insets.sm),
          RevealOnce(
            id: 'insights.trend.${trend.metric}',
            registry: reveals,
            builder: (context, t) => ToneScope(
              tone: spec.tone,
              child: SignalSpark(
                values: <double?>[
                  for (final point in trend.series) point.value,
                ],
                state: dotStateOf(trend),
                usual: usual,
                height: sparkHeight,
                progress: t,
              ),
            ),
          ),
          const SizedBox(height: Insets.sm),
          ReadingChip(
            changeLabel(trend, spec.decimals),
            state: changeStateOf(trend),
          ),
        ],
      ),
    );
    return onOpen == null
        ? tile
        : HTap(onTap: onOpen, semanticLabel: spec.label, child: tile);
  }
}
