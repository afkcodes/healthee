/// [HDebtBars] — each night against the need line, with the shortfall drawn in.
///
/// **Ported from** `instrument_charts.dart`'s `HDebtBars`. Unchanged: the solid
/// bar to the night's own total, the faint ghost continuing up to the target on
/// a night that fell short, the dashed target line, gridlines at 0/3/6/9 h, and
/// the `label  7h 20m  ·  40m short` bubble.
///
/// **The ghost is the point of the chart.** A bar chart of nightly totals says
/// "you slept six hours"; the ghost above it says "and here is the piece that is
/// missing", every night, stacked up the page. Brief §5.4 asks for exactly that
/// — the shape that makes "small nightly shortfall, large monthly cost" visible
/// in a way a single "sleep debt: 120 min" never does.
///
/// Two real changes from legacy, both about not inventing a constant:
///
///   * **The target is a parameter.** Legacy hard-coded `_target = 8.0` hours
///     and a `480` inside the tooltip's shortfall arithmetic, in two places that
///     could disagree. The need comes from `sleep_debt.need_min` on the wire, so
///     it is passed in once and both uses read it.
///   * **Colour follows the owner's approved redesign** (`proposal.css`:
///     `.p-bar.met`, `.p-bar.current`, `.p-owed`). A night that met the need
///     is `fav`; one that fell short is drawn in the card's own family, with
///     what it still needed as a faint ghost of the same hue. No red: a short
///     night is a reading, not an alarm (`APP_DESIGN.md`, no traffic lights).
///     The need line is dotted ink.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/shared/charts/chart_primitives.dart';
import 'package:healthee/shared/format/duration.dart';

/// Nightly sleep totals against a need line.
class HDebtBars extends StatefulWidget {
  /// [totalsMin] and [labels] are oldest first; [needMin] is the target.
  const HDebtBars({
    required this.totalsMin,
    required this.labels,
    required this.needMin,
    required this.progress,
    this.height = 150,
    super.key,
  });

  /// Each night's total sleep time, minutes.
  final List<double> totalsMin;

  /// One short label per night.
  final List<String> labels;

  /// The nightly need, minutes. From the payload, never assumed.
  final int needMin;

  /// How strongly the shortfall is drawn.
  ///
  /// **It was 0.16, against a docstring that calls it the point of the chart.**
  /// At that alpha the missing piece read as empty card, so a week of seven
  /// short nights looked like a week of seven ordinary bars and the debt above
  /// it came from nowhere. It is the one mark on this chart the panel's own
  /// title is about.
  static const double ghostAlpha = 0.34;

  /// How far the bars have grown, 0–1.
  final double progress;

  /// How tall to draw it.
  final double height;

  @override
  State<HDebtBars> createState() => _HDebtBarsState();
}

class _HDebtBarsState extends State<HDebtBars> {
  int? _selected;

