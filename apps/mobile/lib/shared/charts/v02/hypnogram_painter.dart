/// The mark [V02Hypnogram] draws — the night as one continuous band.
///
/// Split out of `v02_hypnogram.dart` when the chart outgrew the 400-line limit.
/// The division is the honest one: the widget decides *what the chart is for* —
/// its height, its empty state, what a screen reader is told — and this decides
/// *what the ink does*.
///
/// ## The shape, and the two it replaced
///
/// First it was pills at lane centres joined by a 2px stroke in the light-stage
/// hue. Then it was a thin ribbon that stepped between four levels on 4px
/// risers, inside a box, over dotted level rules. Both failed on a real night
/// for the same reason — **the furniture outdrew the data**:
///
///   * **`rx: 5` ate a short bout.** A five-minute span is ~6px wide, so the
///     radius consumed the rectangle and it drew as a lozenge with the weight
///     of a forty-minute block.
///   * **Saturated joins read as events.** Forty risers in a stage hue is more
///     ink than the bands they connect. An owner looking at the ribbon saw the
///     verticals first and called the chart broken: tall coloured bars at every
///     change, and a thin line of actual sleep between them.
///   * **A thin band leaves the plot empty.** At 42% of its lane the ribbon
///     used under half the height it was given; the rest was box and rules.
///
/// Now every minute belongs to a **block that fills its level**, so the stages
/// read as areas and their widths can be compared at a glance. Consecutive
/// blocks meet edge to edge, which is what makes the night read as one piece.
/// The join between two levels is a **dotted hairline in the grid colour**: it
/// carries the eye across and is never mistaken for a stage. Awake is a shorter
/// cap above the band, because a wake is an interruption of the night rather
/// than a fourth kind of sleep. There is no box and no level rule; the blocks
/// are the levels.
///
/// Corners stay small ([bandRadius], and never more than half a block's width),
/// so a one-minute bout still draws one minute wide.
///
/// ## The lane labels are still gone
///
/// `Awake / REM / Light / Deep` sat in a 44px gutter, repeating what the colour
/// key under the chart already says. The gutter is the plot's — about 15% more
/// width for the night itself.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/instrument_hues.dart';
import 'package:healthee/core/theme/stage_colors.dart';
import 'package:healthee/data/models/last_sleep.dart';
import 'package:healthee/shared/charts/chart_primitives.dart';
import 'package:healthee/shared/charts/v02/chart_box.dart';
import 'package:healthee/shared/charts/v02/chart_ink.dart';
import 'package:healthee/shared/charts/v02/v02_hypnogram.dart';

/// Draws the blocks, the joins between them and the clock axis.
class HypnogramPainter extends CustomPainter {
  /// Everything the timeline needs, already resolved from the theme.
  const HypnogramPainter({
    required this.spans,
    required this.hues,
    required this.ink,
    required this.progress,
    required this.axis,
  });

  /// The staged spans, oldest first.
  final List<SleepStageSpan> spans;

  /// The app's one stage mapping.
  final InstrumentHues hues;

  /// Grid, label and surface colours.
  final ChartInk ink;

  /// How much of the reveal has run.
  final double progress;

  /// The clocks under the plot, left to right, evenly spaced across the night.
  final List<String> axis;

  /// The gap between two levels. Small, so neighbouring levels read as one
  /// band rather than as four separate rows.
  static const double levelGap = 3;

  /// Awake's height as a fraction of a sleep level's: a cap, not a fourth band.
  static const double awakeFraction = 0.5;

  /// The block's corner. Square enough that a short bout keeps its width.
  static const double bandRadius = 2.5;

  /// Every hairline on this chart.
  static const double hairlineWidth = 1;

  /// The dotted join between two levels — dash, then gap.
  static const double dash = 1.5;
  static const double dashGap = 2.5;

  /// The strip under the plot that carries the clocks.
  static const double captionStrip = 22;

  /// Room above the plot box.
  static const double padTop = 6;

  /// The gap between the plot's bottom edge and the clocks.
  static const double captionGap = 6;

