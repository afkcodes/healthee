/// Today is the v02 prototype's screen, in the prototype's order — held here.
///
/// `design/mobile-preview/screens-overview.js::H.screens.today` is one template
/// literal, and the only way a re-ordering, a dropped panel or a panel that
/// crept back in gets caught is by reading the section list and comparing it to
/// the prototype entry by entry. A rendered scroll cannot do it: most of the
/// screen is off the viewport and a `ListView.builder` has not built it.
///
/// The order below was transcribed from the prototype with it open in a browser
/// (`python3 -m http.server --directory design/mobile-preview`), scrolled top to
/// bottom. Every entry names the prototype construct it came from.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/models/activity_today.dart';
import 'package:healthee/data/models/biological_age.dart';
import 'package:healthee/data/models/recovery_score.dart';
import 'package:healthee/data/models/sleep_health.dart';
import 'package:healthee/data/models/vo2max.dart';
import 'package:healthee/features/today/today_sections.dart';
import 'package:healthee/features/today/v02/day_panels.dart';
import 'package:healthee/features/today/v02/longer_panels.dart';
import 'package:healthee/features/today/v02/night_panels.dart';
import 'package:healthee/features/today/v02/today_chapters.dart';
import 'package:healthee/features/today/v02/today_header.dart';
import 'package:healthee/features/today/v02/today_key_numbers.dart';
import 'package:healthee/features/today/widgets/actions_section.dart';
import 'package:healthee/features/today/widgets/data_health_section.dart';
import 'package:healthee/features/today/widgets/insights_section.dart';
import 'package:healthee/features/today/widgets/stale_sleep_banner.dart';
import 'package:healthee/shared/page_section.dart';
import 'package:healthee/shared/states/reading_view.dart';
import 'package:healthee/shared/v02/chapter.dart';
import 'package:healthee/shared/v02/context_bridge.dart';
import 'package:healthee/shared/v02/entry_card.dart';
import 'package:healthee/shared/v02/section_head.dart';

import '../_today_stubs.dart';
import '_screen_data.dart';

/// The section list, built the way the screen builds it.
///
/// The chapter anchors are supplied, because the nav is only drawn when there is
/// something for it to jump to — a screen with no anchors would be three dead
/// buttons, and `today_chapters.dart` refuses that.
List<PageSection> sections({
  Map<String, Object?> Function(Map<String, Object?> json)? mutate,
}) => todaySections(
  screenData(server: todayView(mutate: mutate)),
  TodayExtras(chapters: TodayChapters()),
);

int _indexOf<T>(List<PageSection> list) =>
    list.indexWhere((section) => section.child is T);

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

/// The chapter heading whose title is [title], by index.
int _chapterIndex(List<PageSection> list, String title) => list.indexWhere(
  (section) =>
      section.child is ChapterHeading &&
      (section.child as ChapterHeading).title == title,
);

