/// The ring round the avatar: what it draws, what it says, and what it is not.
///
/// It is the app's only connection chrome now, so three things about it are
/// claims rather than decoration:
///
///   * **progress is determinate exactly where the fetch reported it.** An
///     indeterminate spinner cannot distinguish a working sync from a stalled
///     one, which is a question that went unanswerable on this project; a
///     determinate arc that stops moving can. Faking a fraction for a phase that
///     has none would put that answer back out of reach in the other direction,
///     so the null case is asserted as hard as the value case.
///   * **each state carries a distinct spoken label.** The strip's headline was
///     carrying that, and four colours are four nothings to a screen reader.
///   * **it is not a button.** Tapping the avatar opens Settings, as it always
///     has, and the ring contributes no gesture of its own.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/ble/strap_progress.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/data/push/push_stamp.dart';
import 'package:healthee/data/sync/connection_health.dart';
import 'package:healthee/data/sync/connection_state.dart';
import 'package:healthee/data/sync/sync_failure.dart';
import 'package:healthee/shared/connection/sync_ring.dart';

final DateTime _now = DateTime(2026, 8, 4, 9, 30);

const SyncFailure _bluetoothOff = SyncFailure(
  headline: 'Bluetooth is off',
  remedy: 'Turn Bluetooth on and try again.',
  code: 'bluetooth_off',
  source: 'test',
);

ConnectionHealth _health(StrapConnection link, {bool signedIn = true}) =>
    connectionHealth(
      link: link,
      now: _now,
      push: const PushStamp.never(),
      signedIn: signedIn,
      lastStrapSync: _now.subtract(const Duration(minutes: 4)),
    );

/// The four states, each from a real link the sync engine can publish.
final Map<SyncRingState, ConnectionHealth>
_states = <SyncRingState, ConnectionHealth>{
  SyncRingState.idle: _health(
    Disconnected(lastCompleteSync: _now.subtract(const Duration(minutes: 4))),
  ),
  SyncRingState.connected: _health(Connected(since: _now)),
  SyncRingState.syncing: _health(
    const Syncing(
      progress: StrapSyncProgress(step: 4, total: 13, label: 'heart rate'),
    ),
  ),
  SyncRingState.needsAttention: _health(const ConnectionFailed(_bluetoothOff)),
};

Widget _ring(ConnectionHealth? health, {VoidCallback? onTap}) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(
    body: Center(
      child: SyncRing(
        health: health,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: const SizedBox(width: 38, height: 38),
        ),
      ),
    ),
  ),
);

CircularProgressIndicator _indicator(WidgetTester tester) => tester
    .widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator));

