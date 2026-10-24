/// The screen's centrepiece, on the page and not on a card.
///
/// In order: the Label with its ⓘ, the sphere with the figure and the verdict
/// in it, one Callout line of what moved the estimate, and a Caption that says
/// it is not a clinical age. The whole face opens the Biological age screen,
/// which holds the ruler and the levers; nothing of them is repeated here.
///
/// ## Everything here is the server's, and an absence stays an absence
///
/// The figure is `biological_age.biological_age`; the verdict is built from
/// `delta_years` and `chronological_age` and is **omitted entirely** when
/// either is null, rather than saying "0.0 years below" about an age nothing
/// compared. The breakdown line is the block's own terms in the payload's
/// order (`ageBreakdownSpan`), so a term the server stops sending stops being
/// shown, and one it left out or could not count is named as such.
///
/// The caption is the server's `disclaimer` when it fits one line, and the
/// app's own short sentence when it does not (the server's runs to two lines
/// on a phone). The full disclaimer stays behind the ⓘ either way.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/data/models/bio_age_block.dart';
import 'package:healthee/data/models/biological_age.dart';
import 'package:healthee/features/today/v02/what_moves_it.dart';
import 'package:healthee/shared/v02/age_orb_hero.dart';
import 'package:healthee/shared/v02/key_number_card.dart';

/// The not-clinical caption under the breakdown.
const String kAgeNotClinical = 'Estimate, not a clinical age';

/// The longest server disclaimer that still sits on one line under the sphere.
const int kAgeCaptionMaxChars = 36;

/// What the prototype prints behind the ⓘ when the server sent no disclaimer.
const String kPopulationModelLabel =
    'Population-based model · not a clinical age';

/// The biological-age hero.
///
/// Nothing here holds state. The sphere's three automatic stops (offscreen,
/// backgrounded, reduced motion) are the field's own.
class TodayBioHero extends StatelessWidget {
  /// [age] is the payload's block and [block] the whole `biological_age`
  /// block it came from; nothing here is computed beyond formatting.
  const TodayBioHero({
    required this.age,
    required this.block,
    this.onOpenBody,
    super.key,
  });

  /// The estimate and everything the server said about it.
  final BiologicalAge age;

  /// The block the breakdown line names its terms from, withheld and left out
  /// ones included.
  final BioAgeBlock block;

  /// A tap anywhere on the hero: the Biological age screen.
  final VoidCallback? onOpenBody;

  @override
  Widget build(BuildContext context) {
    final breakdown = ageBreakdownSpan(
      block,
      AgeOrbHero.breakdownStyle(context.colors),
    );
    return AgeOrbHero(
      value: figureOf(age.biologicalAge),
      verdict: verdictOf(age),
      breakdown: breakdown.toPlainText().isEmpty ? null : breakdown,
      caption: captionOf(age),
      modelLabel: age.disclaimer ?? kPopulationModelLabel,
      onOpen: onOpenBody,
      openSemantics: spokenOf(age, block),
    );
  }

  /// The caption: the server's disclaimer if one line holds it, else ours.
  static String captionOf(BiologicalAge age) {
    final said = age.disclaimer?.trim();
    return said != null && said.isNotEmpty && said.length <= kAgeCaptionMaxChars
        ? said
        : kAgeNotClinical;
  }

  /// `Biological age 34.3 years, 1.7 years younger than your age. Fitness
  /// minus 1.7 years, sleep 0.0 years. Opens the breakdown.`
  static String spokenOf(BiologicalAge age, BioAgeBlock block) {
    final said = verdictOf(age);
    final compared = said == null
        ? ''
        : age.deltaYears == 0
        ? ', your actual age'
        : ', ${said.words} than your age';
    final parts = <String>[
      'Biological age ${figureOf(age.biologicalAge)} years$compared.',
    ];
    final breakdown = ageBreakdownLine(block, spoken: true);
    if (breakdown.isNotEmpty) {
      parts.add('$breakdown.');
    }
    parts.add('Opens the breakdown.');
    return parts.join(' ');
  }

  /// `1.7 years younger`, `2.0 years older`, or `Your actual age`; null when
  /// nothing was compared.
  static Verdict? verdictOf(BiologicalAge age) {
    final delta = age.deltaYears;
    if (delta == null || age.chronologicalAge == null) {
      return null;
    }
    final magnitude = delta.abs().toStringAsFixed(1);
    return delta == 0
        ? const Verdict('Your actual age', VerdictTone.neutral)
        : delta < 0
        ? Verdict('$magnitude years younger', VerdictTone.better)
        : Verdict('$magnitude years older', VerdictTone.worse);
  }

  /// `34.3`, and `34` when the estimate is whole. Never `34.0`.
  static String figureOf(double value) => value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(1);
}
