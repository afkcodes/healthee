/// The look of a reading that is not there: diagonal hatch, never a colour.
///
/// The colour kit's no-data rule: missing data is hatched grey with a dash, a
/// gap stays a gap, and nothing is interpolated or coloured. This is the one
/// painter for it, so a chip, a bar and a sparkline slot cannot each invent
/// their own idea of "empty".
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tokens.dart';

/// Fills [rect] (clipped to [radius]) with diagonal lines in [ink].
void paintHatch(
  Canvas canvas,
  Rect rect, {
  required Color ink,
  double radius = 3,
  double gap = 4,
  double stroke = 1,
}) {
  canvas
    ..save()
    ..clipRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
  final paint = Paint()
    ..color = ink
    ..strokeWidth = stroke;
  for (var x = rect.left - rect.height; x < rect.right; x += gap) {
    canvas.drawLine(
      Offset(x, rect.bottom),
      Offset(x + rect.height, rect.top),
      paint,
    );
  }
  canvas.restore();
}

/// A full-width hatched strip: the empty state of a bar that has no reading.
class HatchStrip extends StatelessWidget {
  /// A strip [height] tall.
  const HatchStrip({this.height = 6, super.key});

  /// Strip thickness.
  final double height;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      height: height + 6,
      width: double.infinity,
      child: CustomPaint(
        painter: _HatchStripPainter(context.colors.ink3, height),
      ),
    ),
  );
}

class _HatchStripPainter extends CustomPainter {
  const _HatchStripPainter(this.ink, this.thickness);

  final Color ink;
  final double thickness;

  @override
  void paint(Canvas canvas, Size size) => paintHatch(
    canvas,
    Rect.fromLTWH(0, (size.height - thickness) / 2, size.width, thickness),
    ink: ink,
    radius: thickness / 2,
  );

  @override
  bool shouldRepaint(_HatchStripPainter old) =>
      old.ink != ink || old.thickness != thickness;
}
