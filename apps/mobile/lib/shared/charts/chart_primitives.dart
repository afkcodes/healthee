/// The two things every ported chart shares: a smooth path, and a tooltip.
///
/// **Ported verbatim** from `~/projects/healthee-legacy/app/lib/ui/
/// instrument_charts.dart` (`smoothPath`, `_drawTooltip`, `_hm`). The geometry
/// is unchanged to the coefficient — these are proven against real payloads and
/// a "tidier" Catmull-Rom is a different curve through the same points.
///
/// What DID change is ownership of the animation. The legacy charts each mixed
/// in `_Reveal`, which built an `AnimationController` in the widget's own
/// `State` and ran it on `initState`. Under `ListView.builder` that is precisely
/// the replay-on-scroll bug `CLAUDE.md` names as a hard rule: the builder
/// destroys an item's element when it leaves the viewport and rebuilds it on the
/// way back, so `initState` runs again and the chart animates again, every time.
///
/// So every chart here takes `progress` as a **parameter** and owns no ticker.
/// The screen wraps it in `RevealOnce`, which asks a registry that outlives the
/// list item whether this chart has been seen — first build animates, every
/// build after paints the finished frame with no controller at all.
///
/// Interaction stayed where it was: a chart that can be scrubbed still holds its
/// own touch index in `State`, because that IS per-instance ephemeral state and
/// losing it on scroll is correct.
library;

import 'package:flutter/material.dart';

/// Catmull-Rom → cubic-bézier smooth path through [points].
///
/// Ported verbatim. The `/6` coefficients are the Catmull-Rom tension the legacy
/// charts were tuned against; they are not a rounding of something neater.
Path smoothPath(List<Offset> points) {
  final path = Path();
  if (points.length < 2) {
    return path;
  }
  path.moveTo(points[0].dx, points[0].dy);
  for (var i = 0; i < points.length - 1; i++) {
    final p0 = i > 0 ? points[i - 1] : points[i];
    final p1 = points[i];
    final p2 = points[i + 1];
    final p3 = i + 2 < points.length ? points[i + 2] : p2;
    path.cubicTo(
      p1.dx + (p2.dx - p0.dx) / 6,
      p1.dy + (p2.dy - p0.dy) / 6,
      p2.dx - (p3.dx - p1.dx) / 6,
      p2.dy - (p3.dy - p1.dy) / 6,
      p2.dx,
      p2.dy,
    );
  }
  return path;
}

/// The tooltip bubble interactive charts share — rounded, bordered, pinned to
/// the top of the plot and clamped around [anchorX].
///
/// Ported verbatim from `_drawTooltip`. Callers draw their own crosshair,
/// because the geometry differs per chart.
void drawChartTooltip(
  Canvas canvas,
  Size size,
  String text, {
  required double anchorX,
  required Color background,
  required Color border,
  required TextStyle style,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  const pad = 7.0;
  final width = painter.width + pad * 2;
  final height = painter.height + pad;
  final left = (anchorX - width / 2).clamp(0.0, size.width - width);
  final box = RRect.fromRectAndRadius(
    Rect.fromLTWH(left, 0, width, height),
    const Radius.circular(7),
  );
  canvas.drawRRect(box, Paint()..color = background);
  canvas.drawRRect(
    box,
    Paint()
      ..color = border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1,
  );
  painter.paint(canvas, Offset(left + pad, (height - painter.height) / 2));
}

/// [color] at [progress] through a reveal, without destroying its own alpha.
///
/// Exists because getting this wrong is invisible until one palette entry is
/// translucent. `h_hypnogram.dart` used to fade its bands with
/// `color.withValues(alpha: progress)`, which REPLACES the alpha — fine while
/// every sleep stage was an opaque accent tint, and wrong the moment `awake`
/// became `HealtheeColors.line`, a 10% hairline chosen precisely so the absence
/// of sleep is the quietest thing on the chart. At progress 1 it became the
/// loudest.
///
/// So the rule is a named function rather than a line every painter retypes: a
/// reveal SCALES what the token already said, it does not overrule it.
Color revealed(Color color, double progress) =>
    color.withValues(alpha: color.a * progress.clamp(0.0, 1.0));

/// Lays out one short label in [style]. Every painter here needs it.
TextPainter chartLabel(String text, TextStyle style) => TextPainter(
  text: TextSpan(text: text, style: style),
  textDirection: TextDirection.ltr,
)..layout();
