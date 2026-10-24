/// The three pieces of geometry the hero instruments needed, and nothing more.
///
/// **This is deliberately not an axis foundation.** The series charts (line,
/// area, bars, buckets, the linked dual axis) share one scale, one axis and one
/// scrubber, and a sibling owns it. The two instruments that use this file each
/// draw a rail with its own rules — the age waterfall's value ladder, and the
/// VO₂max rail's 30-55 scale with a reference line — so they take the
/// value-to-x map, a dashed segment and an anchored label, and draw the rest
/// themselves. If a third instrument ever wants a tick strategy, that is the
/// moment this stops being three functions and starts being someone else's
/// foundation.
library;

import 'package:flutter/material.dart';

/// Maps [value] onto the rail between [left] and [right].
///
/// Unclamped on purpose: a caller that would place a mark outside its own scale
/// has to decide what that means, and the decision is always the same one —
/// draw nothing. See [onScale].
double railX(
  double value, {
  required double low,
  required double high,
  required double left,
  required double right,
}) => left + (value - low) / (high - low) * (right - left);

/// Whether [value] can honestly be drawn on a rail spanning [low] to [high].
///
/// A value outside the scale has no position on it. Clamping one to the edge
/// paints a measurement at a number it does not hold, which is why every caller
/// asks this first and draws nothing when the answer is false.
bool onScale(double value, {required double low, required double high}) =>
    value >= low && value <= high;

/// A dashed segment, drawn as `drawLine` calls.
///
/// The call is `drawLine` rather than a dashed `Path` for a reason the tests
/// depend on: `_chart_probe.dart`'s `markRectsOf` counts paths, rects and
/// circles as **data marks** and deliberately excludes lines. A dashed rule is
/// structure, not data, so drawing it as lines keeps "is there a mark in this
/// column?" a question with one answer.
void drawDashed(
  Canvas canvas,
  Offset from,
  Offset to,
  Paint paint, {
  double dash = 3,
  double gap = 4,
}) {
  final span = to - from;
  final length = span.distance;
  if (length <= 0) {
    return;
  }
  final step = span / length;
  for (var start = 0.0; start < length; start += dash + gap) {
    final end = start + dash < length ? start + dash : length;
    canvas.drawLine(from + step * start, from + step * end, paint);
  }
}

/// Where a label sits relative to the point it labels.
enum LabelAnchor {
  /// The label starts at the point.
  start,

  /// The label is centred on it.
  middle,

  /// The label ends at it.
  end,
}

/// Paints [label] with its baseline-ish top at [at], anchored horizontally.
void paintLabel(
  Canvas canvas,
  TextPainter label,
  Offset at, {
  LabelAnchor anchor = LabelAnchor.start,
}) {
  final dx = switch (anchor) {
    LabelAnchor.start => at.dx,
    LabelAnchor.middle => at.dx - label.width / 2,
    LabelAnchor.end => at.dx - label.width,
  };
  label.paint(canvas, Offset(dx, at.dy));
}

/// A year figure the way the prototype writes it: `36`, `34.3`, `-1.7`.
String formatYears(double value, {bool signed = false}) {
  final rounded = (value * 10).roundToDouble() / 10;
  final text = rounded == rounded.roundToDouble() && !signed
      ? rounded.toStringAsFixed(0)
      : rounded.toStringAsFixed(1);
  return signed && rounded >= 0 ? '+$text' : text;
}
