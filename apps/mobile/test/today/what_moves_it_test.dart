import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/core/theme/appearance_preferences.dart';
import 'package:healthee/core/what_moves_it_preference.dart';
import 'package:healthee/data/models/bio_age_block.dart';
import 'package:healthee/features/today/v02/age_lever_row.dart';
import 'package:healthee/features/today/v02/age_levers.dart';
import 'package:healthee/features/today/v02/what_moves_it.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:healthee/shared/v02/fold.dart';
import 'package:healthee/shared/v02/instruments/zone_bar.dart';

import '../_bio_age_stubs.dart';
import '../_today_stubs.dart';

BioAgeBlock _block() => BioAgeBlock.fromJson(loadTodayJson()['biological_age']);

Widget _host(
  ProviderContainer container, {
  bool openByDefault = false,
  bool reduceMotion = false,
  RevealRegistry? reveals,
  void Function(String)? onOpen,
}) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    theme: AppTheme.light,
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Scaffold(
        body: SingleChildScrollView(
          child: WhatMovesIt(
            block: _block(),
            reveals: reveals ?? RevealRegistry(),
            openByDefault: openByDefault,
            onOpenLever: onOpen,
          ),
        ),
      ),
    ),
  ),
);

const Duration _settle = Duration(seconds: 1);

Future<void> _tapHeader(WidgetTester tester) async {
  await tester.tap(find.byKey(WhatMovesIt.headerKey));
  await tester.pump();
  await tester.pump(_settle);
}

double _foldHeight(WidgetTester tester) =>
    tester.getSize(find.byType(Fold)).height;

void main() {
  testWidgets('it starts collapsed with every term named in the summary', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(_host(container));
    expect(find.text('What moves it'), findsOneWidget);
    expect(find.text('Each reading, turned into years'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(WhatMovesIt.summaryKey))
          .textSpan!
          .toPlainText(),
      'Fitness −1.7 · Sleep 0.0 · Regularity left out',
    );
    expect(_foldHeight(tester), 0);
    expect(find.byType(AgeLeverCard), findsNothing);
  });

  test('the breakdown span reads as the line and tightens the sign', () {
    const style = TextStyle(fontSize: 13);
    final span = ageBreakdownSpan(_block(), style);
    expect(span.toPlainText(), ageBreakdownLine(_block()));
    final signs = <TextSpan>[];
    span.visitChildren((child) {
      if (child is TextSpan && child.text == '\u2212') {
        signs.add(child);
      }
      return true;
    });
    expect(signs, isNotEmpty);
    for (final sign in signs) {
      expect(sign.style!.letterSpacing, closeTo(-0.14 * 13, 1e-9));
    }
  });

  test('the summary names withheld terms as not counted', () {
    final block = BioAgeBlock.fromJson(<String, Object?>{
      'withheld': <String, Object?>{
        'terms': <Object?>[staleWeightTerm()],
      },
      'contributions': const <Object?>[],
    });
    expect(whatMovesItSummary(block), 'Fitness not counted');
  });

  testWidgets('tap expands, shows both levers, tap collapses', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(_host(container));
    await _tapHeader(tester);
    expect(find.byKey(WhatMovesIt.summaryKey), findsNothing);
    expect(find.byKey(leverRowKey('fitness')), findsOneWidget);
    expect(find.byKey(leverRowKey('sleep duration')), findsOneWidget);
    expect(_foldHeight(tester), greaterThan(100));
    await _tapHeader(tester);
    expect(_foldHeight(tester), 0);
    expect(find.byKey(WhatMovesIt.summaryKey), findsOneWidget);
  });

  testWidgets('the choice persists across a new provider container', (
    tester,
  ) async {
    final first = ProviderContainer();
    await tester.pumpWidget(_host(first));
    await _tapHeader(tester);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(
      await tester.runAsync(
        () => first.read(appearancePreferencesProvider).read(kWhatMovesItKey),
      ),
      'true',
    );
    await tester.pumpWidget(const SizedBox());
    first.dispose();

    final next = ProviderContainer();
    addTearDown(next.dispose);
    next.read(whatMovesItOpenProvider);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(next.read(whatMovesItOpenProvider), isTrue);
    await tester.pumpWidget(_host(next));
    await tester.pump(_settle);
    expect(find.byKey(leverRowKey('fitness')), findsOneWidget);
    expect(_foldHeight(tester), greaterThan(100));
  });

  testWidgets('openByDefault starts open, and toggling still writes the pref', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(_host(container, openByDefault: true));
    await tester.pump(_settle);
    expect(find.byKey(leverRowKey('fitness')), findsOneWidget);
    expect(_foldHeight(tester), greaterThan(100));
    expect(container.read(whatMovesItOpenProvider), isFalse);
    await _tapHeader(tester);
    expect(_foldHeight(tester), 0);
    expect(container.read(whatMovesItOpenProvider), isFalse);
    await _tapHeader(tester);
    expect(container.read(whatMovesItOpenProvider), isTrue);
  });

  testWidgets('the header is a button whose label follows the state', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(_host(container));
    expect(find.bySemanticsLabel('What moves it, collapsed'), findsOneWidget);
    await _tapHeader(tester);
    expect(find.bySemanticsLabel('What moves it, expanded'), findsOneWidget);
    expect(find.bySemanticsLabel('What moves it, collapsed'), findsNothing);
    handle.dispose();
  });

  testWidgets('reduced motion is instant', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(_host(container, reduceMotion: true));
    await tester.tap(find.byKey(WhatMovesIt.headerKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(_foldHeight(tester), greaterThan(100));
    await tester.tap(find.byKey(WhatMovesIt.headerKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(_foldHeight(tester), 0);
  });

  testWidgets('animated expansion is not instant', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(_host(container));
    await tester.tap(find.byKey(WhatMovesIt.headerKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final mid = _foldHeight(tester);
    await tester.pump(_settle);
    expect(mid, greaterThan(0));
    expect(mid, lessThan(_foldHeight(tester)));
  });

  testWidgets('re-expanding does not replay the zone bar reveal', (
    tester,
  ) async {
    final reveals = RevealRegistry();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(_host(container, reveals: reveals));
    await _tapHeader(tester);
    expect(reveals.hasSeen('body.lever.fitness'), isTrue);
    await _tapHeader(tester);
    await tester.tap(find.byKey(WhatMovesIt.headerKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byKey(leverRowKey('fitness')),
        matching: find.byKey(ZoneBar.plotKey),
      ),
    );
    final g = (paint.painter! as ZoneBarPainter).geometry;
    expect(g.markerX, closeTo((43 - 20) / 40 * g.width, 1e-6));
  });

  testWidgets('a lever row tap reaches the caller', (tester) async {
    final opened = <String>[];
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(_host(container, onOpen: opened.add));
    await _tapHeader(tester);
    await tester.tap(find.byKey(leverRowKey('fitness')));
    expect(opened, <String>['fitness']);
  });
}
