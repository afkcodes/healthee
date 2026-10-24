/// The one painter behind the line chart and the sparkline — and the one
/// function behind those and the linked chart's panes.
///
/// ## Why they are the same painter and `HArea`/`HSpark` were not
///
/// `h_spark.dart` argues at length that it is not `HArea` with the fill turned
/// off, and it was right: those two disagreed about their **geometry** — one
/// padded its y-range by 18% and inset x by 4, the other used the full box — so
/// merging them would have meant one of the two silently changing shape.
///
/// v02 moved that disagreement into a value: [ChartMetrics]. The sparkline is
/// `ChartMetrics.bare` and the workhorse is `ChartMetrics.series`. Same curve,
/// same fill, same reveal — one difference, named and typed. That is a
/// parameterisation rather than a coincidence, and it means a fix to the curve
/// reaches the 26 px strip in a tile as well as the 168 px chart on a screen.
///
/// [paintSeriesInto] is the same argument one level down: the linked chart draws
/// two series into two lanes of one canvas and cannot be two `CustomPainter`s,
/// so the body-and-trace is a function taking a [ChartBox] rather than a method
/// taking a `Size`.
///
/// ## The reveal is two different animations on purpose
///
/// The **trace** wipes: the canvas is clipped to `progress` of the plot's width
/// and the stroke draws on left to right, which is time passing.
///
/// The **body** fades: its alpha scales with `progress`. A wiped fill has a hard
/// vertical edge, and a hard edge at 60% reads as *the series ends here* — which
/// is a claim about the data made by the animation.
///
/// The last-point dot is drawn **inside the clip**, so it arrives exactly when
/// the trace reaches it rather than pulsing at the far end of an empty plot.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:healthee/shared/charts/chart_reference.dart';
import 'package:healthee/shared/charts/v02/chart_box.dart';
import 'package:healthee/shared/charts/v02/chart_curve.dart';
import 'package:healthee/shared/charts/v02/chart_frame.dart';
import 'package:healthee/shared/charts/v02/chart_ink.dart';
import 'package:healthee/shared/charts/v02/chart_ticks.dart';
import 'package:healthee/shared/usual_range.dart';

/// Draws the body and the trace of [values] inside [box].
///
/// Draws no frame, no captions and no cursor — the caller owns those, because
/// the linked chart's lanes share a cursor and a caption strip that no single
/// series knows about.
void paintSeriesInto(
  Canvas canvas,
  ChartBox box, {
  required List<double?> values,
  required ChartTicks ticks,
  required ChartInk ink,
  required double progress,
  required SeriesCurve curve,
  required double strokeWidth,
  required bool fill,
  required bool lastPointDot,
  Color? dotColor,
}) {
  final runs = seriesRuns(values);
  if (runs.isEmpty) {
    return;
  }
  final paths = <List<Offset>>[
    for (final run in runs)
      <Offset>[
        for (var i = run.first; i <= run.last; i++)
          Offset(box.x(i, values.length), ticks.y(values[i]!, box.plot)),
      ],
  ];
  if (fill) {
    final shader = ink.area(box.plot, progress);
    for (final points in paths) {
      if (points.length < 2) {
        continue;
      }
      final body = Path.from(curvePath(points, curve))
        ..lineTo(points.last.dx, box.plot.bottom)
        ..lineTo(points.first.dx, box.plot.bottom)
        ..close();
      canvas.drawPath(body, Paint()..shader = shader);
    }
  }
  // The wipe front has to clear whatever is drawn AT it. With a last-point dot
  // that is the dot's own reach, not the stroke's — see `kLastPointDotOuter`.
  final front = lastPointDot
      ? math.max(strokeWidth, kLastPointDotOuter)
      : strokeWidth;
  canvas
    ..save()
    ..clipRect(
      Rect.fromLTRB(
        0,
        box.plot.top - strokeWidth * 2,
        box.plot.left + box.plot.width * progress.clamp(0.0, 1.0) + front,
        box.plot.bottom + strokeWidth * 2,
      ),
    );
  final glow = ink.glow(strokeWidth);
  final stroke = ink.stroke(strokeWidth);
  for (final points in paths) {
    if (points.length == 1) {
      // A lone measurement between two holes. A dot is what it is; a segment
      // would be a claim about the hours either side of it.
      canvas.drawCircle(
        points.first,
        strokeWidth * 0.9,
        Paint()..color = ink.family,
      );
      continue;
    }
    final path = curvePath(points, curve);
    if (glow != null) {
      canvas.drawPath(path, glow);
    }
    canvas.drawPath(path, stroke);
  }
  if (lastPointDot && paths.last.isNotEmpty) {
    paintLastPointDot(
      canvas,
      paths.last.last,
      ink: ink,
      progress: progress,
      color: dotColor,
    );
  }
  canvas.restore();
}

