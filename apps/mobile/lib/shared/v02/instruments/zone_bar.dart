/// The zone bar: a reading against a scale, drawn as ten rounded segments in
/// the family hue, a marker with the value above it, and an optional target.
/// The geometry and the shading ramp live in `zone_bar_geometry.dart`.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/shared/v02/instruments/zone_bar_geometry.dart';

export 'package:healthee/shared/v02/instruments/zone_bar_geometry.dart';

/// The bar. Wrap it in a [ToneScope] to choose the family hue.
class ZoneBar extends StatelessWidget {
  const ZoneBar({
    required this.value,
    required this.low,
    required this.high,
    required this.shape,
    required this.valueText,
    required this.unitText,
    this.target,
    this.targetLabel,
    this.lowLabel,
    this.highLabel,
    this.progress = 1,
    super.key,
  });

  /// Identifies the plot for tests.
  static const Key plotKey = ValueKey<String>('zone-bar-plot');

  /// The reading, in the scale's own units.
  final double value;

  /// The scale's low end.
  final double low;

  /// The scale's high end.
  final double high;

  /// How goodness varies along the scale.
  final ZoneShape shape;

  /// The target, in the scale's units.
  final double? target;

  /// The words under the target tick.
  final String? targetLabel;

  /// The reading as text, above the marker.
  final String valueText;

  /// Its unit.
  final String unitText;

  /// The low end label.
  final String? lowLabel;

  /// The high end label.
  final String? highLabel;

  /// 0 to 1: the marker slides in from the low end. Segments never animate.
  final double progress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final geometry = ZoneBarGeometry.compute(
          width: constraints.maxWidth,
          value: value,
          low: low,
          high: high,
          shape: shape,
          target: target,
          targetLabel: targetLabel,
          valueText: valueText,
          unitText: unitText,
          lowLabel: lowLabel,
          highLabel: highLabel,
          progress: progress,
          valueStyle: TypeLadder.title2.copyWith(color: colors.ink),
          unitStyle: TypeLadder.callout.copyWith(color: colors.ink3),
          labelStyle: TypeLadder.micro.copyWith(color: colors.ink3),
          textScaler: MediaQuery.textScalerOf(context),
          dpr: MediaQuery.devicePixelRatioOf(context),
        );
        return SizedBox(
          width: constraints.maxWidth,
          height: geometry.height,
          child: CustomPaint(
            key: plotKey,
            painter: ZoneBarPainter(
              geometry: geometry,
              family: context.family,
              ink: colors.ink,
              tick: colors.ink2,
            ),
          ),
        );
      },
    );
  }
}

/// Paints a [ZoneBarGeometry].
class ZoneBarPainter extends CustomPainter {
  ZoneBarPainter({
    required this.geometry,
    required this.family,
    required this.ink,
    required this.tick,
  });

  /// What to draw.
  final ZoneBarGeometry geometry;

  /// The segments' hue.
  final Color family;

  /// The marker's colour.
  final Color ink;

  /// The target tick's colour.
  final Color tick;

  @override
  void paint(Canvas canvas, Size size) {
    final g = geometry;
    final fill = Paint();
    for (var i = 0; i < g.segments.length; i++) {
      fill.color = family.withValues(alpha: g.alphas[i]);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          g.segments[i],
          const Radius.circular(kZoneRadius),
        ),
        fill,
      );
    }
    final barCentre = g.barTop + kZoneBarHeight / 2;
    if (g.tickX case final double x) {
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(x, barCentre),
          width: kZoneTickWidth,
          height: kZoneTickHeight,
        ),
        fill..color = tick,
      );
    }
    final tip = g.barTop - kZoneMarkerLift;
    canvas.drawPath(
      Path()
        ..moveTo(g.markerX - kZoneMarkerWidth / 2, tip - kZoneMarkerHeight)
        ..lineTo(g.markerX + kZoneMarkerWidth / 2, tip - kZoneMarkerHeight)
        ..lineTo(g.markerX, tip)
        ..close(),
      fill..color = ink,
    );
    g.valuePainter.paint(canvas, g.valueOffset);
    g.targetPainter?.paint(canvas, g.targetOffset!);
    g.lowPainter?.paint(canvas, g.lowOffset);
    g.highPainter?.paint(canvas, g.highOffset);
  }

  // The geometry is rebuilt with every layout pass and is cheap to paint, so
  // there is no field-by-field comparison to get wrong.
  @override
  bool shouldRepaint(ZoneBarPainter old) => true;
}
