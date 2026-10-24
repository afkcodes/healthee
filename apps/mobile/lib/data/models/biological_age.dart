/// Biological age — the payload that exercises all four honesty states at once.
///
/// It is the richest example in the contract snapshot and the reason the union
/// has four cases rather than three:
///
///   * a **value** (34.3 years) — so it is not withheld;
///   * **`caveats`** naming which way the fitness and sleep terms lean — so it is
///     `Caveated`, not `Present`;
///   * an **`excluded`** entry saying sleep regularity cannot be converted into
///     years at all, *alongside* that value — the case that proves an exclusion
///     narrows a number rather than suppressing it;
///   * and a **`withheld`** slot that fires when the inputs cannot carry it.
///
/// The per-lever [contributions] are mandatory for the same reason recovery's
/// factors are: `docs/APP_DESIGN.md` §1 approves biological age as a composite
/// only when it "always renders its per-factor breakdown".
library;

import 'package:healthee/data/honesty/disclosure.dart';
import 'package:meta/meta.dart';

/// One lever's contribution, in years.
@immutable
class AgeContribution {
  /// A named term of the estimate.
  const AgeContribution({
    required this.term,
    required this.deltaYears,
    required this.value,
    required this.target,
    required this.unit,
    required this.method,
    this.comparedAs,
  });

  /// Parses one entry of `contributions`.
  factory AgeContribution.fromJson(Map<String, Object?> json) {
    return AgeContribution(
      term: json['term']! as String,
      deltaYears: (json['delta_years'] as num?)?.toDouble(),
      value: (json['value'] as num?)?.toDouble(),
      target: (json['target'] as num?)?.toDouble(),
      unit: json['unit'] as String?,
      method: json['method'] as String?,
      comparedAs: (json['compared_as'] as num?)?.toDouble(),
    );
  }

  /// Which lever: `fitness`, `sleep`, …
  final String term;

  /// Years added (positive) or removed (negative) by this lever.
  final double? deltaYears;

  /// The owner's own measured value for the lever.
  final double? value;

  /// The reference this lever is scored against.
  final double? target;

  /// Unit of [value] and [target].
  final String? unit;

  /// The instrument behind [value], when it had one.
  final String? method;

  /// **The value the hazard curve was actually read at**, when it is not
  /// [value] itself — the server's own words for the field.
  ///
  /// The sleep term is the live case: the curve was measured on hours people
  /// reported on questionnaires, and questionnaires run long, so the strap's
  /// nightly average is translated to its questionnaire equivalent before the
  /// curve is applied. Null on a term that is read at its own value.
  ///
  /// It is parsed and drawn rather than dropped because the translation is the
  /// thing the server spends a whole caveat disclosing: a panel showing only
  /// [value] would show a number the model did not use.
  final double? comparedAs;
}

/// A motivational biological-age estimate with its levers.
@immutable
class BiologicalAge {
  /// Builds an estimate. Prefer [BiologicalAge.maybe].
  const BiologicalAge({
    required this.biologicalAge,
    required this.chronologicalAge,
    required this.deltaYears,
    required this.contributions,
    required this.disclaimer,
    required this.researchNotes,
    this.exclusions = const <Disclosure>[],
  });

  /// Parses the payload, or null when there is no estimate.
  static BiologicalAge? maybe(Map<String, Object?> json) {
    final years = (json['biological_age'] as num?)?.toDouble();
    if (years == null) {
      return null;
    }
    return BiologicalAge(
      biologicalAge: years,
      chronologicalAge: (json['chronological_age'] as num?)?.toDouble(),
      deltaYears: (json['delta_years'] as num?)?.toDouble(),
      contributions: ageContributionsFrom(json['contributions']),
      disclaimer: json['disclaimer'] as String?,
      researchNotes: researchNotesFrom(json['research_notes']),
      exclusions: ageDisclosuresFrom(json['excluded']),
    );
  }

  /// The estimate, in years.
  final double biologicalAge;

  /// The owner's actual age, for the comparison the number exists to make.
  final double? chronologicalAge;

  /// [biologicalAge] minus [chronologicalAge].
  final double? deltaYears;

  /// The per-lever breakdown. Rendered beside the number, always.
  final List<AgeContribution> contributions;

  /// "Motivational estimate from population data — not a clinical or diagnostic
  /// age." Server-supplied and rendered verbatim: it is a safety statement, and
  /// re-wording a safety statement in the UI layer is how it gets softened.
  final String? disclaimer;

  /// The notes licensing the estimate.
  final List<String> researchNotes;

  /// **`excluded[]`, kept as its own list even when a value arrived.**
  ///
  /// `readingFrom` folds exclusions in with the caveats on a payload that
  /// carries a value, which is right for a card that draws one disclosure line
  /// — but it makes the two indistinguishable, and the screen that opens up
  /// this estimate has a whole panel for the exclusion and a different
  /// disclosure for the caveats. Telling them apart by re-reading a `reason`
  /// string would be a guess; parsing the key the server actually sent is not.
  ///
  /// The [Withheld] case keeps carrying them too. Both are the same claim: the
  /// term is not one of the levers, on a day the number ships and on a day it
  /// does not.
  final List<Disclosure> exclusions;
}

/// `contributions[]`, parsed. The ONE reader of the list: [BiologicalAge.maybe]
/// and `BioAgeBlock` both call it, so a valued day and a withheld day cannot
/// read the same lever two ways.
List<AgeContribution> ageContributionsFrom(Object? raw) => <AgeContribution>[
  for (final entry in (raw is List ? raw : const <Object?>[]))
    if (entry is Map<String, Object?> && entry['term'] is String)
      AgeContribution.fromJson(entry),
];

/// `excluded[]` or `caveats[]`, parsed: every entry with a `reason` and a
/// `message`. An entry missing either is dropped rather than given words.
List<Disclosure> ageDisclosuresFrom(Object? raw) => <Disclosure>[
  for (final entry in (raw is List ? raw : const <Object?>[]))
    if (entry is Map<String, Object?> &&
        entry['reason'] is String &&
        entry['message'] is String)
      Disclosure.fromJson(entry),
];

/// `research_notes[]`, parsed: the note ids, and nothing that is not a string.
List<String> researchNotesFrom(Object? raw) => <String>[
  for (final entry in (raw is List ? raw : const <Object?>[]))
    if (entry is String) entry,
];
