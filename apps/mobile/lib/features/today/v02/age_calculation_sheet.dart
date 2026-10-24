/// "How this is calculated": the sheet behind the screen's one-row card.
///
/// The ladder from your age to the estimate, the arithmetic in words, the
/// model's limits and the notes licensing it. It is a [MetricDetail] through
/// `showMetricInfo`, so the citations reach the reader the one way the app
/// allows: the sheet's own sources row.
///
/// ## The equation is the payload's arithmetic
///
/// [ageEquation] folds over `contributions[]`, so a model that reweights or
/// drops a term rewrites the sentence. It is built from the same numbers the
/// ladder is drawn from, so the sentence and the picture cannot disagree.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/data/honesty/disclosure.dart';
import 'package:healthee/data/models/biological_age.dart';
import 'package:healthee/shared/metric_info/metric_detail.dart';
import 'package:healthee/shared/metric_info/metric_info_sheet.dart';
import 'package:healthee/shared/v02/instruments/age_waterfall.dart';

/// The sheet's heading.
const String kAgeCalculationTitle = 'How this is calculated';

/// What the caveats are called on the sheet.
const String kAgeCaveatsLabel = 'WHAT TILTS THE ESTIMATE';

/// The line about what kind of number this is.
const String kConfidenceNote =
    'This is a population-based motivational model, not a clinical age. The '
    'fitness input is estimated, and its uncertainty carries into the result.';

/// `fitness` → [Tone.fitness]; anything naming sleep → [Tone.sleep].
///
/// An unrecognised term takes the fitness family rather than a hue picked to
/// look distinct, exactly as `recoveryFactorTone` does.
Tone ageTermTone(String term) =>
    term.toLowerCase().contains('sleep') ? Tone.sleep : Tone.fitness;

/// `fitness` → `Fitness`; `sleep duration` → `Sleep duration`.
String ageTermName(String term) {
  final words = term.replaceAll('_', ' ').trim();
  return words.isEmpty ? term : words[0].toUpperCase() + words.substring(1);
}

/// `36 chronological years − 1.7 fitness + 0.0 sleep = 34.3 modelled years.`
String ageEquation(BiologicalAge age, double chronologicalAge) {
  final parts = StringBuffer('${_plain(chronologicalAge)} chronological years');
  for (final term in age.contributions) {
    if (term.deltaYears case final double delta) {
      parts.write(
        ' ${delta < 0 ? '−' : '+'} ${delta.abs().toStringAsFixed(1)} '
        '${term.term.toLowerCase()}',
      );
    }
  }
  parts.write(' = ${_plain(age.biologicalAge)} modelled years.');
  return parts.toString();
}

/// `36`, and `34.3` when there is a tenth to show. Never `36.0`.
String _plain(double value) => value == value.roundToDouble()
    ? value.round().toString()
    : value.toStringAsFixed(1);

/// The sheet's content. [age] is null when the estimate is withheld, and the
/// ladder and the equation then do not exist: they need numbers.
MetricDetail ageCalculationDetail({
  required BiologicalAge? age,
  required List<Disclosure> caveats,
  required List<String> researchNotes,
}) {
  final chronological = age?.chronologicalAge;
  return MetricDetail(
    title: kAgeCalculationTitle,
    figure: age == null || chronological == null
        ? null
        : _Ladder(age: age, chronologicalAge: chronological),
    method: <String>[
      if (age != null && chronological != null) ageEquation(age, chronological),
      kConfidenceNote,
    ],
    disclosures: caveats,
    disclosuresLabel: kAgeCaveatsLabel,
    notes: researchNotes,
  );
}

/// Opens the sheet.
void openAgeCalculation(
  BuildContext context, {
  required BiologicalAge? age,
  required List<Disclosure> caveats,
  required List<String> researchNotes,
}) => showMetricInfo(
  context,
  null,
  detail: ageCalculationDetail(
    age: age,
    caveats: caveats,
    researchNotes: researchNotes,
  ),
);

/// The waterfall, at rest.
class _Ladder extends StatelessWidget {
  const _Ladder({required this.age, required this.chronologicalAge});

  final BiologicalAge age;
  final double chronologicalAge;

  @override
  Widget build(BuildContext context) => ToneScope(
    tone: Tone.fitness,
    child: AgeWaterfall(
      chronologicalAge: chronologicalAge,
      estimate: age.biologicalAge,
      terms: <AgeTerm>[
        for (final term in age.contributions)
          if (term.deltaYears case final double delta)
            AgeTerm.measured(
              ageTermName(term.term),
              delta,
              tone: ageTermTone(term.term),
            ),
      ],
    ),
  );
}
