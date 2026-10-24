/// A past day never wears ANOTHER day's judgements — on any of the fourteen screens.
///
/// `date_control_test.dart` holds this rule for Today, where it was first built.
/// The day follows the reader onto thirteen more screens, and the rule has to
/// hold on every one of them or the feature is a way to put one day's recovery,
/// MVPA, VO₂max, correlations and suggestions under another day's date. That is
/// stale-as-current, which this repo has swept three times.
///
/// **What the rule means changed when the server learned to answer for a day.**
/// Today and Activity read `/api/today`, which now takes `day=YYYY-MM-DD`
/// (`docs/AS_OF_DAY.md`), so their figures ARE that day's and are drawn: the
/// guard there is that the payload must answer for the day being read, not that
/// nothing derived may appear. The screens below that still refuse outright are
/// the ones whose content is LLM-authored or windowed on the current day, and
/// each says which in its own group.
///
/// Asked of the section builders rather than of a rendered scroll wherever
/// possible: what is being asserted is what the screen DECIDED, and a viewport
/// would pass while the offending card sat one scroll below it.
///
/// The other half — that a past day still draws everything it CAN — is asserted
/// beside each refusal, because a screen that answered "no" to everything would
/// satisfy the honesty rule and be useless.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:healthee/data/device/device_day.dart';
import 'package:healthee/data/history/dated_history.dart';
import 'package:healthee/data/models/trend_point.dart';
import 'package:healthee/data/models/vo2max.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/activity/activity_extras.dart';
import 'package:healthee/features/activity/activity_sections.dart';
import 'package:healthee/features/activity/fitness_screen.dart';
import 'package:healthee/features/activity/v02/movement_panels.dart';
import 'package:healthee/features/coach/coach_home_screen.dart';
import 'package:healthee/features/coach/v02/home_job_section.dart';
import 'package:healthee/features/coach/v02/home_review_card.dart';
import 'package:healthee/features/insights/insights_sections.dart';
import 'package:healthee/features/insights/widgets/trends_section.dart';
import 'package:healthee/features/sleep/sleep_history_screen.dart';
import 'package:healthee/features/sleep/sleep_windows.dart';
import 'package:healthee/features/sleep/v02/need_panel.dart';
import 'package:healthee/features/sleep/v02/tail_panels.dart';
import 'package:healthee/features/sleep/v02/timing_panel.dart';
import 'package:healthee/features/today/body_screen.dart';
import 'package:healthee/features/today/recovery_screen.dart';
import 'package:healthee/features/today/today_screen.dart';
import 'package:healthee/shared/page_section.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:healthee/shared/states/reading_view.dart';
import 'package:healthee/shared/v02/dated_panel.dart';
import 'package:healthee/shared/v02/past_day.dart';
import 'package:healthee/shared/v02/view_day.dart';

import '../_sleep_stubs.dart';
import '../_today_stubs.dart';
import '_screen_data.dart';
import '_sleep_host.dart';
import '_today_host.dart';

/// A day the owner has stepped back to, inside the retention window.
const String _past = '2026-08-01';

/// A fortnight of steps that runs PAST the day under test, so a panel windowed
/// on the newest reading rather than on the selection would have somewhere wrong
/// to go.
const DatedHistory _spanning = DatedHistory(
  days: 90,
  series: <String, List<TrendPoint>>{
    'steps_total': <TrendPoint>[
      TrendPoint(date: '2026-07-30', value: 5000),
      TrendPoint(date: '2026-07-31', value: 5100),
      TrendPoint(date: '2026-08-01', value: 5200),
      // Everything below is AFTER the day under test.
      TrendPoint(date: '2026-08-02', value: 9100),
      TrendPoint(date: '2026-08-03', value: 9200),
      TrendPoint(date: '2026-08-04', value: 9300),
    ],
  },
);

bool _has<T>(List<PageSection> list) =>
    list.any((section) => section.child is T);

