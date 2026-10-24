/// What Android back does — all three branches of the rule, including the one
/// that leaves the app.
///
/// Back used to quit from any tab: the shell had no `PopScope`, so the system
/// pop went straight past five branch navigators to the engine. The rule is now
/// in `shared/app_shell.dart` and it is three steps, so this suite is three
/// groups plus a route pushed inside a tab, which is the case the first step
/// exists for and the one a history-list implementation would get wrong.
///
/// **The third outcome is asserted against the platform channel.** Leaving the
/// app is not something a widget test can see in the tree, so this watches
/// `SystemChannels.platform` for the `SystemNavigator.pop` the shell actually
/// sends. A boolean on the shell would have been easier to assert and would have
/// been asserting the flag rather than the behaviour.
///
/// ## What this file does NOT cover, and where that lives
///
/// Everything here is *inside* the shell. That is the whole of the rule and it
/// was still not the whole of the behaviour: every screen the avatar opens lives
/// outside the shell, was reached with `context.go`, and therefore had nothing
/// beneath it — so this rule fired and left the app. `out_of_shell_navigation_
/// test.dart` is that half, and it exists because this file passing was not
/// evidence that back worked.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/sleep/sleep_screen.dart';
import 'package:healthee/features/today/today_screen.dart';

import '_today_host.dart';

/// Records every `SystemNavigator.pop` the app sends while a test runs.
///
/// Filtered to that one method on purpose. The platform channel also carries
/// `SystemChrome` and `SystemSound` traffic that the framework sends on its own,
/// and a list of everything would make "nothing happened" impossible to assert.
List<String> _watchPlatformCalls(WidgetTester tester) {
  final calls = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'SystemNavigator.pop') {
        calls.add(call.method);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return calls;
}

/// Sends one system back press, the way the platform does.
Future<void> _pressBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

/// Pushes a detail route onto whichever branch navigator is showing.
Future<void> _pushDetail(WidgetTester tester) async {
  final context = tester.element(find.byType(TodayScreen).first);
  unawaited(
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => const Scaffold(body: Text('a detail route')),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late LocalStore store;

  setUp(() async {
    store = LocalStore.memory();
    await seedDevice(store);
  });
  tearDown(() async => store.close());

  testWidgets('BACK POPS A ROUTE PUSHED INSIDE A TAB', (tester) async {
    final platform = _watchPlatformCalls(tester);
    await tester.pumpWidget(routedApp(store));
    await tester.pumpAndSettle();
    await _pushDetail(tester);
    expect(find.text('a detail route'), findsOneWidget);

    await _pressBack(tester);

    expect(
      find.text('a detail route'),
      findsNothing,
      reason: 'the tab has its own stack and back is what unwinds it',
    );
    expect(find.byType(TodayScreen), findsOneWidget);
    expect(
      platform,
      isNot(contains('SystemNavigator.pop')),
      reason: 'a pushed route is not a reason to leave the app',
    );
  });

  testWidgets('BACK FROM A NON-TODAY TAB LANDS ON TODAY', (tester) async {
    final platform = _watchPlatformCalls(tester);
    await tester.pumpWidget(routedApp(store));
    await tester.pumpAndSettle();
    await tapTab(tester, 'Sleep');
    expect(find.byType(SleepScreen), findsOneWidget);

    await _pressBack(tester);

    expect(
      find.byType(TodayScreen),
      findsOneWidget,
      reason:
          'a bottom bar implies a home, and back means up before it means out',
    );
    expect(
      platform,
      isNot(contains('SystemNavigator.pop')),
      reason: 'THIS is the bug: back from Sleep used to quit the app',
    );
  });

  testWidgets('back from every non-Today tab lands on Today', (tester) async {
    // Not just Sleep. The rule is about the branch index, so it has to hold for
    // every branch that is not the home one — including the two that landed in
    // this pass and have the least prose written about them.
    for (final tab in <String>['Sleep', 'Activity', 'Insights', 'Coach']) {
      await tester.pumpWidget(routedApp(store));
      await tester.pumpAndSettle();
      await tapTab(tester, tab);
      await _pressBack(tester);

      expect(
        find.byType(TodayScreen),
        findsOneWidget,
        reason: 'back from $tab',
      );
    }
  });

  testWidgets('a pushed route on a non-Today tab pops before the tab changes', (
    tester,
  ) async {
    // The order of the two steps, which is what a "go home on back" shortcut
    // would get wrong: the owner opened something FROM Sleep, and back has to
    // close that before it decides they meant to leave Sleep.
    await tester.pumpWidget(routedApp(store));
    await tester.pumpAndSettle();
    await tapTab(tester, 'Sleep');
    final context = tester.element(find.byType(SleepScreen).first);
    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (context) => const Scaffold(body: Text('a sleep detail')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _pressBack(tester);

    expect(find.text('a sleep detail'), findsNothing);
    expect(
      find.byType(SleepScreen),
      findsOneWidget,
      reason: 'closing a detail is not leaving the tab it was opened from',
    );
  });

  testWidgets('BACK ON TODAY WITH AN EMPTY STACK LEAVES THE APP', (
    tester,
  ) async {
    // The deliberate end of the rule. `shared/app_shell.dart` argues it: the
    // platform contract, no unsaved state, and no "press back again" nag.
    final platform = _watchPlatformCalls(tester);
    await tester.pumpWidget(routedApp(store));
    await tester.pumpAndSettle();
    expect(find.byType(TodayScreen), findsOneWidget);

    await _pressBack(tester);

    expect(
      platform,
      contains('SystemNavigator.pop'),
      reason:
          'a system button that does nothing is the dead-control defect in a '
          'different place',
    );
  });

  testWidgets('back on Today AFTER a round trip still leaves', (tester) async {
    // Going Sleep → back → Today leaves the Today branch at its root, so the
    // next back is the exit. A rule that remembered the visit would trap the
    // owner one press deeper each time they used the bar.
    final platform = _watchPlatformCalls(tester);
    await tester.pumpWidget(routedApp(store));
    await tester.pumpAndSettle();
    await tapTab(tester, 'Activity');
    await _pressBack(tester);
    expect(platform, isEmpty);

    await _pressBack(tester);

    expect(platform, contains('SystemNavigator.pop'));
  });
}
