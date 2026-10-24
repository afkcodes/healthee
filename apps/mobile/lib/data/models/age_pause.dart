/// Why the biological age is paused today, and what would bring it back.
///
/// A pure function over what the server sent and what the profile holds, so
/// every case is a unit test rather than a screenshot. The rule it enforces is
/// the one the card used to break: **a paused estimate always says why.** The
/// server's own sentence is shown verbatim wherever there is one; the app
/// writes a sentence of its own only for the one state the server explains by
/// sending nothing (`biological_age: null`), and then only claims what the
/// profile it can see supports.
library;

import 'package:healthee/core/profile_field.dart';
import 'package:healthee/data/honesty/disclosure.dart';
import 'package:healthee/data/models/bio_age_block.dart';
import 'package:healthee/data/profile/health_profile.dart';
import 'package:meta/meta.dart';

export 'package:healthee/core/profile_field.dart';

/// `vo2max.py` WITHHOLD reason: height, sex, date of birth or weight missing.
const String kProfileOrWeightMissing = 'profile_or_weight_missing';

/// The logged weight behind the BMI is older than the freshness horizon.
const String kLoggedWeightStale = 'logged_weight_stale';

/// The activity self-report the non-exercise model needs was not answered.
const String kSrpaNotReported = 'srpa_not_reported';

/// The reasons a profile edit fixes, so the caller knows to read the profile.
const Set<String> kProfileReasons = <String>{
  kProfileOrWeightMissing,
  kLoggedWeightStale,
  kSrpaNotReported,
};

/// Said when the server sent no block and the profile has no date of birth.
const String kNoDobLine =
    'Your date of birth is not in your profile. The estimate starts from your '
    'age.';

/// Said when the server sent no block and the profile explains none of it.
const String kBothTermsLine =
    'Fitness and sleep both need a current reading before this can be '
    'estimated.';

/// Said when the server sent no block and the profile could not be read.
const String kUnknownProfileLine =
    'The estimate needs your profile and recent readings. Open your profile to '
    'check it.';

/// One sentence of the explanation, and the profile field that fixes it.
@immutable
class PauseLine {
  /// Builds a line.
  const PauseLine(this.message, {this.field, this.term});

  /// The sentence, shown as it is.
  final String message;

  /// The field that would fix it, or null when only time fixes it.
  final ProfileField? field;

  /// Which term of the estimate it is about, when the server said.
  final String? term;
}

/// The whole explanation, never empty.
@immutable
class AgePause {
  /// Builds an explanation.
  const AgePause({
    required this.lines,
    this.action,
    this.profileAction = false,
    this.staleWeightDays,
  });

  /// One per reason, in the server's order, duplicates removed.
  final List<PauseLine> lines;

  /// The field the one primary button opens, or null when none does.
  final ProfileField? action;

  /// Whether a profile edit is the fix but the field is unknown, because the
  /// profile itself could not be read. The button then opens the profile plain.
  final bool profileAction;

  /// How old the stored weight is, when a line is about the weight.
  final int? staleWeightDays;
}

/// Why the estimate is paused.
///
/// [block] is the server's `biological_age` block; [vo2maxWithheld] the VO2max
/// card's own refusal, when it has one; [profile] the owner's profile, or null
/// while it is unknown.
AgePause agePauseOf({
  required BioAgeBlock block,
  required Disclosure? vo2maxWithheld,
  required HealthProfile? profile,
}) {
  final lines = <PauseLine>[];
  var profileAction = false;
  var weightLine = false;

  void add(PauseLine line) {
    if (line.message.trim().isEmpty ||
        lines.any((held) => held.message == line.message)) {
      return;
    }
    lines.add(line);
  }

  PauseLine lineFor(Disclosure said, String fallback) {
    final field = _fieldOf(said.reason, profile);
    // A profile reason always offers the profile: on a field when the profile
    // names one, plain when it is unknown or names none.
    if (field == null && kProfileReasons.contains(said.reason)) {
      profileAction = true;
    }
    if (field == ProfileField.weight) {
      weightLine = true;
    }
    final message = said.message.trim().isEmpty ? fallback : said.message;
    return PauseLine(message, field: field, term: said.term);
  }

  // A present block with no absent terms is a shape the server does not send;
  // it is explained the way a missing block is rather than with nothing.
  if (block.present && block.absentTerms.isNotEmpty) {
    final consequence = block.consequence ?? '';
    for (final term in block.absentTerms) {
      add(lineFor(term, consequence));
    }
  } else {
    if (profile != null && _dobMissing(profile)) {
      add(const PauseLine(kNoDobLine, field: ProfileField.dob));
    }
    if (vo2maxWithheld != null) {
      add(lineFor(vo2maxWithheld, ''));
    }
    if (lines.isEmpty && profile != null && !_dobMissing(profile)) {
      add(const PauseLine(kBothTermsLine));
    }
  }
  if (lines.isEmpty) {
    profileAction = true;
    lines.add(const PauseLine(kUnknownProfileLine));
  }

  final action = <ProfileField?>[
    for (final line in lines) line.field,
  ].whereType<ProfileField>().firstOrNull;
  return AgePause(
    lines: List<PauseLine>.unmodifiable(lines),
    action: action,
    profileAction: action == null && profileAction,
    staleWeightDays: weightLine ? profile?.weightAgeDays : null,
  );
}

/// Whether the profile holds no date of birth, current or legacy.
bool _dobMissing(HealthProfile profile) =>
    profile.dobDate == null && !profile.legacyBirthdayPresent;

/// The field a reason points at, or null when time is the fix.
ProfileField? _fieldOf(String reason, HealthProfile? profile) {
  switch (reason) {
    case kLoggedWeightStale:
      return ProfileField.weight;
    case kSrpaNotReported:
      return ProfileField.activity;
    case kProfileOrWeightMissing:
      if (profile == null) {
        return null;
      }
      if (_dobMissing(profile)) {
        return ProfileField.dob;
      }
      if (profile.heightCm == null) {
        return ProfileField.height;
      }
      if (profile.sex == null) {
        return ProfileField.sex;
      }
      if (profile.weightKg == null) {
        return ProfileField.weight;
      }
      return null;
    default:
      return null;
  }
}
