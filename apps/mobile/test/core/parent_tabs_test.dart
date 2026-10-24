/// The `parents` map itself, against `app.js:8`.
///
/// The widget half — that a stranded detail screen draws a control and that the
/// control lands on the mapped tab — is in
/// `test/features/out_of_shell_navigation_test.dart`, with the back rule it
/// belongs to. This file is the lookup on its own: which tab each screen is
/// filed under, and what an unmapped one does. A pure function gets a unit test
/// rather than a fifth pumped router.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/parent_tabs.dart';
import 'package:healthee/core/router.dart';

void main() {
  group('parentTabFor — app.js:8, screen by screen', () {
    test('recovery is filed under Today', () {
      expect(parentTabFor(Routes.recovery), Routes.today);
    });

    test('sleep-history is filed under Sleep', () {
      expect(parentTabFor(Routes.sleepHistory), Routes.sleep);
    });

    test('the metric screens are filed under Insights', () {
      // `metric`, `metrics` and `insight` are three prototype routes and two
      // app ones — `/history` is both the directory and one metric's series.
      expect(parentTabFor(Routes.history), Routes.insights);
      expect(parentTabFor('${Routes.insight}/caffeine-sleep'), Routes.insights);
    });

    test('the workout, GPS and fitness screens are filed under Activity', () {
      for (final String location in <String>[
        Routes.workouts,
        Routes.workout,
        Routes.routes,
        Routes.gps,
        Routes.fitness,
        Routes.body,
        '${Routes.route}/2026-07-31T07:00:00Z',
      ]) {
        expect(parentTabFor(location), Routes.activity, reason: location);
      }
    });

    test('the challenge, program and journal screens are filed under Actions', () {
      for (final String location in <String>[
        Routes.coachLedger,
        Routes.recommendations,
        Routes.journal,
        '${Routes.challenge}/7',
        '${Routes.program}/3',
      ]) {
        expect(parentTabFor(location), Routes.actions, reason: location);
      }
    });
  });

  group('what the lookup does with the paths it was not given', () {
    test('A QUERY DOES NOT CHANGE WHICH TAB A SCREEN LIVES UNDER', () {
      // `/history?metric=hrv` is the metric detail; `/history` is the
      // directory. Both are Insights, and splitting on `?` is what makes the
      // first one resolve at all rather than falling through to Today.
      expect(parentTabFor('${Routes.history}?metric=hrv'), Routes.insights);
    });

    test('AN UNMAPPED SCREEN GOES TO TODAY, as the prototype does', () {
      // `H.back()` ends `|| 'today'`. Coach is deliberately unmapped in both:
      // five tabs open it, so no one tab owns it.
      expect(parentTabFor('/coach'), Routes.today);
      expect(parentTabFor(Routes.settings), Routes.today);
      expect(parentTabFor('/nothing-like-this'), Routes.today);
    });

    test('a settings sub-path resolves through its first segment', () {
      expect(parentTabFor(Routes.appearance), Routes.today);
    });

    test('the root and the empty string are answerable', () {
      // The redirect can hand this in during a restore, and a lookup that threw
      // would take the back control down with it.
      expect(parentTabFor(Routes.today), Routes.today);
      expect(parentTabFor(''), Routes.today);
    });
  });
}
