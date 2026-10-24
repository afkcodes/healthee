/// The editorial head of Today: legacy's greeting header, and the tab bar.
///
/// The header is v02's `H.header('Today', …)` — the date, the screen's name,
/// and the avatar with its sync ring — plus the `.device-strip` under it. The
/// tests here hold the things about them that are claims rather than layout:
/// the date table has no off-by-one, the strap's charge appears only when one
/// has been read, and **no cheerful phrase sits beside a safety sentence**.
///
/// That last one is why the header says `Today` and nothing else. The pre-v02
/// header opened with a two-line greeting and the obvious next step was to
/// derive a phrase from `recovery_score.band`. The contract snapshot is exactly
/// the case that makes it a bug: `band: "high"` beside guidance that begins
/// "An illness signal is active". v02 removes the salutation outright, which
/// settles it — but the assertion stays, because the band is still on the wire.
library;

import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/router.dart';
import 'package:healthee/core/routes.dart';
import 'package:healthee/core/tabs.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/data/sync/connection_health.dart';
import 'package:healthee/data/sync/connection_state.dart';
import 'package:healthee/features/today/today_labels.dart';
import 'package:healthee/features/today/v02/date_control.dart';
import 'package:healthee/features/today/v02/today_header.dart';
import 'package:healthee/shared/app_tab_bar.dart';
import 'package:healthee/shared/connection/sync_ring.dart';
import 'package:healthee/shared/instrument/h_icon_badge.dart';

import '_today_host.dart';

/// The palette `host` puts the widget in.
const HealtheeColors _light = HealtheeColors.light();

/// One widget in the light theme.
Widget host(Widget child) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(body: child),
);

Widget _header({
  String date = '2026-08-06',
  DateTime? at,
  ConnectionHealth? health,
}) => host(
  TodayHeader(date: date, now: at ?? DateTime(2026, 8, 6, 9), health: health),
);

/// The owner's mark, which is where the strap's charge lives in the one-row head.
Widget _strip({int? battery, ConnectionHealth? health}) =>
    host(OwnerMark(batteryPercent: battery, health: health));

/// One classification, from a real link. There is no `syncing` flag any more:
/// the ring reads `busy` off the same object the card reads its faults off.
ConnectionHealth _connection(StrapConnection link) =>
    connectionHealth(link: link, now: DateTime(2026, 8, 6, 9), signedIn: true);

