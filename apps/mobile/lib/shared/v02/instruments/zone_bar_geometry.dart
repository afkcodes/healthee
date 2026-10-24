/// A reading against a scale: ten rounded segments in one family hue that fade
/// from faint to strong toward "better", a marker above the reading with its
/// value and unit, an optional target tick, and small end labels.
///
/// ## The shading is visual only
///
/// Each segment's opacity says how good that stretch of the scale is, using a
/// plain ramp ([ZoneShape.rising]) or a ramp that peaks at the target and falls
/// twice as fast on the high side ([ZoneShape.peak]). It is a drawing aid. The
/// hazard maths that turns a reading into years lives on the server; nothing
/// here re-implements it, and the segments are not a risk curve.
///
/// ## Pixel geometry
///
/// Segment left edges (and right edges) snap to whole physical pixels, so the
/// ten segments read as evenly spaced and crisp at any device pixel ratio.
/// Heights are measured from the text at the user's text scale, so nothing
/// clips when the system font grows.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:healthee/shared/format/age_lever_format.dart';

/// How "good" varies along the scale.
enum ZoneShape {
  /// Higher is better all the way: the ramp rises left to right.
  rising,

  /// Best at the target; worse on both sides, twice as fast on the high side.
  peak,
}

/// Segments in the bar.
const int kZoneSegments = 10;

/// The gap between segments, logical px.
const double kZoneGap = 3;

/// The bar's height, logical px.
const double kZoneBarHeight = 6;

/// The segment corner radius, logical px.
const double kZoneRadius = 3;

/// The marker's width, logical px.
const double kZoneMarkerWidth = 9;

/// The marker's height, logical px.
const double kZoneMarkerHeight = 6;

/// How far the marker's tip stops above the bar, logical px.
const double kZoneMarkerLift = 3;

/// The space between the value label and the marker, logical px.
const double kZoneValueGap = 2;

/// The target tick's width, logical px.
const double kZoneTickWidth = 1.5;

/// The target tick's height, logical px.
const double kZoneTickHeight = 14;

/// The space between the tick's foot and the labels under it, logical px.
const double kZoneLabelGap = 3;

/// An end label within this many px of the target label is dropped.
const double kZoneLabelClearance = 12;

/// The faintest segment's opacity.
const double kZoneAlphaFloor = 0.16;

/// The strongest segment's opacity is the floor plus this.
const double kZoneAlphaSpan = 0.84;

/// The exponent that shapes the opacity ramp.
const double kZoneAlphaGamma = 1.3;

/// VO2max scale, mL/kg/min.
const double kVo2ScaleLow = 20;

/// VO2max scale, mL/kg/min.
const double kVo2ScaleHigh = 60;

/// Sleep duration scale, hours.
const double kSleepScaleLow = 4;

/// Sleep duration scale, hours.
const double kSleepScaleHigh = 10;

/// How good a point on the scale is, 0 to 1. Visual only.
double zoneGoodness({
  required double x,
  required double low,
  required double high,
  required ZoneShape shape,
  double? target,
}) {
  final double g;
  if (shape == ZoneShape.rising || target == null) {
    g = (x - low) / (high - low);
  } else if (x <= target) {
    g = 1 - (target - x) / (target - low);
  } else {
    g = 1 - 2 * (x - target) / (target - low);
  }
  return g.clamp(0.0, 1.0);
}

/// A segment's opacity for goodness [g].
double zoneAlpha(double g) =>
    kZoneAlphaFloor + kZoneAlphaSpan * math.pow(g, kZoneAlphaGamma);

/// The scale widened in whole units, only as far as needed to hold [value].
({double low, double high}) zoneDomain(double low, double high, double value) =>
    (
      low: math.min(low, value.floorToDouble()),
      high: math.max(high, value.ceilToDouble()),
    );

/// Where everything sits, in logical px. Pure: built from numbers and styles.
class ZoneBarGeometry {
  ZoneBarGeometry._({
    required this.width,
    required this.height,
    required this.barTop,
    required this.segments,
    required this.alphas,
    required this.markerX,
    required this.valuePainter,
    required this.valueOffset,
    required this.tickX,
    required this.targetPainter,
    required this.targetOffset,
    required this.lowPainter,
    required this.lowOffset,
    required this.highPainter,
    required this.highOffset,
    required this.domainLow,
    required this.domainHigh,
  });

