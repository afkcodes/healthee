/// [HArea] — a smooth area + line with a draw-on reveal, scrubbable by touch.
///
/// **Ported from** `instrument_charts.dart`'s `HArea`. The painter's geometry is
/// unchanged: the same 0.18 y-padding, the same 4 px x-padding, the same
/// gradient from 32% alpha to nothing, the same crosshair-dot-bubble on touch.
///
/// Two changes, both required by this repo's rules:
///
///   * **`progress` is a parameter, not a controller.** See
///     `chart_primitives.dart` for the whole argument; the short version is that
///     an `AnimationController` in a `ListView.builder` item replays on every
///     scroll-back, which `CLAUDE.md` names as a hard rule.
///   * **Colours are roles.** `HColors.paper`/`paper2` became
///     [HealtheeColors.surface]/[HealtheeColors.ink]; the caller passes the line
///     colour, which is `accent` for the owner's own data everywhere it is used.
///
/// ## The third change, and it is the owner's (2026-08-06)
///
/// [references] — the horizontal lines this chart is read against. Legacy has
/// none, and their absence is what the owner's *"this graphs all look similar"*
/// report was really about; `chart_reference.dart` carries the whole argument
/// and the departure. With an empty list the geometry is byte-for-byte legacy's:
/// [ChartScale] is this painter's own scale extracted, and it only widens when a
/// reference asks it to.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/shared/charts/chart_primitives.dart';
import 'package:healthee/shared/charts/chart_reference.dart';

/// A smooth area chart over [data], revealed left-to-right by [progress].
class HArea extends StatefulWidget {
  /// [data] is in series order; [progress] is 0–1 from `RevealOnce`.
  const HArea(
    this.data, {
    required this.color,
    required this.progress,
    this.height = 30,
    this.strokeWidth = 2.2,
    this.fill = true,
    this.unit = '',
    this.digits = 0,
    this.references = const <ChartReference>[],
    super.key,
  });

  /// The values, oldest first.
  final List<double> data;

  /// The line colour. `accent` for the owner's own data.
  final Color color;

  /// How much of the line to draw, 0–1.
  final double progress;

  /// How tall to draw it.
  final double height;

  /// Line weight.
  final double strokeWidth;

  /// Whether to fill under the line.
  final bool fill;

  /// Unit shown in the scrub bubble.
  final String unit;

  /// Decimal places in the scrub bubble.
  final int digits;

  /// The lines this series is read against. Empty is legacy's chart exactly.
  ///
  /// They widen the plot's scale rather than clipping to its edge — see
  /// `chart_reference.dart`, which is the whole reason a reference here is a
  /// claim rather than a decoration.
  final List<ChartReference> references;

  @override
  State<HArea> createState() => _HAreaState();
}

class _HAreaState extends State<HArea> {
  int? _touch;
  double _width = 1;

  /// Touch state is per-instance and ephemeral, so it stays in `State`. Losing
  /// it when the item scrolls away is correct — nobody is still holding a finger
  /// on a chart that is off screen.
  /// Legacy holds a tapped value on screen for 1200 ms after the finger
  /// leaves (`instrument_charts.dart:77`), so a tap is readable. A drag still
  /// clears the moment it ends.
  static const Duration _linger = Duration(milliseconds: 1200);

  void _clearAfterLinger() {
    Future<void>.delayed(_linger, () {
      if (mounted) {
        setState(() => _touch = null);
      }
    });
  }

