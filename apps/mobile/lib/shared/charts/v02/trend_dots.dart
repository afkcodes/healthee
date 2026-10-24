/// One reading per night, as dots on the owner's usual band.
///
/// `design/mobile-preview/proposal.js::dots`, which the owner approved for the
/// `Beyond a single night` cards: the usual band shaded, the period's average
/// as a dashed line, a dot per measured night joined by straight segments, a
/// hollow dot for a night outside the band, and three values named (the lowest,
/// the highest and the last). A night with no reading breaks the line.
///
/// The band and the average are given, never computed here: the caller owns
/// the one definition of "usual" (`usual_range.dart`).
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/core/theme/type_scale_keys.dart';
import 'package:healthee/shared/usual_range.dart';

/// The chart, at a fixed height.
class TrendDots extends StatelessWidget {
  /// [values] is oldest first; null is an unmeasured night.
  const TrendDots({
    required this.values,
    required this.progress,
    required this.semanticLabel,
    this.band,
    this.average,
    this.digits = 0,
    this.ceiling,
    this.captions = const <String>[],
    super.key,
  });

  /// `.p-chart { viewBox: 0 0 340 142 }`.
  static const double height = 142;

  final List<double?> values;
  final double progress;
  final String semanticLabel;
  final UsualRange? band;
  final double? average;
  final int digits;

  /// A scale that cannot pass this, 100 for a percentage.
  final double? ceiling;

  /// The first and last date, under the plot.
  final List<String> captions;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticLabel,
    image: true,
    child: ExcludeSemantics(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: TrendDotsPainter(
            values: values,
            band: band,
            average: average,
            digits: digits,
            ceiling: ceiling,
            captions: captions,
            progress: progress,
            colors: context.colors,
            family: context.family,
          ),
        ),
      ),
    ),
  );
}

/// Paints [TrendDots].
class TrendDotsPainter extends CustomPainter {
  /// Everything it draws is given.
  TrendDotsPainter({
    required this.values,
    required this.band,
    required this.average,
    required this.digits,
    required this.ceiling,
    required this.captions,
    required this.progress,
    required this.colors,
    required this.family,
  });

  final List<double?> values;
  final UsualRange? band;
  final double? average;
  final int digits;
  final double? ceiling;
  final List<String> captions;
  final double progress;
  final HealtheeColors colors;
  final Color family;

  /// The axis labels' gutter on the right, and the plot's top and bottom.
  static const double gutter = 36;
  static const double top = 24;
  static const double bottomPad = 24;

  @override
  void paint(Canvas canvas, Size size) {
    final present = <double>[for (final v in values) ?v];
    if (present.isEmpty) {
      return;
    }
    final right = size.width - gutter;
    final bottom = size.height - bottomPad;
    var lo = [...present, ?band?.low].reduce((a, b) => a < b ? a : b);
    var hi = [...present, ?band?.high].reduce((a, b) => a > b ? a : b);
    final pad = ((hi - lo) * 0.15).clamp(1.0, double.infinity);
    lo -= pad;
    hi = ceiling == null ? hi + pad : (hi + pad).clamp(lo + 1, ceiling!);
    double y(double v) => bottom - (v - lo) / (hi - lo) * (bottom - top);
    double x(int i) => values.length < 2
        ? right / 2
        : 6 + i * (right - 12) / (values.length - 1);

    canvas.saveLayer(
      Offset.zero & size,
      Paint()..color = colors.ink.withValues(alpha: progress.clamp(0, 1)),
    );
    final grid = Paint()
      ..color = colors.line
      ..strokeWidth = 1;
    for (final t in <double>[0.1, 0.5, 0.9]) {
      final v = lo + (hi - lo) * t;
      canvas.drawLine(Offset(0, y(v)), Offset(right, y(v)), grid);
      _text(canvas, v.round().toString(), Offset(size.width, y(v)), end: true);
    }
    if (band case final UsualRange b) {
      canvas.drawRRect(
        RRect.fromLTRBR(
          0,
          y(b.high),
          right,
          y(b.low),
          const Radius.circular(4),
        ),
        Paint()..color = family.withValues(alpha: 0.16),
      );
    }
    if (average case final double mean) {
      final dash = Paint()
        ..color = colors.ink3
        ..strokeWidth = 1.2;
      for (var at = 0.0; at < right; at += 8) {
        canvas.drawLine(
          Offset(at, y(mean)),
          Offset((at + 4).clamp(0, right), y(mean)),
          dash,
        );
      }
    }
    final line = Paint()
      ..color = family.withValues(alpha: 0.5)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    Offset? previous;
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      final here = v == null ? null : Offset(x(i), y(v));
      if (previous != null && here != null) {
        canvas.drawLine(previous, here, line);
      }
      previous = here;
    }
    final lowest = present.reduce((a, b) => a < b ? a : b);
    final highest = present.reduce((a, b) => a > b ? a : b);
    final last = values.lastIndexWhere((v) => v != null);
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == null) {
        continue;
      }
      final at = Offset(x(i), y(v));
      final outside = band != null && band!.sideOf(v) != UsualSide.within;
      final r = i == last ? 4.5 : 3.5;
      canvas.drawCircle(at, r + 1.5, Paint()..color = colors.surface);
      canvas.drawCircle(
        at,
        outside ? r - 0.8 : r,
        Paint()
          ..color = family
          ..style = outside ? PaintingStyle.stroke : PaintingStyle.fill
          ..strokeWidth = 1.6,
      );
      final named =
          i == last ||
          (v == lowest && values.indexOf(lowest) == i) ||
          (v == highest && values.indexOf(highest) == i);
      if (named) {
        _text(
          canvas,
          v.toStringAsFixed(digits),
          Offset(i == last ? right : at.dx, at.dy - 12),
          end: i == last,
          ink: colors.ink,
        );
      }
    }
    if (captions.length == 2) {
      _text(canvas, captions.first, Offset(0, size.height - 8), start: true);
      _text(canvas, captions.last, Offset(right, size.height - 8), end: true);
    }
    canvas.restore();
  }

  void _text(
    Canvas canvas,
    String text,
    Offset at, {
    bool end = false,
    bool start = false,
    Color? ink,
  }) {
    TextPainter lay(TextStyle style) => TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final painter = lay(KeyType.rangeEnd.copyWith(color: ink ?? colors.ink2));
    final dx = end
        ? at.dx - painter.width
        : start
        ? at.dx
        : at.dx - painter.width / 2;
    final origin = Offset(dx, at.dy - painter.height / 2);
    // A halo in the card's own surface, so a label never reads through a line.
    lay(
      KeyType.rangeEnd.copyWith(
        foreground: Paint()
          ..color = colors.surface
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      ),
    ).paint(canvas, origin);
    painter.paint(canvas, origin);
  }

  @override
  bool shouldRepaint(TrendDotsPainter old) =>
      old.progress != progress ||
      old.values != values ||
      old.band != band ||
      old.average != average ||
      old.colors != colors ||
      old.family != family;
}
