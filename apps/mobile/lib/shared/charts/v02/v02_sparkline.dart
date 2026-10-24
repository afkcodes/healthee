/// The compact variant: the same series, in a tile or a row, with no chrome.
///
/// ## The same painter, one value different
///
/// `HSpark`'s docstring argues it is not `HArea` with the fill turned off, and
/// on those two it was right — they disagreed about their geometry, so merging
/// them would have changed one chart's shape in silence.
///
/// v02 moved that disagreement into [ChartMetrics]. This is
/// `ChartMetrics.bare` — no gutter, no captions, no bubble band, so the plot is
/// the whole box — and the workhorse is `ChartMetrics.series`. Everything else
/// is shared, which means the curve that cannot overshoot and the fill that
/// fades rather than wipes reach a 26 px strip in a tile as well as a 168 px
/// chart on a screen.
///
/// ## What it keeps and what it drops
///
/// It keeps the **last-point dot**: in a strip with no axis, that dot is the
/// only thing saying which end is today. The fill is opt-in: the colour
/// kit keeps gradients for rings and goal-met bars, so the strip is flat unless
/// a caller asks for the body.
///
/// It drops the axis, the captions and the scrubber. A number this small is a
/// *shape*, and a shape does not need a scale printed beside it — the tile's own
/// figure is the value.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/shared/charts/v02/chart_box.dart';
import 'package:healthee/shared/charts/v02/chart_curve.dart';
import 'package:healthee/shared/charts/v02/chart_ink.dart';
import 'package:healthee/shared/charts/v02/chart_ticks.dart';
import 'package:healthee/shared/charts/v02/chart_void.dart';
import 'package:healthee/shared/charts/v02/series_painter.dart';
import 'package:healthee/shared/usual_range.dart';
import 'package:healthee/shared/v02/reading_state.dart';

/// A tiny line over [values], with a body under it and a dot on the newest
/// sample.
class V02Sparkline extends StatelessWidget {
  /// [values] is oldest first; a `null` breaks the line.
  const V02Sparkline(
    this.values, {
    required this.progress,
    this.height = 26,
    this.curve = SeriesCurve.monotone,
    this.strokeWidth = 2,
    this.fill = false,
    this.usual,
    this.state,
    super.key,
  });

  /// The series, oldest first. Fewer than two measured samples draws nothing.
  final List<double?> values;

  /// 0–1 from `RevealOnce`.
  final double progress;

  /// How tall the strip is. Held whether or not anything is drawn.
  final double height;

  /// How the samples are joined. See `chart_curve.dart`.
  final SeriesCurve curve;

  /// Line weight.
  final double strokeWidth;

  /// Whether to lay a body under the line. Flat by default: gradients belong
  /// to rings and goal-met bars (colour kit rule 6).
  final bool fill;

  /// The owner's usual range, drawn as the `band` token behind the line.
  final UsualRange? usual;

  /// The newest reading's state. Tints ONLY the newest dot; null keeps the
  /// domain colour.
  final ReadingState? state;

  @override
  Widget build(BuildContext context) {
    if (!canDrawSeries(values)) {
      return ChartVoid(height: height);
    }
    final band = usual;
    final colors = context.colors;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: SeriesPainter(
          values: values,
          ticks: ChartTicks.nice(
            values.whereType<double>(),
            include: <double>[
              if (band != null) ...<double>[band.low, band.high],
            ],
          ),
          metrics: ChartMetrics.bare,
          ink: ChartInk.of(context),
          progress: progress,
          curve: curve,
          strokeWidth: strokeWidth,
          fill: fill,
          captions: const <String>[],
          references: const [],
          labelled: false,
          touch: null,
          bubbleText: null,
          lastPointDot: true,
          usual: band,
          bandColor: band == null ? null : colors.band,
          dotColor: state?.dotIn(colors),
        ),
      ),
    );
  }
}