  void _scrub(double dx) {
    if (widget.data.length < 2) {
      return;
    }
    const padX = 4.0;
    final fraction = ((dx - padX) / (_width - padX * 2)).clamp(0.0, 1.0);
    setState(() => _touch = (fraction * (widget.data.length - 1)).round());
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) => _scrub(details.localPosition.dx),
      onTapUp: (_) => _clearAfterLinger(),
      onHorizontalDragStart: (details) => _scrub(details.localPosition.dx),
      onHorizontalDragUpdate: (details) => _scrub(details.localPosition.dx),
      onHorizontalDragEnd: (_) => setState(() => _touch = null),
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: LayoutBuilder(
          builder: (context, box) {
            _width = box.maxWidth;
            return CustomPaint(
              painter: _AreaPainter(
                data: widget.data,
                color: widget.color,
                ink3: colors.ink3,
                referenceInk: colors.reference,
                bubbleInk: colors.surface,
                progress: widget.progress,
                strokeWidth: widget.strokeWidth,
                fill: widget.fill,
                touch: _touch,
                unit: widget.unit,
                digits: widget.digits,
                references: widget.references,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AreaPainter extends CustomPainter {
  const _AreaPainter({
    required this.data,
    required this.color,
    required this.ink3,
    required this.referenceInk,
    required this.bubbleInk,
    required this.progress,
    required this.strokeWidth,
    required this.fill,
    required this.touch,
    required this.unit,
    required this.digits,
    required this.references,
  });

  final List<double> data;
  final Color color;
  final Color ink3;
  final Color referenceInk;
  final Color bubbleInk;
  final double progress;
  final double strokeWidth;
  final bool fill;
  final int? touch;
  final String unit;
  final int digits;
  final List<ChartReference> references;

  /// Legacy's `padX`, unchanged. Its `yPad` now lives in [ChartScale].
  static const double _padX = 4;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) {
      return;
    }
    final scale = ChartScale.of(
      data,
      include: <double>[for (final line in references) line.value],
    );
    double x(int i) =>
        _padX + (i / (data.length - 1)) * (size.width - _padX * 2);
    double y(double v) => scale.y(v, size.height);

    final points = [
      for (var i = 0; i < data.length; i++) Offset(x(i), y(data[i])),
    ];
    final line = smoothPath(points);

    if (fill) {
      final area = Path.from(line)
        ..lineTo(x(data.length - 1), size.height)
        ..lineTo(x(0), size.height)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: 0.32 * progress),
              color.withValues(alpha: 0),
            ],
          ).createShader(Offset.zero & size),
      );
    }

    // ON the fill, UNDER the trace — the 2026-08-06 repair. It used to be
    // painted first, which put a grey hairline and a grey caption beneath a warm
    // 32% wash: the owner's report on that build was that the heart-rate chart
    // "looks wried", and what he was looking at was `ink3` seen through clay.
    // "Ground under the measurement" is about the DATA LINE, which still crosses
    // over it; a reference the fill has muddied is not ground, it is sludge.
    for (final reference in references) {
      paintChartReference(
        canvas,
        size,
        reference,
        scale: scale,
        color: referenceInk,
        progress: progress,
      );
    }

    final metric = line.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * progress),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    _paintScrub(canvas, size, x, y);
  }

  void _paintScrub(
    Canvas canvas,
    Size size,
    double Function(int) x,
    double Function(double) y,
  ) {
    final index = touch;
    if (index == null || index < 0 || index >= data.length) {
      return;
    }
    final px = x(index);
    final py = y(data[index]);
    canvas.drawLine(
      Offset(px, 0),
      Offset(px, size.height),
      Paint()
        ..color = ink3.withValues(alpha: 0.45)
        ..strokeWidth = 1,
    );
    canvas.drawCircle(Offset(px, py), 4, Paint()..color = color);
    canvas.drawCircle(
      Offset(px, py),
      4,
      Paint()
        ..color = bubbleInk
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    final text =
        '${data[index].toStringAsFixed(digits)}'
        '${unit.isNotEmpty ? ' $unit' : ''}';
    final painter = chartLabel(
      text,
      TypeLadder.micro.copyWith(color: bubbleInk),
    );
    final width = painter.width + 12;
    final height = painter.height + 6;
    final left = (px - width / 2).clamp(0.0, size.width - width);
    // Floats ABOVE the plot, which is why the caller must not clip: these are
    // often 30 px minis and a bubble inside them would cover the line.
    final top = -height - 4;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, width, height),
        const Radius.circular(6),
      ),
      Paint()..color = color,
    );
    painter.paint(canvas, Offset(left + 6, top + 3));
  }

  @override
  bool shouldRepaint(_AreaPainter old) =>
      old.progress != progress ||
      old.data != data ||
      old.color != color ||
      old.touch != touch ||
      old.references != references;
}