void main() {
  group("the prototype's order, entry by entry", () {
    test('EVERY SECTION THE PROTOTYPE DRAWS IS DRAWN, AND IN ITS ORDER', () {
      final list = sections();
      final order = <int>[
        // `H.header('Today', …)` and `<a class="device-strip">` under it, now
        // one row: the day, the strap chip, the avatar.
        _indexOf<TodayHeader>(list),
        // `H.scenarioNotice()`'s live equivalent — see `today_sections.dart`.
        _indexOf<DataHealthSection>(list),
        // `H.bioHero()` — the sphere, the figure, the line of what moved it.
        _indexOf<ReadingView<BiologicalAge>>(list),
        // `summaryTiles()` — recovery · sleep · movement.
        _indexOf<TodayKeyNumbers>(list),
        // `<nav class="chapter-nav">`.
        _indexOf<TodayChapterNav>(list),
        // `H.chapter('overnight','Last night → today', …)`.
        _chapterIndex(list, 'Last night → today'),
        // `H.recoveryPanel()`.
        _indexOf<ReadingView<RecoveryScore>>(list),
        // `nightCharts()`'s first `.twin-panels` — HRV beside resting heart.
        _nthOf<TwinPanels>(list, 0),
        // `H.panel('Sleep stages · seven nights', …)`.
        _indexOf<SleepWeekPanel>(list),
        // `H.panel('Sleep health, beyond duration', …)`.
        _indexOf<ReadingView<SleepHealth>>(list),
        // `H.bridge('sleep', …)`.
        _nthOf<ContextBridge>(list, 0),
        // The second `.twin-panels` — blood oxygen beside need & debt.
        _nthOf<TwinPanels>(list, 1),
        // `H.chapter('daytime','Movement → recovery', …)`.
        _chapterIndex(list, 'Movement → recovery'),
        // `H.panel('Heart rate & stress', …)`.
        _indexOf<HeartStressPanel>(list),
        // `H.panel('Steps & energy', …)`.
        _indexOf<StepsEnergyPanel>(list),
        // `H.bridge('movement', …)`.
        _nthOf<ContextBridge>(list, 1),
        // `H.panel('Effort in context', …)`.
        _indexOf<ReadingView<CardioLoad>>(list),
        // The third `.twin-panels` — active minutes beside strength. The
        // reading wraps the LEFT PANEL rather than the pair, so the row's own
        // type is what sits in the list; `today_day_sections.dart` says why.
        _nthOf<TwinPanels>(list, 2),
        // `H.chapter('longer-view','Patterns → small changes', …)`.
        _chapterIndex(list, 'Patterns → small changes'),
        // `H.panel('Cardiorespiratory fitness', …)`.
        _indexOf<ReadingView<Vo2max>>(list),
        // `H.panel('Daily journal', …)`.
        _indexOf<JournalPanel>(list),
        // This app's own: the recommendations the prototype has no surface for.
        _indexOf<ActionsSection>(list),
        // `.relationship-grid`'s heading, then the findings under it.
        _indexOf<SectionHead>(list),
        _indexOf<InsightsSection>(list),
        // `.relationship-grid` — the coach and the actions entry points.
        _indexOf<EntryGrid>(list),
        // `H.footer()`.
        _indexOf<DataFooter>(list),
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

    test('THE THREE CHAPTERS ARE THE THREE THE NAV JUMPS TO', () {
      // A fourth chapter with no button, or a button with no chapter, is a
      // control that scrolls to nothing — the failure `today_chapters.dart`
      // spends thirty lines avoiding.
      final list = sections();
      final headings = <String>[
        for (final section in list)
          if (section.child is ChapterHeading)
            (section.child as ChapterHeading).title,
      ];
      expect(headings, hasLength(TodayChapterNav.labels.length));
      expect(headings, <String>[
        'Last night → today',
        'Movement → recovery',
        'Patterns → small changes',
      ]);
    });

    test('the nav is absent when nothing gave it anchors', () {
      // `TodayExtras.chapters` null: three buttons that jump nowhere is worse
      // than no buttons at all.
      final list = todaySections(
        screenData(server: todayView()),
        const TodayExtras(),
      );
      expect(_indexOf<TodayChapterNav>(list), -1);
      // The chapters themselves stay: they are content, not navigation.
      expect(_chapterIndex(list, 'Last night → today'), isNonNegative);
    });
  });

  group('the gaps are v02’s two rungs, not legacy’s four', () {
    test('a panel gap is 12 and a block gap is 32, and they are different', () {
      // The brief's tokens: cards 12 apart (`Insets.cardGap`), sections 32
      // apart (`Insets.section`). Two rungs, and the grouping is carried by
      // them being unequal.
      expect(PageSpacing.panel, 12);
      expect(PageSpacing.block, 32);
      expect(PageSpacing.panel, lessThan(PageSpacing.block));
    });

    test('THE SCREEN USES THOSE TWO AND NOT LEGACY’S LADDER', () {
      final list = sections();
      final gaps = <double>{
        for (final section in list)
          if (section.gap > 0) section.gap,
      };
      expect(
        gaps.difference(<double>{PageSpacing.panel, PageSpacing.block}),
        isEmpty,
        reason:
            'a v02 screen uses one ladder or the other; a legacy rung here is '
            'the two systems drifting into one screen',
      );
    });

    test('a bridge is a block break, and two panels are a panel break', () {
      final list = sections();
      // **The bridge OWNS that gap now.** `.context-bridge` still follows
      // `.section`-spaced content, but the spacer section above it is gone: the
      // rule the bridge draws has to span the gap in order to reach the card it
      // hangs off, and a spacer between them made it start below the gap and
      // connect to nothing. Same spacing on screen, carried by the widget —
      // see `ContextBridge.leadIn`.
      expect(list[_nthOf<ContextBridge>(list, 0) - 1].gap, 0);
      expect(
        (list[_nthOf<ContextBridge>(list, 0)].child as ContextBridge).leadIn,
        PageSpacing.block,
      );
      // `H.recoveryPanel()` then the twin pair: `.panel { margin-top: 12px }`.
      expect(
        list[_indexOf<ReadingView<RecoveryScore>>(list)].gap,
        PageSpacing.panel,
      );
    });
  });

  group('the conditional sections are the payload’s conditions', () {
    test('the stale-sleep banner appears only for a night over 24 h old', () {
      expect(_indexOf<StaleSleepBanner>(sections()), -1);

      final stale = todaySections(
        screenData(
          server: todayView(
            mutate: (json) => {
              ...json,
              'last_sleep': {
                ...json['last_sleep']! as Map<String, Object?>,
                'end_iso': '2026-07-20T01:00:00+00:00',
              },
            },
          ),
        ),
        TodayExtras(chapters: TodayChapters()),
      );
      final banner = _indexOf<StaleSleepBanner>(stale);
      expect(banner, isNonNegative);
      // It dates the whole overnight chapter, so it comes first inside it.
      expect(banner, greaterThan(_chapterIndex(stale, 'Last night → today')));
      expect(banner, lessThan(_indexOf<ReadingView<RecoveryScore>>(stale)));
    });

    test('one night is not a week', () {
      final oneNight = sections(
        mutate: (json) => {
          ...json,
          'sleep_history_7d': [(json['sleep_history_7d']! as List).first],
        },
      );
      expect(_indexOf<SleepWeekPanel>(oneNight), -1);
    });

    test(
      'two hours is not a day, and the linked chart is not drawn for it',
      () {
        final thin = sections(
          mutate: (json) => {
            ...json,
            'today_hr_series': const <Object?>[],
            'today_stress_series': const <Object?>[],
          },
        );
        expect(_indexOf<HeartStressPanel>(thin), -1);
      },
    );

    test('no recommendations means no suggested-actions block at all', () {
      final none = sections(
        mutate: (json) => {
          ...json,
          'recommendations': const <Object?>[],
          'action': null,
        },
      );
      expect(_indexOf<ActionsSection>(none), -1);
    });

    test('no findings means no heading — a heading over nothing is dead', () {
      final none = sections(
        mutate: (json) => {...json, 'top_findings': const <Object?>[]},
      );
      expect(_indexOf<SectionHead>(none), -1);
      expect(_indexOf<InsightsSection>(none), -1);
    });

    test('nothing logged means no journal panel', () {
      final none = sections(
        mutate: (json) => {...json, 'routine': const <String, Object?>{}},
      );
      expect(_indexOf<JournalPanel>(none), -1);
    });
  });

  group('the two fields that can never have content', () {
    test('PAI AND ANOMALIES GET NO SECTION, ON ANY PAYLOAD', () {
      // `read/today.py:83` sets `anomalies` to `[]` unconditionally and `pai` is
      // null on this account. A heading that can never have content under it is
      // dead code, and a zero-state for a field the server never fills is a
      // gap the owner is invited to read as a measurement.
      //
      // Asserted on a payload that DOES carry both, so this fails the day
      // somebody adds a section keyed on them rather than the day the fixture
      // changes.
      final withBoth = sections(
        mutate: (json) => {
          ...json,
          'pai': const <String, Object?>{'score': 84},
          'anomalies': const <Object?>[
            <String, Object?>{'metric': 'rhr_daily', 'z': 3.1},
          ],
        },
      );
      final types = <String>[
        for (final section in withBoth) section.child.runtimeType.toString(),
      ];
      for (final name in types) {
        expect(name.toLowerCase(), isNot(contains('pai')));
        expect(name.toLowerCase(), isNot(contains('anomal')));
      }
      // And the list is the same length as without them: nothing appeared.
      expect(withBoth, hasLength(sections().length));
    });
  });
}
