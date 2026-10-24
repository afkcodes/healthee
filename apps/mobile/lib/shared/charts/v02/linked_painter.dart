/// Two series, two scales, one hour — the geometry and the painter.
///
/// ## The scales are independent, and they are labelled
///
/// Heart rate is 40–140 bpm and stress is a 0–100 index. Forcing them onto one
/// axis would either flatten the heart rate into the bottom third or stretch
/// stress across a range it does not have; drawing them on two **unlabelled**
/// axes is worse still, because then the crossing point of the two traces looks
/// like it means something and it means nothing at all.
///
/// So each pane owns its axis, prints it in its own gutter, and the panes are
/// stacked rather than overlaid. What is shared is exactly one thing: **the
/// hour**. That is the claim the chart is making, and it is the only one it can
/// support — hence the caveat the widget carries under it.
///
/// ## Lanes, not a translate
///
/// Each pane is a [ChartBox] shifted into its lane, so everything is painted in
/// absolute coordinates. `ChartBox.shift` records why: a `canvas.translate`
/// would make a recorded-canvas assertion compare the bottom pane's rects in the
/// wrong frame, and the label-never-overlaps-data test would be measuring
/// fiction.
///
/// ## No bubbles here
///
/// The line chart puts its value in a bubble above the plot. This chart has two
/// values and one cursor, and two bubbles in two label bands would sit beside
/// the pane titles already written there. The readout row under the chart
/// carries both readings with their own colour keys instead — one place to look,
/// and the two numbers side by side, which is the comparison the chart exists to
/// support.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/shared/charts/chart_primitives.dart';
import 'package:healthee/shared/charts/v02/chart_box.dart';
import 'package:healthee/shared/charts/v02/chart_curve.dart';
import 'package:healthee/shared/charts/v02/chart_frame.dart';
import 'package:healthee/shared/charts/v02/chart_ink.dart';
import 'package:healthee/shared/charts/v02/chart_ticks.dart';
import 'package:healthee/shared/charts/v02/linked_lane_marks.dart';
import 'package:healthee/shared/charts/v02/series_painter.dart';

/// One of the two signals: what it is, and the samples it took.
@immutable
class LinkedPane {
  /// [tone] is a category, not a colour — see `chart_ink.dart` on why naming a
  /// tone is not a hole in the no-`Color` rule.
  const LinkedPane({
    required this.tone,
    required this.label,
    required this.values,
    this.unit = '',
    this.digits = 0,
    this.curve = SeriesCurve.monotone,
    this.bars = false,
    this.reference,
  });

  /// Which family this signal belongs to.
  final Tone tone;

  /// Its name, written above its own pane.
  final String label;

  /// Its samples, aligned index-for-index with the other pane's. A `null` is a
  /// hole and breaks that pane's line without touching the other's.
  final List<double?> values;

  /// The unit, shown in the readout.
  final String unit;

  /// Decimal places in the readout.
  final int digits;

  /// How this signal's samples are joined. See `chart_curve.dart`.
  final SeriesCurve curve;

  /// Draws the samples as columns on a zero-based axis instead of a line.
  final bool bars;

  /// A dashed line across the pane in its own colour, or null for none. It
  /// widens the pane's axis so it can never sit off the plot.
  final LaneReference? reference;

  /// The reading at [index], or null when there is none.
  double? valueAt(int? index) {
    if (index == null || index < 0 || index >= values.length) {
      return null;
    }
    final value = values[index];
    return value != null && value.isFinite ? value : null;
  }

  /// The reading at [index] as words: `68 bpm`, or `—` for a hole.
  String readingAt(int? index) {
    final value = valueAt(index);
    return value == null
        ? '—'
        : '${value.toStringAsFixed(digits)}${unit.isEmpty ? '' : ' $unit'}';
  }
}

/// A pane with its tone and its axis resolved.
@immutable
class LinkedLane {
  /// Built by the widget, which is where a `BuildContext` exists.
  const LinkedLane({
    required this.pane,
    required this.ink,
    required this.ticks,
  });

  /// What is drawn.
  final LinkedPane pane;

  /// The pane's own resolved family.
  final ChartInk ink;

  /// The pane's own axis.
  final ChartTicks ticks;
}

/// The lane boxes for [lanes] panes stacked inside [size].
///
/// The last lane carries the shared caption strip, because the hour axis is
/// written once under the pair — writing it under each pane would say the two
/// panes have two time axes.
List<ChartBox> linkedBoxes(Size size, int lanes) {
  if (lanes < 1) {
    return const <ChartBox>[];
  }
  final laneHeight = (size.height - _captionStrip) / lanes;
  return <ChartBox>[
    for (var i = 0; i < lanes; i++)
      (i == lanes - 1
              ? _lastLane.box(Size(size.width, laneHeight + _captionStrip))
              : _lane.box(Size(size.width, laneHeight)))
          .shift(i * laneHeight),
  ];
}

