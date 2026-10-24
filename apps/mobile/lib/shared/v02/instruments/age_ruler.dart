/// Your biological age against your actual age, drawn as a ruler: fine ticks
/// every quarter year, a needle at the estimate, a span lit in the verdict
/// colour between the estimate and your actual age, and a small triangle
/// marking the actual age.
///
/// Every tick is a filled rectangle on a whole physical pixel and every gap is
/// a whole number of physical pixels, so the ruler reads as evenly spaced and
/// crisp at any device pixel ratio. The scale runs eight years either side of
/// your actual age, widened in whole years to keep the estimate on it.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/shared/format/age_lever_format.dart';
import 'package:healthee/shared/v02/key_number_card.dart';

/// Years either side of the actual age on the base scale.
const double kAgeRulerSpan = 8;

/// Ticks per year: one every quarter year.
const int kAgeRulerTicksPerYear = 4;

/// A whole-year tick's height, logical px.
const double kAgeRulerYearTick = 16;

/// A quarter-year tick's height, logical px.
const double kAgeRulerQuarterTick = 10;

/// A tick's width, logical px, before snapping to whole physical pixels.
const double kAgeRulerTickWidth = 1;

/// The needle's width, logical px, before snapping.
const double kAgeRulerNeedleWidth = 3;

/// The needle's height, logical px.
const double kAgeRulerNeedleHeight = 30;

/// The needle's corner radius, logical px.
const double kAgeRulerNeedleRadius = 1.5;

/// The bg-coloured gap cut into the ticks on each side of the needle.
const double kAgeRulerNeedleGap = 2;

/// The actual-age triangle's width, logical px.
const double kAgeRulerTriangleWidth = 8;

/// The actual-age triangle's height, logical px.
const double kAgeRulerTriangleHeight = 6;

/// The gap between the needle's foot and the triangle's apex, logical px.
const double kAgeRulerTriangleGap = 3;

/// Tick ink opacity on a light theme.
const double kAgeRulerTickAlphaLight = 0.24;

/// Tick ink opacity on a dark theme.
const double kAgeRulerTickAlphaDark = 0.22;

/// The clear space a label keeps from its neighbours, logical px.
const double kAgeRulerLabelClearance = 8;

/// The vertical centre of the ticks, from the top, logical px.
const double kAgeRulerAxisY = 44;

/// The top of the "your age" and end-value row, logical px.
const double kAgeRulerBottomRowY = 72;

/// The ruler.
class AgeRuler extends StatelessWidget {
  const AgeRuler({
    required this.estimate,
    required this.actual,
    this.progress = 1,
    this.semanticLabel,
    this.excludeFromSemantics = false,
    super.key,
  });

  /// Identifies the plot for tests.
  static const Key plotKey = ValueKey<String>('age-ruler-plot');

  /// The whole ruler's height: the end labels, ticks and the labels under them.
  static const double height = 92;

  /// Your biological age, in years.
  final double estimate;

  /// Your age, in years.
  final double actual;

  /// 0 to 1 from the reveal: the needle slides from the actual age to the
  /// estimate and the lit span grows with it. The grey ticks never animate.
  final double progress;

  /// Overrides the spoken label.
  final String? semanticLabel;

  /// True inside a hero that owns the label.
  final bool excludeFromSemantics;

  @override
  Widget build(BuildContext context) {
    final scale = AgeRulerScale(estimate: estimate, actual: actual);
    final colors = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final delta = estimate - actual;
    final verdict = switch (verdictForDelta(delta)) {
      VerdictTone.better => colors.fav,
      VerdictTone.worse => colors.alert,
      VerdictTone.neutral => colors.ink2,
    };
    final plot = SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        key: plotKey,
        painter: _RulerPainter(
          scale: scale,
          actual: actual,
          shown: actual + delta * progress.clamp(0, 1),
          dpr: MediaQuery.devicePixelRatioOf(context),
          textScaler: MediaQuery.textScalerOf(context),
          ink: colors.ink,
          ink2: colors.ink2,
          ink3: colors.ink3,
          bg: colors.bg,
          verdict: verdict,
          tick: colors.ink.withValues(
            alpha: dark ? kAgeRulerTickAlphaDark : kAgeRulerTickAlphaLight,
          ),
        ),
      ),
    );
    if (excludeFromSemantics) return ExcludeSemantics(child: plot);
    return Semantics(
      label:
          semanticLabel ??
          'Biological age ${formatAge(estimate)} on a scale from '
              '${formatAge(scale.low)} to ${formatAge(scale.high)}. '
              'Your actual age is ${formatAge(actual)}.',
      child: ExcludeSemantics(child: plot),
    );
  }
}