void main() {
  group('the date eyebrow', () {
    testWidgets("abbreviates the day and month, as legacy's does", (
      tester,
    ) async {
      await tester.pumpWidget(_header());
      await tester.pumpAndSettle();

      expect(find.text('THU · AUG 6'), findsOneWidget);
    });

    test('every weekday and month has a name', () {
      // Off-by-one in a hand-rolled name table is the classic version of this
      // bug, and it only shows on one day of the week.
      expect(prettyDate('2026-01-05'), 'MON · JAN 5');
      expect(prettyDate('2026-12-27'), 'SUN · DEC 27');
    });

    test('an unparseable date keeps its own text rather than going blank', () {
      // Legacy's `catch` — a date we cannot read is still information, and a gap
      // where a date belongs reads as a broken header.
      expect(prettyDate('not-a-date'), 'NOT-A-DATE');
    });
  });

  group('the screen names itself', () {
    testWidgets('THE HEAD IS ONE ROW, AND THE DAY IS THE HEADLINE', (
      tester,
    ) async {
      await tester.pumpWidget(_header());
      await tester.pumpAndSettle();

      // The prototype's README: *"replaces generic main-screen slogans with
      // direct labels such as Today, Sleep, Activity"*. The pre-v02 header's
      // largest type was a greeting to an owner whose name nothing stores; the
      // v02 one was a 27px `Today` the tab bar already says, in the accent,
      // with a filled glyph. The date has taken that line.
      expect(find.textContaining('Good morning'), findsNothing);
      expect(find.textContaining('there.'), findsNothing);
      // With no navigation there is no window, so no day can be `Today` — the
      // header names the day it is showing.
      expect(find.text(prettyDate('2026-08-06')), findsOneWidget);

      // ONE row: the day, the strap and the avatar share a horizontal band.
      final day = tester.getRect(find.text(prettyDate('2026-08-06')));
      final avatar = tester.getRect(find.byType(HStrapMark));
      expect(
        day.center.dy,
        moreOrLessEquals(avatar.center.dy, epsilon: 2),
        reason: 'the day and the avatar are on separate lines',
      );
    });

    testWidgets('the newest day is called Today, an older one is dated', (
      tester,
    ) async {
      const window = DateNavigation(
        earliest: '2026-07-01',
        latest: '2026-08-06',
        onSelect: _ignore,
      );
      await tester.pumpWidget(
        host(
          TodayHeader(
            date: '2026-08-06',
            now: DateTime(2026, 8, 6, 9),
            navigation: window,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Today'), findsOneWidget);

      await tester.pumpWidget(
        host(
          TodayHeader(
            date: '2026-08-04',
            now: DateTime(2026, 8, 6, 9),
            navigation: window,
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Not `Today` — the word would be a lie about the day on screen, which is
      // the whole reason the title stopped being a constant.
      expect(find.text('Today'), findsNothing);
      expect(find.text(prettyDate('2026-08-04')), findsOneWidget);
    });
  });

  group('the strap battery', () {
    testWidgets('is absent entirely when nothing has read one', (tester) async {
      await tester.pumpWidget(_strip());
      await tester.pumpAndSettle();

      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets('shows the charge when there is one', (tester) async {
      await tester.pumpWidget(_strip(battery: 71));
      await tester.pumpAndSettle();

      expect(find.text('71%'), findsOneWidget);
    });

    testWidgets('THE CHARGE IS GREEN ONLY WHEN THE LINK IS QUIET', (
      tester,
    ) async {
      // A green anything beside a strap nobody has heard from is the flattery
      // this product exists not to do, so the classification decides it. The
      // carrier moved — the watch glyph went inside the mark's circle and wears
      // the accent there, so the charge beside it is the one element still free
      // to hold a state — but the rule did not.
      await tester.pumpWidget(_strip(battery: 71));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.text('71%')).style!.color,
        _light.ink2,
        reason: 'nothing has classified a link, so nothing may read healthy',
      );

      await tester.pumpWidget(
        _strip(
          battery: 71,
          health: _connection(Connected(since: DateTime(2026, 8, 6, 9))),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(OwnerMark), findsOneWidget);
      // The two words the mark dropped are in its semantics, not on the row —
      // there is one strap, and its name spent a line saying so.
      expect(find.text(OwnerMark.deviceName), findsNothing);
      expect(find.text(OwnerMark.action), findsNothing);
    });
  });

  group('the owner mark', () {
    testWidgets('carries no ring when nothing has classified a link', (
      tester,
    ) async {
      await tester.pumpWidget(_header());
      await tester.pumpAndSettle();

      expect(find.byType(SyncRing), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(HStrapMark), findsOneWidget);
    });

    testWidgets('draws the ring once there IS a classification', (
      tester,
    ) async {
      await tester.pumpWidget(
        _header(health: _connection(Connected(since: DateTime(2026, 8, 6, 9)))),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(HStrapMark), findsOneWidget);
    });

    testWidgets('THE DATE ROW CARRIES NO SECOND MARK', (tester) async {
      // The 7 px dot went with the strip. Two marks for one fact was the whole
      // argument for the dot's existence, and it cuts both ways — the ring says
      // `live` and `idle` in the same colours, eight pixels to the right.
      await tester.pumpWidget(
        _header(health: _connection(Connected(since: DateTime(2026, 8, 6, 9)))),
      );
      await tester.pump();

      expect(
        find.byType(CircularProgressIndicator),
        findsOneWidget,
        reason: 'exactly one mark in this row reports the connection',
      );
    });
  });

  group('the header beside an overridden guidance', () {
    late LocalStore store;

    setUp(() async {
      store = LocalStore.memory();
      await seedDevice(store);
    });
    tearDown(() async => store.close());

    testWidgets('NO CHEERFUL PHRASE SITS BESIDE THE ILLNESS SENTENCE', (
      tester,
    ) async {
      await tester.pumpWidget(todayHost(store));
      await tester.pumpAndSettle();

      // The fixture's band is `high` and its guidance is the illness override,
      // which the recovery card renders verbatim.
      await reveal(tester, find.textContaining('An illness signal is active'));
      expect(
        find.textContaining('An illness signal is active'),
        findsOneWidget,
      );
      for (final flattery in <String>[
        'Well recovered',
        'well recovered',
        'Primed',
        'PRIMED',
        'Ready to train',
      ]) {
        expect(
          find.textContaining(flattery),
          findsNothing,
          reason: 'the band is not a phrase, and the flag overrides the day',
        );
      }
    });
  });

  group('the tab bar', () {
    testWidgets('shows every tab', (tester) async {
      await tester.pumpWidget(
        host(AppTabBar(currentIndex: 0, onSelect: (_) {})),
      );
      await tester.pumpAndSettle();

      for (final tab in kAppTabs) {
        expect(find.text(tab.label), findsOneWidget);
      }
    });

    test('THE BAR CONTAINS NO DEAD CONTROL', () {
      // It used to draw Actions dimmed and inert. `core/tabs.dart` argues why a
      // navigation control that never responds is worse than four tabs; this is
      // the check that the argument stayed applied. There is no way to express a
      // routeless tab any more, so the assertion is on the list's contents.
      expect(kAppTabs.map((tab) => tab.label), <String>[
        'Today',
        'Sleep',
        'Activity',
        'Insights',
        'Coach',
      ]);
      // The Coach tab is the weekly plan on `/actions`. The chat is still a
      // FAB on Today and its own route (`/coach`), never a tab.
      expect(kAppTabs.last.route, Routes.actions);
      expect(kAppTabs.map((tab) => tab.route), isNot(contains(Routes.coach)));
    });

    test('EVERY TAB NAMES A ROUTE THE ROUTER WIRES', () {
      // The failure this guards is a tab pointing at a path nobody registered.
      // The router builds its branches from this same list, so the check is now
      // that the paths are the agreed ones rather than invented here.
      const wired = <String>{
        Routes.today,
        Routes.sleep,
        Routes.activity,
        Routes.insights,
        Routes.actions,
      };
      for (final tab in kAppTabs) {
        expect(
          wired,
          contains(tab.route),
          reason: '${tab.label} is a live tab',
        );
      }
    });

    testWidgets('a tap reports its BRANCH INDEX, the active tab included', (
      tester,
    ) async {
      // Index, not route: the shell moves by branch and pressing the tab you are
      // already on is what pops that branch to its root.
      final pressed = <int>[];
      await tester.pumpWidget(
        host(AppTabBar(currentIndex: 0, onSelect: pressed.add)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Activity'));
      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();

      expect(pressed, <int>[2, 0]);
    });

    testWidgets(
      'every tab is a button to a screen reader, the active one selected',
      (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          host(AppTabBar(currentIndex: 1, onSelect: (_) {})),
        );
        await tester.pumpAndSettle();

        for (final tab in kAppTabs) {
          expect(find.bySemanticsLabel(tab.label), findsOneWidget);
        }
        expect(
          tester
              .getSemantics(find.bySemanticsLabel('Sleep'))
              .flagsCollection
              .isSelected,
          Tristate.isTrue,
        );
        handle.dispose();
      },
    );
  });
}

/// A `DateNavigation` needs a callback and these cases never press anything.
void _ignore(String _) {}
