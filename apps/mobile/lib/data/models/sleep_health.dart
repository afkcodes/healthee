/// The four-dimension sleep judgement, and the cutoffs it is judged against.
///
/// ## Four judgements. Never one number, in this app's UI.
///
/// The payload carries `score` and `max_score: 4` and it would be trivial to
/// draw "3/4". Brief §5.3 forbids it, and the reason is on the wire itself: the
/// server sends `point_duration` / `point_efficiency` / `point_regularity` /
/// `point_timing` as separate 0-or-1 fields **precisely so the app can show four
/// judgements rather than a fake composite**. Summing them asserts that a night
/// that was long enough but badly timed is "the same as" one that was short but
/// well timed, and nothing in the evidence supports that trade.
///
/// So [dimensions] is the public shape and [score] is deliberately not exposed
/// as a headline. [SleepDimension] pairs each judgement with **its own published
/// cutoff**, taken from the payload rather than hard-coded here — the cutoffs
/// are science, they live on the server, and a copy in the UI is a second
/// definition waiting to drift.
library;

import 'package:healthee/shared/format/duration.dart';
import 'package:healthee/shared/format/iso_clock.dart';
import 'package:meta/meta.dart';

/// One dimension: what it measures, what it scored, and against what.
@immutable
class SleepDimension {
  /// A named judgement with its cutoff.
  const SleepDimension({
    required this.name,
    required this.passed,
    required this.reading,
    required this.cutoff,
    required this.source,
  });

  /// Owner-facing name — "Duration", "Efficiency", "Regularity", "Timing".
  final String name;

  /// Whether the night met this dimension's cutoff. Null when the dimension
  /// could not be scored at all, which is different from failing it.
  final bool? passed;

  /// The owner's own value, already formatted with its unit.
  final String? reading;

  /// The published threshold, already formatted.
  final String cutoff;

  /// Where the cutoff comes from, in a few words. Brief §4.2 names all four.
  final String source;
}

/// Sleep health for one night, as four independent judgements.
@immutable
class SleepHealth {
  /// Built by [SleepHealth.maybe].
  const SleepHealth({
    required this.date,
    required this.tstMin,
    required this.tibMin,
    required this.efficiencyPct,
    required this.sri,
    required this.midpointLocal,
    required this.dimensions,
    required this.researchNotes,
  });

  /// Parses `sleep_health`, or null when there is no night to judge.
  static SleepHealth? maybe(Map<String, Object?> json) {
    final tst = (json['tst_min'] as num?)?.toInt();
    if (tst == null) {
      return null;
    }
    final cutoffs = json['cutoffs'] is Map<String, Object?>
        ? json['cutoffs']! as Map<String, Object?>
        : const <String, Object?>{};
    final efficiency = (json['efficiency_pct'] as num?)?.toDouble();
    final sri = (json['sri'] as num?)?.toDouble();
    return SleepHealth(
      date: json['date'] as String?,
      tstMin: tst,
      tibMin: (json['tib_min'] as num?)?.toInt(),
      efficiencyPct: efficiency,
      sri: sri,
      midpointLocal: json['midpoint_local'] as String?,
      dimensions: _dimensions(json, cutoffs, tst, efficiency, sri),
      researchNotes: [
        for (final entry in (json['research_notes'] as List? ?? const []))
          if (entry is String) entry,
      ],
    );
  }

  /// The night this judges.
  final String? date;

  /// Total sleep time, minutes.
  final int tstMin;

  /// Time in bed, minutes.
  final int? tibMin;

  /// Sleep efficiency, percent.
  final double? efficiencyPct;

  /// Sleep Regularity Index over the trailing fortnight, 0–100.
  final double? sri;

  /// Sleep midpoint in the owner's own zone, ISO-8601.
  final String? midpointLocal;

  /// The four judgements, in the order the brief lists them.
  final List<SleepDimension> dimensions;

  /// The notes licensing the cutoffs.
  final List<String> researchNotes;

  /// How many dimensions were met. For a caption, never for a headline figure.
  int get met => dimensions.where((d) => d.passed ?? false).length;

  static List<SleepDimension> _dimensions(
    Map<String, Object?> json,
    Map<String, Object?> cutoffs,
    int tstMin,
    double? efficiencyPct,
    double? sri,
  ) {
    bool? point(String key) => switch (json[key]) {
      final num value => value >= 1,
      _ => null,
    };
    final hours = (cutoffs['duration_hours'] as List?)?.cast<Object?>();
    final band = (cutoffs['timing_hour_band'] as List?)?.cast<Object?>();
    final efficiencyMin = (cutoffs['efficiency_min'] as num?)?.toDouble();
    final sriMin = (cutoffs['sri_min'] as num?)?.toDouble();
    return <SleepDimension>[
      SleepDimension(
        name: 'Duration',
        passed: point('point_duration'),
        reading: durationText(tstMin),
        cutoff: hours == null ? '7–9 h' : '${hours.first}–${hours.last} h',
        // NSF 2015's expert consensus, not AASM's (audit D13, 2026-09-08).
        // `sleep_duration_mortality.md:146-151` attributes the 7-9 h band to NSF;
        // AASM's own figure is a one-sided "at least 7 h"
        // (`sleep_timing_chronotype.md:74`), so the label contradicted the band it
        // sat under — and contradicted this app's own `sleep` explainer, which has
        // said "National Sleep Foundation's 2015 expert consensus" since the
        // grounding pass.
        source: 'NSF 2015 consensus (18–64)',
      ),
      SleepDimension(
        name: 'Efficiency',
        passed: point('point_efficiency'),
        reading: efficiencyPct == null
            ? null
            : '${efficiencyPct.toStringAsFixed(1)}%',
        cutoff: efficiencyMin == null
            ? '≥ 85%'
            : '≥ ${(efficiencyMin * 100).round()}%',
        source: 'Clinical insomnia criterion',
      ),
      SleepDimension(
        name: 'Regularity',
        passed: point('point_regularity'),
        reading: sri?.toStringAsFixed(0),
        cutoff: sriMin == null ? '≥ 70' : '≥ ${sriMin.toStringAsFixed(0)}',
        // SEVEN nights, not fourteen: `derive/sleep_score.py:41` is `SRI_DAYS = 7`
        // (Phillips 2017's minimum window). 14 is the SLEEP-DEBT window
        // (`SLEEP_DEBT_WINDOW`), and the two were transposed here — a caption
        // describing a different computation from the one that produced the number
        // beside it (audit D13, 2026-09-08).
        source: 'SRI over 7 nights',
      ),
      SleepDimension(
        name: 'Timing',
        passed: point('point_timing'),
        reading: clockOfIso(json['midpoint_local']),
        cutoff: band == null
            ? '02:00–04:00'
            : '${_hourLabel(band.first)}–${_hourLabel(band.last)}',
        source: 'Chronotype studies',
      ),
    ];
  }

  static String _hourLabel(Object? hour) {
    final value = (hour as num?)?.toDouble() ?? 0;
    final whole = value.floor();
    final minutes = ((value - whole) * 60).round();
    return '${whole.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}';
  }
}