/// Draws a line/area series, its frame, and the cursor over it.
class SeriesPainter extends CustomPainter {
  /// Everything is resolved before construction; the painter asks for nothing.
  const SeriesPainter({
    required this.values,
    required this.ticks,
    required this.metrics,
    required this.ink,
    required this.progress,
    required this.curve,
    required this.strokeWidth,
    required this.fill,
    required this.captions,
    required this.references,
    required this.labelled,
    required this.touch,
    required this.bubbleText,
    required this.lastPointDot,
    this.usual,
    this.bandColor,
    this.dotColor,
  });

  /// The series, oldest first. A `null` is a hole and breaks the line.
  final List<double?> values;

  /// The axis every y comes from.
  final ChartTicks ticks;

  /// The chrome spec. Determines the plot rect, and the touch mapping with it.
  final ChartMetrics metrics;

  /// The resolved tone. See `chart_ink.dart`.
  final ChartInk ink;

  /// 0–1 from `RevealOnce`.
  final double progress;

  /// Monotone for a continuous signal, straight for totals and extrema.
  final SeriesCurve curve;

  /// Trace weight.
  final double strokeWidth;

  /// Whether to lay a gradient body under the trace.
  final bool fill;

  /// The first and last edge captions, or empty for none.
  final List<String> captions;

  /// The lines this series is read against.
  final List<ChartReference> references;

  /// Whether to write the tick values in the gutter.
  final bool labelled;

  /// The sample under the finger, or null.
  final int? touch;

  /// What the bubble says about [touch]. Null draws no bubble.
  final String? bubbleText;

  /// Whether to ring the newest sample.
  final bool lastPointDot;

  /// The owner's usual range, drawn flat behind the trace, or null.
  final UsualRange? usual;

  /// The `band` token the [usual] range is drawn in. Null draws no band.
  final Color? bandColor;

  /// The newest dot's colour — a state colour. Null keeps the domain colour.
  final Color? dotColor;

  @override
  void paint(Canvas canvas, Size size) {
    final box = metrics.box(size);
    if (!box.isDrawable || values.isEmpty) {
      return;
    }
    paintChartFrame(
      canvas,
      box,
      ticks,
      ink: ink,
      progress: progress,
      labelled: labelled,
    );
    for (final reference in references) {
      paintPlotReference(
        canvas,
        box,
        reference,
        ticks: ticks,
        ink: ink,
        progress: progress,
      );
    }
    _paintBand(canvas, box);
    paintSeriesInto(
      canvas,
      box,
      values: values,
      ticks: ticks,
      ink: ink,
      progress: progress,
      curve: curve,
      strokeWidth: strokeWidth,
      fill: fill,
      lastPointDot: lastPointDot,
      dotColor: dotColor,
    );
    paintEdgeCaptions(canvas, box, captions, ink: ink, progress: progress);
    _paintCursor(canvas, box);
  }

  void _paintBand(Canvas canvas, ChartBox box) {
    final range = usual;
    final colour = bandColor;
    if (range == null || colour == null) {
      return;
    }
    final top = ticks
        .y(range.high, box.plot)
        .clamp(box.plot.top, box.plot.bottom);
    final bottom = ticks
        .y(range.low, box.plot)
        .clamp(box.plot.top, box.plot.bottom);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(box.plot.left, top, box.plot.right, bottom),
        const Radius.circular(3),
      ),
      Paint()..color = colour,
    );
  }

  void _paintCursor(Canvas canvas, ChartBox box) {
    final index = touch;
    if (index == null || index < 0 || index >= values.length) {
      return;
    }
    final x = box.x(index, values.length);
    paintScrubCursor(
      canvas,
      x,
      top: box.plot.top,
      bottom: box.plot.bottom,
      ink: ink,
    );
    final value = values[index];
    if (value != null && value.isFinite) {
      paintLastPointDot(
        canvas,
        Offset(x, ticks.y(value, box.plot)),
        ink: ink,
        progress: 1,
        radius: 4,
      );
    }
    final text = bubbleText;
    if (text != null) {
      paintScrubBubble(canvas, box, text, anchorX: x, ink: ink);
    }
  }

  @override
  bool shouldRepaint(SeriesPainter old) =>
      old.progress != progress ||
      old.values != values ||
      old.touch != touch ||
      old.bubbleText != bubbleText ||
      old.ink.family != ink.family ||
      old.ticks.low != ticks.low ||
      old.ticks.high != ticks.high ||
      old.references != references ||
      old.usual != usual ||
      old.bandColor != bandColor ||
      old.dotColor != dotColor;
}
