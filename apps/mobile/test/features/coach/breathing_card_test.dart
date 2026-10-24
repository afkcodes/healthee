/// The Breathing card: which rows show, which is done, which is next, and where
/// each control goes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/routes.dart';
import 'package:healthee/data/basics/breathing/breathing_plan.dart';
import 'package:healthee/data/basics/breathing/breathing_settings.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/coach/v02/breathing_card.dart';
import 'package:healthee/features/coach/v02/breathing_format.dart'
    show clockParts;
import 'package:healthee/features/coach/v02/breathing_play_button.dart';
import 'package:healthee/features/coach/v02/todays_basics_section.dart';

import '_breathing_fakes.dart';

void main() {
  late LocalStore store;
  late BreathingHarness harness;
  setUp(() {
    store = LocalStore.memory();
    harness = BreathingHarness(store);
  });
  tearDown(() => store.close());

  Future<void> pump(
    WidgetTester tester, {
    double textScale = 1,
    Widget? water,
  }) async {
    tester.view
      ..physicalSize = const Size(390 * 3, 1200)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      harness.app(
        Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: TodaysBasicsSection(water: water),
          ),
        ),
        textScale: textScale,
      ),
    );
    await tester.pumpAndSettle();
  }

  test('rowStates: done stay done, the first left is next, the rest later', () {
    final items = cardItems(defaultBreathingPlan());
    final states = rowStates(items, {BreathingItemKind.morning});
    expect(states, {
      BreathingItemKind.morning: BreathingRowState.done,
      BreathingItemKind.midday: BreathingRowState.next,
      BreathingItemKind.night: BreathingRowState.later,
    });
    expect(
      rowStates(items, {}).values.where((s) => s == BreathingRowState.next),
      hasLength(1),
    );
  });

  testWidgets('the section head, the water slot and the card', (tester) async {
    await pump(tester, water: const Text('the water card'));
    expect(find.text("Today's basics"), findsOneWidget);
    expect(find.text('tap to log'), findsOneWidget);
    expect(find.text('the water card'), findsOneWidget);
    expect(find.text('Breathing'), findsOneWidget);
    final water = tester.getTopLeft(find.text('the water card')).dy;
    expect(water, lessThan(tester.getTopLeft(find.text('Breathing')).dy));
  });

  testWidgets('one done, the next filled, the later one outline', (
    tester,
  ) async {
    harness.done = {BreathingItemKind.morning};
    await pump(tester);
    expect(find.text('1 of 3 today · edit plan'), findsOneWidget);
    final buttons = tester
        .widgetList<BreathingPlayButton>(find.byType(BreathingPlayButton))
        .map((b) => b.state)
        .toList();
    expect(buttons, [
      BreathingRowState.done,
      BreathingRowState.next,
      BreathingRowState.later,
    ]);
    expect(find.text('Morning · 5 min'), findsOneWidget);
    expect(find.text('Steady · 5 in, 5 out'), findsOneWidget);
    expect(find.text('Box · 4, 4, 4, 4'), findsOneWidget);
    expect(find.text('Long exhale · 4 in, 6 out'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });

  testWidgets('times are set as 8:30 over am', (tester) async {
    await pump(tester);
    final morning = clockParts(
      defaultBreathingPlan().item(BreathingItemKind.morning)!.minuteOfDay!,
    );
    expect(find.text(morning.time), findsOneWidget);
    expect(find.text('2:00'), findsOneWidget);
    expect(find.text('pm'), findsNWidgets(2));
  });

  testWidgets('a disabled item is hidden and the count follows', (
    tester,
  ) async {
    harness.planFor = (s) => defaultBreathingPlan(
      settings: s.copyWith(off: {BreathingItemKind.midday}),
    );
    await pump(tester);
    expect(find.textContaining('Midday'), findsNothing);
    expect(find.text('0 of 2 today · edit plan'), findsOneWidget);
    expect(find.byType(BreathingPlayButton), findsNWidgets(2));
  });

  testWidgets('the on-demand item is never a row', (tester) async {
    await pump(tester);
    expect(find.textContaining('If you wake'), findsNothing);
  });

  testWidgets('everything off says so and keeps edit plan', (tester) async {
    harness.planFor = (s) => defaultBreathingPlan(
      settings: s.copyWith(
        off: {
          BreathingItemKind.morning,
          BreathingItemKind.midday,
          BreathingItemKind.night,
        },
      ),
    );
    await pump(tester);
    expect(find.text('0 of 0 today · edit plan'), findsOneWidget);
    expect(find.textContaining('switched off'), findsOneWidget);
  });

  testWidgets('edit plan opens the plan', (tester) async {
    await pump(tester);
    await tester.tap(find.text('0 of 3 today · edit plan'));
    await tester.pumpAndSettle();
    expect(harness.visited.single, Routes.breathingPlan);
  });

  testWidgets('a play button opens that item', (tester) async {
    await pump(tester);
    await tester.tap(find.bySemanticsLabel('Start Midday'));
    // The player's sphere never stops turning, so settle is not an option.
    await tester.pump(const Duration(milliseconds: 500));
    expect(harness.visited.single, '${Routes.breathingPlayer}?item=midday');
  });

  testWidgets('the owner done set is not read from the strap', (tester) async {
    // With nothing done the card claims nothing: no check anywhere.
    await pump(tester);
    expect(find.byIcon(Icons.check_rounded), findsNothing);
  });

  for (final scale in <double>[1, 1.3]) {
    testWidgets('nothing overflows at text $scale', (tester) async {
      harness.done = {BreathingItemKind.morning};
      await pump(tester, textScale: scale);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a plan that cannot load shows the failure and a retry', (
    tester,
  ) async {
    var fail = true;
    harness.planFor = (s) {
      if (fail) throw StateError('store down');
      return defaultBreathingPlan(settings: s);
    };
    await pump(tester);
    expect(find.text("Couldn't load your plan."), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('0 of 3 today · edit plan'), findsOneWidget);
    expect(const BreathingSettings().off, isEmpty);
  });
}
