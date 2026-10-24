/// The chrome: rules, tick labels, edge captions, reference lines, and the
/// cursor. Everything a chart draws that is **not** the measurement.
///
/// The whole file obeys one invariant, which `chart_box.dart` makes geometric:
/// words go in [ChartBox.values], [ChartBox.captions] and [ChartBox.bubble];
/// lines go in [ChartBox.plot]. Nothing here writes inside the plot.
///
/// ## Restraint is the design
///
/// The prototype dashes its gridlines (`stroke-dasharray: 3 4`). Dashes at 10 px
/// spacing on a 1 px rule read as texture, and texture competes with the trace.
/// These are solid, one pixel, in the palette's own [ChartInk.grid] — which is
/// `line` at half alpha and is not re-derived here, because the three painters
/// that each derived their own shipped the grid at five times its intended
/// weight.
///
/// A reference line keeps the prototype's dash, and there it earns it: the dash
/// is the only thing distinguishing *the owner's own baseline* from *a borrowed
/// convention*, a distinction `chart_reference.dart` argues at length and which
/// must not be carried by hue, because hue is rationed to judgement.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:healthee/shared/charts/chart_primitives.dart';
import 'package:healthee/shared/charts/chart_reference.dart';
import 'package:healthee/shared/charts/v02/chart_box.dart';
import 'package:healthee/shared/charts/v02/chart_ink.dart';
import 'package:healthee/shared/charts/v02/chart_ticks.dart';

/// Air between the widget's right edge and the end of a tick label.
const double _gutterPad = 2;

/// Draws the rules and the numbers beside them.
///
/// [progress] fades the whole frame in with the series, so a chart never shows
/// an empty axis waiting for its data.
void paintChartFrame(
  Canvas canvas,
  ChartBox box,
  ChartTicks ticks, {
  required ChartInk ink,
  required double progress,
  bool labelled = true,
}) {
  final rule = ink.gridPaint(progress);
  for (final value in ticks.values) {
    final y = ticks.y(value, box.plot);
    canvas.drawLine(Offset(box.plot.left, y), Offset(box.plot.right, y), rule);
    if (labelled && box.values.width > 0) {
      _writeTickLabel(canvas, box, ticks.label(value), y, ink, progress);
    }
  }
}

/// One value written in the right-hand gutter, vertically centred on its rule.
void _writeTickLabel(
  Canvas canvas,
  ChartBox box,
  String text,
  double y,
  ChartInk ink,
  double progress,
) {
  final painter = chartLabel(
    text,
    ink.labelStyle.copyWith(color: revealed(ink.ink3, progress)),
  );
  // Clamped into the plot's own vertical band, not the widget's. Two reasons,
  // and the second one shipped as a bug in the bar chart's first draft:
  //
  //   * the top rule's label would otherwise be half outside the box;
  //   * the BOTTOM rule's label, centred, hangs into the caption strip — where
  //     it meets the last column's caption coming the other way, and the two
  //     words sit on top of each other in the corner.
  //
  // So the last value rides just above its own rule. It cannot reach the plot
  // horizontally whatever y it lands at, because the numbers are right-aligned
  // against the widget's edge and floored at the gutter's own left edge, which
  // is `padRight` clear of the plot.
  final top = (y - painter.height / 2).clamp(
    0.0,
    box.plot.bottom - painter.height,
  );
  final left = math.max(
    box.values.left,
    box.values.right - _gutterPad - painter.width,
  );
  painter.paint(canvas, Offset(left, top));
}

/// The two edge captions — the first at the plot's left, the last at its right.
///
/// Two, not one per sample: a 24-hour trace has 288 samples and an axis that
/// names every fourth hour is six labels of noise under a chart whose subject is
/// the shape. The scrubber names the sample you are actually asking about.
void paintEdgeCaptions(
  Canvas canvas,
  ChartBox box,
  List<String> captions, {
  required ChartInk ink,
  required double progress,
}) {
  if (captions.isEmpty || box.captions.height <= 0) {
    return;
  }
  final style = ink.labelStyle.copyWith(color: revealed(ink.ink3, progress));
  final top = box.captions.top + ChartMetrics.clearance + 1;
  final first = chartLabel(captions.first, style);
  first.paint(canvas, Offset(box.plot.left, top));
  if (captions.length > 1) {
    final last = chartLabel(captions.last, style);
    last.paint(canvas, Offset(box.plot.right - last.width, top));
  }
}

