/// **A withheld field renders as withheld, with its reason, on every panel.**
///
/// The failure this suite exists to catch is a quiet one: a field the server
/// refused, rendered as a blank or a zero. A zero is a measurement — it says the
/// owner slept nothing, weighed nothing, breathed nothing — and a blank says
/// nothing at all. `Reading` makes the refusal a type, and this suite is the
/// proof that every Sleep panel still renders that type as words the owner can
/// act on.
///
/// Each case blanks a field on the committed contract snapshot and asserts the
/// server's own sentence reaches the screen. Blanking is the one thing a fixture
/// read from a snapshot cannot do on its own, which is what `sleepPageWithout`
/// is for — and it asserts the field is really on the wire first, so a rename
/// fails the suite instead of quietly making every case vacuous.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/honesty/sleep_gap.dart';
import 'package:healthee/data/models/sleep_night.dart';
import 'package:healthee/features/sleep/sleep_windows.dart';
import 'package:healthee/features/sleep/v02/checks_panel.dart';
import 'package:healthee/features/sleep/v02/need_panel.dart';
import 'package:healthee/features/sleep/v02/sleep_reading.dart';
import 'package:healthee/features/sleep/v02/trend_panels.dart';
import 'package:healthee/features/sleep/v02/vitals_panel.dart';
import 'package:healthee/shared/reveal_once.dart';

import '../_sleep_stubs.dart';
import '_sleep_host.dart';

/// The sentence the server sends for a metric it has not derived.
final String _notDerived = SleepGap.notDerived.message;

/// The sentence it sends for a signal it did not sample.
final String _notSampled = SleepGap.notSampled.message;

