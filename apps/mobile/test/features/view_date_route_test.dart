/// The selected day, in the route: written, read back, carried, and bounded.
///
/// Four things are asserted here and every one of them is silent when it breaks
/// — the screen still draws, the header still says a date, and nothing throws:
///
///   1. choosing a day puts `?date=` in the location;
///   2. a tab switch keeps it;
///   3. a link that names a day is adopted;
///   4. a link that names a day outside the retention window is NOT, and the
///      location is corrected so the address and the header cannot disagree.
///
/// `test/mutations.sh` breaks each of these on purpose and requires this file to
/// notice. The round trip itself (`dateLocation`/`viewDateOf`) is asserted as
/// plain functions first, because a query string is easy to get almost right.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:healthee/core/routes.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/today/today_labels.dart';
import 'package:healthee/features/today/today_screen.dart';
import 'package:healthee/features/today/v02/today_header.dart';

import '_today_host.dart';

/// Where the app currently is, query string and all.
String _location(WidgetTester tester) => GoRouter.of(
  tester.element(find.byType(TodayScreen, skipOffstage: false).first),
).routerDelegate.currentConfiguration.uri.toString();

/// Navigates the real router, the way a deep link or a notification does.
Future<void> _go(WidgetTester tester, String location) async {
  GoRouter.of(
    tester.element(find.byType(TodayScreen, skipOffstage: false).first),
  ).go(location);
  await tester.pumpAndSettle();
}

void main() {
  group('the round trip', () {
    test('THE DAY IS WRITTEN, AND REMOVED AGAIN ON THE LATEST DAY', () {
      // A link to the current day must stay the plain route, so it still means
      // "the newest readings" tomorrow. `H.setViewDate` deletes the parameter
      // for exactly this reason.
      expect(
        dateLocation('/', '2026-07-29', '2026-08-04'),
        '/?date=2026-07-29',
      );
      expect(
        dateLocation('/?date=2026-07-29', '2026-08-04', '2026-08-04'),
        '/',
      );
      expect(dateLocation('/sleep', '2026-08-04', '2026-08-04'), '/sleep');
    });

    test('and every other parameter survives it', () {
      // `/history?metric=hrv` is one route carrying two things. A day stamped
      // on by dropping the metric would silently open a different measurement.
      expect(
        dateLocation('/history?metric=hrv', '2026-07-29', '2026-08-04'),
        '/history?metric=hrv&date=2026-07-29',
      );
      expect(
        dateLocation(
          '/history?metric=hrv&date=2026-07-29',
          '2026-08-04',
          '2026-08-04',
        ),
        '/history?metric=hrv',
      );
    });

    test('IT READS BACK ONLY WHAT IS ACTUALLY A DAY', () {
      expect(viewDateOf(Uri.parse('/?date=2026-07-29')), '2026-07-29');
      expect(viewDateOf(Uri.parse('/')), isNull);
      expect(viewDateOf(Uri.parse('/?date=')), isNull);
      expect(viewDateOf(Uri.parse('/?date=yesterday')), isNull);
      expect(viewDateOf(Uri.parse('/?date=2026-7-9')), isNull);
      // `DateTime` rolls this into 3 March without complaining, and the app
      // would then be showing a date nobody wrote.
      expect(viewDateOf(Uri.parse('/?date=2026-02-31')), isNull);
    });

    test('the fifteen date-aware routes are fourteen paths here', () {
      // `metrics` and `metric` are one route in this app — `/history` with and
      // without a `metric=`. Everything else maps one to one. `/trends` is the
      // redesign's, and its periods end on the day being read.
      expect(kDateAwareRoutes.length, 14);
      for (final path in <String>[
        Routes.today,
        Routes.sleep,
        Routes.activity,
        Routes.insights,
        Routes.actions,
        Routes.recovery,
        Routes.trends,
        Routes.body,
        Routes.fitness,
        Routes.history,
        Routes.sleepHistory,
        Routes.workouts,
        Routes.journal,
        Routes.recommendations,
      ]) {
        expect(isDateAwareRoute(path), isTrue, reason: path);
      }
      // The coach is not about a day, so a day would be a parameter nothing
      // reads — and it carries a `topic` of its own that must not be disturbed.
      expect(isDateAwareRoute(Routes.coach), isFalse);
      expect(isDateAwareRoute(Routes.settings), isFalse);
    });
  });

  group('the day rides in the route', () {
    late LocalStore store;

    setUp(() async {
      store = LocalStore.memory();
      await seedDevice(store);
    });

    tearDown(() => store.close());

    testWidgets('CHOOSING A DAY PUTS IT IN THE LOCATION', (tester) async {
      await tester.pumpWidget(routedApp(store));
      await tester.pumpAndSettle();
      expect(_location(tester), Routes.today);

      await chooseDay(tester, '2026-08-03');

      expect(_location(tester), '/?date=2026-08-03');
    });

    testWidgets('AND A TAB SWITCH KEEPS IT', (tester) async {
      // The prototype's parameter survives a tab switch — it is global view
      // state, not per-screen. The tab bar's `go` knows nothing about days, so
      // if the redirect stops re-stamping the location the day is dropped here
      // and nowhere else.
      await tester.pumpWidget(routedApp(store));
      await tester.pumpAndSettle();
      await chooseDay(tester, '2026-08-03');

      await tapTab(tester, 'Activity');

      expect(_location(tester), '/activity?date=2026-08-03');
    });

    testWidgets('A LINK THAT NAMES A DAY OPENS ON IT', (tester) async {
      await tester.pumpWidget(routedApp(store));
      await tester.pumpAndSettle();

      await _go(tester, '/?date=2026-08-01');

      expect(_location(tester), '/?date=2026-08-01');
      expect(find.text(prettyDate('2026-08-01')), findsOneWidget);
    });

    testWidgets('A DAY OUTSIDE THE RETENTION WINDOW IS REFUSED', (
      tester,
    ) async {
      // `horizon_prune.dart` deletes a day at 60, so 1999 is a day this phone
      // cannot speak about. The screen must not show it, and — the silent half
      // — the LOCATION must not keep claiming it, or the address bar and the
      // header say two different things.
      await tester.pumpWidget(routedApp(store));
      await tester.pumpAndSettle();

      await _go(tester, '/?date=1999-01-01');

      expect(_location(tester), Routes.today);
      // The newest day the window reaches is called `Today`; see `dayTitle`.
      // Scoped to the head, because the tab bar names this screen too — which
      // is the whole reason the head no longer carries a 27px title of its own.
      expect(
        find.descendant(
          of: find.byType(TodayHeader),
          matching: find.text('Today'),
        ),
        findsOneWidget,
      );

      // Tomorrow is refused the same way, and for a plainer reason: there are
      // no measurements from it.
      await _go(tester, '/?date=2026-08-05');
      expect(_location(tester), Routes.today);
    });
  });
}
