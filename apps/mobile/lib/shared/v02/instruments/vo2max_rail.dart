/// **The VO₂max rail** — the estimate as a dot, the age/sex median as a line,
/// and the instrument's error magnitude as an extent around it.
///
/// ## The wording is part of the instrument
///
/// `charts-detail.js` labels the shaded extent *"illustrative extent of supplied
/// error magnitude … **Not a confidence interval**"*, and `screens-fitness.js`
/// repeats it in the visible note: *"Supplied error magnitude: ±2.95 ml/kg/min,
/// derived from MAPE 6.85%. The band is not a confidence interval."*
///
/// That distinction is load-bearing and it is **drawn by this widget**, not left
/// to the card around it. A shaded band beside a number reads as a 95% interval
/// to anyone who has seen one before; this one is a single instrument's typical
/// error, applied symmetrically, with no distribution behind it. A caller cannot
/// place the extent without the sentence because the widget renders both or
/// neither — and when no error magnitude is supplied it draws **no extent at
/// all** and says so, rather than inventing a width.
///
/// ## The window widens rather than clipping
///
/// The prototype's rail is a fixed 30-55. A real owner can sit outside it, so
/// the window opens to the next 5 that contains the estimate, its extent and the
/// median. Every tick is labelled, so a widened rail is legible as a widened
/// rail — the reader is never shown a different scale without being told.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/core/theme/type_scale.dart';
import 'package:healthee/shared/charts/chart_primitives.dart';
import 'package:healthee/shared/v02/instruments/instrument_geometry.dart';

/// The rail's default low end, in ml/kg/min. `charts-detail.js`: `x(30)`.
const double kRailDefaultLow = 30;

/// Its default high end.
const double kRailDefaultHigh = 55;

/// The gap between labelled ticks.
const double kRailTickStep = 5;

/// The sentence the extent may never be shown without.
const String kErrorMagnitudeNote = 'not a confidence interval';

/// The VO₂max estimate on a rail, with its reference median and error extent.
class Vo2maxRail extends StatelessWidget {
  /// Builds the rail. [errorMagnitude] of null draws no extent and says so.
  const Vo2maxRail({
    required this.estimate,
    required this.medianForAge,
    required this.errorMagnitude,
    this.progress = 1,
    super.key,
  });

  /// Identifies the plot for tests.
  static const Key plotKey = ValueKey<String>('vo2max-rail-plot');

  /// The plot's own height, above the note.
  static const double railHeight = 100;

  /// The gap between the plot and the note.
  static const double noteGap = 6;

  /// The estimate, in ml/kg/min.
  final double estimate;

  /// The age and sex reference. Null draws no reference line.
  final double? medianForAge;

  /// The instrument's error magnitude — **not** a confidence half-width.
  final double? errorMagnitude;

  /// Reveal progress, 0-1. The extent opens outward from the estimate.
  final double progress;

  /// The window the rail spans, widened to hold everything it must draw.
  ({double low, double high}) get window {
    final error = errorMagnitude ?? 0;
    final values = <double>[estimate - error, estimate + error, ?medianForAge];
    final low = math.min(
      kRailDefaultLow,
      ((values.reduce(math.min) - 2) / kRailTickStep).floorToDouble() *
          kRailTickStep,
    );
    final high = math.max(
      kRailDefaultHigh,
      ((values.reduce(math.max) + 2) / kRailTickStep).ceilToDouble() *
          kRailTickStep,
    );
    return (low: low, high: high);
  }

  /// The note under the rail. Named so the test can restate it by hand.
  String get note {
    final error = errorMagnitude;
    if (error == null) {
      return 'No error magnitude supplied, so no extent is drawn.';
    }
    return '±${error.toStringAsFixed(2)} ml/kg/min is the supplied '
        'error magnitude, $kErrorMagnitudeNote.';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          height: railHeight,
          child: CustomPaint(
            key: plotKey,
            painter: _Vo2maxRailPainter(
              estimate: estimate,
              medianForAge: medianForAge,
              errorMagnitude: errorMagnitude,
              progress: progress.clamp(0.0, 1.0),
              window: window,
              family: context.family,
              familySoft: context.familySoft,
              ink: colors.ink,
              ink2: colors.ink2,
              grid: colors.grid,
              reference: colors.reference,
            ),
            child: const SizedBox.expand(),
          ),
        ),
        const SizedBox(height: noteGap),
        Text(note, style: TypeScale.panelNote.copyWith(color: colors.ink2)),
      ],
    );
  }
}

class _Vo2maxRailPainter extends CustomPainter {
  const _Vo2maxRailPainter({
    required this.estimate,
    required this.medianForAge,
    required this.errorMagnitude,
    required this.progress,
    required this.window,
    required this.family,
    required this.familySoft,
    required this.ink,
    required this.ink2,
    required this.grid,
    required this.reference,
  });

  final double estimate;
  final double? medianForAge;
  final double? errorMagnitude;
  final double progress;
  final ({double low, double high}) window;
  final Color family;
  final Color familySoft;
  final Color ink;
  final Color ink2;
  final Color grid;
  final Color reference;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }
    final left = size.width * 0.05;
    final right = size.width * 0.95;
    final axis = size.height * 0.48;
    double x(double value) => railX(
      value,
      low: window.low,
      high: window.high,
      left: left,
      right: right,
    );

    canvas.drawLine(
      Offset(left, axis),
      Offset(right, axis),
      Paint()
        ..color = grid
        ..strokeWidth = 1,
    );

    final error = errorMagnitude;
    if (error != null && error > 0) {
      final half = (x(estimate + error) - x(estimate - error)) / 2 * progress;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            x(estimate) - half,
            axis - 18,
            x(estimate) + half,
            axis + 18,
          ),
          const Radius.circular(8),
        ),
        Paint()..color = familySoft,
      );
    }

    final median = medianForAge;
    if (median != null && onScale(median, low: window.low, high: window.high)) {
      drawDashed(
        canvas,
        Offset(x(median), axis - 32),
        Offset(x(median), axis + 31),
        Paint()
          ..color = reference
          ..strokeWidth = 1,
        dash: 4,
        gap: 4,
      );
    }

    if (onScale(estimate, low: window.low, high: window.high)) {
      canvas.drawCircle(
        Offset(x(estimate), axis),
        6,
        Paint()..color = revealed(family, progress),
      );
      paintLabel(
        canvas,
        chartLabel(
          estimate.toStringAsFixed(1),
          TypeScale.panelTitle.copyWith(color: ink),
        ),
        Offset(x(estimate), axis - 48),
        anchor: LabelAnchor.middle,
      );
    }

    final style = TypeScale.colourKey.copyWith(color: ink2);
    for (
      var value = window.low;
      value <= window.high + 0.001;
      value += kRailTickStep
    ) {
      paintLabel(
        canvas,
        chartLabel(value.toStringAsFixed(0), style),
        Offset(x(value), axis + 36),
        anchor: LabelAnchor.middle,
      );
    }
  }

  @override
  bool shouldRepaint(_Vo2maxRailPainter old) =>
      old.estimate != estimate ||
      old.medianForAge != medianForAge ||
      old.errorMagnitude != errorMagnitude ||
      old.progress != progress ||
      old.family != family;
}
