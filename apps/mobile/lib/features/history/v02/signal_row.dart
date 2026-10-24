/// One line of the Health signals screen, as data: what it reads, how it is
/// judged and how it is said aloud.
///
/// Nothing here draws. [SignalRow] is built by `signal_rows.dart` from the
/// snapshot and drawn by `signal_row_view.dart`, so the verdict a chip prints,
/// the dot on the strip and the sentence a screen reader hears all come from
/// the one [Judgement] and cannot disagree.
library;

import 'package:flutter/foundation.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/data/honesty/reading.dart';
import 'package:healthee/shared/usual_range.dart';
import 'package:healthee/shared/v02/reading_state.dart';

/// What the right-hand figure is, once formatted.
@immutable
class SignalFigure {
  /// [text] is the figure; [unit] is drawn smaller beside it (may be empty).
  const SignalFigure(this.text, [this.unit = '']);

  /// The figure, e.g. `43.9`, `3,214` or `7 h 1 min`.
  final String text;

  /// The unit, e.g. `ms`. Empty when the figure carries its own.
  final String unit;
}

/// The shape of the middle column.
enum SignalGraphic {
  /// A fortnight line against the usual band.
  spark,

  /// A 6 px progress bar: a goal, or a count of short nights.
  bar,

  /// Four pass/fail squares: the sleep-health checks.
  checks,
}

/// One metric's row.
@immutable
class SignalRow {
  /// A row. [figure] null means no reading.
  const SignalRow({
    required this.metric,
    required this.title,
    required this.caption,
    required this.judgement,
    required this.tone,
    this.figure,
    this.graphic = SignalGraphic.spark,
    this.values = const <double?>[],
    this.usual,
    this.progress,
    this.checks = const <bool?>[],
    this.spoken = '',
    this.withheld,
  });

  /// The canonical metric id; the history route is keyed by it.
  final String metric;

  /// The owner-facing name.
  final String title;

  /// Two short lines: polarity and usual range, or a goal.
  final String caption;

  /// The verdict, shared by the chip, the dot and the screen reader.
  final Judgement judgement;

  /// The group's family, or [Tone.load] for cardio load.
  final Tone tone;

  /// The figure, or null for "No reading".
  final SignalFigure? figure;

  /// What the middle column draws.
  final SignalGraphic graphic;

  /// The newest-last series for a [SignalGraphic.spark].
  final List<double?> values;

  /// The server's usual range behind the line.
  final UsualRange? usual;

  /// 0 to 1 for a [SignalGraphic.bar].
  final double? progress;

  /// Pass, miss or unknown, for [SignalGraphic.checks].
  final List<bool?> checks;

  /// The figure with its unit as a screen reader says it.
  final String spoken;

  /// The server's refusal, when it carried the metric and withheld it.
  final Withheld<double>? withheld;

  /// Whether this row has a figure.
  bool get hasReading => figure != null;

  /// One sentence for the whole row, e.g. `Overnight HRV 43.9 milliseconds,
  /// below your usual of 44 to 57`.
  String semanticLabel(String Function(double) say) {
    if (!hasReading) {
      return '$title, no reading';
    }
    final range = usual == null
        ? ''
        : ' of ${say(usual!.low)} to ${say(usual!.high)}';
    final verdict = switch (judgement.words) {
      'Usual' => 'within your usual$range',
      final String w when w.contains('Below usual') => 'below your usual$range',
      final String w when w.contains('Above usual') => 'above your usual$range',
      final String w when w.contains('Outside usual') =>
        'outside your usual$range',
      final String w => w.toLowerCase(),
    };
    return '$title $spoken, $verdict';
  }
}
