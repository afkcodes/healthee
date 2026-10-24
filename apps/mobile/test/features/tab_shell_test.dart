/// What a tab switch costs — measured, because it used to cost everything.
///
/// The bar was five per-screen copies over four sibling `GoRoute`s, so every tab
/// switch built a new page and threw the old one away. Scrolling Today two
/// screenfuls, tapping Sleep and tapping Today put Today back at the top.
///
/// Two of the three things that went with the scroll offset are invisible, which
/// is why this file exists rather than a note in a docstring:
///
///   * **The reveal registry died with the screen.** `RevealOnce` holds "have I
///     been seen" in the SCREEN's `State` precisely so a `ListView.builder` can
///     destroy and rebuild the chart without replaying it — and the navigation
///     layer was destroying the screen. CLAUDE.md's rule was held perfectly
///     inside a screen and defeated between them.
///   * **Providers re-read**, so a tab switch could re-hit the network.
///
/// Both are downstream of one fact — does the screen's `State` survive a round
/// trip — so that is what is asserted, twice, from two directions: the scroll
/// position that only a live `Scrollable` can hold, and the identity of the
/// `RevealOnce` state objects, which is what decides whether a reveal is re-armed
/// at all.
///
/// The last two are about the bar as a surface rather than as navigation: the
/// content must be laid out ABOVE it, not under it, and the tab you are standing
/// on must be legible as such by SHAPE, not by brightness alone.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/tabs.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/sleep/sleep_screen.dart';
import 'package:healthee/features/today/today_screen.dart';
import 'package:healthee/shared/app_tab_bar.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:solar_icons/solar_icons.dart';

import '_today_host.dart';

/// The Today branch's scroll position, whichever branch is on screen.
///
/// Scoped to `TodayScreen` on purpose: once Sleep has been visited both branches
/// are in the tree (that is what an `IndexedStack` is), so an unscoped finder
/// would silently read the wrong list.
double _todayOffset(WidgetTester tester) {
  final scrollable = find.descendant(
    of: find.byType(TodayScreen),
    matching: find.byType(Scrollable),
  );
  return tester.state<ScrollableState>(scrollable.first).position.pixels;
}

/// Every live `RevealOnce` state object on the Today branch, in tree order.
List<State<RevealOnce>> _revealStates(WidgetTester tester) {
  final reveals = find.descendant(
    of: find.byType(TodayScreen),
    matching: find.byType(RevealOnce),
  );
  return tester.stateList<State<RevealOnce>>(reveals).toList();
}

void main() {
  late LocalStore store;

  setUp(() async {
    store = LocalStore.memory();
    await seedDevice(store);
  });
  tearDown(() async => store.close());

  testWidgets('SCROLL POSITION SURVIVES A TAB ROUND TRIP', (tester) async {
    await tester.pumpWidget(routedApp(store));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(TodayScreen), const Offset(0, -600));
    await tester.pumpAndSettle();
    final scrolled = _todayOffset(tester);
    expect(scrolled, greaterThan(0), reason: 'the drag has to have moved it');

    await tapTab(tester, 'Sleep');
    expect(
      find.byType(SleepScreen),
      findsOneWidget,
      reason: 'the bar has to actually navigate',
    );
    await tapTab(tester, 'Today');

    expect(
      _todayOffset(tester),
      scrolled,
      reason:
          'the owner scrolled to something and looked at another tab; coming '
          'back to the top is the app losing their place',
    );
  });

  testWidgets('A REVEALED CHART DOES NOT REPLAY ON RETURN', (tester) async {
    // Tall enough that the charts are actually built (the hero holds none now). The default
    // 800×600 leaves Today opening on the header, the greeting and the recovery
    // gauge, and a test that captured an empty list of reveals would pass by
    // measuring nothing.
    tester.view
      ..physicalSize = const Size(420, 3000)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(routedApp(store));
    await tester.pumpAndSettle();

    // Every reveal on the first screenful has now played out.
    final before = _revealStates(tester);
    expect(before, isNotEmpty, reason: 'Today opens on charts');

    await tapTab(tester, 'Sleep');
    await tapTab(tester, 'Today');

    // Identity, not "is anything animating". `RevealOnce` asks the registry
    // exactly once, in `initState` — so the same `State` objects coming back is
    // the proof that no reveal was re-armed, and it cannot be confounded by an
    // ink splash from the tap that navigated. A rebuilt screen would give new
    // ones, ask again, and animate.
    expect(
      _revealStates(tester),
      before,
      reason:
          'a chart animating again on the way back is the replay CLAUDE.md '
          'forbids — the reveal registry must survive with the screen',
    );
  });

  testWidgets('THE BAR IS UNDER THE CONTENT, NOT OVER IT', (tester) async {
    await tester.pumpWidget(routedApp(store));
    await tester.pumpAndSettle();

    final bar = tester.getRect(find.byType(AppTabBar));
    final list = tester.getRect(
      find
          .descendant(
            of: find.byType(TodayScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );

    expect(
      list.bottom,
      lessThanOrEqualTo(bar.top),
      reason:
          'the scroll must end where the bar begins — a card sliced mid-chart '
          'is a chart the owner cannot read',
    );
    expect(
      bar.bottom,
      tester.view.physicalSize.height / tester.view.devicePixelRatio,
    );
  });

  testWidgets('THE TAB YOU ARE ON IS FILLED, THE OTHERS ARE OUTLINED', (
    tester,
  ) async {
    // The selected state used to be the accent and nothing else. At 20px a
    // green outline and a grey outline are one shape at two brightnesses, and
    // the two of them sit 60px apart on a bar read at a glance. Weight is the
    // second channel.
    await tester.pumpWidget(routedApp(store));
    await tester.pumpAndSettle();

    for (final AppTab tab in kAppTabs) {
      expect(
        tab.activeIcon,
        isNot(tab.icon),
        reason: 'a filled state identical to the resting one is not a state',
      );
    }

    // Asked of the bar alone: the screen above it may use the same glyphs
    // (the age card badges fitness with the Activity tab's runner).
    Finder inBar(IconData icon) => find.descendant(
      of: find.byType(AppTabBar),
      matching: find.byIcon(icon),
    );
    expect(inBar(SolarIconsBold.sun), findsOneWidget);
    expect(inBar(SolarIconsOutline.sun), findsNothing);
    for (final AppTab tab in kAppTabs.skip(1)) {
      expect(inBar(tab.icon), findsOneWidget, reason: tab.label);
      expect(inBar(tab.activeIcon), findsNothing, reason: tab.label);
    }
  });
}
