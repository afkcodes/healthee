/// The painter behind the bar chart and the intraday buckets.
///
/// Both are the same picture at two densities — a value per slot, standing on a
/// baseline — and the density is a number ([barFraction]), not a second painter.
///
/// ## A goal decides weight when there is one
///
/// With a target, a bar below it is drawn at 32% and a bar at or above it at
/// full weight (with the dark-theme glow: goal-met bars are the only bars that
/// glow). Without one, emphasis picks the bar read, and nothing glows.
///
/// ## Weight carries emphasis; hue never does
///
/// The prototype gives the current bar its own class and a different fill
/// (`--chart-strong` against `--chart-light`). In v02 those are the same family
/// at two alphas, and that is a rule rather than a shortcut: a past day is the
/// same metric as today, so it is the same colour, quieter. A different hue
/// would say it is a different kind of thing — and the three hues that *do* say
/// something (`fav`, `unf`, `alert`) are rationed to judgement, which "this is
/// the bar you are reading" is not.
///
/// ## A measured zero is not an unmeasured day
///
/// A `null` slot draws nothing at all. A slot measured as **zero** draws a
/// [_floorMark] — two pixels standing on the baseline. Without it the two
/// states are the same picture, and "you took no steps" would be indis-
/// tinguishable from "the strap was not worn", which is the exact confusion this
/// app exists not to create.
///
/// ## Labels that do not fit are dropped, not shrunk
///
/// Fourteen day labels under a fortnight of bars will not fit at 10 px, and 6 px
/// type is not a smaller label — it is an unreadable one. So the painter
/// measures, computes a stride, and labels every nth slot, anchored so that the
/// **last** slot is always among them: the current day is the one a reader looks
/// for. Each surviving label is centred in a slot it fits inside, which is what
/// makes "no glyph overlaps another glyph" true by construction rather than by
/// inspection.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:healthee/shared/charts/chart_primitives.dart';
import 'package:healthee/shared/charts/chart_reference.dart';
import 'package:healthee/shared/charts/v02/chart_box.dart';
import 'package:healthee/shared/charts/v02/chart_frame.dart';
import 'package:healthee/shared/charts/v02/chart_ink.dart';
import 'package:healthee/shared/charts/v02/chart_ticks.dart';

/// Draws a column series, its frame, its target line and its captions.
class ColumnPainter extends CustomPainter {
  /// Everything is resolved before construction; the painter asks for nothing.
  const ColumnPainter({
    required this.values,
    required this.ticks,
    required this.metrics,
    required this.ink,
    required this.progress,
    required this.labels,
    required this.captions,
    required this.target,
    required this.emphasis,
    required this.barFraction,
    required this.maxBarWidth,
  });

  /// One value per slot, oldest first. A `null` was not measured.
  final List<double?> values;

  /// The axis. Pinned to zero for anything counted.
  final ChartTicks ticks;

  /// The chrome spec.
  final ChartMetrics metrics;

  /// The resolved tone.
  final ChartInk ink;

  /// 0–1 from `RevealOnce`. Bars grow out of the baseline.
  final double progress;

  /// One caption per slot, or empty for none.
  final List<String> labels;

  /// The two edge captions, used when [labels] is empty.
  final List<String> captions;

  /// The line the columns are read against, or null.
  final ChartReference? target;

  /// Which slot is being read — drawn at full weight. Null emphasises none.
  final int? emphasis;

  /// How much of its slot a bar fills. 0.58 is the prototype's.
  final double barFraction;

  /// A ceiling, so seven bars in a wide card do not become seven slabs.
  final double maxBarWidth;

  /// The height of a measured zero. See the library docstring.
  static const double _floorMark = 2;

  /// The weight of a bar below its goal.
  static const double belowGoalAlpha = 0.32;

  @override
  void paint(Canvas canvas, Size size) {
    final box = metrics.box(size);
    if (!box.isDrawable || values.isEmpty) {
      return;
    }
    paintChartFrame(canvas, box, ticks, ink: ink, progress: progress);
    final line = target;
    if (line != null) {
      paintPlotReference(
        canvas,
        box,
        line,
        ticks: ticks,
        ink: ink,
        progress: progress,
      );
    }
    final slot = box.plot.width / values.length;
    final width = math.min(slot * barFraction, maxBarWidth);
    final baseline = ticks.y(math.max(ticks.low, 0), box.plot);
    final radius = Radius.circular(math.min(5, width / 2));
    for (var i = 0; i < values.length; i++) {
      _paintColumn(canvas, box, i, slot, width, baseline, radius);
    }
    _paintCaptions(canvas, box, slot);
  }

  void _paintColumn(
    Canvas canvas,
    ChartBox box,
    int index,
    double slot,
    double width,
    double baseline,
    Radius radius,
  ) {
    final value = values[index];
    if (value == null || !value.isFinite) {
      return;
    }
    final centre = box.plot.left + slot * (index + 0.5);
    final full = baseline - ticks.y(value, box.plot);
    final height = math.max(full.abs() * progress.clamp(0.0, 1.0), _floorMark);
    final rect = RRect.fromRectAndCorners(
      Rect.fromLTWH(centre - width / 2, baseline - height, width, height),
      topLeft: radius,
      topRight: radius,
    );
    // With a target, the goal decides: a bar below it is dimmed to 32% and a
    // bar at or above it is full domain colour with the glow. Without one, the
    // bar being read is full and the rest are quiet, and nothing glows.
    final goal = target?.value;
    final met = goal != null && value >= goal;
    final alpha = goal != null
        ? (met ? 1.0 : belowGoalAlpha)
        : (index == emphasis ? 1.0 : 0.42);
    if (met && ink.isDark) {
      // The glow is dark-only for the reason `chart_ink.dart` gives: on a light
      // ground the identical paint reads as a smudge under the bar.
      canvas.drawRRect(
        rect,
        Paint()
          ..color = ink.family.withValues(alpha: 0.35 * progress)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
    canvas.drawRRect(rect, ink.bar(alpha));
  }

  void _paintCaptions(Canvas canvas, ChartBox box, double slot) {
    if (labels.isEmpty) {
      paintEdgeCaptions(canvas, box, captions, ink: ink, progress: progress);
      return;
    }
    final stride = _labelStride(slot);
    for (var i = 0; i < values.length && i < labels.length; i++) {
      if ((values.length - 1 - i) % stride != 0) {
        continue;
      }
      paintColumnCaption(
        canvas,
        box,
        labels[i],
        x: box.plot.left + slot * (i + 0.5),
        slot: slot * stride,
        ink: ink,
        progress: progress,
      );
    }
  }

  /// Label every nth slot, where n is the smallest stride that fits.
  int _labelStride(double slot) {
    var widest = 0.0;
    for (final label in labels) {
      widest = math.max(widest, chartLabel(label, ink.labelStyle).width);
    }
    var stride = 1;
    while (stride < 6 && widest > slot * stride - 4) {
      stride++;
    }
    return stride;
  }

  @override
  bool shouldRepaint(ColumnPainter old) =>
      old.progress != progress ||
      old.values != values ||
      old.emphasis != emphasis ||
      old.ink.family != ink.family ||
      old.ticks.high != ticks.high ||
      old.target != target;
}
