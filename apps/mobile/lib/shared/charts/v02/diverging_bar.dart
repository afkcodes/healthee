/// A correlation, drawn from zero.
///
/// The colour kit's correlation bar: it diverges from a centre tick, **moving
/// together is Strain blue, moving opposite is Activity orange**, and neither
/// is good or bad. A strong negative is not an alarm; it is a direction.
/// `r` runs −1 to +1 and a bar's length is its magnitude.
///
/// A bar that is NOT a correlation, the biological-age years for one, passes a
/// [DivergingBar.state]: both sides then take that state's colour (the verdict
/// the number earned) instead of the together and opposite hues.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/instrument_hues.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/shared/v02/reading_state.dart';

/// The bar.
class DivergingBar extends StatelessWidget {
  /// [r] is the correlation, clamped to −1 to +1.
  const DivergingBar({required this.r, this.height = 6, this.state, super.key});

  /// The coefficient, or any value already scaled to −1 to +1.
  final double r;

  /// The verdict colour for a bar that is not a correlation; null draws the
  /// together and opposite hues.
  final ReadingState? state;

  /// Track thickness.
  final double height;

  @override
  Widget build(BuildContext context) {
    final hues = context.hues;
    final verdict = state?.dotIn(context.colors);
    return SizedBox(
      height: height + 6,
      width: double.infinity,
      child: CustomPaint(
        painter: DivergingBarPainter(
          r: r.clamp(-1.0, 1.0),
          thickness: height,
          together: verdict ?? hues.strain,
          opposite: verdict ?? hues.movement,
          colors: context.colors,
        ),
      ),
    );
  }
}

/// Paints [DivergingBar].
class DivergingBarPainter extends CustomPainter {
  /// Everything it draws is given.
  DivergingBarPainter({
    required this.r,
    required this.thickness,
    required this.together,
    required this.opposite,
    required this.colors,
  });

  final double r;
  final double thickness;
  final Color together;
  final Color opposite;
  final HealtheeColors colors;

  /// The centre tick's width.
  static const double tick = 2;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.width / 2;
    final top = (size.height - thickness) / 2;
    final radius = Radius.circular(thickness / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, top, size.width, thickness),
        radius,
      ),
      Paint()..color = colors.surface2,
    );
    final length = r.abs() * mid;
    if (length > 0) {
      final rect = r > 0
          ? Rect.fromLTWH(mid, top, length, thickness)
          : Rect.fromLTWH(mid - length, top, length, thickness);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          rect,
          topRight: r > 0 ? radius : Radius.zero,
          bottomRight: r > 0 ? radius : Radius.zero,
          topLeft: r < 0 ? radius : Radius.zero,
          bottomLeft: r < 0 ? radius : Radius.zero,
        ),
        Paint()..color = r > 0 ? together : opposite,
      );
    }
    canvas.drawRect(
      Rect.fromLTWH(mid - tick / 2, top - 3, tick, thickness + 6),
      Paint()..color = colors.ink2,
    );
  }

  @override
  bool shouldRepaint(DivergingBarPainter old) =>
      old.r != r ||
      old.together != together ||
      old.opposite != opposite ||
      old.colors != colors;
}
