/// `/api/sleep` and `/api/sleep/consistency`, parsed off the committed contract.
///
/// The models are the boundary Standards §3 asks for — "the data layer parses
/// JSON into typed models; feature code never reads raw `Map<String, dynamic>`"
/// — and the interesting half of that boundary here is which [Reading] case each
/// field lands in. `data/honesty/sleep_gap.dart` decides that from the payload's
/// SHAPE, so these tests take the shape apart.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/stage_colors.dart';
import 'package:healthee/data/honesty/reading.dart';
import 'package:healthee/data/honesty/sleep_gap.dart';
import 'package:healthee/data/models/sleep_consistency.dart';
import 'package:healthee/features/sleep/sleep_format.dart';
import 'package:healthee/shared/format/duration.dart';

import '../_sleep_stubs.dart';

void main() {
  group('the sleep page', () {
    test('parses the contract snapshot', () {
      final page = sleepPageFixture();
      expect(page.nights, isNotEmpty);
      final night = page.latest!;
      expect(night.tstMin, const Present<double>(380));
      expect(night.efficiencyPct, const Present<double>(84.4));
      expect(night.stages!.total, 400);
      expect(night.timeline, hasLength(3));
      expect(night.start, isNotNull);
    });

    test('A NIGHT WITH NO SESSION BLAMES THE SESSION, NOT THE SERVER', () {
      // The three gaps are read off the payload's own shape. Getting this wrong
      // is not a wrong pixel — it is telling the owner to sync when the strap
      // was in a drawer, or the reverse.
      final night = sleepPageWithout(<String>[
        'session_source',
        'start_iso',
        'end_iso',
        'tst_min',
        'spo2_avg',
      ]).nights.first;
      expect(night.start, isNull);
      expect(
        (night.tstMin as Withheld<double>).disclosure.reason,
        SleepGap.noSession.reason,
      );
      expect(
        (night.spo2Avg as Withheld<double>).disclosure.reason,
        SleepGap.noSession.reason,
      );
    });

    test('a session with no physiology blames the SAMPLES', () {
      final night = sleepPageWithout(<String>['spo2_avg', 'rhr']).nights.first;
      expect(
        (night.spo2Avg as Withheld<double>).disclosure.reason,
        SleepGap.notSampled.reason,
        reason: 'the strap logs SpO₂ on a schedule; a gap is a sampling gap',
      );
      expect(
        (night.restingHr as Withheld<double>).disclosure.reason,
        SleepGap.notDerived.reason,
        reason: 'resting HR is the SERVER\'s `rhr_daily`, not a raw sample',
      );
    });

    test('a point is a bool, and a missing point is neither pass nor fail', () {
      final scored = sleepPageFixture().nights.first;
      expect(scored.pointDuration, const Present<bool>(true));
      expect(scored.pointTiming, const Present<bool>(false));

      final unscored = sleepPageWithout(<String>['point_timing']).nights.first;
      expect(unscored.pointTiming, isA<Withheld<bool>>());
      expect(unscored.pointTiming.valueOrNull, isNull);
    });
  });

  group('the regularity block', () {
    test('parses the contract snapshot', () {
      final block = consistencyFixture();
      expect(block.medianBedtime, '23:00');
      expect(block.hasBand, isTrue);
      expect(block.sri, const Present<double>(74));
      expect(block.tonight, isNull, reason: 'the snapshot is a free owner’s');
    });

    test('SRI ARRIVES WITHHELD WHEN THE SERVER SAYS SO', () {
      // `read/sleep_extras.py::_sri_block` nulls `sri` and moves the value into
      // `sri_withheld`. Legacy read `data['sri']`, found null and drew nothing.
      final block = SleepConsistency.fromJson(<String, Object?>{
        ...loadJson(kConsistencySnapshotPath),
        'sri': null,
        'sri_withheld': const <String, Object?>{
          'reason': 'not_derived_yet',
          'message': 'Wear the strap for a week and this comes back.',
          'last_as_of_date': '2026-07-01',
          'age_days': 30,
        },
      });
      final withheld = block.sri;
      expect(withheld, isA<Withheld<double>>());
      expect(
        (withheld as Withheld<double>).disclosure.message,
        'Wear the strap for a week and this comes back.',
      );
      expect(withheld.disclosure.asOfDate, '2026-07-01');
    });

    test(
      'the tonight lever prefers the coach line over the deterministic one',
      () {
        final withBoth = TonightLever.maybe(<String, Object?>{
          'title': 'Tonight',
          'lever': 'wake',
          'coach': 'the model wrote this',
          'action': 'the fallback',
        })!;
        expect(withBoth.prose, 'the model wrote this');

        final fallback = TonightLever.maybe(<String, Object?>{
          'title': 'Tonight',
          'lever': 'bedtime',
          'coach': '   ',
          'action': 'the fallback',
        })!;
        expect(fallback.prose, 'the fallback');
      },
    );
  });

  group('the formatters', () {
    test('legacy’s strings, to the character', () {
      expect(durationText(425), '7\u00A0h 5\u00A0min');
      expect(durationText(60), '1\u00A0h');
      expect(durationText(35), '35\u00A0min');
      expect(durationText(80), '1\u00A0h 20\u00A0min');
      expect(clock(DateTime(2026, 8, 4, 23, 30)), '11:30p');
      expect(clock(DateTime(2026, 8, 4, 0, 5)), '12:05a');
      expect(
        napRange(DateTime(2026, 8, 4, 14, 30), DateTime(2026, 8, 4, 15, 5)),
        '2:30 pm–3:05 pm',
      );
      expect(weekdayInitials('2026-08-04'), 'Tu');
    });

    test('ONE SHORT DATE, not two orderings one card apart', () {
      // Legacy had `_napDate` → `4 Aug` in the naps column and `_shortDate` →
      // `Aug 4` in the odd-nights list, both on the Sleep tab. There is one
      // function now, and it answers day-month.
      expect(shortDate('2026-08-04'), '4 Aug');
      expect(shortDate('2026-01-31'), '31 Jan');
      // An unparseable date says nothing rather than leaking the raw ISO into a
      // 50 px column — `_shortDate` echoed it back.
      expect(shortDate('not-a-date'), '');
      expect(shortDate(null), '');
    });

    test('THE 18:00 SCALE RUNS THROUGH MIDNIGHT WITHOUT WRAPPING', () {
      // The whole point of legacy's `_hoursFrom6pm`: a bedtime at 23:00 and a
      // wake at 06:00 must sort on one axis, or the timing chart draws a line
      // that leaps the height of the plot every night.
      expect(hoursFrom6pm(DateTime(2026, 8, 4, 18)), 0);
      expect(hoursFrom6pm(DateTime(2026, 8, 4, 22)), 4);
      expect(hoursFrom6pm(DateTime(2026, 8, 5)), 6);
      expect(hoursFrom6pm(DateTime(2026, 8, 5, 6)), 12);
    });

    test('a stale session is NEVER captioned as last night', () {
      final end = DateTime(2026, 8, 3, 7);
      expect(nightLabel(end, DateTime(2026, 8, 3, 9)), 'Last night');
      expect(nightLabel(end, DateTime(2026, 8, 4, 9)), 'Night before last');
      expect(nightLabel(end, DateTime(2026, 8, 6, 9)), '3 nights ago');
      expect(noSleepLastNight(end, DateTime(2026, 8, 3, 9)), isFalse);
      expect(noSleepLastNight(end, DateTime(2026, 8, 4, 9)), isTrue);
    });

    test('A STAGE THE STRAP DID NOT NAME IS NOT LAUNDERED INTO LIGHT SLEEP', () {
      // Legacy's `_normStage` ended `return 'core'`, so an unreadable code
      // became a named stage here, one layer BEFORE the colour mapping — fixing
      // only `sleepStage` would have left this path turning it blue anyway.
      expect(normaliseStage('deepSleep'), 'deep');
      expect(normaliseStage('REM'), 'rem');
      expect(normaliseStage('awake'), 'awake');
      expect(normaliseStage('light'), 'core');
      expect(normaliseStage('core'), 'core');
      expect(normaliseStage('something-nobody-measured'), kUnrecognisedStage);
      expect(normaliseStage(null), kUnrecognisedStage);
      expect(normaliseStage(''), kUnrecognisedStage);
    });
  });
}
