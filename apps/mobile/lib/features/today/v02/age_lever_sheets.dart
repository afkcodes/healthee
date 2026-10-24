/// What a lever's row opens: the sheet that explains one term of the estimate.
///
/// Every row of the lever card opens one. The sheet holds what the screen no
/// longer prints under the card: the term's own explanation, its numbers as
/// text, the rail or bars it was read off, the caveats that tilt it, and the
/// notes behind it, all through `showMetricInfo`.
///
/// | The row is…             | The sheet holds                                  |
/// | ----------------------- | ------------------------------------------------ |
/// | fitness, counted        | the VO₂max rail, the reference, the caveats      |
/// | sleep, counted          | the two bars, the translation, the caveats       |
/// | withheld today          | the server's message and why it takes the number |
/// | excluded, never counted | the server's full paragraph, verbatim            |
///
/// An excluded term is not a withheld one and the sheet says which: it offers
/// no remedy, because nothing the owner does would change it, only the way to
/// where the measurement IS shown.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/data/honesty/disclosure.dart';
import 'package:healthee/data/models/bio_age_block.dart';
import 'package:healthee/data/models/biological_age.dart';
import 'package:healthee/data/models/vo2max.dart';
import 'package:healthee/features/today/v02/age_calculation_sheet.dart';
import 'package:healthee/shared/format/metric_names.dart';
import 'package:healthee/shared/metric_info/metric_detail.dart';
import 'package:healthee/shared/metric_info/metric_info_sheet.dart';
import 'package:healthee/shared/v02/comparison_bars.dart';
import 'package:healthee/shared/v02/instruments/vo2max_rail.dart';

/// The line under the fitness rail.
const String kFitnessTermNote =
    'The model compares fitness against its own reference and converts the '
    'result into a year contribution.';

/// The line under the sleep bars.
const String kSleepTermNote =
    'This age term uses a documented self-report translation. It is separate '
    'from the 8h sleep-need reference.';

/// What a withheld term's refusal is called on the sheet.
const String kLeverWithheldLabel = 'WHY THIS IS NOT COUNTED TODAY';

/// What an excluded term's paragraph is called on the sheet.
const String kLeverExcludedLabel = 'LEFT OUT, NOT COUNTED AS ZERO';

/// The explainer a sheet opens beside its detail, and the detail.
typedef LeverSheet = ({String? infoKey, MetricDetail detail});

/// The sheet for [term], or null when the block names no such lever.
///
/// Pure: the screen hands in where its buttons go and this decides only what
/// is said, so the content can be tested without a route.
LeverSheet? leverSheetFor(
  String term, {
  required BioAgeBlock block,
  required List<Disclosure> caveats,
  Vo2max? vo2max,
  VoidCallback? openSleep,
  VoidCallback? openFitness,
}) {
  final key = term.toLowerCase();
  for (final c in block.contributions) {
    if (c.term.toLowerCase() != key) continue;
    if (ageTermTone(c.term) == Tone.sleep) {
      return _sleep(c, caveats, openSleep);
    }
    return _fitness(c, caveats, vo2max, openFitness);
  }
  for (final d in block.absentTerms) {
    if ((d.term ?? d.reason).toLowerCase() == key) {
      return _withheld(d, block, openSleep, openFitness);
    }
  }
  for (final d in block.exclusions) {
    if ((d.term ?? d.reason).toLowerCase() == key) {
      return _excluded(d, openSleep);
    }
  }
  return null;
}

/// Opens [term]'s sheet. Does nothing for a term the block does not name.
void openAgeLever(
  BuildContext context,
  String term, {
  required BioAgeBlock block,
  required List<Disclosure> caveats,
  Vo2max? vo2max,
  VoidCallback? openSleep,
  VoidCallback? openFitness,
}) {
  final sheet = leverSheetFor(
    term,
    block: block,
    caveats: caveats,
    vo2max: vo2max,
    openSleep: openSleep,
    openFitness: openFitness,
  );
  if (sheet != null) {
    showMetricInfo(context, sheet.infoKey, detail: sheet.detail);
  }
}