  void _pick(Offset position, Size size) {
    final count = widget.totalsMin.length;
    if (count == 0) {
      return;
    }
    const leftPad = 26.0;
    final index = ((position.dx - leftPad) / ((size.width - leftPad) / count))
        .floor();
    setState(() => _selected = (index >= 0 && index < count) ? index : null);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, box) {
          final size = Size(box.maxWidth, box.maxHeight);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => _pick(details.localPosition, size),
            onPanStart: (details) => _pick(details.localPosition, size),
            onPanUpdate: (details) => _pick(details.localPosition, size),
            onPanEnd: (_) => setState(() => _selected = null),
            child: CustomPaint(
              size: size,
              painter: _DebtPainter(
                totalsMin: widget.totalsMin,
                labels: widget.labels,
                needMin: widget.needMin,
                colors: colors,
                family: context.family,
                selected: _selected,
                progress: widget.progress,
                labelStyle: TypeLadder.micro.copyWith(color: colors.ink3),
                bubbleStyle: TypeLadder.micro.copyWith(color: colors.ink),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DebtPainter extends CustomPainter {
  const _DebtPainter({
    required this.totalsMin,
    required this.labels,
    required this.needMin,
    required this.colors,
    required this.family,
    required this.selected,
    required this.progress,
    required this.labelStyle,
    required this.bubbleStyle,
  });

  final List<double> totalsMin;
  final List<String> labels;
  final int needMin;
  final HealtheeColors colors;
  final Color family;
  final int? selected;
  final double progress;
  final TextStyle labelStyle;
  final TextStyle bubbleStyle;

  static const double _leftPad = 26;
  static const double _topPad = 6;
  static const double _labelHeight = 18;

  @override
  void paint(Canvas canvas, Size size) {
    final hours = [for (final minutes in totalsMin) minutes / 60.0];
    final count = hours.length;
    if (count == 0) {
      return;
    }
    final targetHours = needMin / 60.0;
    final yMax =
        [targetHours + 1, ...hours].reduce((a, b) => a > b ? a : b) + 0.5;
    final plotWidth = size.width - _leftPad;
    final plotHeight = size.height - _topPad - _labelHeight;
    double yAt(double h) => _topPad + (1 - h / yMax) * plotHeight;
    final baseline = yAt(0);

    _paintGrid(canvas, size, yMax, yAt);
    _paintTargetLine(canvas, size, yAt(targetHours));

    final slot = plotWidth / count;
    final barWidth = (slot * 0.5).clamp(6.0, 26.0);
    for (var i = 0; i < count; i++) {
      _paintNight(
        canvas,
        centre: _leftPad + slot * i + slot / 2,
        barWidth: barWidth,
        hours: hours[i],
        targetHours: targetHours,
        baseline: baseline,
        yAt: yAt,
        label: i < labels.length ? labels[i] : null,
      );
    }
    _paintCrosshair(canvas, size, slot, baseline);
  }

  void _paintGrid(
    Canvas canvas,
    Size size,
    double yMax,
    double Function(double) yAt,
  ) {
    final grid = Paint()
      // `colors.grid`, never `line` scaled here: `withValues` REPLACES the
      // alpha, so the old `line.withValues(alpha: 0.5)` drew a 10% hairline at
      // 50% — see `palette.dart`'s `DarkPalette.grid`.
      ..color = colors.grid
      ..strokeWidth = 1;
    for (final hour in const [0, 3, 6, 9]) {
      if (hour > yMax) {
        continue;
      }
      final y = yAt(hour.toDouble());
      canvas.drawLine(Offset(_leftPad, y), Offset(size.width, y), grid);
      final label = chartLabel(hoursText(hour), labelStyle);
      label.paint(
        canvas,
        Offset(_leftPad - label.width - 5, y - label.height / 2),
      );
    }
  }

  void _paintTargetLine(Canvas canvas, Size size, double y) {
    final dash = Paint()
      ..color = colors.ink.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    for (var x = _leftPad; x < size.width; x += 7) {
      canvas.drawLine(Offset(x, y), Offset(x + 4, y), dash);
    }
  }

  void _paintNight(
    Canvas canvas, {
    required double centre,
    required double barWidth,
    required double hours,
    required double targetHours,
    required double baseline,
    required double Function(double) yAt,
    required String? label,
  }) {
    final met = hours >= targetHours;
    final colour = met ? colors.fav : family;
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTRB(
          centre - barWidth / 2,
          yAt(hours * progress),
          centre + barWidth / 2,
          baseline,
        ),
        topLeft: const Radius.circular(3),
        topRight: const Radius.circular(3),
      ),
      Paint()..color = colour,
    );
    if (!met) {
      // The ghost: the piece that is missing, drawn where it would have been.
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTRB(
            centre - barWidth / 2,
            yAt(targetHours),
            centre + barWidth / 2,
            yAt(hours),
          ),
          topLeft: const Radius.circular(3),
          topRight: const Radius.circular(3),
        ),
        Paint()
          ..color = family.withValues(alpha: HDebtBars.ghostAlpha * progress),
      );
    }
    if (label != null) {
      final painter = chartLabel(label, labelStyle);
      painter.paint(canvas, Offset(centre - painter.width / 2, baseline + 5));
    }
  }

  void _paintCrosshair(Canvas canvas, Size size, double slot, double baseline) {
    final index = selected;
    if (index == null || index < 0 || index >= totalsMin.length) {
      return;
    }
    final centre = _leftPad + slot * index + slot / 2;
    final slept = totalsMin[index].round();
    final short = (needMin - slept).clamp(0, needMin);
    canvas.drawLine(
      Offset(centre, 0),
      Offset(centre, baseline),
      Paint()
        ..color = colors.ink3.withValues(alpha: 0.35)
        ..strokeWidth = 1,
    );
    final label = index < labels.length ? labels[index] : '';
    drawChartTooltip(
      canvas,
      size,
      '$label  ${durationText(slept)}'
      '${short > 0 ? '  ·  ${durationText(short)} short' : ''}',
      anchorX: centre,
      background: colors.surface,
      border: colors.line,
      style: bubbleStyle,
    );
  }

  @override
  bool shouldRepaint(_DebtPainter old) =>
      old.progress != progress ||
      old.totalsMin != totalsMin ||
      old.selected != selected;
}