void main() {
  group('THE FOUR STATES ARE FOUR STATES', () {
    test('every link maps to exactly one, and all four are reachable', () {
      for (final entry in _states.entries) {
        expect(ringStateOf(entry.value), entry.key);
      }
      expect(_states.keys.toSet(), SyncRingState.values.toSet());
    });

    test('the fault state follows `quiet`, which is computed in ONE place', () {
      // A data-side fault has no link fault at all, so a ring reading
      // `linkAlerts` — or re-deriving quietness — would draw the resting state
      // over a phone that cannot reach its server.
      final signedOut = _health(
        Disconnected(lastCompleteSync: _now),
        signedIn: false,
      );
      expect(signedOut.linkAlerts, isEmpty);
      expect(signedOut.quiet, isFalse);
      expect(ringStateOf(signedOut), SyncRingState.needsAttention);
    });

    testWidgets('each one draws a distinct colour from the token set', (
      tester,
    ) async {
      const colors = HealtheeColors.light();
      final drawn = <SyncRingState, Color?>{};
      for (final entry in _states.entries) {
        await tester.pumpWidget(_ring(entry.value));
        await tester.pump();
        drawn[entry.key] = _indicator(tester).color;
      }

      expect(drawn[SyncRingState.idle], colors.ink2);
      expect(drawn[SyncRingState.connected], colors.accent);
      expect(drawn[SyncRingState.syncing], colors.accent);
      // Full ink, never `unf` or `alert`: `README.md` reserves one red for
      // illness and forbids `unf` as a warning colour. Loud is weight here, the
      // same rule `health_lines.dart` applies to the card's typography.
      expect(drawn[SyncRingState.needsAttention], colors.ink);
      expect(drawn[SyncRingState.needsAttention], isNot(colors.unf));
      expect(drawn[SyncRingState.needsAttention], isNot(colors.alert));
    });
  });

  group('PROGRESS IS DETERMINATE ONLY WHERE THE FETCH REPORTED IT', () {
    testWidgets('a reported step draws the fraction the fetcher gave', (
      tester,
    ) async {
      await tester.pumpWidget(_ring(_states[SyncRingState.syncing]));
      await tester.pump();

      // 4 of 13, reporting the step that STARTED — `strap_progress.dart` is
      // explicit that it must never read 100% while work is still running.
      expect(_indicator(tester).value, closeTo(3 / 13, 1e-9));
    });

    for (final (name, link) in <(String, StrapConnection)>[
      ('scanning', const Scanning()),
      ('connecting', const Connecting()),
      ('authenticating', const Authenticating()),
      ('syncing before the first fetch', const Syncing()),
    ]) {
      testWidgets('$name spins rather than inventing a fraction', (
        tester,
      ) async {
        await tester.pumpWidget(_ring(_health(link)));
        await tester.pump();

        expect(
          _indicator(tester).value,
          isNull,
          reason:
              'a determinate bar that is really a guess is the thing '
              '`strap_progress.dart` exists to avoid',
        );
      });
    }

    testWidgets('the three still states draw a COMPLETE circle, not progress', (
      tester,
    ) async {
      for (final state in <SyncRingState>[
        SyncRingState.idle,
        SyncRingState.connected,
        SyncRingState.needsAttention,
      ]) {
        await tester.pumpWidget(_ring(_states[state]));
        await tester.pump();
        expect(_indicator(tester).value, 1, reason: '$state is not progress');
      }
    });
  });

  group('EACH STATE CARRIES A DISTINCT SPOKEN LABEL', () {
    test('no two states announce the same sentence', () {
      final labels = _states.values.map(ringLabel).toList();
      expect(labels.toSet(), hasLength(labels.length), reason: '$labels');
      for (final label in labels) {
        expect(label, isNotEmpty);
      }
    });

    test('a running sync names the step, not "in progress"', () {
      expect(
        ringLabel(_states[SyncRingState.syncing]!),
        'Syncing — heart rate, step 4 of 13',
      );
    });

    test('a phase with no fraction still says which phase', () {
      expect(ringLabel(_health(const Authenticating())), 'Authenticating');
    });

    test('the fault label names the fault AND points at the card', () {
      // The ring cannot explain a fault, so it says where the explanation is.
      final label = ringLabel(_states[SyncRingState.needsAttention]!);
      expect(label, startsWith('Bluetooth is off'));
      expect(label, contains('Data health'));
    });

    test('several faults are counted, not silently reduced to one', () {
      final health = connectionHealth(
        link: const ConnectionFailed(_bluetoothOff),
        now: _now,
        signedIn: false,
        lastStrapSync: _now,
      );
      expect(health.alerts.length, greaterThan(1));
      expect(
        ringLabel(health),
        contains('and ${health.alerts.length - 1} more'),
      );
    });

    testWidgets('the label reaches a screen reader', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_ring(_states[SyncRingState.connected]));
      await tester.pump();

      expect(find.bySemanticsLabel('Connected'), findsOneWidget);
      handle.dispose();
    });
  });

  group('THE RING IS NOT A CONTROL', () {
    testWidgets('the child keeps its own gesture', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _ring(_states[SyncRingState.syncing], onTap: () => taps++),
      );
      await tester.pump();

      await tester.tap(find.byType(GestureDetector).last);
      expect(taps, 1, reason: 'the avatar still opens Settings');
    });

    testWidgets('a null classification draws NO ring at all', (tester) async {
      // Not a reassuring one. Nothing has classified anything here.
      await tester.pumpWidget(_ring(null));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets("legacy's 46 px geometry is unchanged", (tester) async {
      await tester.pumpWidget(_ring(_states[SyncRingState.syncing]));
      await tester.pump();

      expect(
        tester.getSize(find.byType(CircularProgressIndicator)),
        const Size(SyncRing.defaultDiameter, SyncRing.defaultDiameter),
      );
      expect(_indicator(tester).strokeWidth, SyncRing.defaultStroke);
    });
  });
}