String _hours(double value) => '${value.toStringAsFixed(1)} h';

List<Disclosure> _about(
  List<Disclosure> caveats,
  bool Function(String) wants,
) => <Disclosure>[
  for (final c in caveats)
    if (wants((c.term ?? '').toLowerCase())) c,
];

LeverSheet _fitness(
  AgeContribution c,
  List<Disclosure> caveats,
  Vo2max? vo2max,
  VoidCallback? open,
) {
  final value = c.value;
  return (
    infoKey: 'vo2max',
    detail: MetricDetail(
      title: ageTermName(c.term),
      method: <String>[
        kFitnessTermNote,
        if (c.method case final String method) 'Read by ${methodLabel(method)}',
        if (value != null) 'VO₂max estimate ${value.toStringAsFixed(1)}',
        if (c.target case final double target)
          'Age-model target ${target.toStringAsFixed(1)}',
      ],
      notes: vo2max?.researchNotes ?? const <String>[],
      disclosures: _about(caveats, (t) => t == 'fitness'),
      disclosuresLabel: kAgeCaveatsLabel,
      figure: value == null
          ? null
          : ToneScope(
              tone: Tone.fitness,
              child: Vo2maxRail(
                estimate: value,
                medianForAge: vo2max?.medianForAge,
                errorMagnitude: vo2max?.standardErrorMlKgMin,
              ),
            ),
      action: open == null
          ? null
          : MetricAction('Open the fitness detail', open),
    ),
  );
}

LeverSheet _sleep(
  AgeContribution c,
  List<Disclosure> caveats,
  VoidCallback? open,
) {
  final bars = <ComparisonBar>[
    if (c.value case final double v) ComparisonBar('Wearable', v, _hours(v)),
    if (c.comparedAs case final double v)
      ComparisonBar('Compared as', v, _hours(v)),
  ];
  return (
    infoKey: 'sleep',
    detail: MetricDetail(
      title: ageTermName(c.term),
      method: <String>[
        kSleepTermNote,
        if (c.value case final double v) '${_hours(v)} wearable average',
        if (c.comparedAs case final double v) 'Compared as ${_hours(v)}',
      ],
      disclosures: _about(caveats, (t) => t.contains('sleep')),
      disclosuresLabel: kAgeCaveatsLabel,
      figure: bars.isEmpty
          ? null
          : ToneScope(tone: Tone.sleep, child: ComparisonBars(bars)),
      action: open == null
          ? null
          : MetricAction('See your complete sleep picture', open),
    ),
  );
}

LeverSheet _withheld(
  Disclosure d,
  BioAgeBlock block,
  VoidCallback? openSleep,
  VoidCallback? openFitness,
) {
  final term = d.term ?? d.reason;
  final sleep = ageTermTone(term) == Tone.sleep;
  final open = sleep ? openSleep : openFitness;
  return (
    infoKey: null,
    detail: MetricDetail(
      title: ageTermName(term),
      disclosures: <Disclosure>[
        if (d.message.isNotEmpty) d,
        if (block.consequence case final String why when why.isNotEmpty)
          Disclosure(reason: 'withheld_consequence', message: why),
      ],
      disclosuresLabel: kLeverWithheldLabel,
      action: open == null
          ? null
          : MetricAction(
              sleep
                  ? 'See your complete sleep picture'
                  : 'Open the fitness detail',
              open,
            ),
    ),
  );
}

LeverSheet _excluded(Disclosure d, VoidCallback? openSleep) => (
  infoKey: null,
  detail: MetricDetail(
    title: ageTermName(d.term ?? d.reason),
    // Verbatim: the reasoning about the two calculators is the server's, and
    // re-wording it would soften a statement about what is knowable.
    disclosures: <Disclosure>[d],
    disclosuresLabel: kLeverExcludedLabel,
    action: openSleep == null
        ? null
        : MetricAction('Still visible in Sleep', openSleep),
  ),
);
