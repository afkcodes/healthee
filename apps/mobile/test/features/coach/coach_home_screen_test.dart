import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/basics/breathing/breathing_plan.dart';
import 'package:healthee/data/challenges/health_program.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/coach/coach_home_screen.dart';

import '../_today_host.dart';
import '_coach_home_fakes.dart';

HealthProgram _plan({int? weeks, int settled = 0}) => HealthProgram(
  id: 3,
  title: 'The 4-week plan',
  why: 'Build up.',
  status: 'active',
  rungs: const [],
  settledRungs: settled,
  weeks: weeks,
);

void main() {
  late LocalStore store;
  setUp(() => store = LocalStore.memory());
  tearDown(() => store.close());

  Future<void> pump(
    WidgetTester tester,
    CoachHost host, {
    double width = 390,
    double scale = 1,
  }) async {
    tester.view
      ..physicalSize = Size(width * 3, 3600)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      todayHost(
        store,
        home: host.scope(
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: const CoachHomeScreen(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the eyebrow is the date alone with no program', (tester) async {
    final host = await CoachHost.create()
      ..today = '2026-08-04';
    await pump(tester, host);
    expect(find.text('Tue 4 Aug'), findsOneWidget);
    expect(find.text('Coach'), findsOneWidget);
    expect(host.reviews.calls, 0);
  });

  testWidgets('week N of M appears when a program supplies both', (
    tester,
  ) async {
    final host = await CoachHost.create()
      ..today = '2026-08-04'
      ..program = _plan(weeks: 4, settled: 1);
    await pump(tester, host);
    expect(find.text('Tue 4 Aug · week 2 of 4'), findsOneWidget);
  });

  testWidgets('a program with no week count gives the date alone', (
    tester,
  ) async {
    final host = await CoachHost.create()
      ..today = '2026-08-04'
      ..program = _plan();
    await pump(tester, host);
    expect(find.text('Tue 4 Aug'), findsOneWidget);
  });

  testWidgets("Today's basics sits between the job and the record", (
    tester,
  ) async {
    final host = await CoachHost.create()
      ..today = '2026-08-04'
      ..breathingDone = {BreathingItemKind.morning};
    await pump(tester, host);
    tester.view.physicalSize = const Size(390 * 3, 12000);
    await tester.pumpAndSettle();
    double top(Finder f) => tester.getTopLeft(f).dy;
    final job = top(find.text("This week's job"));
    final basics = top(find.text("Today's basics"));
    final record = top(find.text('Your record'));
    expect(job, lessThan(basics));
    expect(basics, lessThan(record));
    expect(find.text('Breathing'), findsOneWidget);
    expect(find.text('1 of 3 today · edit plan'), findsOneWidget);
  });

  for (final width in <double>[320, 360, 390, 414]) {
    testWidgets('nothing overflows at $width wide, text 1.3, review open', (
      tester,
    ) async {
      final host = await CoachHost.create()
        ..today = '2026-08-04';
      await pump(tester, host, width: width, scale: 1.3);
      await tester.tap(find.text('Weekly review'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Straight talk'), findsOneWidget);
    });
  }
}
