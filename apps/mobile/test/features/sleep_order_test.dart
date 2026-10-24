/// Sleep is the v02 prototype's screen, in the prototype's order — held here.
///
/// `design/mobile-preview/sleep-history-view.js::H.screens.sleep` is one
/// template literal, and the only way a re-ordering, a dropped panel or a panel
/// that crept back in gets caught is by reading the section list and comparing
/// it to the prototype entry by entry. A rendered scroll cannot do it: most of
/// this screen is off the viewport and a lazy list has not built it.
///
/// The order below was transcribed with the prototype open in a browser
/// (`python3 -m http.server --directory design/mobile-preview`), scrolled top to
/// bottom at 390 px. Every entry names the prototype construct it came from.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/models/sleep_consistency.dart';
import 'package:healthee/features/sleep/v02/bed_wake_week.dart';
import 'package:healthee/features/sleep/v02/checks_panel.dart';
import 'package:healthee/features/sleep/v02/naps_panel.dart';
import 'package:healthee/features/sleep/v02/need_panel.dart';
import 'package:healthee/features/sleep/v02/night_panels.dart';
import 'package:healthee/features/sleep/v02/sleep_reading.dart';
import 'package:healthee/features/sleep/v02/tail_panels.dart';
import 'package:healthee/features/sleep/v02/timing_panel.dart';
import 'package:healthee/features/sleep/v02/trend_panels.dart';
import 'package:healthee/features/sleep/v02/vitals_panel.dart';
import 'package:healthee/features/sleep/v02/week_panel.dart';
import 'package:healthee/features/sleep/v02/withheld_night.dart';
import 'package:healthee/shared/findings_section.dart';
import 'package:healthee/shared/page_section.dart';
import 'package:healthee/shared/v02/chapter.dart';
import 'package:healthee/shared/v02/data_footer.dart';
import 'package:healthee/shared/v02/page_header.dart';

import '../_sleep_stubs.dart';
import '_sleep_host.dart';

/// The nth section whose child is a [T], counting from zero.
int _nthOf<T>(List<PageSection> list, int n) {
  var seen = 0;
  for (var i = 0; i < list.length; i++) {
    if (list[i].child is T) {
      if (seen == n) {
        return i;
      }
      seen++;
    }
  }
  return -1;
}

