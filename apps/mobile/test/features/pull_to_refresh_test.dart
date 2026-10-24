/// Pull-to-refresh is the manual sync, and it takes the un-debounced path.
///
/// This is what let the permanent "Sync now" button go. `sync_controller.dart`
/// keeps two entry points on purpose:
///
/// ```text
///   autoSyncNow()  debounced   a heuristic, run on a foreground transition
///   syncNow()      NEVER       what the owner asked for, right now
/// ```
///
/// and its own docstring says why the distinction is load-bearing: *"an explicit
/// request is not a heuristic, and a heuristic that could be triggered by asking
/// would make the button feel broken exactly when someone reached for it."*
/// Pulling down is asking. If the gesture were wired to [autoSyncNow] it would
/// silently do nothing inside the debounce window, which is the same broken
/// feeling with no button to blame.
///
/// The assertion is on WHICH METHOD RAN, not on whether data changed: a test that
/// checked for new rows would pass with either entry point on the first pull of a
/// cold app, and fail for reasons about the gate on the second.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/data/sync/connection_state.dart';
import 'package:healthee/data/sync/sync_controller.dart';
import 'package:healthee/data/sync/sync_outcome.dart';
import 'package:healthee/features/coach/coach_home_screen.dart';
import 'package:healthee/features/insights/insights_screen.dart';
import 'package:healthee/features/sleep/sleep_screen.dart';
import 'package:healthee/features/today/today_screen.dart';

import '_today_host.dart';
import 'coach/_coach_home_fakes.dart' show stubbedBasics;

/// A controller that records which entry point was called and runs nothing.
class _RecordingSync extends SyncController {
  final List<String> calls = <String>[];

  @override
  StrapConnection build() => Disconnected(lastCompleteSync: now);

  @override
  Future<SyncOutcome?> syncNow() async {
    calls.add('syncNow');
    return null;
  }

  @override
  Future<SyncOutcome?> autoSyncNow() async {
    calls.add('autoSyncNow');
    return null;
  }
}

Widget _host(LocalStore store, _RecordingSync sync, Widget home) =>
    todayHost(store, sync: sync, home: home);

/// Drags the list down far enough to trip the refresh indicator.
///
/// A held drag rather than a fling: a fling is ballistic and its velocity
/// decides whether the indicator arms, which makes the test's outcome depend on
/// how long the screen's own list happens to be.
Future<void> _pullDown(WidgetTester tester, Finder screen) async {
  final list = find
      .descendant(of: screen, matching: find.byType(Scrollable))
      .first;
  final gesture = await tester.startGesture(tester.getCenter(list));
  for (var step = 0; step < 8; step++) {
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump();
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  late LocalStore store;
  late _RecordingSync sync;

  setUp(() async {
    store = LocalStore.memory();
    await seedDevice(store);
    sync = _RecordingSync();
  });
  tearDown(() async => store.close());

  testWidgets('PULLING DOWN CALLS THE UN-DEBOUNCED SYNC', (tester) async {
    await tester.pumpWidget(_host(store, sync, TodayScreen(now: now)));
    await tester.pumpAndSettle();

    await _pullDown(tester, find.byType(TodayScreen));

    expect(sync.calls, contains('syncNow'));
    expect(
      sync.calls,
      isNot(contains('autoSyncNow')),
      reason:
          'the debounced path would silently decline inside its window, which '
          'is a gesture the owner learns not to trust',
    );
  });

  // The gesture is on the shared shell, so it is one implementation — but a
  // screen that forgot `AlwaysScrollableScrollPhysics` would not scroll on a
  // short day and the pull would never start.
  //
  // One test per screen rather than a loop in one body: a second `pumpWidget`
  // inside a test UPDATES the existing `ProviderScope` rather than replacing it,
  // so a fresh notifier override is not applied and the recorder for the second
  // screen stays empty — a green-looking test measuring the first screen twice.
  for (final screen in <Widget>[
    const SleepScreen(),
    const InsightsScreen(),
    const CoachHomeScreen(),
  ]) {
    testWidgets('${screen.runtimeType} refreshes the same way', (tester) async {
      final recorder = _RecordingSync();
      await tester.pumpWidget(
        _host(
          store,
          recorder,
          screen is CoachHomeScreen ? stubbedBasics(screen) : screen,
        ),
      );
      await tester.pumpAndSettle();

      await _pullDown(tester, find.byType(screen.runtimeType));

      expect(recorder.calls, contains('syncNow'));
    });
  }

  testWidgets('THE STRIP IS NOT THE ONLY WAY TO SYNC ANY MORE', (tester) async {
    // The healthy state draws no strip and no button at all — the gesture is
    // the whole manual path, which is what let the permanent chrome go.
    await tester.pumpWidget(_host(store, sync, TodayScreen(now: now)));
    await tester.pumpAndSettle();

    expect(find.text('Sync now'), findsNothing);
    await _pullDown(tester, find.byType(TodayScreen));
    expect(sync.calls, contains('syncNow'));
  });
}