void main() {
  setUpAll(loadSleepFont);

  group('the reading at the top of the screen', () {
    testWidgets('A WITHHELD TIME ASLEEP IS A DASH AND A REASON, NEVER A ZERO', (
      tester,
    ) async {
      final page = sleepPageWithout(<String>['tst_min']);
      await tester.pumpWidget(
        sleepPanelHost(SleepReading(night: page.nights.first)),
      );
      await tester.pumpAndSettle();

      expect(find.text('—'), findsWidgets);
      expect(find.textContaining('Time asleep: $_notDerived'), findsOneWidget);
      // The zero a nullable double would have produced.
      expect(find.text('0\u00A0min'), findsNothing);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('a withheld device score keeps its caption and says why', (
      tester,
    ) async {
      final page = sleepPageWithout(<String>['zepp_score']);
      await tester.pumpWidget(
        sleepPanelHost(SleepReading(night: page.nights.first)),
      );
      await tester.pumpAndSettle();

      expect(find.text(kDeviceScoreCaption), findsOneWidget);
      expect(
        find.textContaining("The strap's sleep score: $_notDerived"),
        findsOneWidget,
      );
    });

    test(
      'an unmeasured time in bed drops its figure rather than writing a dash',
      () {
        // A legend entry for a value nobody has is not a smaller truth, it is
        // noise — and the refusal is still stated, in the note under the block.
        final page = sleepPageWithout(<String>['tib_min']);
        final night = page.nights.first;
        expect(
          SleepReading.stats(night).map((stat) => stat.$1),
          isNot(contains('Time in bed')),
        );
        expect(SleepReading.refusals(night), contains(contains('Time in bed')));
      },
    );
  });

  group('the overnight table', () {
    testWidgets('EVERY REFUSED MEASUREMENT NAMES ITSELF AND ITS REASON', (
      tester,
    ) async {
      final page = sleepPageWithout(<String>[
        'spo2_avg',
        'respiratory_rate',
        'skin_temp_c',
      ]);
      final windows = SleepWindows(page, kSleepNow);
      await tester.pumpWidget(
        sleepPanelHost(
          OvernightPanel(
            night: windows.latest,
            recent: windows.recent,
            reveals: RevealRegistry(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final label in <String>[
        'Blood oxygen',
        'Breathing',
        'Skin temperature',
      ]) {
        expect(
          find.textContaining('$label: $_notSampled'),
          findsOneWidget,
          reason: label,
        );
      }
      // And the measured half of the table is untouched, so this is three rows
      // falling silent rather than the panel failing.
      expect(find.text('Resting heart'), findsOneWidget);
      expect(find.text('HRV'), findsOneWidget);
    });

    test('a full payload writes no refusal line at all', () {
      final windows = SleepWindows(sleepPageFixture(), kSleepNow);
      final panel = OvernightPanel(
        night: windows.latest,
        recent: windows.recent,
        reveals: RevealRegistry(),
      );
      expect(OvernightPanel.refusals(panel.vitals), isEmpty);
    });
  });

  group('the four checks', () {
    testWidgets('a refused reading draws no verdict and says what is absent', (
      tester,
    ) async {
      final page = sleepPageWithout(<String>['sri', 'point_regularity']);
      await tester.pumpWidget(
        sleepPanelHost(
          SleepChecksPanel(
            night: page.nights.first,
            cutoffs: page.cutoffs,
            notes: const <String>[],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No regularity reading.'), findsOneWidget);
      // The row is still there with its published range, so the reader can see
      // WHAT was not measured rather than a check quietly disappearing.
      expect(find.text('Regularity · SRI'), findsOneWidget);
      expect(find.text('70 or above'), findsOneWidget);
    });
  });

  group('need and debt', () {
    testWidgets('a night with no total drops its derived statistics', (
      tester,
    ) async {
      final page = sleepPageWithout(<String>['tst_min']);
      final windows = SleepWindows(page, kSleepNow);
      await tester.pumpWidget(
        sleepPanelHost(
          SleepNeedPanel(
            night: windows.latest,
            nights: windows.debt,
            needMin: kSleepNeedFixture,
            reveals: RevealRegistry(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // No performance percentage is invented from a night nobody measured.
      expect(find.text('Sleep performance'), findsNothing);
      expect(find.text('Nightly gap'), findsNothing);
      expect(find.textContaining('Last night: $_notDerived'), findsOneWidget);
      // **The window it CAN speak for is still stated**, in the note rather
      // than as a third statistic. `Nights counted` and its bare track went
      // together: the track drew one of three figures beside it with nothing
      // saying which, and the count it repeated is in these words already.
      expect(
        find.textContaining('measured nights of the last seven'),
        findsOneWidget,
      );
      expect(find.text('THE MEASURED WEEK'), findsOneWidget);
    });
  });

  group('the fortnight panels', () {
    testWidgets('a trend with no readings says so and plots nothing', (
      tester,
    ) async {
      await tester.pumpWidget(
        sleepPanelHost(
          SleepTrendPanel(
            trend: kSleepTrends.first,
            recent: const [],
            reveals: RevealRegistry(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('No night in the last fortnight carries this reading.'),
        findsOneWidget,
      );
      expect(find.text('—'), findsWidgets);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('a measured fortnight says how many nights are behind it', (
      tester,
    ) async {
      final windows = SleepWindows(sleepPageFixture(), kSleepNow);
      await tester.pumpWidget(
        sleepPanelHost(
          SleepTrendPanel(
            trend: kSleepTrends.first,
            recent: windows.recent,
            reveals: RevealRegistry(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('nights measured through'), findsOneWidget);
    });
  });

  group('a session that never happened', () {
    testWidgets(
      'THE REASON IS THE SESSION, NOT A DERIVATION THAT DID NOT RUN',
      (tester) async {
        // A night the strap never recorded is a different absence from one the
        // server has not worked out yet, and the two send different sentences.
        // Only the first tells the owner to wear the band.
        final night = SleepNight.fromJson(const <String, Object?>{
          'date': '2026-07-31',
        });
        expect(
          SleepReading.refusals(night),
          everyElement(contains(SleepGap.noSession.message)),
        );
        await tester.pumpWidget(sleepPanelHost(SleepReading(night: night)));
        await tester.pumpAndSettle();
        expect(find.textContaining(SleepGap.noSession.message), findsOneWidget);
        // And nothing anywhere on the block is a zero standing in for it.
        expect(find.text('0'), findsNothing);
        expect(find.text('0\u00A0min'), findsNothing);
      },
    );
  });
}