/// A whole number without decimals, else one decimal.
String formatAge(double years) {
  final text = years.toStringAsFixed(1);
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}

/// The ruler's domain in whole years.
class AgeRulerScale {
  const AgeRulerScale._(this.low, this.high);

  /// The base domain, widened in whole years when the estimate overruns an
  /// edge, and again so it never sits on the very edge.
  factory AgeRulerScale({required double estimate, required double actual}) {
    var low = (actual - kAgeRulerSpan).floorToDouble();
    var high = (actual + kAgeRulerSpan).ceilToDouble();
    if (estimate < low) {
      low = estimate.floorToDouble();
      if (estimate - low < 1) low -= 1;
    }
    if (estimate > high) {
      high = estimate.ceilToDouble();
      if (high - estimate < 1) high += 1;
    }
    return AgeRulerScale._(low, high);
  }

  /// The left end, whole years.
  final double low;

  /// The right end, whole years.
  final double high;

  /// Gaps between ticks.
  int get intervals => ((high - low) * kAgeRulerTicksPerYear).round();
}

/// Where the ticks sit for one width and pixel ratio.
class AgeRulerGeometry {
  AgeRulerGeometry({
    required this.scale,
    required double width,
    required this.dpr,
  }) {
    final n = scale.intervals;
    tickWidth = math.max(1, (kAgeRulerTickWidth * dpr).round()) / dpr;
    // The last tick has a width of its own, so it is inside the content width.
    spacing = ((width - tickWidth) * dpr / n).floorToDouble() / dpr;
    left = ((width - spacing * n - tickWidth) / 2 * dpr).round() / dpr;
  }

  /// The domain.
  final AgeRulerScale scale;

  /// Device pixels per logical pixel.
  final double dpr;

  /// Logical gap between ticks: a whole number of physical pixels.
  late final double spacing;

  /// The first tick's left edge.
  late final double left;

  /// A tick's width: a whole number of physical pixels.
  late final double tickWidth;

  /// The i-th tick's left edge.
  double tickX(int i) => left + i * spacing;

  /// The centre of the tick at [years], exact rather than rounded.
  double centreOf(double years) =>
      left +
      (years - scale.low) * kAgeRulerTicksPerYear * spacing +
      tickWidth / 2;

  /// The tick index nearest [years], to the quarter.
  int indexOf(double years) =>
      ((years - scale.low) * kAgeRulerTicksPerYear).round();

  /// [v] on the nearest whole physical pixel.
  double snap(double v) => (v * dpr).round() / dpr;
}

class _RulerPainter extends CustomPainter {
  _RulerPainter({
    required this.scale,
    required this.actual,
    required this.shown,
    required this.dpr,
    required this.textScaler,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.bg,
    required this.verdict,
    required this.tick,
  });

  final AgeRulerScale scale;
  final double actual;

  /// The needle's age: the estimate once the reveal is done.
  final double shown;
  final double dpr;
  final TextScaler textScaler;
  final Color ink;
  final Color ink2;
  final Color ink3;
  final Color bg;
  final Color verdict;
  final Color tick;