void main() {
  group("the prototype's order, entry by entry", () {
    test('EVERY SECTION THE PROTOTYPE DRAWS IS DRAWN, AND IN ITS ORDER', () {
      final list = sleepList();
      final order = <int>[
        // `H.header('Sleep','')` — the date, the h1, the avatar.
        indexOfSection<V02PageHeader>(list),
        // **This app's own, and FIRST.** The prototype has no box for the
        // night's written reading, and the owner asked for it above the
        // charts: it is the answer, and the panels under it are the working.
        indexOfSection<SleepAnalysisPanel>(list),
        // `.sleep-reading` and the `.colour-key` under it.
        indexOfSection<SleepReading>(list),
        // `H.panel('How your night unfolded', …, 'sleep-history','moon')`.
        indexOfSection<NightTimelinePanel>(list),
        // `H.panel('Every stage, accounted for', …)`.
        indexOfSection<StageTablePanel>(list),
        // `H.panel('Your body overnight','oxygen', …, 'metrics','heart')`.
        indexOfSection<OvernightPanel>(list),
        // `H.panel('Your four sleep checks', …)`.
        indexOfSection<SleepChecksPanel>(list),
        // `head('p-week', 'This week', …)` — the approved redesign's part.
        _nthOf<ChapterHeading>(list, 0),
        // `H.panel('Sleep need & debt', …)`.
        indexOfSection<SleepNeedPanel>(list),
        // `H.panel('Your week, stage by stage', …)`.
        indexOfSection<StageWeekPanel>(list),
        // `timingCard(P.week)` — bed and wake bars for the week.
        indexOfSection<BedWakeWeekPanel>(list),
        // `H.panel('Sleep timing', …, '', 'clock')`.
        indexOfSection<SleepTimingPanel>(list),
        // `H.chapter('sleep-trends','Beyond a single night','sleep','insights')`.
        _nthOf<ChapterHeading>(list, 1),
        // `['efficiency','regularity','hrv'].map(H.historyPanel)`.
        _nthOf<SleepTrendPanel>(list, 0),
        _nthOf<SleepTrendPanel>(list, 1),
        _nthOf<SleepTrendPanel>(list, 2),
        // `H.panel('Naps & your day', …, 'journal','moon')`.
        indexOfSection<NapsPanel>(list),
        // ⛔ **No `H.link('Sleep recommendations','actions')`.** The prototype
        // ends the screen with a call to action; the owner asked for it out.
        // It sent the reader to a tab that had nothing sleep-specific waiting
        // for them — a door labelled with a promise nothing behind it kept.
        indexOfSection<FindingsSection>(list),
        // `H.footer()`.
        indexOfSection<DataFooter>(list),
      ];
      for (final index in order) {
        expect(index, isNonNegative, reason: 'a prototype section is missing');
      }
      // Strictly increasing: every section sits after the one the prototype
      // puts before it. This is the assertion a re-order fails.
      for (var i = 1; i < order.length; i++) {
        expect(
          order[i],
          greaterThan(order[i - 1]),
          reason: 'section $i is out of the prototype’s order',
        );
      }
    });

    test(
      'the three trend panels are efficiency, regularity, HRV in that order',
      () {
        final list = sleepList();
        final titles = <String>[
          for (final section in list)
            if (section.child case final SleepTrendPanel panel)
              panel.trend.title,
        ];
        expect(titles, <String>[
          'Sleep efficiency',
          'Sleep regularity',
          'Heart-rate variability',
        ]);
      },
    );

    test('the surfaces the prototype has no box for all sit AFTER it', () {
      // The rule the Activity rebuild set: an app-only surface is kept, and it
      // never interrupts the prototype's own sequence.
      final withLever = SleepConsistency.fromJson(<String, Object?>{
        ...loadJson(kConsistencySnapshotPath),
        'tonight': const <String, Object?>{
          'title': 'Lights out by 23:00',
          'lever': 'bedtime',
          'target_clock': '23:00',
          'action': 'Start winding down at 22:15.',
        },
      });
      final list = sleepList(consistency: withLever);
      // `NapsPanel` is the prototype's last box now — the `Sleep
      // recommendations` link that used to close the screen is gone.
      final lastPrototypePanel = indexOfSection<NapsPanel>(list);
      for (final ours in <int>[
        indexOfSection<TonightPanel>(list),
        indexOfSection<FindingsSection>(list),
      ]) {
        expect(ours, greaterThan(lastPrototypePanel));
      }
      // **`SleepAnalysisPanel` is the stated exception**, the second after the
      // stale banner: the owner asked for the night's written reading above the
      // charts rather than under them. An exception that is written down and
      // asserted is a decision; one that is merely true is a drift.
      expect(
        indexOfSection<SleepAnalysisPanel>(list),
        lessThan(indexOfSection<SleepReading>(list)),
      );
    });

    test('THE STALE BANNER IS THE ONE EXCEPTION, AND IT IS NEAR THE TOP', () {
      // A sentence saying "everything below is from an older night" is worth
      // nothing underneath the thing it qualifies.
      final list = sleepList(now: kSleepNow.add(const Duration(days: 7)));
      final banner = indexOfSection<StaleNightNotice>(list);
      expect(banner, isNonNegative);
      expect(banner, lessThan(indexOfSection<SleepReading>(list)));
      // And it is absent on a fresh night, so it is a state rather than furniture.
      expect(indexOfSection<StaleNightNotice>(sleepList()), -1);
    });
  });

  group('the gaps are v02’s two rungs, not legacy’s four', () {
    test('THE SCREEN USES THOSE TWO AND NOTHING ELSE', () {
      final gaps = <double>{
        for (final section in sleepList())
          if (section.gap > 0) section.gap,
      };
      expect(gaps, isNotEmpty);
      expect(
        gaps.difference(<double>{PageSpacing.panel, PageSpacing.block}),
        isEmpty,
        reason:
            'a literal at a call site is how a ladder stops being one — see '
            'page_section.dart',
      );
    });
  });

  group('nothing on this screen combines the four dimensions', () {
    test('NO SECTION IS A SLEEP SCORE', () {
      // `/api/sleep` sends `score` — how many of the four passed — and no
      // surface may draw it. `feedback_no_composite_score`: three out of four
      // is a tally of unlike things and a reader will take it for a mark.
      final names = <String>[
        for (final section in sleepList())
          section.child.runtimeType.toString().toLowerCase(),
      ];
      for (final name in names) {
        expect(name, isNot(contains('score')));
      }
    });

    test('the payload really does carry the count this screen refuses', () {
      // Proves the test above is refusing something rather than passing because
      // there was never anything to refuse.
      expect(sleepPageFixture().nights.first.healthScore.hasValue, isTrue);
    });
  });
}
