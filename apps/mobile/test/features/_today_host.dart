/// The Today host every widget suite in this directory pumps.
///
/// Extracted on its second use (Standards §1). Two suites now render this
/// screen — one about what it draws, one about the connection strip in its
/// chrome — and a second copy of these overrides is a second chance to forget
/// one of them, which shows up as "pumpAndSettle timed out" rather than as
/// anything about the test.
///
/// Not a `*_test.dart` file, so it is never run as a suite.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/app.dart';
import 'package:healthee/ble/models/device_daily_totals.dart';
import 'package:healthee/ble/models/strap_sample.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/data/challenges/health_program.dart';
import 'package:healthee/data/history/dated_history.dart';
import 'package:healthee/data/models/sleep_consistency.dart';
import 'package:healthee/data/models/sleep_page.dart';
import 'package:healthee/data/models/today_view.dart';
import 'package:healthee/data/profile/health_profile.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/data/sync/connection_state.dart';
import 'package:healthee/data/sync/sync_controller.dart';
import 'package:healthee/features/today/today_screen.dart';
import 'package:healthee/features/today/v02/today_header.dart';
import 'package:healthee/shared/app_tab_bar.dart';

import '../store/strap_store_test.dart' show nightOn, resultWith;
import '_today_overrides.dart';

export '_today_overrides.dart'
    show FixedConnection, FixedGps, now, profileFixture, todayDate;

/// The screen over [store], with the day, the clock, the link and the payload
/// all pinned.
///
/// The connection is ALWAYS overridden, even when a test does not care about
/// it. The real controller opens a strap session as soon as anything watches it
/// — which is the point of the feature and exactly wrong inside a widget test,
/// where it would reach for a radio that does not exist. The lifecycle
/// behaviour has its own suite (`test/sync/foreground_lifecycle_test.dart`)
/// against a scripted device.
/// The server session is ALWAYS overridden too, and defaults to signed in. The
/// real provider reaches the platform keystore, which a `flutter test` host does
/// not have — and the data-health strip speaks up when there is no session, so
/// leaving it unpinned would make every "this section falls silent" assertion
/// depend on a plugin channel that is not there.
///
/// [reducedMotion] defaults to TRUE and almost every suite wants it — see the
/// `MediaQuery` in the body. `today_hero_test.dart` is the one that turns it off,
/// because the halo running is the thing it is about.
///
/// [home] is the screen under test and defaults to Today. Sleep, Activity, Coach
/// and Diagnostics read the SAME two providers through the same shell
/// (`shared/instrument_screen.dart`), so one host serves all five rather than
/// four more copies of these overrides.
Widget todayHost(
  LocalStore store, {
  StrapConnection? connection,
  SyncController? sync,
  TodayView? server,
  bool serverUnreachable = false,
  ThemeData? themeOverride,
  bool signedIn = true,
  bool reducedMotion = true,
  Widget? home,
  SleepPage? sleep,
  SleepConsistency? consistency,
  HealthProfile? profile,
  bool profileFails = false,
  List<HealthProgram> suggestedPrograms = const [],
  DatedHistory? history,
}) {
  return todayScoped(
    store,
    connection: connection,
    sync: sync,
    server: server,
    serverUnreachable: serverUnreachable,
    signedIn: signedIn,
    sleep: sleep,
    consistency: consistency,
    profile: profile,
    profileFails: profileFails,
    suggestedPrograms: suggestedPrograms,
    history: history,
    child: MaterialApp(
      theme: themeOverride ?? AppTheme.light,
      // **Reduced motion, always.** Today's hero carries `AgeSphere`, a dot
      // field on a ticker, and a running one times out every `pumpAndSettle`.
      // `age_sphere.dart` holds still under `disableAnimations`, as a phone would.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
        child: child!,
      ),
      home: home ?? TodayScreen(now: now),
    ),
  );
}

/// The whole app on its REAL router, so tab switching is the real thing.
///
/// [todayHost] pumps one screen with no router at all, which is right for asking
/// what a screen draws and useless for asking what a tab switch costs. The
/// pairing summary is pinned to a paired strap because `buildRouter` redirects an
/// unpaired app to `/pairing` — a test of the tab shell would otherwise never see
/// a tab.
Widget routedApp(LocalStore store, {TodayView? server}) {
  // `HealtheeApp` builds its own `MaterialApp`, which installs
  // `MediaQuery.fromView` and overrides anything wrapped around it — so the
  // reduced-motion switch `todayHost` uses cannot be reached from out here.
  // The platform dispatcher is where that `MediaQuery` reads the flag from, and
  // the binding clears its test values after every test.
  //
  // Same reason as `todayHost`: Today's hero halo never lets a tree settle.
  TestWidgetsFlutterBinding.ensureInitialized()
      .platformDispatcher
      .accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
  );
  return todayScoped(
    store,
    paired: true,
    server: server,
    child: const HealtheeApp(),
  );
}

/// Seeds one ordinary day of strap measurements.
Future<void> seedDevice(LocalStore store) async {
  await store.strapWriter.saveSync(
    resultWith(
      totals: DeviceDailyTotals(
        steps: 9264,
        distanceM: 6710,
        calories: 412,
        readAt: DateTime(2026, 8, 4, 9, 12),
      ),
      samples: [
        StrapSample(DateTime(2026, 8, 4, 7), 'hr', 61),
        StrapSample(DateTime(2026, 8, 4, 9), 'hr', 68),
        StrapSample(DateTime(2026, 8, 4, 8), 'hrv', 47),
      ],
      sleep: [nightOn(DateTime(2026, 8, 3, 23, 40))],
      battery: 71,
    ),
  );
  await store.strapWriter.stampAttempt(
    at: DateTime(2026, 8, 4, 9, 12),
    outcomeId: 'complete',
    complete: true,
  );
}

/// Scrolls until [finder] is on screen. The list is a `ListView.builder`, so
/// most of Today is not built until it is needed — which is the point of it.
Future<void> reveal(WidgetTester tester, Finder finder) =>
    tester.scrollUntilVisible(
      finder,
      400,
      // The page's own list, explicitly. Today's chapter nav is a horizontal
      // `SingleChildScrollView` inside it (`chapter.dart` says why), so the
      // default `find.byType(Scrollable)` resolves two and throws before it
      // scrolls anything. The outer list is an ancestor, so it is first.
      scrollable: find.byType(Scrollable).first,
    );

/// Taps the tab named [label], **scoped to the bar**.
///
/// `find.text('Sleep')` used to be unique while Today was drawing one screen of
/// index cards. It is not since the legacy port: the recovery card has a factor
/// row called "Sleep" and the signal ladder a marker called "Sleep duration".
/// The bar is the only place any of those words is a control, so that is where a
/// test taps.
Future<void> tapTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(AppTabBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

/// Moves the screen to [iso] the way the owner now does.
///
/// **The two chevrons are gone.** The day is a pill that opens the month grid,
/// and the grid is the control — `Latest`, the retention window and every day
/// in it, in one place, instead of one day per press. Every test that used to
/// press `date.previous` presses a cell here instead; the claim each was making
/// is unchanged.
Future<void> chooseDay(WidgetTester tester, String iso) async {
  await tester.tap(find.byType(DayPill));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey<String>('calendar.$iso')));
  await tester.pumpAndSettle();
}

/// Opens the month grid and leaves it open.
Future<void> openCalendar(WidgetTester tester) async {
  await tester.tap(find.byType(DayPill));
  await tester.pumpAndSettle();
}
