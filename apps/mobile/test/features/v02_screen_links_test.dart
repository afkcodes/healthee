/// **The four new screens are reachable, and this is what proves it.**
///
/// A screen nothing opens is the defect this work exists to fix, and it is
/// invisible: the code compiles, the route resolves, and nobody ever gets there.
/// `reachability_test.dart` makes the same argument for the settings index; this
/// file makes it for `body`, `fitness`, `recovery` and `sleep-history`, and it
/// makes it by **tapping the real control on the real router** rather than by
/// asserting a route constant, which would go green on a screen with no door.
///
/// The doorways walked here are `docs/V02_CONNECTIVITY.md` section 2's, and the
/// first of them is the one section 0 corrected: **Today's entry points are the
/// three hero summary rows**, not a panel `Details` link. The recovery row is
/// what opens `#recovery`, so that is the tap this suite makes.
///
/// The panel `Details` links themselves — and the two bridges, the device strip
/// and the metric directory's closing rows — are `panel_links_test.dart`. The
/// seam is the kind of control, not the destination: several of them land on
/// screens this file also reaches, by a different door.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/router.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/activity/fitness_screen.dart';
import 'package:healthee/features/insights/v02/pattern_panels.dart';
import 'package:healthee/features/sleep/sleep_history_screen.dart';
import 'package:healthee/features/today/body_screen.dart';
import 'package:healthee/features/today/recovery_screen.dart';

import '_today_host.dart';

/// A phone-shaped viewport tall enough that a doorway further down the scroll
/// is actually built. A `ListView` does not build what it cannot show, and a
/// tap on an unbuilt row is a test that proves nothing.
void _tallPhone(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(420, 3400)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Taps [finder] after scrolling it into the enclosing list.
Future<void> _open(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

void main() {
  late LocalStore store;

  setUp(() async {
    store = LocalStore.memory();
    await seedDevice(store);
  });
  tearDown(() async => store.close());

  test('every new screen has a route constant, and it is the design’s own', () {
    // The paths are the prototype's hashes, so a deep link written from the
    // design lands where the design says it does.
    expect(Routes.body, '/body');
    expect(Routes.fitness, '/fitness');
    expect(Routes.recovery, '/recovery');
    expect(Routes.sleepHistory, '/sleep-history');
  });

  group('from Today', () {
    testWidgets('THE RECOVERY KEY NUMBER OPENS RECOVERY', (tester) async {
      _tallPhone(tester);
      await tester.pumpWidget(routedApp(store));
      await tester.pumpAndSettle();

      await _open(tester, find.bySemanticsLabel(RegExp(r'^Recovery\. ')));
      expect(find.byType(RecoveryScreen), findsOneWidget);
    });

    testWidgets('THE HERO OPENS THE BIOLOGICAL AGE SCREEN', (tester) async {
      _tallPhone(tester);
      await tester.pumpWidget(routedApp(store));
      await tester.pumpAndSettle();

      await _open(
        tester,
        find.bySemanticsLabel(RegExp(r'^Biological age 34\.3 years')),
      );
      expect(find.byType(BodyScreen), findsOneWidget);
    });
  });

  group('from the other tabs', () {
    testWidgets('SLEEP’S DETAILS OPENS THE SLEEP HISTORY', (tester) async {
      _tallPhone(tester);
      await tester.pumpWidget(routedApp(store));
      await tester.pumpAndSettle();
      await tapTab(tester, 'Sleep');

      await _open(tester, find.text('Details'));
      expect(find.byType(SleepHistoryScreen), findsOneWidget);
    });

    testWidgets('ACTIVITY’S BRIDGE OPENS RECOVERY', (tester) async {
      _tallPhone(tester);
      await tester.pumpWidget(routedApp(store));
      await tester.pumpAndSettle();
      await tapTab(tester, 'Activity');

      await _open(tester, find.text('View recovery'));
      expect(find.byType(RecoveryScreen), findsOneWidget);
    });

    testWidgets('INSIGHTS’ FITNESS → AGE TILE OPENS THE AGE MODEL', (
      tester,
    ) async {
      _tallPhone(tester);
      await tester.pumpWidget(routedApp(store));
      await tester.pumpAndSettle();
      await tapTab(tester, 'Insights');

      await _open(tester, find.byType(AgeHeroTile));
      expect(find.byType(BodyScreen), findsOneWidget);
    });

    testWidgets('Insights’ Sleep history row reaches the nights', (
      tester,
    ) async {
      _tallPhone(tester);
      await tester.pumpWidget(routedApp(store));
      await tester.pumpAndSettle();
      await tapTab(tester, 'Insights');

      await _open(tester, find.text('Sleep history'));
      expect(find.byType(SleepHistoryScreen), findsOneWidget);
    });

    testWidgets('Insights’ Fitness estimates row reaches fitness', (
      tester,
    ) async {
      _tallPhone(tester);
      await tester.pumpWidget(routedApp(store));
      await tester.pumpAndSettle();
      await tapTab(tester, 'Insights');

      await _open(tester, find.text('Fitness estimates'));
      expect(find.byType(FitnessScreen), findsOneWidget);
    });
  });
}
