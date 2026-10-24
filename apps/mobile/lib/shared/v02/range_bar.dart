/// `.p-range` — a track, the owner's usual range shaded on it, and today's mark.
///
/// The redesign's one way of answering "is this a good number for me?"
/// (`design/mobile-preview/proposal.js::rangeBar`). It draws three things and
/// claims nothing else:
///
///   * the **track**, from [min] to [max], so the reading has a scale;
///   * the **band**, the owner's own [UsualRange] (`usual_range.dart` is the
///     one definition of it), in the card's family colour;
///   * the **mark**, the reading itself, in ink. A reading off the track's
///     scale is held at the end it passed, never drawn off the bar.
///
/// Under it: the two ends, and the band named in words beneath the band. With
/// no band yet, the words say why instead ([pendingLabel]), centred, so a new
/// owner sees a bar that is learning rather than a bar that forgot something.
///
/// No red, amber or green here (`APP_DESIGN.md`, honest colour): the band is
/// the family's hue at the same strength whatever the reading is. The verdict
/// in words is the card's job, beside the figure.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/core/theme/type_scale_keys.dart';
import 'package:healthee/shared/usual_range.dart';

/// A reading against the owner's usual range.
class RangeBar extends StatelessWidget {
  /// [min] < [max]. [band] null draws the track and the mark only.
  const RangeBar({
    required this.value,
    required this.min,
    required this.max,
    required this.startLabel,
    required this.endLabel,
    required this.semanticLabel,
    this.band,
    this.usualLabel,
    this.pendingLabel,
    super.key,
  }) : assert(min < max, 'a track needs two different ends');

  /// `.p-range-track { height: 10px }`.
  static const double trackHeight = 10;

  /// `.p-range-mark { width: 4px; height: 20px }`, and its 2px surface ring.
  static const double markWidth = 4;
  static const double markHeight = 20;
  static const double markRing = 2;

  /// `.p-range-band { background: color-mix(--family 45%) }`.
  static const double bandAlpha = 0.45;

  /// `.p-range-ends { margin-top: 7px }`.
  static const double labelGap = 7;

  /// The reading.
  final double value;

  /// The track's two ends, in the reading's own unit.
  final double min;
  final double max;

  /// The ends as the owner reads them, `0` and `100`, `4h` and `9h`.
  final String startLabel;
  final String endLabel;

  /// The owner's usual range, or null while there is none.
  final UsualRange? band;

  /// The band in words, `usual 55 to 72`. Drawn under the band.
  final String? usualLabel;

  /// What stands in for the band while there is none, `learning your usual`.
  final String? pendingLabel;

  /// The whole bar in one sentence, for a screen reader.
  final String semanticLabel;

  /// Where [at] falls along a track [width] wide.
  double xOf(double at, double width) =>
      ((at - min) / (max - min)).clamp(0.0, 1.0) * width;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final family = context.family;
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                height: markHeight,
                child: CustomPaint(
                  painter: _RangePainter(
                    track: colors.surface2,
                    band: family.withValues(alpha: bandAlpha),
                    mark: colors.ink,
                    ring: colors.surface,
                    bandFrom: band == null ? null : xOf(band!.low, width),
                    bandTo: band == null ? null : xOf(band!.high, width),
                    markAt: xOf(value, width),
                  ),
                ),
              ),
              const SizedBox(height: labelGap - (markHeight - trackHeight) / 2),
              _labels(context, width, colors, family),
            ],
          );
        },
      ),
    );
  }

  Widget _labels(
    BuildContext context,
    double width,
    HealtheeColors colors,
    Color family,
  ) {
    final endStyle = KeyType.rangeEnd.copyWith(color: colors.ink3);
    final middle = band == null ? pendingLabel : usualLabel;
    final middleStyle = band == null
        ? endStyle
        : KeyType.rangeUsual.copyWith(color: colors.ink2);
    final centre = band == null
        ? width / 2
        : (xOf(band!.low, width) + xOf(band!.high, width)) / 2;
    return SizedBox(
      height: _lineHeight(endStyle),
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned(left: 0, child: Text(startLabel, style: endStyle)),
          Positioned(right: 0, child: Text(endLabel, style: endStyle)),
          if (middle != null)
            Positioned(
              left: _centredLeft(middle, middleStyle, centre, width),
              child: Text(middle, style: middleStyle, maxLines: 1),
            ),
        ],
      ),
    );
  }

  /// The left edge that centres [text] on [centre], kept inside the bar.
  static double _centredLeft(
    String text,
    TextStyle style,
    double centre,
    double width,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final half = painter.width / 2;
    return math.max(0, math.min(centre - half, width - painter.width));
  }

  static double _lineHeight(TextStyle style) =>
      (style.fontSize ?? 10.5) * (style.height ?? 1.2);
}

class _RangePainter extends CustomPainter {
  const _RangePainter({
    required this.track,
    required this.band,
    required this.mark,
    required this.ring,
    required this.bandFrom,
    required this.bandTo,
    required this.markAt,
  });

  final Color track;
  final Color band;
  final Color mark;
  final Color ring;
  final double? bandFrom;
  final double? bandTo;
  final double markAt;

  @override
  void paint(Canvas canvas, Size size) {
    const height = RangeBar.trackHeight;
    final top = (size.height - height) / 2;
    const radius = Radius.circular(height / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, top, size.width, height),
        radius,
      ),
      Paint()..color = track,
    );
    final from = bandFrom;
    final to = bandTo;
    if (from != null && to != null) {
      // A band whose quartiles meet still draws: a sliver one track-height wide
      // centred on them, so "your days were all the same" is visible.
      final left = math.min(from, to - height / 2);
      final right = math.max(to, from + height / 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            math.max(0, left),
            top,
            math.min(size.width, right),
            top + height,
          ),
          radius,
        ),
        Paint()..color = band,
      );
    }
    final x = markAt.clamp(
      RangeBar.markWidth / 2,
      size.width - RangeBar.markWidth / 2,
    );
    final markRect = Rect.fromCenter(
      center: Offset(x, size.height / 2),
      width: RangeBar.markWidth,
      height: RangeBar.markHeight,
    );
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(
          markRect.inflate(RangeBar.markRing),
          const Radius.circular(RangeBar.markWidth / 2 + RangeBar.markRing),
        ),
        Paint()..color = ring,
      )
      ..drawRRect(
        RRect.fromRectAndRadius(
          markRect,
          const Radius.circular(RangeBar.markWidth / 2),
        ),
        Paint()..color = mark,
      );
  }

  @override
  bool shouldRepaint(_RangePainter old) =>
      old.track != track ||
      old.band != band ||
      old.mark != mark ||
      old.ring != ring ||
      old.bandFrom != bandFrom ||
      old.bandTo != bandTo ||
      old.markAt != markAt;
}
