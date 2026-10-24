/// The whole `biological_age` block, parsed whether or not it carries a number.
///
/// ## Why this exists beside [BiologicalAge]
///
/// `readingFrom` decides the block's honesty first and returns `Withheld` before
/// the value parser ever runs, which is right for the honesty union and wrong
/// for everything else the server sent on that day. A withheld day still ships
/// the chronological age, the contribution of every term that IS current, the
/// three caveats, the disclaimer, the research notes and `data_confidence`
/// (`analytics/biological_age.py::_estimate`). Read only through the reading,
/// all of that was dropped on the floor, and the per-term reasons survived only
/// as names on a card.
///
/// This model is the other half: it never decides whether there is a number. It
/// keeps what was said. The `Reading<BiologicalAge>` beside it on
/// `TodaySnapshot` is untouched and still the one thing that decides.
///
/// A block the server sent as `null` (no date of birth, no profile, or no term
/// current at all: `biological_age.py` returns `None` for each) parses to
/// [BioAgeBlock.absent] with [present] false. That is a state the server sends
/// on purpose, and the caller explains it rather than calling it a bug.
library;

import 'package:healthee/data/honesty/disclosure.dart';
import 'package:healthee/data/models/biological_age.dart';
import 'package:meta/meta.dart';

/// Everything the server said about biological age on one day.
@immutable
class BioAgeBlock {
  /// Builds a block. Prefer [BioAgeBlock.fromJson].
  const BioAgeBlock({
    required this.present,
    this.chronologicalAge,
    this.dataConfidence,
    this.contributions = const <AgeContribution>[],
    this.caveats = const <Disclosure>[],
    this.exclusions = const <Disclosure>[],
    this.disclaimer,
    this.researchNotes = const <String>[],
    this.consequence,
    this.absentTerms = const <Disclosure>[],
  });

  /// Parses the raw `biological_age` value, whatever it is.
  factory BioAgeBlock.fromJson(Object? raw) {
    if (raw is! Map<String, Object?>) {
      return absent;
    }
    final withheld = raw['withheld'];
    final refusal = withheld is Map<String, Object?>
        ? withheld
        : const <String, Object?>{};
    return BioAgeBlock(
      present: true,
      chronologicalAge: (raw['chronological_age'] as num?)?.toDouble(),
      dataConfidence: raw['data_confidence'] as String?,
      contributions: ageContributionsFrom(raw['contributions']),
      caveats: ageDisclosuresFrom(raw['caveats']),
      exclusions: ageDisclosuresFrom(raw['excluded']),
      disclaimer: raw['disclaimer'] as String?,
      researchNotes: researchNotesFrom(raw['research_notes']),
      consequence: refusal['consequence'] as String?,
      absentTerms: _absentTerms(refusal),
    );
  }

  /// The server sent `biological_age: null`, or no key at all.
  static const BioAgeBlock absent = BioAgeBlock(present: false);

  /// False when the server sent no block at all.
  final bool present;

  /// The owner's age on the day, in years.
  final double? chronologicalAge;

  /// `ok`, or `insufficient_data` on a withheld day. Null when not sent.
  final String? dataConfidence;

  /// The terms that ARE current. On a withheld day these are the ones that
  /// survived; the server never adds a contribution for an absent term.
  final List<AgeContribution> contributions;

  /// Which way the terms lean. Sent on withheld days too.
  final List<Disclosure> caveats;

  /// Levers the estimate permanently does not price.
  final List<Disclosure> exclusions;

  /// The server's safety line, verbatim.
  final String? disclaimer;

  /// The notes licensing the estimate.
  final List<String> researchNotes;

  /// `withheld.consequence`: why one absent term takes the whole number.
  final String? consequence;

  /// `withheld.terms[]`: each absent term, its reason id and the server's own
  /// remedy. A term with an empty or missing message is kept with an empty
  /// message so its reason still counts; the caller supplies the fallback.
  final List<Disclosure> absentTerms;

  /// Whether the server refused the number today.
  bool get isWithheld => absentTerms.isNotEmpty;

  /// `withheld.terms[]`, or, for a refusal that names no terms and carries a
  /// single `reason` and `message` of its own, that one sentence as one term.
  /// Either way a sentence the server wrote is kept rather than dropped.
  static List<Disclosure> _absentTerms(Map<String, Object?> refusal) {
    final terms = <Disclosure>[
      for (final entry
          in (refusal['terms'] is List
              ? refusal['terms']! as List<Object?>
              : const <Object?>[]))
        if (entry is Map<String, Object?> && entry['reason'] is String)
          Disclosure(
            reason: entry['reason']! as String,
            message: entry['message'] is String
                ? entry['message']! as String
                : '',
            term: entry['term'] as String?,
          ),
    ];
    if (terms.isEmpty && refusal['reason'] is String) {
      return <Disclosure>[
        Disclosure(
          reason: refusal['reason']! as String,
          message: refusal['message'] is String
              ? refusal['message']! as String
              : '',
        ),
      ];
    }
    return terms;
  }
}