  @override
  void paint(Canvas canvas, Size size) {
    final geo = AgeRulerGeometry(scale: scale, width: size.width, dpr: dpr);
    final actualAt = geo.centreOf(actual);
    final a = geo.indexOf(actual);
    final s = geo.indexOf(shown);
    final litFrom = math.min(a, s);
    final litTo = math.max(a, s);
    for (var i = 0; i <= scale.intervals; i++) {
      final tall = i % kAgeRulerTicksPerYear == 0;
      final h = geo.snap(tall ? kAgeRulerYearTick : kAgeRulerQuarterTick);
      canvas.drawRect(
        Rect.fromLTWH(
          geo.tickX(i),
          geo.snap(kAgeRulerAxisY - h / 2),
          geo.tickWidth,
          h,
        ),
        Paint()..color = i >= litFrom && i <= litTo ? verdict : tick,
      );
    }
    _needle(canvas, geo, geo.centreOf(shown));
    const apex =
        kAgeRulerAxisY + kAgeRulerNeedleHeight / 2 + kAgeRulerTriangleGap;
    const half = kAgeRulerTriangleWidth / 2;
    canvas.drawPath(
      Path()
        ..moveTo(actualAt, apex)
        ..lineTo(actualAt - half, apex + kAgeRulerTriangleHeight)
        ..lineTo(actualAt + half, apex + kAgeRulerTriangleHeight)
        ..close(),
      Paint()..color = ink2,
    );
    _labels(canvas, size, geo, actualAt);
  }

  void _needle(Canvas canvas, AgeRulerGeometry geo, double centre) {
    final w = geo.snap(kAgeRulerNeedleWidth);
    final left = geo.snap(centre - w / 2);
    final top = geo.snap(kAgeRulerAxisY - kAgeRulerNeedleHeight / 2);
    canvas.drawRect(
      Rect.fromLTWH(
        left - kAgeRulerNeedleGap,
        top,
        w + 2 * kAgeRulerNeedleGap,
        kAgeRulerNeedleHeight,
      ),
      Paint()..color = bg,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, w, kAgeRulerNeedleHeight),
        const Radius.circular(kAgeRulerNeedleRadius),
      ),
      Paint()..color = ink,
    );
  }

  TextPainter _measure(String text, TextStyle style, Color colour) =>
      TextPainter(
        text: TextSpan(
          text: text,
          style: style.copyWith(color: colour),
        ),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
        maxLines: 1,
      )..layout();

  void _labels(Canvas canvas, Size size, AgeRulerGeometry geo, double at) {
    final leftEdge = geo.left;
    final rightEdge = geo.left + geo.spacing * scale.intervals + geo.tickWidth;
    final you = _measure(
      '${formatAge(actual)} · your age',
      TypeLadder.caption,
      ink2,
    );
    final youLeft = math.min(
      math.max(0.0, at - you.width / 2),
      math.max(0.0, size.width - you.width),
    );
    final youBox = Rect.fromLTWH(
      youLeft,
      kAgeRulerBottomRowY,
      you.width,
      you.height,
    );
    final younger = _measure('Younger', TypeLadder.caption, ink3);
    final older = _measure('Older', TypeLadder.caption, ink3);
    if (leftEdge + younger.width + kAgeRulerLabelClearance <=
        rightEdge - older.width) {
      younger.paint(canvas, Offset(leftEdge, 0));
      older.paint(canvas, Offset(rightEdge - older.width, 0));
    }
    you.paint(canvas, youBox.topLeft);
    final lowText = _measure(formatAge(scale.low), TypeLadder.micro, ink3);
    final highText = _measure(formatAge(scale.high), TypeLadder.micro, ink3);
    // Micro text shares the caption's baseline, so it sits lower by the
    // difference in their line heights.
    final rowY = kAgeRulerBottomRowY + you.height - lowText.height;
    final lowBox = Rect.fromLTWH(leftEdge, rowY, lowText.width, lowText.height);
    final highBox = Rect.fromLTWH(
      rightEdge - highText.width,
      rowY,
      highText.width,
      highText.height,
    );
    final keepOut = youBox.inflate(kAgeRulerLabelClearance);
    if (!keepOut.overlaps(lowBox)) lowText.paint(canvas, lowBox.topLeft);
    if (!keepOut.overlaps(highBox)) highText.paint(canvas, highBox.topLeft);
  }

  @override
  bool shouldRepaint(_RulerPainter old) =>
      old.scale.low != scale.low ||
      old.scale.high != scale.high ||
      old.actual != actual ||
      old.shown != shown ||
      old.dpr != dpr ||
      old.textScaler != textScaler ||
      old.ink != ink ||
      old.ink2 != ink2 ||
      old.ink3 != ink3 ||
      old.bg != bg ||
      old.verdict != verdict ||
      old.tick != tick;
}
