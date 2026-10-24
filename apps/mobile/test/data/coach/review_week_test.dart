import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/coach/review_models.dart';
import 'package:healthee/data/coach/review_week.dart';

import '../../features/coach/_coach_home_fakes.dart';

void main() {
  group('coachWeekBounds mirrors the server week_bounds', () {
    test('a weekday is in the week it is in', () {
      for (final day in <DateTime>[
        DateTime(2026, 10, 19), // Monday
        DateTime(2026, 10, 21),
        DateTime(2026, 10, 24), // Saturday
      ]) {
        expect(coachWeekBounds(day), (from: '2026-10-19', to: '2026-10-25'));
      }
    });

    test('Sunday looks ahead: the review sets next week\'s job', () {
      expect(coachWeekBounds(DateTime(2026, 10, 25)), (
        from: '2026-10-26',
        to: '2026-11-01',
      ));
    });

    test('across a year end, both days', () {
      expect(coachWeekBounds(DateTime(2026, 12, 30)), (
        from: '2026-12-28',
        to: '2027-01-03',
      ));
      expect(coachWeekBounds(DateTime(2026, 12, 27)), (
        from: '2026-12-28',
        to: '2027-01-03',
      ));
    });

    test('a time of day changes nothing', () {
      expect(coachWeekBounds(DateTime(2026, 10, 25, 23, 59)), (
        from: '2026-10-26',
        to: '2026-11-01',
      ));
    });
  });

  test('mondayOf', () {
    expect(isoDay(mondayOf(DateTime(2026, 10, 25))), '2026-10-19');
    expect(isoDay(mondayOf(DateTime(2026, 10, 19))), '2026-10-19');
  });

  group('the review parses defensively', () {
    test('blank texts are null and a job without an id is no job', () {
      final parsed = CoachReview.fromJson(<String, Object?>{
        'week_from': '2026-10-19',
        'week_to': '2026-10-25',
        'review': '   ',
        'pattern': null,
        'job': <String, Object?>{'action': 'walk', 'target': 20},
        'generated_at': 'not a date',
        'cached': 'yes',
      });
      expect(parsed.review, isNull);
      expect(parsed.pattern, isNull);
      expect(parsed.job, isNull);
      expect(parsed.generatedAt, isNull);
      expect(parsed.cached, isFalse);
      expect(parsed.researchNoteIds, isEmpty);
    });

    test('the committed snapshot round-trips its job', () {
      final job = review().job!;
      expect(job.challengeId, 12);
      expect(job.daysRequired, 4);
      expect(job.withSlot('at 7:30 pm').slot, 'at 7:30 pm');
      expect(job.withSlot('at 7:30 pm').floor, job.floor);
    });
  });
}
