/// The whole `biological_age` block survives a day the number is paused.
///
/// `readingFrom` returns `Withheld` before the value parser runs, so everything
/// else the server sent that day used to be dropped. `BioAgeBlock` keeps it.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/honesty/reading.dart';
import 'package:healthee/data/models/bio_age_block.dart';
import 'package:healthee/data/models/biological_age.dart';
import 'package:healthee/data/models/today_snapshot.dart';

import '../_bio_age_stubs.dart';
import '../_today_stubs.dart';

void main() {
  test('the committed snapshot parses whole', () {
    final block = BioAgeBlock.fromJson(loadTodayJson()['biological_age']);

    expect(block.present, isTrue);
    expect(block.isWithheld, isFalse);
    expect(block.chronologicalAge, 36);
    expect(block.dataConfidence, 'ok');
    expect(block.contributions.map((c) => c.term), <String>[
      'fitness',
      'sleep duration',
    ]);
    expect(block.caveats, hasLength(3));
    expect(block.exclusions, hasLength(1));
    expect(block.disclaimer, startsWith('Motivational estimate'));
    expect(block.researchNotes, <String>['biological_age_estimate']);
  });

  test(
    'a paused day keeps contributions, caveats, disclaimer and confidence',
    () {
      final block = BioAgeBlock.fromJson(
        withheldBioAge(absentTerms: <Map<String, Object?>>[staleWeightTerm()]),
      );

      expect(block.present, isTrue);
      expect(block.isWithheld, isTrue);
      expect(block.dataConfidence, 'insufficient_data');
      expect(block.chronologicalAge, 36);
      expect(block.contributions.map((c) => c.term), <String>[
        'sleep duration',
      ]);
      expect(block.caveats, hasLength(3));
      expect(block.exclusions, hasLength(1));
      expect(block.disclaimer, isNotNull);
      expect(block.researchNotes, isNotEmpty);
      expect(block.consequence, kRequiredTermsMessage);
      expect(block.absentTerms.single.reason, 'logged_weight_stale');
      expect(block.absentTerms.single.message, kStaleWeightMessage);
      expect(block.absentTerms.single.term, 'fitness');
    },
  );

  test('the snapshot carries the block beside an untouched reading', () {
    final json = <String, Object?>{
      ...loadTodayJson(),
      'biological_age': withheldBioAge(
        absentTerms: <Map<String, Object?>>[staleWeightTerm()],
      ),
    };
    final snapshot = TodaySnapshot.fromJson(json);

    expect(snapshot.biologicalAge, isA<Withheld<BiologicalAge>>());
    expect(snapshot.bioAgeBlock.contributions, hasLength(1));
    expect(snapshot.bioAgeBlock.caveats, hasLength(3));
  });

  test('a null block parses to absent, not to an error', () {
    final snapshot = TodaySnapshot.fromJson(nullBioAge(loadTodayJson()));

    expect(snapshot.bioAgeBlock.present, isFalse);
    expect(snapshot.bioAgeBlock.contributions, isEmpty);
    expect(snapshot.bioAgeBlock.absentTerms, isEmpty);
    expect(BioAgeBlock.fromJson('not an object').present, isFalse);
  });

  test('a lone reason and message is kept as one absent term', () {
    final block = BioAgeBlock.fromJson(const <String, Object?>{
      'biological_age': null,
      'withheld': <String, Object?>{
        'reason': 'not_derived_yet',
        'message': 'Sync the strap.',
      },
    });

    expect(block.absentTerms.single.reason, 'not_derived_yet');
    expect(block.absentTerms.single.message, 'Sync the strap.');
  });

  test('one reader of contributions serves both models', () {
    final raw = loadTodayJson()['biological_age']! as Map<String, Object?>;
    final age = BiologicalAge.maybe(raw)!;
    final block = BioAgeBlock.fromJson(raw);

    expect(
      age.contributions.map((c) => c.term),
      block.contributions.map((c) => c.term),
    );
  });
}