  /// The narrowest a block may draw. A one-minute bout on a nine-hour night is
  /// a third of a pixel; at that width it is not drawn at all, and a stage the
  /// night actually contained would be missing from the picture.
  static const double minBlockWidth = 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final box = _box(size);
    if (!box.isDrawable) {
      return;
    }
    final window = _window();
    if (window <= 0) {
      return;
    }
    final levels = _Levels(box.plot);
    _paintJoins(canvas, box, window, levels);
    _paintBlocks(canvas, box, window, levels);
    _paintAxis(canvas, box);
  }

  /// The plot fills the width; the clocks sit in a strip beneath it.
  ChartBox _box(Size size) {
    const top = padTop;
    final bottom = size.height - captionStrip;
    return ChartBox(
      plot: Rect.fromLTRB(0, top, size.width, bottom),
      values: Rect.zero,
      captions: Rect.fromLTRB(0, bottom, size.width, size.height),
      bubble: Rect.zero,
    );
  }

  /// First start to last end — the night's own length, never a fixed window.
  double _window() {
    var start = spans.first.startOffsetMin;
    var end = spans.first.endOffsetMin;
    for (final span in spans) {
      start = math.min(start, span.startOffsetMin);
      end = math.max(end, span.endOffsetMin);
    }
    return end - start;
  }

  double _originMin() {
    var start = spans.first.startOffsetMin;
    for (final span in spans) {
      start = math.min(start, span.startOffsetMin);
    }
    return start;
  }

  /// How far along the night the reveal has reached, as an x.
  double _reach(ChartBox box) =>
      box.plot.left + box.plot.width * progress.clamp(0.0, 1.0);

  /// The dotted hairline from one block to the next, where the level changes.
  ///
  /// Drawn first, so a block's own edge covers the join's ends. It runs from
  /// the bottom of the upper block to the top of the lower one and no further:
  /// a join that crossed a block would draw a line through a measurement.
  void _paintJoins(Canvas canvas, ChartBox box, double window, _Levels levels) {
    final reach = _reach(box);
    final paint = Paint()
      ..color = revealed(ink.ink3, progress)
      ..strokeWidth = hairlineWidth;
    for (var i = 1; i < spans.length; i++) {
      final x = _x(box, spans[i].startOffsetMin, window);
      if (x > reach) {
        break;
      }
      final before = levels.of(_laneOf(spans[i - 1].stage));
      final after = levels.of(_laneOf(spans[i].stage));
      if (before.top == after.top) {
        continue;
      }
      final upper = before.top < after.top ? before : after;
      final lower = before.top < after.top ? after : before;
      var y = upper.bottom;
      while (y < lower.top) {
        canvas.drawLine(
          Offset(x, y),
          Offset(x, math.min(y + dash, lower.top)),
          paint,
        );
        y += dash + dashGap;
      }
    }
  }

  /// One block per span, each filling its level.
  ///
  /// **The reveal sweeps along the night; it does not inflate the blocks.**
  /// Growing every block's height at once made the whole plot pulse, and a
  /// night is a sequence — so it arrives as one.
  void _paintBlocks(
    Canvas canvas,
    ChartBox box,
    double window,
    _Levels levels,
  ) {
    if (progress <= 0) {
      return;
    }
    final reach = _reach(box);
    for (final span in spans) {
      final left = _x(box, span.startOffsetMin, window);
      if (left > reach) {
        break;
      }
      final level = levels.of(_laneOf(span.stage));
      final right = math.min(_x(box, span.endOffsetMin, window), reach);
      final rect = Rect.fromLTWH(
        left,
        level.top,
        math.max(right - left, minBlockWidth),
        level.height,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rect,
          Radius.circular(math.min(bandRadius, rect.width / 2)),
        ),
        Paint()..color = sleepStageColor(hues, span.stage),
      );
    }
  }

  /// The clocks, evenly spaced: the first flush left, the last flush right.
  void _paintAxis(Canvas canvas, ChartBox box) {
    if (axis.isEmpty) {
      return;
    }
    final style = ink.labelStyle.copyWith(color: revealed(ink.ink3, progress));
    final last = axis.length - 1;
    for (var i = 0; i < axis.length; i++) {
      final painter = chartLabel(axis[i], style);
      final at = last == 0 ? 0.0 : i / last;
      final x = box.plot.left + box.plot.width * at;
      // Flush at the ends, centred between them — a centred first label hangs
      // off the plot's left edge and reads as belonging to the card, not the
      // axis.
      final left = switch (i) {
        0 => x,
        _ when i == last => x - painter.width,
        _ => x - painter.width / 2,
      };
      painter.paint(canvas, Offset(left, box.captions.top + captionGap));
    }
  }

  /// `core` is the server's word for the strap's `light`. One stage, one lane.
  static String _laneOf(String stage) => stage == 'core' ? 'light' : stage;

  double _x(ChartBox box, double minutes, double window) =>
      box.plot.left +
      ((minutes - _originMin()) / window).clamp(0.0, 1.0) * box.plot.width;

  @override
  bool shouldRepaint(HypnogramPainter old) =>
      old.progress != progress ||
      old.spans != spans ||
      old.axis != axis ||
      old.ink.family != ink.family;
}

/// Where each level sits in the plot: the awake cap, then three sleep levels.
class _Levels {
  _Levels(Rect plot)
    : _top = plot.top,
      _sleep =
          (plot.height - HypnogramPainter.levelGap * 3) /
          (3 + HypnogramPainter.awakeFraction);

  final double _top;
  final double _sleep;

  double get _awake => _sleep * HypnogramPainter.awakeFraction;

  /// The vertical extent of [lane]. An unknown stage sits with Light, the one
  /// level every night has, rather than off the plot.
  ({double top, double bottom, double height}) of(String lane) {
    if (lane == 'awake') {
      return (top: _top, bottom: _top + _awake, height: _awake);
    }
    final index = kHypnogramLanes.indexOf(lane);
    final row = index < 1 ? 1 : index - 1;
    final top =
        _top +
        _awake +
        HypnogramPainter.levelGap +
        row * (_sleep + HypnogramPainter.levelGap);
    return (top: top, bottom: top + _sleep, height: _sleep);
  }
}
