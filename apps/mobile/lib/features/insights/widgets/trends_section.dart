/// Longer patterns: each tracked metric's recent window as one tile, and the
/// only place on this screen where a change is judged better or worse.
///
/// A tile is a figure (the window's mean), its shape (a domain-colour line over
/// the owner's usual band, with one state-coloured newest dot) and one chip for
/// how the window moved. `MetricTrend`, `verdictFor` and `metric_polarity.dart`
/// are the same objects as before the colour pass, and the colour rule they
/// encode is the same rule.
///
/// ## Why a trend may be coloured when a correlation may not
///
/// A trend is this owner's own series against its own past, and
/// `shared/format/metric_polarity.dart` holds the one table that says which way
/// each metric has to move for the owner to be better off. That is a claim the
/// product makes (better or worse than the owner's own normal). The sign of a
/// correlation says *moved together* or *moved opposite*, a direction and not a
/// verdict, so "What moved together" spends the together and opposite hues and
/// never the better and worse ones.
///
/// ## The colourless chips are the point of the coloured ones
///
/// Calories carry polarity `neutral` and their chip is the secondary ink on the
/// neutral well, and a metric the table has never heard of gets the same. A
/// screen that tinted everything would teach the owner that colour here is
/// decoration, and then the chips where it is a claim would say nothing.
///
/// ## What the window can and cannot say
///
/// The server sends 14 days per metric. The change is the newest third's mean
/// against the oldest third's within those days; it is not "against the prior
/// 14 days", which the payload does not carry, and the chip says "over 14d".
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/features/insights/widgets/metric_trend.dart';
import 'package:healthee/features/insights/widgets/pattern_tile.dart';
import 'package:healthee/shared/reveal_once.dart';

export 'package:healthee/features/insights/widgets/metric_trend.dart';

/// The tiles, two across and three down, with the legend under them.
class TrendsGrid extends StatelessWidget {
  /// [trends] may be empty, in which case nothing renders at all. A heading over
  /// no tiles reads as breakage; the honest state is silence, and
  /// `insights_sections.dart` drops the heading with it.
  const TrendsGrid({
    required this.trends,
    required this.reveals,
    this.onOpenMetric,
    super.key,
  });

  /// One entry per metric that had a window to show.
  final List<MetricTrend> trends;

  /// Where "this chart has already animated" is remembered. The screen's.
  final RevealRegistry reveals;

  /// Opens one metric's own history.
  final void Function(String metric)? onOpenMetric;

  @override
  Widget build(BuildContext context) {
    if (trends.isEmpty) {
      return const SizedBox.shrink();
    }
    final rows = <Widget>[];
    for (var i = 0; i < trends.length; i += 2) {
      final left = _tile(trends[i]);
      // An odd tail draws beside an empty half rather than stretched: a tile's
      // proportions are part of how it reads.
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(child: left),
              const SizedBox(width: Insets.cardGap),
              Expanded(
                child: i + 1 < trends.length
                    ? _tile(trends[i + 1])
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var i = 0; i < rows.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: Insets.cardGap),
          rows[i],
        ],
        const SizedBox(height: Insets.md),
        const PatternLegend(),
      ],
    );
  }

  Widget _tile(MetricTrend trend) => PatternTile(
    trend: trend,
    reveals: reveals,
    onOpen: onOpenMetric == null ? null : () => onOpenMetric!(trend.metric),
  );
}

/// `your usual range · outside, worse · better`: what the tiles' marks mean.
class PatternLegend extends StatelessWidget {
  /// The legend line.
  const PatternLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = TypeLadder.caption.copyWith(color: colors.ink2);
    Widget item(Widget mark, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        mark,
        const SizedBox(width: Insets.sm - 2),
        Text(text, style: style),
      ],
    );
    Widget dot(Color color) => SizedBox.square(
      dimension: 8,
      child: DecoratedBox(
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
    return Wrap(
      spacing: Insets.lg,
      runSpacing: Insets.xs,
      children: <Widget>[
        item(
          SizedBox(
            width: 20,
            height: 10,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.band,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          'your usual range',
        ),
        item(dot(colors.alert), 'outside, worse'),
        item(dot(colors.fav), 'better'),
      ],
    );
  }
}
