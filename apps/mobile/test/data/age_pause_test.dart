/// Why the biological age is paused, and which profile field would fix it.
///
/// `agePauseOf` is a pure function, so every case the card can be in is a row
/// here rather than a screenshot. The rule under test: a paused estimate always
/// says why, in the server's words wherever the server had any.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/honesty/disclosure.dart';
import 'package:healthee/data/models/age_pause.dart';
import 'package:healthee/data/models/bio_age_block.dart';
import 'package:healthee/data/profile/health_profile.dart';

import '../_bio_age_stubs.dart';

BioAgeBlock _block(List<Map<String, Object?>> terms, {bool keepSleep = true}) =>
    BioAgeBlock.fromJson(
      withheldBioAge(absentTerms: terms, keepSleep: keepSleep),
    );

HealthProfile _profile({
  String? dobDate = '1990-05-01',
  bool legacyBirthday = false,
  double? heightCm = 176,
  String? sex = 'male',
  double? weightKg = 72.5,
  int? weightAgeDays = 3,
}) => HealthProfile(
  dobDate: dobDate,
  legacyBirthdayPresent: legacyBirthday,
  heightCm: heightCm,
  sex: sex,
  weightKg: weightKg,
  weightAgeDays: weightAgeDays,
);

void main() {
  group('a block with absent terms', () {
    test('missing weight points at the weight field', () {
      final pause = agePauseOf(
        block: _block([profileMissingTerm()]),
        vo2maxWithheld: null,
        profile: _profile(weightKg: null, weightAgeDays: null),
      );

      expect(pause.lines.single.message, kProfileMissingMessage);
      expect(pause.lines.single.field, ProfileField.weight);
      expect(pause.action, ProfileField.weight);
      expect(pause.profileAction, isFalse);
    });

    test('the first missing profile field wins, in the server order', () {
      final pause = agePauseOf(
        block: _block([profileMissingTerm()]),
        vo2maxWithheld: null,
        profile: _profile(heightCm: null, weightKg: null),
      );
      expect(pause.action, ProfileField.height);

      final sex = agePauseOf(
        block: _block([profileMissingTerm()]),
        vo2maxWithheld: null,
        profile: _profile(sex: null, weightKg: null),
      );
      expect(sex.action, ProfileField.sex);
    });

    test('a birthday held only by the old server is not missing', () {
      final pause = agePauseOf(
        block: _block([profileMissingTerm()]),
        vo2maxWithheld: null,
        profile: _profile(dobDate: null, legacyBirthday: true, weightKg: null),
      );
      expect(pause.action, ProfileField.weight);
    });

    test('too few nights: the server sentence, verbatim, and no button', () {
      final pause = agePauseOf(
        block: _block([noNightsTerm()], keepSleep: false),
        vo2maxWithheld: null,
        profile: _profile(),
      );

      expect(pause.lines.single.message, kNoNightsMessage);
      expect(pause.lines.single.field, isNull);
      expect(pause.action, isNull);
      expect(pause.profileAction, isFalse);
    });

    test('a stale weight carries its age and points at the weight', () {
      final pause = agePauseOf(
        block: _block([staleWeightTerm()]),
        vo2maxWithheld: null,
        profile: _profile(weightAgeDays: 41),
      );

      expect(pause.lines.single.message, kStaleWeightMessage);
      expect(pause.action, ProfileField.weight);
      expect(pause.staleWeightDays, 41);
    });

    test('no stale-weight age when the profile does not know it', () {
      final pause = agePauseOf(
        block: _block([staleWeightTerm()]),
        vo2maxWithheld: null,
        profile: _profile(weightAgeDays: null),
      );
      expect(pause.staleWeightDays, isNull);
    });

    test('an unanswered activity question points at the activity field', () {
      final pause = agePauseOf(
        block: _block([
          absentTerm(
            term: 'fitness',
            reason: 'srpa_not_reported',
            message: kSrpaMessage,
          ),
        ]),
        vo2maxWithheld: null,
        profile: _profile(),
      );
      expect(pause.action, ProfileField.activity);
      expect(pause.lines.single.message, kSrpaMessage);
    });

    test('two absent terms are two lines, in order; the first button wins', () {
      final pause = agePauseOf(
        block: _block([noNightsTerm(), staleWeightTerm()], keepSleep: false),
        vo2maxWithheld: null,
        profile: _profile(weightAgeDays: 20),
      );

      expect(pause.lines.map((line) => line.message), <String>[
        kNoNightsMessage,
        kStaleWeightMessage,
      ]);
      expect(pause.action, ProfileField.weight);
    });

    test('identical messages are said once', () {
      final pause = agePauseOf(
        block: _block([staleWeightTerm(), staleWeightTerm()]),
        vo2maxWithheld: null,
        profile: _profile(),
      );
      expect(pause.lines, hasLength(1));
    });

    test('the partial case keeps the sleep contribution on the block', () {
      final block = _block([staleWeightTerm()]);
      expect(block.contributions.map((c) => c.term), <String>[
        'sleep duration',
      ]);
      expect(block.isWithheld, isTrue);
    });

    test('an unknown reason code still shows the server text', () {
      final pause = agePauseOf(
        block: _block([
          absentTerm(
            term: 'fitness',
            reason: 'a_reason_added_next_year',
            message: 'Something new the server wants said.',
          ),
        ]),
        vo2maxWithheld: null,
        profile: _profile(),
      );

      expect(
        pause.lines.single.message,
        'Something new the server wants said.',
      );
      expect(pause.action, isNull);
      expect(pause.profileAction, isFalse);
    });

    test('an empty term message falls back to the consequence', () {
      final pause = agePauseOf(
        block: _block([
          absentTerm(term: 'fitness', reason: 'not_derived_yet', message: ''),
        ]),
        vo2maxWithheld: null,
        profile: _profile(),
      );

      expect(pause.lines.single.message, kRequiredTermsMessage);
      expect(pause.lines.single.message, isNotEmpty);
    });

    test(
      'an unknown profile still offers the profile for a profile reason',
      () {
        final pause = agePauseOf(
          block: _block([profileMissingTerm()]),
          vo2maxWithheld: null,
          profile: null,
        );

        expect(pause.lines.single.message, kProfileMissingMessage);
        expect(pause.action, isNull);
        expect(pause.profileAction, isTrue);
        expect(pause.staleWeightDays, isNull);
      },
    );
  });

  group('a block the server sent as null', () {
    const absent = BioAgeBlock.absent;

    test('no date of birth says so and points at it', () {
      final pause = agePauseOf(
        block: absent,
        vo2maxWithheld: null,
        profile: _profile(dobDate: null),
      );

      expect(pause.lines.single.message, kNoDobLine);
      expect(pause.action, ProfileField.dob);
    });

    test('a VO2max refusal explains it, verbatim, with its field', () {
      final pause = agePauseOf(
        block: absent,
        vo2maxWithheld: const Disclosure(
          reason: 'logged_weight_stale',
          message: kStaleWeightMessage,
        ),
        profile: _profile(weightAgeDays: 30),
      );

      expect(pause.lines.single.message, kStaleWeightMessage);
      expect(pause.action, ProfileField.weight);
      expect(pause.staleWeightDays, 30);
    });

    test('a full profile and nothing else says both readings are needed', () {
      final pause = agePauseOf(
        block: absent,
        vo2maxWithheld: null,
        profile: _profile(),
      );

      expect(pause.lines.single.message, kBothTermsLine);
      expect(pause.action, isNull);
      expect(pause.profileAction, isFalse);
    });

    test('an unknown profile says to open it, and offers to', () {
      final pause = agePauseOf(
        block: absent,
        vo2maxWithheld: null,
        profile: null,
      );

      expect(pause.lines.single.message, kUnknownProfileLine);
      expect(pause.profileAction, isTrue);
      expect(pause.action, isNull);
    });

    test('never says the old "bug on our side" sentence', () {
      for (final profile in <HealthProfile?>[
        null,
        _profile(),
        _profile(dobDate: null),
      ]) {
        final pause = agePauseOf(
          block: absent,
          vo2maxWithheld: null,
          profile: profile,
        );
        for (final line in pause.lines) {
          expect(line.message, isNot(contains('bug')));
          expect(line.message.trim(), isNotEmpty);
        }
      }
    });
  });
}
