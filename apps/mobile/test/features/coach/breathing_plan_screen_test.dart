/// The Breathing plan screen: an intro made of the plan's own values, the
/// items with their switches, and the patterns with their evidence.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/routes.dart';
import 'package:healthee/data/basics/breathing/breathing_pattern.dart';
import 'package:healthee/data/basics/breathing/breathing_plan.dart';
import 'package:healthee/data/basics/breathing/breathing_settings.dart';
import 'package:healthee/data/basics/breathing/breathing_settings_provider.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/coach/breathing_plan_screen.dart';
import 'package:healthee/features/coach/v02/breathing_intro.dart';

import '_breathing_fakes.dart';

/// Finds a rich text by its plain words.
Finder rich(String text) => find.byWidgetPredicate(
  (w) => w is RichText && w.text.toPlainText() == text,
);

Finder button(String tooltip) =>
    find.byWidgetPredicate((w) => w is IconButton && w.tooltip == tooltip);

/// Lets real I/O (the memory database) finish, then the frames after it.
Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 80)),
  );
  await tester.pumpAndSettle();
}

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
    Brightness brightness = Brightness.light,
  }) async {
    tester.view
      ..physicalSize = const Size(390 * 3, 12000)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      harness.app(
        const BreathingPlanScreen(),
        textScale: textScale,
        brightness: brightness,
      ),
    );
    await tester.pumpAndSettle();
  }

  ProviderContainer container(WidgetTester tester) => ProviderScope.containerOf(
    tester.element(find.byType(BreathingPlanScreen)),
  );

  group('the intro', () {
    test('is built from nights used, the stress day and the plan total', () {
      String plain(BreathingPlan p) =>
          breathingIntro(p).map((s) => s.text).join();
      expect(
        plain(defaultBreathingPlan()),
        "Built from your last 14 nights and yesterday's stress. "
        '19 minutes a day at three set times, plus one for bad nights.',
      );
      expect(
        plain(defaultBreathingPlan(stress: false)),
        'Built from your last 14 nights. 19 minutes a day at three set times.',
      );
      expect(
        plain(defaultBreathingPlan(nights: 1, stress: false)),
        startsWith('Built from your last night. '),
      );
      expect(
        plain(defaultBreathingPlan(nights: 0, stress: false)),
        startsWith('Not enough nights yet, so the times are defaults.'),
      );
    });

    test('the minutes follow the switches and are the only bold run', () {
      final plan = defaultBreathingPlan(
        settings: const BreathingSettings(off: {BreathingItemKind.midday}),
      );
      final bold = breathingIntro(plan).where((s) => s.bold).toList();
      expect(bold.single.text, '15 minutes a day');
    });

    test('a stress peak days back is named as such, not as yesterday', () {
      final plan = BreathingPlan(
        defaultBreathingPlan().items,
        nightsUsed: 14,
        stressDaysAgo: 3,
      );
      expect(
        breathingIntro(plan).first.text,
        'Built from your last 14 nights and stress from 3 days ago. ',
      );
    });

    testWidgets('shows on screen with the minutes bold', (tester) async {
      await pump(tester);
      expect(
        rich(
          "Built from your last 14 nights and yesterday's stress. "
          '19 minutes a day at three set times, plus one for bad nights.',
        ),
        findsOneWidget,
      );
      expect(find.text('Breathing plan'), findsOneWidget);
      expect(find.text('Coach'), findsOneWidget);
    });
  });

  group('the items', () {
    testWidgets('four rows with their time, pattern and reason', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('Morning'), findsOneWidget);
      expect(find.text('Midday'), findsOneWidget);
      expect(find.text('Night'), findsOneWidget);
      expect(find.text('If you wake'), findsOneWidget);
      expect(find.text('2:00 pm · 4 min'), findsOneWidget);
      expect(find.text('10:15 pm · 10 min'), findsOneWidget);
      expect(find.text('On demand · 5 min'), findsOneWidget);
      expect(find.text('Steady · 5 in, 5 out'), findsOneWidget);
      expect(find.text('Box · 4, 4, 4, 4'), findsOneWidget);
      expect(find.byType(Switch), findsNWidgets(4));
    });

    testWidgets('the owner numbers in a reason are bold, the rest is not', (
      tester,
    ) async {
      await pump(tester);
      final plan = defaultBreathingPlan();
      final reason = plan.item(BreathingItemKind.morning)!.reasonParts;
      final bold = reason.where((s) => s.bold).map((s) => s.text).toList();
      expect(bold, hasLength(2));
      expect(bold.last, '43.9');
      final text = tester.widget<RichText>(
        rich(plan.item(BreathingItemKind.morning)!.reason),
      );
      final spans = (text.text as TextSpan).children!.cast<TextSpan>();
      for (final span in spans) {
        final isBold = span.style?.fontWeight == FontWeight.w700;
        expect(isBold, bold.contains(span.text), reason: span.text);
      }
      expect(find.textContaining('Stress hit'), findsOneWidget);
    });

    testWidgets('a switch saves, schedules and redraws', (tester) async {
      await pump(tester);
      await tester.tap(find.byType(Switch).at(1));
      await settle(tester);
      expect(harness.notifications.synced, hasLength(1));
      final plan = harness.notifications.synced.single;
      expect(plan.item(BreathingItemKind.midday)!.enabled, isFalse);
      expect(plan.item(BreathingItemKind.morning)!.enabled, isTrue);
      expect(tester.widget<Switch>(find.byType(Switch).at(1)).value, isFalse);
      expect(find.textContaining('15 minutes a day'), findsOneWidget);
      final saved = await container(
        tester,
      ).read(breathingSettingsControllerProvider.future);
      expect(saved.off, {BreathingItemKind.midday});
    });

    testWidgets('no on-demand item: four rows become three and no extras', (
      tester,
    ) async {
      harness.planFor = (s) => defaultBreathingPlan(stress: false, settings: s);
      await pump(tester);
      expect(find.text('If you wake'), findsNothing);
      expect(find.byType(Switch), findsNWidgets(3));
      expect(find.text('Accept all 3'), findsOneWidget);
      expect(find.textContaining('bad nights'), findsNothing);
      expect(find.textContaining('stress.'), findsNothing);
    });

    testWidgets('leaving the screen right after a toggle still syncs', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.byType(Switch).at(1));
      // Pop the plan before the save and the schedule have finished.
      await tester.pumpWidget(harness.app(const SizedBox()));
      await tester.pump();
      await settle(tester);
      expect(harness.notifications.synced, hasLength(1));
    });

    testWidgets('accept all turns everything on and schedules once', (
      tester,
    ) async {
      harness.planFor = (s) => defaultBreathingPlan(
        settings: s.copyWith(off: {BreathingItemKind.midday}),
      );
      await pump(tester);
      await tester.tap(find.text('Accept all 4'));
      await settle(tester);
      final saved = await container(
        tester,
      ).read(breathingSettingsControllerProvider.future);
      expect(saved.off, isEmpty);
      expect(saved.acceptedAt, isNotNull);
      expect(harness.notifications.synced, hasLength(1));
      expect(find.text(kBreathingAcceptNote), findsOneWidget);
    });

    testWidgets('tapping the night time opens the free from picker', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.text('10:15 pm · 10 min'));
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(harness.notifications.synced, isEmpty);
    });
  });

  group('the patterns', () {
    testWidgets('only Steady and Long exhale cite the note', (tester) async {
      await pump(tester);
      expect(
        find.text('Established · $kSlowBreathingNoteId'),
        findsNWidgets(2),
      );
      expect(find.text('Not in our base'), findsNWidgets(2));
      expect(find.text(kBreathingFootnote), findsOneWidget);
      for (final p in kBreathPresets) {
        expect(find.text(p.blurb), findsOneWidget);
        expect(find.text(p.dotted), findsOneWidget);
      }
      expect(find.text('4·7·8'), findsOneWidget);
    });

    testWidgets('a preset starts an ad hoc session with it', (tester) async {
      await pump(tester);
      await tester.tap(find.text(kBox.blurb));
      await tester.pump(const Duration(milliseconds: 500));
      expect(harness.visited.single, '${Routes.breathingPlayer}?pattern=box');
    });

    testWidgets('the custom editor stops at the limits and saves', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.bySemanticsLabel('Set a custom pattern'));
      await tester.pumpAndSettle();
      expect(find.text('Custom pattern'), findsOneWidget);
      final less = button('Less Breathe in');
      for (var i = 0; i < 3; i++) {
        await tester.tap(less);
        await tester.pump();
      }
      expect(tester.widget<IconButton>(less).onPressed, isNull);
      final lessHold = button('Less Hold');
      expect(tester.widget<IconButton>(lessHold).onPressed, isNull);
      final more = button('More Breathe out');
      for (var i = 0; i < 8; i++) {
        await tester.tap(more);
        await tester.pump();
      }
      expect(tester.widget<IconButton>(more).onPressed, isNull);
      await tester.tap(find.text('Save'));
      await settle(tester);
      final saved = await container(
        tester,
      ).read(breathingSettingsControllerProvider.future);
      expect(saved.custom, isNotNull);
      expect(saved.custom!.inSeconds, 1);
      expect(saved.custom!.outSeconds, 12);
      expect(find.text('1·12'), findsOneWidget);
      expect(find.text('Not in our base'), findsNWidgets(3));
    });
  });

  testWidgets('a plan that cannot load shows the failure', (tester) async {
    harness.planFor = (s) => throw StateError('store down');
    await pump(tester);
    expect(find.text("Couldn't load your plan."), findsOneWidget);
    expect(find.text('Patterns'), findsOneWidget);
  });

  for (final brightness in Brightness.values) {
    testWidgets('nothing overflows at text 1.3, $brightness', (tester) async {
      await pump(tester, textScale: 1.3, brightness: brightness);
      expect(tester.takeException(), isNull);
    });
  }
}