void main() {
  group('Activity', () {
    test('THE DERIVED HALF IS DRAWN, FOR THE DAY IT ANSWERS FOR', () {
      // Reversed on purpose. Activity's figures come from `/api/today`, which
      // takes a `day` now (`docs/AS_OF_DAY.md`), so VO₂max here is that day's own
      // stored row rather than the current day's under an older header. The
      // notice that used to head this screen refused something we can now answer,
      // and a refusal you are not entitled to is its own kind of dishonesty.
      final past = activitySections(
        screenData(
          day: DeviceDay.empty(_past),
          server: todayViewFor(_past, today: todayDate),
        ),
        const ActivityExtras(),
      );
      expect(
        _has<PastDayNotice>(past),
        isFalse,
        reason: 'nothing left to refuse',
      );
      expect(
        _has<ReadingView<Vo2max>>(past),
        isTrue,
        reason: 'VO₂max as of that day',
      );
      // The strap's own counts are stored per calendar day, so they stay.
      expect(_has<MovementPanel>(past), isTrue);
    });

    test('AND A PAYLOAD ABOUT ANOTHER DAY IS STILL NOT THIS DAY’S', () {
      // The guard that replaced the refusal, on this screen too: the answer on
      // hand while the new request is in flight is about the wrong day, and
      // drawing it would be the same stale-as-current failure with a shorter
      // lifetime. `ScreenData.snapshot` is where that is decided, once.
      final mid = activitySections(
        screenData(
          day: DeviceDay.empty(_past),
          server: todayViewFor(todayDate, today: todayDate),
        ),
        const ActivityExtras(),
      );
      expect(_has<ReadingView<Vo2max>>(mid), isFalse);
    });

    test('A PAYLOAD THAT SAYS IT IS NOT TODAY IS NOT DRAWN AS TODAY', () {
      // The other direction of the same guard, and the one an exact-date test
      // cannot see. On the CURRENT day the question is the server's own
      // `is_today`, not a string comparison — because a payload dated a few days
      // back IS drawn here when it came from the cache, with its own date on it.
      // What must never be drawn is a payload that says outright it is about
      // another day, which is what the in-flight answer says after stepping
      // forward to the newest day.
      final mid = activitySections(
        screenData(server: todayViewFor(_past, today: todayDate)),
        const ActivityExtras(),
      );
      expect(
        _has<ReadingView<Vo2max>>(mid),
        isFalse,
        reason: "a payload about $_past was drawn as the current day's",
      );
    });

    test('A DATED SERIES ENDS ON THE CHOSEN DAY, NOT ON THE NEWEST READING', () {
      // The stale-as-current failure with a chart instead of a figure. The series
      // runs to 4 August and the header says 1 August, so a window taken from the
      // newest reading would put three days of the reader's future on screen
      // under an older date — and the panel's own figure would be one of them.
      final panel =
          activitySections(
                screenData(
                  day: DeviceDay.empty(_past),
                  server: todayViewFor(_past, today: todayDate),
                  history: _spanning,
                ),
                const ActivityExtras(),
              )
              .map((section) => section.child)
              .whereType<DatedPanel>()
              .firstWhere((panel) => panel.metric == 'steps_total');

      expect(panel.window.days.last, _past);
      expect(panel.window.on(_past), 5200);
      for (final point in panel.window.observed) {
        expect(
          point.date.compareTo(_past) <= 0,
          isTrue,
          reason: '${point.date} is after the day being read',
        );
      }
      // 9100, 9200 and 9300 are the readings from after the selection.
      expect(panel.window.values, isNot(contains(9100.0)));
    });

    test('and the current day still draws all of it', () {
      final today = activitySections(
        screenData(server: todayView()),
        const ActivityExtras(),
      );
      expect(_has<PastDayNotice>(today), isFalse);
      expect(_has<ReadingView<Vo2max>>(today), isTrue);
      expect(_has<MovementPanel>(today), isTrue);
    });
  });

  group('Insights', () {
    test('THE PATTERNS ARE NOT DATED BACKWARDS', () {
      final past = insightsSections(
        screenData(day: DeviceDay.empty(_past), server: todayView()),
        const InsightsExtras(),
      );
      expect(_has<PastDayNotice>(past), isTrue);
      expect(
        _has<TrendsGrid>(past),
        isFalse,
        reason: 'the trend windows end today whatever the header says',
      );
    });

    test('and the current day still draws them', () {
      final today = insightsSections(
        screenData(server: todayView()),
        const InsightsExtras(),
      );
      expect(_has<PastDayNotice>(today), isFalse);
      expect(_has<TrendsGrid>(today), isTrue);
    });
  });

  group('Coach', () {
    test('YESTERDAY GETS NO REVIEW AND NO CURRENT JOB', () {
      final past = coachHomeSections(
        screenData(day: DeviceDay.empty(_past), server: todayView()),
      );
      expect(_has<PastDayNotice>(past), isTrue);
      expect(
        _has<WeeklyReviewCard>(past),
        isFalse,
        reason: "this week's review is not what that day was told",
      );
      expect(
        _has<CoachJobSection>(past),
        isFalse,
        reason: 'a job and its dots are as of now',
      );
    });

    test('and the current day still draws them', () {
      final today = coachHomeSections(screenData(server: todayView()));
      expect(_has<PastDayNotice>(today), isFalse);
      expect(_has<WeeklyReviewCard>(today), isTrue);
      expect(_has<CoachJobSection>(today), isTrue);
    });
  });

  group('Sleep', () {
    test('THE WINDOW ENDS ON THE CHOSEN NIGHT, NOT ON THE NEWEST ONE', () {
      // The seam `sleep_history_screen.dart` used to record: its rows set the
      // day and Sleep still opened on the latest night.
      final page = sleepPageFixture();
      final chosen = page.nights[2].date;
      final windows = SleepWindows.through(page, kSleepNow, chosen);

      expect(windows, isNotNull);
      expect(windows!.latest.date, chosen);
      expect(
        windows.recent.first.date,
        chosen,
        reason: 'every chart on the screen reads this window',
      );
      for (final night in windows.recent) {
        expect(night.date.compareTo(chosen) <= 0, isTrue);
      }
    });

    test('and a day older than every night is an answer, not a crash', () {
      expect(
        SleepWindows.through(sleepPageFixture(), kSleepNow, '1999-01-01'),
        isNull,
      );
      final sections = sleepList(day: '1999-01-01');
      expect(_has<PastDayNotice>(sections), isTrue);
    });

    test('THE DEBT MODEL IS REFUSED ON A PAST NIGHT, THE CHARTS ARE NOT', () {
      final page = sleepPageFixture();
      final past = sleepList(page: page, day: page.nights[2].date);

      expect(
        _has<SleepNeedPanel>(past),
        isFalse,
        reason: 'debt is a fourteen-night model computed to now',
      );
      expect(
        _has<SleepAnalysisPanel>(past),
        isFalse,
        reason: 'the written analysis is of the latest data',
      );
      expect(_has<PastDayNotice>(past), isTrue);
      // The nightly measurements are dated and stay.
      expect(_has<SleepTimingPanel>(past), isTrue);
    });

    test('and the newest night still draws the whole screen', () {
      final today = sleepList();
      expect(_has<SleepNeedPanel>(today), isTrue);
      expect(_has<SleepAnalysisPanel>(today), isTrue);
      expect(_has<PastDayNotice>(today), isFalse);
    });
  });

  group('Sleep history', () {
    test('THE NIGHT LIST ENDS ON THE DAY BEING READ', () {
      final page = sleepPageFixture();
      final chosen = page.nights[3].date;
      final detail = SleepHistoryDetail(
        page: page,
        view: ViewDay(day: chosen, latest: page.nights.first.date),
        reveals: RevealRegistry(),
      );

      expect(detail.window.first.date, chosen);
      expect(detail.week.last.date, chosen);
      expect(
        detail.window.length,
        lessThan(page.nights.length),
        reason: 'nights after the chosen one are not in the window',
      );
    });
  });

  group('the pushed screens, on the real router', () {
    late LocalStore store;

    setUp(() async {
      store = LocalStore.memory();
      await seedDevice(store);
    });

    tearDown(() => store.close());

    /// Steps back a day, then opens [location].
    Future<void> openPast(WidgetTester tester, String location) async {
      await tester.pumpWidget(routedApp(store));
      await tester.pumpAndSettle();
      await chooseDay(tester, '2026-08-03');
      await tester.pumpAndSettle();
      GoRouter.of(
        tester.element(find.byType(TodayScreen, skipOffstage: false).first),
      ).go(location);
      await tester.pumpAndSettle();
    }

    testWidgets('RECOVERY REFUSES RATHER THAN RE-DATING ITS SCORE', (
      tester,
    ) async {
      await openPast(tester, '/recovery');
      expect(find.text(kRecoveryPastTitle), findsOneWidget);
      expect(find.byType(RecoveryDetail), findsNothing);
    });

    testWidgets('AND SO DOES BIOLOGICAL AGE', (tester) async {
      await openPast(tester, '/body');
      expect(find.text(kBodyPastTitle), findsOneWidget);
      expect(find.byType(BodyDetail), findsNothing);
    });

    testWidgets('AND SO DOES FITNESS', (tester) async {
      await openPast(tester, '/fitness');
      expect(find.text(kFitnessPastTitle), findsOneWidget);
      expect(find.byType(FitnessDetail), findsNothing);
    });

    testWidgets('THE HEADER PROMISES THE NEWEST READINGS ONLY WHEN IT CAN', (
      tester,
    ) async {
      // `Latest sample` promises the newest readings there are. The words are
      // the contract, so this is the one on the current day.
      await tester.pumpWidget(routedApp(store));
      await tester.pumpAndSettle();
      GoRouter.of(
        tester.element(find.byType(TodayScreen, skipOffstage: false).first),
      ).go('/sleep');
      await tester.pumpAndSettle();

      expect(find.textContaining(kLatestSample), findsOneWidget);
      expect(find.textContaining(kSelectedDay), findsNothing);
    });

    testWidgets('AND SAYS Selected day ON ANY OLDER ONE', (tester) async {
      await openPast(tester, '/sleep');

      expect(find.textContaining(kSelectedDay), findsOneWidget);
      expect(find.textContaining(kLatestSample), findsNothing);
    });
  });
}