  /// Lays the bar out inside [width].
  factory ZoneBarGeometry.compute({
    required double width,
    required double value,
    required double low,
    required double high,
    required ZoneShape shape,
    required String valueText,
    required String unitText,
    required TextStyle valueStyle,
    required TextStyle unitStyle,
    required TextStyle labelStyle,
    required TextScaler textScaler,
    required double dpr,
    double? target,
    String? targetLabel,
    String? lowLabel,
    String? highLabel,
    double progress = 1,
  }) {
    final domain = zoneDomain(low, high, value);
    final span = domain.high - domain.low;
    double xOf(double v) => (v - domain.low) / span * width;

    TextPainter paint(InlineSpan span) => TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout();

    final valuePainter = paint(
      TextSpan(
        style: valueStyle,
        children: <InlineSpan>[
          TextSpan(text: valueText),
          TextSpan(text: '$kNbsp$unitText', style: unitStyle),
        ],
      ),
    );
    final barTop =
        valuePainter.height +
        kZoneValueGap +
        kZoneMarkerHeight +
        kZoneMarkerLift;
    final barCentre = barTop + kZoneBarHeight / 2;

    final shown = domain.low + (value - domain.low) * progress.clamp(0.0, 1.0);
    final markerX = xOf(shown);
    final valueOffset = Offset(
      (markerX - valuePainter.width / 2).clamp(
        0.0,
        math.max(0.0, width - valuePainter.width),
      ),
      0,
    );

    TextPainter? label(String? text) =>
        text == null ? null : paint(TextSpan(text: text, style: labelStyle));
    final labelTop = barCentre + kZoneTickHeight / 2 + kZoneLabelGap;
    final targetPainter = target == null ? null : label(targetLabel);
    final tickX = target == null ? null : xOf(target);
    Offset? targetOffset;
    if (targetPainter != null && tickX != null) {
      targetOffset = Offset(
        (tickX - targetPainter.width / 2).clamp(
          0.0,
          math.max(0.0, width - targetPainter.width),
        ),
        labelTop,
      );
    }
    bool clear(TextPainter p, Offset o) {
      if (targetPainter == null || targetOffset == null) {
        return true;
      }
      final gap = o.dx < targetOffset.dx
          ? targetOffset.dx - (o.dx + p.width)
          : o.dx - (targetOffset.dx + targetPainter.width);
      return gap >= kZoneLabelClearance;
    }

    var lowPainter = label(lowLabel);
    var lowOffset = Offset(0, labelTop);
    if (lowPainter != null && !clear(lowPainter, lowOffset)) {
      lowPainter = null;
    }
    var highPainter = label(highLabel);
    var highOffset = Offset(
      highPainter == null ? 0 : width - highPainter.width,
      labelTop,
    );
    if (highPainter != null && !clear(highPainter, highOffset)) {
      highPainter = null;
      highOffset = Offset.zero;
    }
    if (lowPainter == null) {
      lowOffset = Offset.zero;
    }

    final segW = (width - (kZoneSegments - 1) * kZoneGap) / kZoneSegments;
    double snap(double v) => (v * dpr).roundToDouble() / dpr;
    final segments = <Rect>[];
    final alphas = <double>[];
    for (var i = 0; i < kZoneSegments; i++) {
      final left = i * (segW + kZoneGap);
      final l = snap(left);
      final r = snap(left + segW);
      segments.add(Rect.fromLTRB(l, barTop, r, barTop + kZoneBarHeight));
      final centre = domain.low + (left + segW / 2) / width * span;
      alphas.add(
        zoneAlpha(
          zoneGoodness(
            x: centre,
            low: domain.low,
            high: domain.high,
            shape: shape,
            target: target,
          ),
        ),
      );
    }

    final labelHeights = <double>[
      for (final p in <TextPainter?>[targetPainter, lowPainter, highPainter])
        if (p != null) p.height,
    ];
    final bottom = labelHeights.isEmpty
        ? barCentre + kZoneTickHeight / 2
        : labelTop + labelHeights.reduce(math.max);
    return ZoneBarGeometry._(
      width: width,
      height: bottom,
      barTop: barTop,
      segments: segments,
      alphas: alphas,
      markerX: markerX,
      valuePainter: valuePainter,
      valueOffset: valueOffset,
      tickX: tickX,
      targetPainter: targetPainter,
      targetOffset: targetOffset,
      lowPainter: lowPainter,
      lowOffset: lowOffset,
      highPainter: highPainter,
      highOffset: highOffset,
      domainLow: domain.low,
      domainHigh: domain.high,
    );
  }

  /// The bar's width, logical px.
  final double width;

  /// The whole plot's height, logical px.
  final double height;

  /// The top edge of the segments, logical px.
  final double barTop;

  /// The ten segments.
  final List<Rect> segments;

  /// Each segment's opacity.
  final List<double> alphas;

  /// The marker's centre x, after the reveal's progress.
  final double markerX;

  /// The value and unit.
  final TextPainter valuePainter;

  /// Where [valuePainter] is drawn.
  final Offset valueOffset;

  /// The target tick's centre x, or null.
  final double? tickX;

  /// The target label, or null.
  final TextPainter? targetPainter;

  /// Where [targetPainter] is drawn.
  final Offset? targetOffset;

  /// The low end label, or null when absent or dropped.
  final TextPainter? lowPainter;

  /// Where [lowPainter] is drawn.
  final Offset lowOffset;

  /// The high end label, or null when absent or dropped.
  final TextPainter? highPainter;

  /// Where [highPainter] is drawn.
  final Offset highOffset;

  /// The scale's low end after widening.
  final double domainLow;

  /// The scale's high end after widening.
  final double domainHigh;
}
