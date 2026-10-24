/// The Coach button belongs to Today, and to nothing else.
///
/// `~/projects/healthee-legacy/app/lib/main.dart:399` is one line —
/// `if (_tab == 0) return CoachFab(onTap: _openCoach);` — and it is the whole
/// shape this suite defends. Coach was a tab here, which put a chat surface in
/// the primary navigation beside four screens of measurements and left Insights
/// homeless.
///
/// It also checks the tab set itself from the running shell rather than from the
/// list constant: `today_header_test.dart` asserts what `kAppTabs` contains, and
/// this asserts what the owner can actually see and press, which is the thing a
/// wrong branch order would break without changing the list at all.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/routes.dart';
import 'package:healthee/core/tabs.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/coach/widgets/coach_fab.dart';
import 'package:healthee/features/today/v02/today_header.dart';
import 'package:healthee/shared/app_tab_bar.dart';

import '_today_host.dart';

void main() {
  late LocalStore store;

  setUp(() async {
    store = LocalStore.memory();
    await seedDevice(store);
  });
  tearDown(() async => store.close());

  testWidgets('THE FIVE TABS ARE THERE, AND COACH IS NOT ONE OF THEM', (
    tester,
  ) async {
    await tester.pumpWidget(routedApp(store));
    await tester.pumpAndSettle();

    for (final label in <String>[
      'Today',
      'Sleep',
      'Activity',
      'Insights',
      'Coach',
    ]) {
      // Scoped to the bar: `Today` is also the screen's own h1 since the v02
      // redesign, so an unscoped finder would be asking about the title.
      expect(
        find.descendant(of: find.byType(AppTabBar), matching: find.text(label)),
        findsOneWidget,
        reason: '$label is a tab',
      );
    }
    // The Coach TAB is the weekly plan (`/actions`); the chat is still a button
    // on Today and a route behind it, not a tab.
    expect(kAppTabs.last.route, Routes.actions);
  });

  testWidgets('THE COACH BUTTON IS IN TODAY’S HEADER AND NOWHERE ELSE', (
    tester,
  ) async {
    await tester.pumpWidget(routedApp(store));
    await tester.pumpAndSettle();
    expect(find.byType(CoachFab), findsOneWidget, reason: 'Today has it');
    // In the header, not floating over the content.
    expect(
      find.descendant(
        of: find.byType(TodayHeader),
        matching: find.byType(CoachFab),
      ),
      findsOneWidget,
    );
    expect(find.byType(FloatingActionButton), findsNothing);

    for (final tab in <String>['Sleep', 'Activity', 'Insights', 'Coach']) {
      await tapTab(tester, tab);
      expect(
        find.byType(CoachFab),
        findsNothing,
        reason: '$tab must not carry a second entrance to one surface',
      );
    }

    await tapTab(tester, 'Today');
    expect(find.byType(CoachFab), findsOneWidget, reason: 'and it comes back');
  });

  testWidgets('there is no record-workout FAB on Activity', (tester) async {
    // Legacy has one (`main.dart:400`). This app has no workout recorder, and a
    // control that starts a recording nothing can stop would be worse than none.
    await tester.pumpWidget(routedApp(store));
    await tester.pumpAndSettle();
    await tapTab(tester, 'Activity');

    expect(find.byType(FloatingActionButton), findsNothing);
  });
}
