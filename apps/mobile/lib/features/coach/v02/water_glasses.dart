/// The row of glasses under the water headline.
///
/// Drawn with a small painter, no assets. Filled glasses take the Body hue,
/// the next one is a dashed outline in it, the rest are plain outlines. Only
/// the next glass and the full ones react to a tap.
library;

import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/data/basics/water/water_day.dart';
import 'package:healthee/data/basics/water/water_settings.dart';

/// How a glass is drawn.
enum GlassState {
  /// Logged.
  full,

  /// The one a tap would log.
  next,

  /// Later ones, not tappable.
  empty,
}

/// The semantics label for glass [number] (from 1).
String glassLabel(int number, GlassState state, {String? time}) =>
    switch (state) {
      GlassState.full =>
        'Glass $number, full${time == null ? '' : ', logged $time'}. '
            'Double tap to undo the last entry',
      GlassState.next =>
        'Glass $number, empty. Double tap to log $kGlassMl millilitres',
      GlassState.empty => 'Glass $number, empty',
    };

/// The glasses for [day], [target] being the owner's count.
class WaterGlasses extends StatelessWidget {
  /// Glasses for [day]; [onLog] and [onUndo] are the two taps.
  const WaterGlasses({
    required this.day,
    required this.target,
    required this.onLog,
    required this.onUndo,
    super.key,
  });

  /// Today.
  final WaterDay day;

  /// The owner's glass count.
  final int target;

  /// A tap on the next glass.
  final VoidCallback onLog;

  /// A tap on a full glass.
  final VoidCallback onUndo;

  /// The narrowest a glass and its time may be at normal text size.
  static const double minCell = 38;

  @override
  Widget build(BuildContext context) {
    final filled = day.filled;
    // Always one more than filled, so a drink beyond the count can be logged.
    final count = math.max(target, filled + 1);
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(
      builder: (context, box) {
        final cell = minCell * math.max(1, scale);
        final perRow = math.max(1, (box.maxWidth / cell).floor());
        final width = box.maxWidth / math.min(perRow, count);
        return Wrap(
          children: <Widget>[
            for (var i = 0; i < count; i++)
              SizedBox(
                width: width,
                child: _Glass(
                  number: i + 1,
                  state: i < filled
                      ? GlassState.full
                      : i == filled
                      ? GlassState.next
                      : GlassState.empty,
                  time: i < filled ? day.timeLabel(i) : null,
                  onLog: onLog,
                  onUndo: onUndo,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Glass extends StatelessWidget {
  const _Glass({
    required this.number,
    required this.state,
    required this.time,
    required this.onLog,
    required this.onUndo,
  });

  final int number;
  final GlassState state;
  final String? time;
  final VoidCallback onLog;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final action = switch (state) {
      GlassState.full => onUndo,
      GlassState.next => onLog,
      GlassState.empty => null,
    };
    return Semantics(
      label: glassLabel(number, state, time: time),
      button: action != null,
      onTap: action,
      excludeSemantics: true,
      child: InkResponse(
        onTap: action,
        radius: 28,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(height: 4),
              CustomPaint(
                size: const Size(24, 32),
                painter: GlassPainter(
                  state: state,
                  family: context.family,
                  outline: colors.ink3,
                ),
              ),
              SizedBox(
                height: 18,
                child: time == null
                    ? null
                    : Text(
                        time!,
                        maxLines: 1,
                        style: TypeLadder.micro.copyWith(color: colors.ink3),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Draws one glass: a cup wider at the rim than at the foot.
class GlassPainter extends CustomPainter {
  /// A glass in [state]; [family] is the Body hue, [outline] the quiet line.
  const GlassPainter({
    required this.state,
    required this.family,
    required this.outline,
  });

  /// Which of the three looks.
  final GlassState state;

  /// The fill and the next glass's dashes.
  final Color family;

  /// The outline of an empty glass.
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = size.width * 0.14;
    const stroke = 1.6;
    final path = Path()
      ..moveTo(stroke, stroke)
      ..lineTo(size.width - stroke, stroke)
      ..lineTo(size.width - inset, size.height - stroke * 2)
      ..quadraticBezierTo(
        size.width - inset - 1,
        size.height - stroke,
        size.width - inset - 4,
        size.height - stroke,
      )
      ..lineTo(inset + 4, size.height - stroke)
      ..quadraticBezierTo(
        inset + 1,
        size.height - stroke,
        inset,
        size.height - stroke * 2,
      )
      ..close();
    switch (state) {
      case GlassState.full:
        canvas.drawPath(path, Paint()..color = family);
      case GlassState.next:
        _dashed(
          canvas,
          path,
          Paint()
            ..color = family
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke,
        );
      case GlassState.empty:
        canvas.drawPath(
          path,
          Paint()
            ..color = outline
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke
            ..strokeJoin = StrokeJoin.round,
        );
    }
  }

  void _dashed(Canvas canvas, Path path, Paint paint) {
    for (final PathMetric metric in path.computeMetrics()) {
      var at = 0.0;
      while (at < metric.length) {
        canvas.drawPath(metric.extractPath(at, at + 3), paint);
        at += 6;
      }
    }
  }

  @override
  bool shouldRepaint(GlassPainter old) =>
      old.state != state || old.family != family || old.outline != outline;
}
