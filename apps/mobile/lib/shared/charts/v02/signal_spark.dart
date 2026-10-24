/// A reading's recent run, drawn against the owner's own usual range.
///
/// The colour kit's chart grammar, in one place:
///
///   * the **line is the domain colour** (`context.family`), never green or
///     red, and its segments are straight: nightly values are points joined by
///     lines, not a curve that could draw a minimum no night measured;
///   * **behind it, the usual range** as the `band` token, so the line reads as
///     "inside my normal" or "outside it" without a legend;
///   * **only the newest dot takes a state colour**, from [ReadingState];
///     inside the range it is the primary ink, not green;
///   * **a gap stays a gap**: a null breaks the line and nothing is drawn
///     across it.
///
/// Fewer than two measured values draws the hatched empty strip, never a flat
/// line that would read as a steady reading.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/shared/charts/v02/hatch.dart';
import 'package:healthee/shared/usual_range.dart';
import 'package:healthee/shared/v02/reading_state.dart';

/// The strip.
class SignalSpark extends StatelessWidget {
  /// [values] is oldest first; null is an unmeasured slot.
  const SignalSpark({
    required this.values,
    required this.state,
    this.usual,
    this.height = 32,
    this.progress = 1,
    super.key,
  });

  /// Fewer measured values than this draws the empty strip.
  static const int minMeasured = 2;

  /// The series, oldest first.
  final List<double?> values;

  /// The newest dot's state.
  final ReadingState state;

  /// The usual range behind the line, or null before there is one.
  final UsualRange? usual;

  /// Height of the strip.
  final double height;

  /// 0 to 1 from a reveal; the line is drawn left to right.
  final double progress;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: SignalSparkPainter(
          values: values,
          state: state,
          usual: usual,
          progress: progress,
          colors: context.colors,
          family: context.family,
        ),
      ),
    ),
  );
}

/// Paints [SignalSpark].
class SignalSparkPainter extends CustomPainter {
  /// Everything it draws is given.
  SignalSparkPainter({
    required this.values,
    required this.state,
    required this.usual,
    required this.progress,
    required this.colors,
    required this.family,
  });

  final List<double?> values;
  final ReadingState state;
  final UsualRange? usual;
  final double progress;
  final HealtheeColors colors;
  final Color family;

  /// Line weight.
  static const double stroke = 1.75;

  /// The newest dot's radius.
  static const double dotRadius = 2.75;

  /// Room above and below the plot so the dot and the stroke are not clipped.
  static const double inset = 4;

  /// The band's corner.
  static const double bandRadius = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final present = <double>[for (final v in values) ?v];
    if (present.length < SignalSpark.minMeasured) {
      paintHatch(
        canvas,
        Rect.fromLTWH(0, size.height / 2 - 1, size.width, 2),
        ink: colors.ink3,
        radius: 1,
      );
      return;
    }
    var lo = present.reduce((a, b) => a < b ? a : b);
    var hi = present.reduce((a, b) => a > b ? a : b);
    final band = usual;
    if (band != null) {
      lo = lo < band.low ? lo : band.low;
      hi = hi > band.high ? hi : band.high;
    }
    final span = hi - lo == 0 ? 1.0 : hi - lo;
    double y(double v) =>
        size.height - inset - (v - lo) / span * (size.height - 2 * inset);
    double x(int i) => values.length < 2
        ? size.width / 2
        : dotRadius + i / (values.length - 1) * (size.width - 2 * dotRadius);
    if (band != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(0, y(band.high), size.width, y(band.low)),
          const Radius.circular(bandRadius),
        ),
        Paint()..color = colors.band,
      );
    }
    final line = Paint()
      ..color = family
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas
      ..save()
      ..clipRect(
        Rect.fromLTWH(0, 0, size.width * progress.clamp(0, 1), size.height),
      );
    Path? run;
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == null || !v.isFinite) {
        if (run != null) {
          canvas.drawPath(run, line);
        }
        run = null;
        continue;
      }
      if (run == null) {
        run = Path()..moveTo(x(i), y(v));
      } else {
        run.lineTo(x(i), y(v));
      }
    }
    if (run != null) {
      canvas.drawPath(run, line);
    }
    canvas.restore();
    final last = values.isEmpty ? null : values.last;
    if (last != null && last.isFinite && progress >= 1) {
      canvas.drawCircle(
        Offset(x(values.length - 1), y(last)),
        dotRadius,
        Paint()..color = state.dotIn(colors),
      );
    }
  }

  @override
  bool shouldRepaint(SignalSparkPainter old) =>
      old.progress != progress ||
      old.state != state ||
      old.values != values ||
      old.usual != usual ||
      old.family != family ||
      old.colors != colors;
}
