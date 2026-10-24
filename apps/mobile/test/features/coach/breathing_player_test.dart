/// The breathing player on fake time: the phase, the countdown and the counts
/// follow the clock, and what is logged follows how the session ended.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:healthee/core/routes.dart';
import 'package:healthee/data/basics/breathing/breathing_plan.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/shared/v02/instruments/age_sphere.dart';

import '_breathing_fakes.dart';

const String _caption =
    'Logs 10 min of meditation when you finish. '
    'Ending early logs what you did.';

void main() {
  late LocalStore store;
  late BreathingHarness harness;
  setUp(() {
    store = LocalStore.memory();
    harness = BreathingHarness(store);
  });
  tearDown(() => store.close());

  /// Opens the player from a home screen so back has somewhere to go.
  Future<void> open(
    WidgetTester tester,
    String location, {
    bool reduced = false,
    double textScale = 1,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view
      ..physicalSize = const Size(390 * 3, 3000)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      harness.app(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => context.push(location),
              child: const Text('open'),
            ),
          ),
        ),
        reducedMotion: reduced,
        textScale: textScale,
        brightness: brightness,
      ),
    );
    await tester.tap(find.text('open'));
    // The sphere never stops turning, so frames are pumped by hand.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  Future<void> run(WidgetTester tester, int seconds) =>
      tester.pump(Duration(seconds: seconds));

  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  const night = '${Routes.breathingPlayer}?item=night';

  testWidgets('opens on the item with its title, time and chips', (
    tester,
  ) async {
    await open(tester, night);
    expect(find.text('Night wind-down'), findsOneWidget);
    expect(find.text('10:15 pm · 10 min'), findsOneWidget);
    for (final name in ['Steady', 'Long exhale', 'Box', '4-7-8']) {
      expect(find.textContaining(name, findRichText: true), findsOneWidget);
    }
    expect(find.text('Breathe in'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('Breath 1 of 60'), findsOneWidget);
    expect(find.text('10:00 left'), findsOneWidget);
    expect(find.text('In 4'), findsOneWidget);
    expect(find.text('Out 6'), findsOneWidget);
    expect(find.text(_caption), findsOneWidget);
    expect(find.textContaining('Sound'), findsNothing);
  });

  testWidgets('item titles', (tester) async {
    await open(tester, '${Routes.breathingPlayer}?item=morning');
    expect(find.text('Morning breathing'), findsOneWidget);
  });

  testWidgets('the phase, countdown, breath and time left follow the clock', (
    tester,
  ) async {
    await open(tester, night);
    await run(tester, 4);
    expect(find.text('Breathe out'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    await run(tester, 3);
    expect(find.text('3'), findsOneWidget);
    await run(tester, 227);
    expect(find.text('Breath 24 of 60'), findsOneWidget);
    expect(find.text('6:06 left'), findsOneWidget);
  });

  testWidgets('pause holds the clock and resume carries on', (tester) async {
    await open(tester, night);
    await run(tester, 2);
    await tester.tap(find.bySemanticsLabel('Pause'));
    await run(tester, 1);
    final held = find.text('10:00 left');
    await run(tester, 60);
    expect(find.text('Breath 1 of 60'), findsOneWidget);
    expect(held, findsNothing);
    expect(find.bySemanticsLabel('Resume'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Resume'));
    await run(tester, 2);
    await run(tester, 2);
    expect(find.text('Breathe out'), findsOneWidget);
  });

  testWidgets('ending early logs the whole minutes actually breathed', (
    tester,
  ) async {
    await open(tester, night);
    await run(tester, 150);
    await tester.tap(find.text('End'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('This logs 2 min of meditation.'), findsOneWidget);
    await tester.tap(find.text('End session'));
    await flush(tester);
    expect(harness.log.minutes, [2]);
    expect(harness.done, contains(BreathingItemKind.night));
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('under a minute logs nothing and does not mark it done', (
    tester,
  ) async {
    await open(tester, night);
    await run(tester, 30);
    await tester.tap(find.text('End'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('nothing is logged'), findsOneWidget);
    await tester.tap(find.text('End session'));
    await flush(tester);
    expect(harness.log.minutes, isEmpty);
    expect(harness.done, isEmpty);
  });

  testWidgets('keep going resumes where it was', (tester) async {
    await open(tester, night);
    await run(tester, 20);
    await tester.tap(find.text('End'));
    await tester.pump(const Duration(milliseconds: 300));
    await run(tester, 60);
    await tester.tap(find.text('Keep going'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('9:40 left'), findsOneWidget);
    await run(tester, 10);
    expect(find.text('9:30 left'), findsOneWidget);
    expect(harness.log.minutes, isEmpty);
  });

  testWidgets('finishing logs the full planned minutes and marks it done', (
    tester,
  ) async {
    await open(tester, night);
    await run(tester, 601);
    await flush(tester);
    expect(harness.log.minutes, [10]);
    expect(harness.done, contains(BreathingItemKind.night));
    expect(find.text('Done'), findsOneWidget);
    expect(
      find.text('Logged 10 min to your journal as meditation.'),
      findsOneWidget,
    );
    expect(find.text('Close'), findsOneWidget);
    expect(find.text('0:00 left'), findsOneWidget);
  });

  testWidgets('a failed save is said and can be retried', (tester) async {
    harness.log.failNext = true;
    await open(tester, night);
    await run(tester, 601);
    await flush(tester);
    expect(find.text("Couldn't save this to your journal."), findsOneWidget);
    expect(harness.log.minutes, isEmpty);
    await tester.tap(find.text('Try again'));
    await flush(tester);
    expect(harness.log.minutes, [10]);
  });

  testWidgets('a chip restarts the timeline with that pattern', (tester) async {
    await open(tester, night);
    await run(tester, 25);
    expect(find.text('Breath 3 of 60'), findsOneWidget);
    final box = find.bySemanticsLabel('Box 4, 4, 4, 4');
    await tester.ensureVisible(box);
    await tester.tap(box);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Breath 1 of 37'), findsOneWidget);
    expect(find.text('10:00 left'), findsOneWidget);
    expect(find.text('Hold 4'), findsNWidgets(2));
    expect(find.text('Breathe in'), findsOneWidget);
    await run(tester, 4);
    expect(find.text('Hold'), findsOneWidget);
  });

  testWidgets('a pattern link is an ad hoc session named for the pattern', (
    tester,
  ) async {
    await open(tester, '${Routes.breathingPlayer}?pattern=box');
    expect(find.text('Box 4·4·4·4'), findsNothing);
    expect(find.text('5 min session'), findsOneWidget);
    expect(find.text('Breath 1 of 18'), findsOneWidget);
    await run(tester, 301);
    await flush(tester);
    expect(harness.log.minutes, [5]);
    expect(harness.done, isEmpty);
  });

  testWidgets('an unknown session says so', (tester) async {
    await open(tester, '${Routes.breathingPlayer}?item=lunch');
    expect(find.text('That session is not available'), findsOneWidget);
  });

  group('the sphere', () {
    AgeSphere sphere(WidgetTester tester) =>
        tester.widget<AgeSphere>(find.byType(AgeSphere));

    testWidgets('breathes in the Mind hue and holds on a pause', (
      tester,
    ) async {
      await open(tester, night);
      expect(sphere(tester).useFamily, isTrue);
      final breath = sphere(tester).breath!;
      await run(tester, 2);
      final mid = breath.value;
      expect(mid, greaterThan(0.72));
      await run(tester, 2);
      expect(breath.value, 1);
      await tester.tap(find.bySemanticsLabel('Pause'));
      await run(tester, 1);
      final held = breath.value;
      await run(tester, 30);
      expect(breath.value, held);
    });

    testWidgets('reduced motion leaves it still; words and bars still move', (
      tester,
    ) async {
      await open(tester, night, reduced: true);
      expect(sphere(tester).breath, isNull);
      await run(tester, 4);
      expect(find.text('Breathe out'), findsOneWidget);
      expect(find.text('6'), findsOneWidget);
      expect(find.text('9:56 left'), findsOneWidget);
    });
  });

  for (final brightness in Brightness.values) {
    testWidgets('nothing overflows at text 1.3, $brightness', (tester) async {
      await open(tester, night, textScale: 1.3, brightness: brightness);
      await run(tester, 4);
      expect(tester.takeException(), isNull);
    });
  }
}
