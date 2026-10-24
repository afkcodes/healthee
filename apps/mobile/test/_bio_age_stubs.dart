/// Server-shaped `biological_age` blocks for the paused-estimate tests.
///
/// `analytics/biological_age.py::_estimate` is what the phone actually receives
/// on a day a term is missing: no number, but the chronological age, the
/// contribution of every term that IS current, the three caveats, the standing
/// exclusion, the disclaimer, the research notes and
/// `data_confidence: insufficient_data`, over a `withheld` block that names each
/// absent term. A fixture that blanked all of that out would pass tests the real
/// payload fails, which is how the card came to print only term names.
///
/// The caveats, exclusion and current contributions are lifted from the committed
/// contract snapshot rather than retyped, so they cannot drift from the wire.
///
/// Not a `*_test.dart` file, so it is never run as a suite.
library;

import '_today_stubs.dart';

/// `derive/freshness.py`: the weight behind the BMI is older than 14 days.
const String kStaleWeightMessage =
    'This estimate runs on your BMI, and the weight behind it is more than 14 '
    'days old, old enough that we would be guessing at your mass, so we won’t '
    'guess at your fitness either. Log a weight and it returns.';

/// `derive/vo2max.py::WITHHOLD_MESSAGES[profile_or_weight_missing]`.
const String kProfileMissingMessage =
    'We need your height, sex and date of birth, plus at least one logged '
    'weight, before this estimate can be computed.';

/// `derive/srpa.py::SRPA_NOT_REPORTED_MESSAGE`.
const String kSrpaMessage =
    'This estimate needs one thing we cannot read off the strap: how much '
    'deliberate aerobic exercise you actually do in a typical week. Answer the '
    'activity-level question in your profile and the estimate returns.';

/// `analytics/biological_age_terms.py::SLEEP_DURATION_MESSAGES`.
const String kNoNightsMessage =
    'No sleep has been recorded in the last 14 nights, so there is no nightly '
    'average to work from. Wear the strap overnight and this comes back.';

/// `REQUIRED_TERMS_MESSAGE`, as the server sends it.
const String kRequiredTermsMessage =
    'Biological age is your chronological age plus each term’s year '
    'contribution, so a term with no current value is not left out: it would '
    'silently assert you sit exactly at the reference for that lever. There is '
    'no biological age to report without all of them. The terms below are the '
    'ones that are current.';

/// One `withheld.terms[]` entry.
Map<String, Object?> absentTerm({
  required String term,
  required String reason,
  required String message,
}) => <String, Object?>{'term': term, 'reason': reason, 'message': message};

/// The fitness term, absent because the weight behind it is stale.
Map<String, Object?> staleWeightTerm() => absentTerm(
  term: 'fitness',
  reason: 'logged_weight_stale',
  message: kStaleWeightMessage,
);

/// The fitness term, absent because the profile lacks an input.
Map<String, Object?> profileMissingTerm() => absentTerm(
  term: 'fitness',
  reason: 'profile_or_weight_missing',
  message: kProfileMissingMessage,
);

/// The sleep term, absent because no night was recorded in the window.
Map<String, Object?> noNightsTerm() => absentTerm(
  term: 'sleep duration',
  reason: 'no_recorded_nights_in_window',
  message: kNoNightsMessage,
);

/// The `biological_age` block of a day the number is paused.
///
/// [absentTerms] are the `withheld.terms[]`. With [keepSleep] the current sleep
/// contribution stays, as it does on the server when only fitness is absent.
Map<String, Object?> withheldBioAge({
  required List<Map<String, Object?>> absentTerms,
  bool keepSleep = true,
}) {
  final real = loadTodayJson()['biological_age']! as Map<String, Object?>;
  final contributions = (real['contributions']! as List<Object?>)
      .cast<Map<String, Object?>>();
  return <String, Object?>{
    'chronological_age': real['chronological_age'],
    'biological_age': null,
    'delta_years': null,
    'data_confidence': 'insufficient_data',
    'withheld': <String, Object?>{
      'consequence': kRequiredTermsMessage,
      'terms': absentTerms,
    },
    'contributions': <Object?>[
      if (keepSleep)
        for (final c in contributions)
          if (c['term'] == 'sleep duration') c,
    ],
    'excluded': real['excluded'],
    'caveats': real['caveats'],
    'disclaimer': real['disclaimer'],
    'research_notes': real['research_notes'],
  };
}

/// A `mutate` for `todayView` that pauses the age with [absentTerms], and
/// optionally withholds the VO2max card with [vo2max] too.
Map<String, Object?> Function(Map<String, Object?>) pausedToday({
  required List<Map<String, Object?>> absentTerms,
  bool keepSleep = true,
  Map<String, Object?>? vo2max,
}) =>
    (json) => <String, Object?>{
      ...json,
      'biological_age': withheldBioAge(
        absentTerms: absentTerms,
        keepSleep: keepSleep,
      ),
      'vo2max': ?vo2max,
    };

/// A `mutate` for `todayView`: the server sent `biological_age: null`.
Map<String, Object?> nullBioAge(Map<String, Object?> json) => <String, Object?>{
  ...json,
  'biological_age': null,
};
