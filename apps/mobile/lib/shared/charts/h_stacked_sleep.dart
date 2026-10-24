/// [HStackedSleep] — seven nights of stacked stage minutes, with hour gridlines.
///
/// **Ported from** `instrument_charts.dart`'s `HStackedSleep`. The axis logic is
/// unchanged and is the interesting part: the top of the chart is the tallest
/// night rounded UP to an even number of hours, with a floor of two, so the
/// dashed gridlines land on 0h / 2h / 4h … and every night is read against the
/// same clock rather than against itself.
///
/// Changed: `progress` is a parameter (see `chart_primitives.dart`), and the
/// four-hue stage palette became shades of one accent — `stage_colors.dart`
/// carries that argument.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/instrument_hues.dart';
import 'package:healthee/core/theme/stage_colors.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/data/models/sleep_history.dart';
import 'package:healthee/shared/charts/chart_primitives.dart';
import 'package:healthee/shared/format/duration.dart';

/// A week of nights, stacked deep → light → REM → awake.
class HStackedSleep extends StatelessWidget {
  /// [nights] is oldest first; [progress] is 0–1 from `RevealOnce`.
  const HStackedSleep(
    this.nights, {
    required this.progress,
    this.height = 110,
    super.key,
  });

  /// The nights to draw.
  final List<SleepNightSummary> nights;

  /// How far the bars have grown, 0–1.
  final double progress;

  /// How tall to draw the chart. 110 is legacy's default.
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hues = context.hues;
    if (nights.isEmpty) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _StackedPainter(
          nights: nights,
          colors: colors,
          hues: hues,
          progress: progress,
          labelStyle: TypeLadder.micro.copyWith(color: colors.ink3),
          lastLabelStyle: TypeLadder.micro.copyWith(color: colors.ink2),
        ),
      ),
    );
  }
}

class _StackedPainter extends CustomPainter {
  const _StackedPainter({
    required this.nights,
    required this.colors,
    required this.hues,
    required this.progress,
    required this.labelStyle,
    required this.lastLabelStyle,
  });

  final List<SleepNightSummary> nights;
  final HealtheeColors colors;
  final InstrumentHues hues;
  final double progress;
  final TextStyle labelStyle;
  final TextStyle lastLabelStyle;

  static const double _gap = 12;
  static const double _labelHeight = 16;
  static const double _leftPad = 26;

  @override
  void paint(Canvas canvas, Size size) {
    if (nights.isEmpty) {
      return;
    }
    final axisMinutes = _axisMinutes();
    final count = nights.length;
    final chartHeight = size.height - _labelHeight;
    final plotWidth = size.width - _leftPad;
    final barWidth = (plotWidth - _gap * (count - 1)) / count;
    double yFor(double minutes) =>
        chartHeight - (minutes / axisMinutes) * chartHeight;

    _paintGrid(canvas, size, axisMinutes, yFor);

    for (var i = 0; i < count; i++) {
      final night = nights[i];
      final x = _leftPad + i * (barWidth + _gap);
      if (!night.hasBreakdown) {
        _paintUnmeasured(canvas, x, barWidth, chartHeight);
      } else {
        var stacked = 0.0;
        for (final stage in kSleepStages) {
          final minutes = _minutesIn(night, stage).toDouble();
          final segment = (minutes / axisMinutes) * chartHeight * progress;
          canvas.drawRect(
            Rect.fromLTWH(
              x,
              chartHeight - stacked - segment,
              barWidth,
              segment,
            ),
            Paint()..color = sleepStageColor(hues, stage),
          );
          stacked += segment;
        }
      }
      final label = chartLabel(
        night.weekdayInitial,
        i == count - 1 ? lastLabelStyle : labelStyle,
      );
      label.paint(
        canvas,
        Offset(x + barWidth / 2 - label.width / 2, size.height - 11),
      );
    }
  }

  /// A night with NO stage breakdown, drawn as an absence rather than as zero.
  ///
  /// Four zero-height segments are pixel-identical to a night of literal zero
  /// sleep, and that is exactly what this chart used to paint for a night the
  /// strap never staged — the loudest end of the A5 chain, because the owner sees
  /// a bar chart saying they did not sleep.
  ///
  /// A short hollow stub on the baseline instead: it occupies the night's slot so
  /// the week still reads as seven nights and the weekday label still has a bar
  /// to sit under, and it is visibly not a measurement. No new colour — the grid
  /// tone is already the app's "structure, not data" ink.
  void _paintUnmeasured(
    Canvas canvas,
    double x,
    double barWidth,
    double chartHeight,
  ) {
    const double stubHeight = 3;
    canvas.drawRect(
      Rect.fromLTWH(x, chartHeight - stubHeight, barWidth, stubHeight),
      Paint()
        ..color = colors.grid
        ..style = PaintingStyle.fill,
    );
  }

  void _paintGrid(
    Canvas canvas,
    Size size,
    double axisMinutes,
    double Function(double) yFor,
  ) {
    final grid = Paint()
      // One definition of a gridline; see `palette.dart`'s `DarkPalette.grid`.
      // This one was the loudest of the three at 0.7 — 70% white on dark.
      ..color = colors.grid
      ..strokeWidth = 1;
    final maxHours = (axisMinutes / 60).round();
    for (var hour = 0; hour <= maxHours; hour += 2) {
      final y = yFor(hour * 60);
      // Hand-dashed: Flutter has no dashed line, and a solid grid at this
      // weight competes with the bars it is meant to sit behind.
      for (var x = _leftPad; x < size.width; x += 6) {
        canvas.drawLine(Offset(x, y), Offset(x + 3, y), grid);
      }
      final label = chartLabel(hoursText(hour), labelStyle);
      label.paint(
        canvas,
        Offset(_leftPad - label.width - 6, y - label.height / 2),
      );
    }
  }

  /// The chart top, in minutes: the tallest night rounded up to an EVEN hour,
  /// never below two. Legacy's rule, kept — it is what makes the gridlines land
  /// on round hours for every week rather than most weeks.
  double _axisMinutes() {
    // An unmeasured night has no height to fit, and `_totalOf` already answers 0
    // for one — so no `hasBreakdown` branch here. A conditional was written and
    // then removed: its mutation SURVIVED, which is the honest way to find out a
    // guard guards nothing (`HOW_WE_VERIFY.md` section 2). The absence is drawn
    // by `_paintUnmeasured`, not by the axis.
    final tallest = nights.map(_totalOf).reduce((a, b) => a > b ? a : b);
    var hours = (tallest / 60).ceil();
    if (hours < 2) {
      hours = 2;
    }
    if (hours.isOdd) {
      hours += 1;
    }
    return hours * 60.0;
  }

  /// A night's stacked height. An unmeasured night sums to 0 and never reaches
  /// the painter's stacking branch, so a zero here only ever sets the axis floor.
  static int _totalOf(SleepNightSummary night) =>
      (night.deepMin ?? 0) +
      (night.lightMin ?? 0) +
      (night.remMin ?? 0) +
      (night.awakeMin ?? 0);

  static int _minutesIn(SleepNightSummary night, String stage) =>
      switch (stage) {
        'deep' => night.deepMin ?? 0,
        'light' => night.lightMin ?? 0,
        'rem' => night.remMin ?? 0,
        'awake' => night.awakeMin ?? 0,
        _ => 0,
      };

  @override
  bool shouldRepaint(_StackedPainter old) =>
      old.progress != progress || old.nights != nights;
}
