/// The two marks a linked-chart lane can draw besides a line: columns, and a
/// dashed reference in the lane's own domain colour.
///
/// Both are opt-in per pane (`LinkedPane.bars`, `LinkedPane.reference`); a pane
/// that sets neither draws exactly what it always did.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:healthee/shared/charts/chart_primitives.dart';
import 'package:healthee/shared/charts/v02/chart_box.dart';
import 'package:healthee/shared/charts/v02/chart_ink.dart';
import 'package:healthee/shared/charts/v02/chart_ticks.dart';

/// A labelled value drawn as a dashed line across a lane: the resting heart
/// rate, for one.
@immutable
class LaneReference {
  /// [value] in the lane's own units, [label] the words beside the line.
  const LaneReference({required this.value, required this.label});

  /// Where the line sits on the lane's axis.
  final double value;

  /// `resting 57`.
  final String label;
}

/// Paints one column per sample, centred on the same x the line lanes use so
/// one cursor runs through both. The tallest column is full weight and the rest
/// are quiet, so the peak reads without a legend.
void paintLaneBars(
  Canvas canvas,
  ChartBox box, {
  required List<double?> values,
  required ChartTicks ticks,
  required ChartInk ink,
  required double progress,
}) {
  final measured = <double>[
    for (final value in values)
      if (value != null && value.isFinite) value,
  ];
  if (measured.isEmpty) {
    return;
  }
  final peak = measured.reduce(math.max);
  final slot = box.plot.width / math.max(1, values.length);
  final width = math.min(slot * 0.58, 14.0);
  final baseline = ticks.y(math.max(ticks.low, 0), box.plot);
  final t = progress.clamp(0.0, 1.0);
  for (var i = 0; i < values.length; i++) {
    final value = values[i];
    if (value == null || !value.isFinite) {
      continue;
    }
    final height = math.max((baseline - ticks.y(value, box.plot)) * t, 2.0);
    final centre = box.x(i, values.length);
    final left = (centre - width / 2).clamp(
      box.plot.left,
      box.plot.right - width,
    );
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(left, baseline - height, width, height),
        topLeft: Radius.circular(math.min(4, width / 2)),
        topRight: Radius.circular(math.min(4, width / 2)),
      ),
      ink.bar(value == peak ? 1 : 0.5),
    );
  }
}

/// Paints [reference] as a dashed line in the lane's family colour with its
/// label under the line at the plot's left edge. Off the axis draws nothing.
void paintLaneReference(
  Canvas canvas,
  ChartBox box,
  LaneReference reference, {
  required ChartTicks ticks,
  required ChartInk ink,
  required double progress,
}) {
  final y = ticks.y(reference.value, box.plot);
  if (!y.isFinite || y < box.plot.top - 0.5 || y > box.plot.bottom + 0.5) {
    return;
  }
  final paint = Paint()
    ..color = ink.family.withValues(alpha: progress.clamp(0.0, 1.0))
    ..strokeWidth = 1;
  const dash = 4.0;
  const gap = 3.0;
  for (var x = box.plot.left; x < box.plot.right; x += dash + gap) {
    canvas.drawLine(
      Offset(x, y),
      Offset(math.min(x + dash, box.plot.right), y),
      paint,
    );
  }
  chartLabel(
    reference.label,
    ink.labelStyle.copyWith(
      color: ink.family.withValues(alpha: progress.clamp(0.0, 1.0)),
    ),
  ).paint(canvas, Offset(box.plot.left + 2, y + 2));
}
