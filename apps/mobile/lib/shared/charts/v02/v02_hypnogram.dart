/// [V02Hypnogram] — the night's stage timeline, drawn as one continuous band.
///
/// The mark itself, and the two shapes it replaced, are documented on
/// `HypnogramPainter`. This half is the chart's contract: the window is the
/// night's own, the hues are never handed in, and the axis is built here rather
/// than in the painter because it is the one part that needs a calendar.
///
/// ## The window is the night's own, not a fixed 450 minutes
///
/// The prototype divides by a literal `450` because its fixture is one 7½-hour
/// night. A real night that ran longer would draw off the right edge. The span
/// is the measured one — first start to last end — so the plot always ends
/// where the night did.
///
/// ## No hue is ever handed in
///
/// Stage hues resolve through `InstrumentHues.sleepStage`, the app's one stage
/// mapping (`core/theme/instrument_hues.dart`).
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/instrument_hues.dart';
import 'package:healthee/data/models/last_sleep.dart';
import 'package:healthee/shared/charts/v02/chart_ink.dart';
import 'package:healthee/shared/charts/v02/chart_void.dart';
import 'package:healthee/shared/charts/v02/hypnogram_painter.dart';

/// The lanes, top to bottom, in the prototype's order.
const List<String> kHypnogramLanes = <String>['awake', 'rem', 'light', 'deep'];

/// One night's stages, laid out along the time it took.
class V02Hypnogram extends StatelessWidget {
  /// [spans] is chronological; [startAt] and [endAt] bound the clock axis.
  const V02Hypnogram(
    this.spans, {
    required this.progress,
    this.height = 165,
    this.startAt,
    this.endAt,
    this.semanticLabel,
    super.key,
  });

  /// The staged spans, oldest first.
  final List<SleepStageSpan> spans;

  /// How much of the reveal has run, 0–1.
  final double progress;

  /// How tall to draw it.
  final double height;

  /// When the night began. Null draws no axis rather than a guessed one.
  final DateTime? startAt;

  /// When it ended.
  final DateTime? endAt;

  /// What a screen reader is told.
  final String? semanticLabel;

  /// How many clocks run under the plot, ends included.
  static const int axisTicks = 4;

  /// The clocks under the plot, evenly spaced from [startAt] to [endAt].
  ///
  /// **Empty unless both ends are known.** An axis interpolated from one end
  /// and a duration would be a claim about when the night ran, made out of a
  /// measurement of how long it ran — and it would look identical to a real one.
  List<String> get axis {
    final start = startAt;
    final end = endAt;
    if (start == null || end == null || !end.isAfter(start)) {
      return const <String>[];
    }
    final span = end.difference(start);
    return <String>[
      for (var i = 0; i < axisTicks; i++)
        _clock(start.add(span * (i / (axisTicks - 1)))),
    ];
  }

  /// `02:10` — the 24-hour clock the rest of the sleep surfaces use.
  static String _clock(DateTime at) =>
      '${at.hour}:${at.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    if (spans.isEmpty) {
      return ChartVoid(height: height);
    }
    final chart = SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: HypnogramPainter(
          spans: spans,
          hues: context.hues,
          ink: ChartInk.of(context),
          progress: progress,
          axis: axis,
        ),
      ),
    );
    final label = semanticLabel;
    return label == null ? chart : Semantics(label: label, child: chart);
  }
}
