/// Legacy's Today vocabulary — the exact words, and the two repaired flaws.
///
/// `today_labels.dart` is where a number becomes the string legacy prints, so
/// these are the assertions that a port stayed a port. Two of them assert the
/// opposite of legacy on purpose, and both are marked.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/features/today/today_labels.dart';
import 'package:healthee/shared/format/duration.dart';

void main() {
  group('the figures', () {
    test('four digits and up are comma-grouped, and nothing else is', () {
      expect(commaGrouped(9264), '9,264');
      expect(commaGrouped(412), '412');
      expect(commaGrouped(1234567), '1,234,567');
    });

    test('a duration reads as a clock in a tile and as words elsewhere', () {
      expect(clockDuration(380), '6:20');
      expect(durationText(380), '6\u00A0h 20\u00A0min');
      expect(hoursText(380 / 60), '6.3\u00A0h');
    });

    test(
      'a median under 1000 is not grouped; 14-DAY TREND when there is none',
      () {
        expect(medianFoot(55), 'MED 55');
        expect(medianFoot(9264), 'MED 9,264');
        expect(medianFoot(null), '14-DAY TREND');
      },
    );
  });

  group('the stage foot', () {
    test('percentages are of time ASLEEP, so awake is not in the denominator', () {
      // 90 deep + 200 light + 90 rem = 380 asleep; the 20 awake minutes are not
      // part of it. Counting them would make every night look lighter than it was.
      const totals = <String, int>{
        'deep': 90,
        'light': 200,
        'rem': 90,
        'awake': 20,
      };
      expect(stageFoot(totals), 'DEEP 24% · REM 24%');
    });

    test('a night with no stages prints dashes, never zeroes', () {
      // A zero is a measurement. This is the absence of one.
      expect(stageFoot(const <String, int>{}), 'DEEP — · REM —');
    });
  });

  // The `hypnogram spans` group lived here. `hypnogramSpans` went with the Sleep
  // tile's hypnogram (owner-delegated departure, 2026-08-06 — `today_tiles.dart`),
  // and its two assertions did not evaporate: `HStageBar` drops zero-minute
  // stages itself and draws NOTHING for a night with none, which
  // `test/features/grid_sleep_cell_test.dart` asserts against the real widget
  // rather than against a helper feeding it.

  group('the sleep-night label', () {
    final now = DateTime(2026, 8, 4, 9, 30);

    test('counts CALENDAR days from waking, not hours', () {
      // A nap that ended at 02:00 this morning is still last night, even though
      // it ended more than 24 h after the previous one.
      expect(sleepNightLabel('2026-08-04T02:00:00', now), 'Last night');
      expect(sleepNightLabel('2026-08-03T07:00:00', now), 'Night before last');
      expect(sleepNightLabel('2026-08-01T07:00:00', now), '3 nights ago');
    });

    test('an unknown or unparseable end falls back to "Last night"', () {
      expect(sleepNightLabel(null, now), 'Last night');
      expect(sleepNightLabel('not-a-date', now), 'Last night');
    });

    test('the stale banner fires at 24 hours, and not before', () {
      expect(noSleepLastNight('2026-08-03T10:00:00', now), isFalse);
      expect(noSleepLastNight('2026-08-03T09:00:00', now), isTrue);
      expect(noSleepLastNight(null, now), isFalse);
    });
  });

  group('the delta direction', () {
    test('higher is good for some metrics and bad for others', () {
      expect(favorableDirection('hrv_sleep_avg', 1.2), isTrue);
      expect(favorableDirection('hrv_sleep_avg', -1.2), isFalse);
      // A LOW resting heart rate is the good one, which is the whole point of
      // the table.
      expect(favorableDirection('rhr_daily', -1.2), isTrue);
      expect(favorableDirection('rhr_daily', 1.2), isFalse);
    });

    test('EXACTLY ZERO HAS NO DIRECTION', () {
      // A reading sitting on its own median has not moved, and a badge is a
      // claim that it has.
      expect(favorableDirection('rhr_daily', 0), isNull);
      expect(favorableDirection('rhr_daily', null), isNull);
    });
  });

  group('the clock captions', () {
    test('legacy\'s short format, from a real hour', () {
      expect(shortClock(0), '12a');
      expect(shortClock(6), '6a');
      expect(shortClock(12), '12p');
      expect(shortClock(18), '6p');
      expect(shortClock(23), '11p');
    });
  });

  group('the date eyebrow', () {
    test(
      'abbreviates, and keeps an unreadable date rather than blanking it',
      () {
        expect(prettyDate('2026-08-04'), 'TUE · AUG 4');
        expect(prettyDate('nonsense'), 'NONSENSE');
      },
    );
  });
}