/// The x-geometry the scrubber must share with the painter. Only [padX] and the
/// gutter affect which sample a finger lands on, so this is the whole contract.
const ChartMetrics linkedScrubMetrics = ChartMetrics(valueGutter: _gutter);

/// Draws every lane, then the one cursor through all of them.
class LinkedPainter extends CustomPainter {
  /// Everything is resolved before construction.
  const LinkedPainter({
    required this.lanes,
    required this.progress,
    required this.captions,
    required this.touch,
  });

  /// The panes, top first.
  final List<LinkedLane> lanes;

  /// 0–1 from `RevealOnce`. Both panes reveal together, because they are one
  /// picture.
  final double progress;

  /// The two edge captions — the first and last sample's time.
  final List<String> captions;

  /// The sample under the finger, or null.
  final int? touch;

  @override
  void paint(Canvas canvas, Size size) {
    final boxes = linkedBoxes(size, lanes.length);
    if (boxes.isEmpty || !boxes.first.isDrawable) {
      return;
    }
    for (var i = 0; i < lanes.length; i++) {
      _paintLane(canvas, boxes[i], lanes[i], last: i == lanes.length - 1);
    }
    _paintCursor(canvas, boxes);
  }

  void _paintLane(
    Canvas canvas,
    ChartBox box,
    LinkedLane lane, {
    required bool last,
  }) {
    paintChartFrame(canvas, box, lane.ticks, ink: lane.ink, progress: progress);
    // The pane's name goes in the band reserved above its plot — the same band
    // the line chart puts its bubble in, spent here on saying which signal this
    // is. Inside the plot it would sit on the trace.
    chartLabel(
      lane.pane.label,
      lane.ink.labelStyle.copyWith(color: revealed(lane.ink.ink3, progress)),
    ).paint(canvas, Offset(box.plot.left, box.bubble.top + 1));
    if (lane.pane.bars) {
      paintLaneBars(
        canvas,
        box,
        values: lane.pane.values,
        ticks: lane.ticks,
        ink: lane.ink,
        progress: progress,
      );
    } else {
      paintSeriesInto(
        canvas,
        box,
        values: lane.pane.values,
        ticks: lane.ticks,
        ink: lane.ink,
        progress: progress,
        curve: lane.pane.curve,
        strokeWidth: 2.2,
        fill: true,
        lastPointDot: false,
      );
    }
    if (lane.pane.reference case final LaneReference reference) {
      paintLaneReference(
        canvas,
        box,
        reference,
        ticks: lane.ticks,
        ink: lane.ink,
        progress: progress,
      );
    }
    if (last) {
      paintEdgeCaptions(
        canvas,
        box,
        captions,
        ink: lane.ink,
        progress: progress,
      );
    }
  }

  void _paintCursor(Canvas canvas, List<ChartBox> boxes) {
    final index = touch;
    if (index == null) {
      return;
    }
    final count = lanes.first.pane.values.length;
    if (index < 0 || index >= count) {
      return;
    }
    final x = boxes.first.x(index, count);
    // One line through both plots AND the gap between them. That continuity is
    // the entire assertion the chart makes: the same instant, twice.
    paintScrubCursor(
      canvas,
      x,
      top: boxes.first.plot.top,
      bottom: boxes.last.plot.bottom,
      ink: lanes.first.ink,
    );
    for (var i = 0; i < lanes.length; i++) {
      final value = lanes[i].pane.valueAt(index);
      if (value != null) {
        paintLastPointDot(
          canvas,
          Offset(x, lanes[i].ticks.y(value, boxes[i].plot)),
          ink: lanes[i].ink,
          progress: 1,
          radius: 4,
        );
      }
    }
  }

  @override
  bool shouldRepaint(LinkedPainter old) =>
      old.progress != progress ||
      old.touch != touch ||
      old.lanes != lanes ||
      old.captions != captions;
}

/// The shared hour axis, written once under the bottom pane.
const double _captionStrip = 15;

/// Room for a three-digit axis label beside either pane.
const double _gutter = ChartMetrics.gutterWidth;

/// Air under a pane's plot, so the NEXT pane's title cannot touch its trace.
/// Without it the two lanes abut and the second title sits one pixel under the
/// first pane's area fill — non-overlapping, and unreadable.
const double _laneGap = 5;

const ChartMetrics _lane = ChartMetrics(
  valueGutter: _gutter,
  captionStrip: _laneGap,
  bubbleBand: 15,
  padTop: 3,
);

const ChartMetrics _lastLane = ChartMetrics(
  valueGutter: _gutter,
  captionStrip: _captionStrip,
  bubbleBand: 15,
  padTop: 3,
);