/// A label centred under [x], clipped away when it would touch its neighbour.
///
/// Returns the rect it occupied, or null when it was dropped. Bar charts use it
/// for day names, and dropping rather than shrinking is deliberate: 6 px type is
/// not a smaller label, it is an unreadable one.
Rect? paintColumnCaption(
  Canvas canvas,
  ChartBox box,
  String text, {
  required double x,
  required double slot,
  required ChartInk ink,
  required double progress,
}) {
  if (text.isEmpty || box.captions.height <= 0) {
    return null;
  }
  final painter = chartLabel(
    text,
    ink.labelStyle.copyWith(color: revealed(ink.ink3, progress)),
  );
  if (painter.width > slot) {
    return null;
  }
  final left = (x - painter.width / 2).clamp(
    0.0,
    box.captions.right - painter.width,
  );
  final top = box.captions.top + ChartMetrics.clearance + 1;
  painter.paint(canvas, Offset(left, top));
  return Rect.fromLTWH(left, top, painter.width, painter.height);
}

/// Draws [reference] across the plot in [ticks]' scale.
///
/// The v02 twin of `paintChartReference`, which draws against `ChartScale`'s
/// height-relative geometry rather than a plot rect. Same contract, same dash,
/// same rationing of colour — a line and nothing else, with the words living in
/// `ChartReferenceCaption` under the chart.
void paintPlotReference(
  Canvas canvas,
  ChartBox box,
  ChartReference reference, {
  required ChartTicks ticks,
  required ChartInk ink,
  required double progress,
}) {
  final y = ticks.y(reference.value, box.plot);
  if (!y.isFinite || y < box.plot.top - 0.5 || y > box.plot.bottom + 0.5) {
    return;
  }
  final paint = ink.referencePaint(progress);
  if (!reference.isDashed) {
    canvas.drawLine(Offset(box.plot.left, y), Offset(box.plot.right, y), paint);
    return;
  }
  for (var x = box.plot.left; x < box.plot.right; x += _dash + _dashGap) {
    final end = (x + _dash).clamp(box.plot.left, box.plot.right);
    canvas.drawLine(Offset(x, y), Offset(end, y), paint);
  }
}

/// The vertical line under the finger, spanning [top] to [bottom].
///
/// Takes explicit bounds so the linked chart can run one cursor through two
/// plots and the gap between them — which is the entire point of that chart.
void paintScrubCursor(
  Canvas canvas,
  double x, {
  required double top,
  required double bottom,
  required ChartInk ink,
}) => canvas.drawLine(
  Offset(x, top),
  Offset(x, bottom),
  Paint()
    ..color = ink.family.withValues(alpha: 0.55)
    ..strokeWidth = 1,
);

/// The value bubble, drawn in the band reserved for it above the plot.
///
/// It never covers the plot, which is the departure from the ported `HArea`:
/// that one floats its bubble at a negative y, outside its own box, so it
/// survives only as long as no ancestor clips and it sits over the neighbouring
/// content when nothing does.
void paintScrubBubble(
  Canvas canvas,
  ChartBox box,
  String text, {
  required double anchorX,
  required ChartInk ink,
}) {
  if (box.bubble.height <= 0) {
    return;
  }
  // Plain micro, like every chart label: the ladder sets it at 400 on its own
  // 14 px line, and the legacy bubbles (`h_area`, `h_debt_bars`) match.
  final painter = chartLabel(text, ink.labelStyle.copyWith(color: ink.surface));
  final width = painter.width + 14;
  final height = painter.height + 6;
  final left = (anchorX - width / 2).clamp(0.0, box.bubble.right - width);
  final top = box.bubble.bottom - height;
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, width, height),
      const Radius.circular(7),
    ),
    Paint()..color = ink.family,
  );
  painter.paint(canvas, Offset(left + 7, top + 3));
}

/// The dot on the newest sample, ringed in the surface so it reads on any fill.
/// How far the last-point dot reaches from its centre, halo included.
///
/// Stated once because two files need it: `chart_frame.dart` draws it, and
/// `series_painter.dart` has to leave the reveal wipe wide enough not to slice
/// it. It was sliced — the wipe's right edge was `plot.right + strokeWidth`, the
/// dot sits ON `plot.right`, and 3.3px of it went missing on every sparkline in
/// the app. The halo hid the damage: it is painted in the surface colour, so its
/// own cut edge is invisible against the card and only the coloured centre
/// looked wrong.
const double kLastPointDotOuter = 3.5 + 1.8;

void paintLastPointDot(
  Canvas canvas,
  Offset point, {
  required ChartInk ink,
  required double progress,
  double radius = 3.5,
  Color? color,
}) {
  final r = radius * progress.clamp(0.0, 1.0);
  if (r <= 0) {
    return;
  }
  canvas
    ..drawCircle(point, r + 1.8, Paint()..color = ink.surface)
    ..drawCircle(point, r, Paint()..color = color ?? ink.family);
}

const double _dash = 3;
const double _dashGap = 3;
