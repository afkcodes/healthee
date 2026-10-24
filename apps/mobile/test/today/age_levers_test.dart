import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/data/models/bio_age_block.dart';
import 'package:healthee/features/today/v02/age_lever_row.dart';
import 'package:healthee/features/today/v02/age_levers.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:healthee/shared/v02/instruments/zone_bar.dart';

import '../_bio_age_stubs.dart';
import '../_today_stubs.dart';

BioAgeBlock snapshotBlock() =>
    BioAgeBlock.fromJson(loadTodayJson()['biological_age']);

BioAgeBlock withheldBlock() => BioAgeBlock.fromJson(
  withheldBioAge(absentTerms: <Map<String, Object?>>[staleWeightTerm()]),
);

Widget host(Widget child, {double width = 390}) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(
    body: SingleChildScrollView(
      child: SizedBox(width: width, child: child),
    ),
  ),
);

ZoneBarGeometry geometryIn(WidgetTester tester, Finder row) {
  final paint = tester.widget<CustomPaint>(
    find.descendant(of: row, matching: find.byKey(ZoneBar.plotKey)),
  );
  return (paint.painter! as ZoneBarPainter).geometry;
}

Finder rowOf(String term) => find.byKey(leverRowKey(term));

void main() {
  testWidgets('rows follow the payload: counted, withheld, excluded', (
    tester,
  ) async {
    final block = BioAgeBlock.fromJson(<String, Object?>{
      ...withheldBioAge(absentTerms: <Map<String, Object?>>[staleWeightTerm()]),
    });
    await tester.pumpWidget(
      host(AgeLeverCard(block: block, reveals: RevealRegistry())),
    );
    final order = <String>[
      for (final key in <String>['sleep duration', 'fitness', 'regularity'])
        key,
    ];
    final tops = <double>[
      for (final term in order) tester.getTopLeft(rowOf(term)).dy,
    ];
    expect(tops, orderedEquals(<double>[...tops]..sort()));
  });

  testWidgets('one surface card, no card inside it', (tester) async {
    await tester.pumpWidget(
      host(AgeLeverCard(block: snapshotBlock(), reveals: RevealRegistry())),
    );
    final surfaces = find.byWidgetPredicate(
      (w) => w is DecoratedBox && w.decoration is ShapeDecoration,
    );
    expect(surfaces, findsOneWidget);
    expect(find.byType(Card), findsNothing);
  });

  testWidgets('the fitness row: value, target, caption, no 7-day', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(AgeLeverCard(block: snapshotBlock(), reveals: RevealRegistry())),
    );
    await tester.pump(const Duration(seconds: 1));
    final row = rowOf('fitness');
    final g = geometryIn(tester, row);
    expect(g.valuePainter.plainText, '43.0 mL/kg/min');
    expect(g.targetPainter!.plainText, '40 median for your age group');
    expect(
      find.descendant(of: row, matching: find.text('FITNESS · VO₂MAX')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.text('From a recorded session')),
      findsOneWidget,
    );
    expect(find.textContaining('7-day'), findsNothing);
    expect(
      find.descendant(of: row, matching: find.text('years')),
      findsOneWidget,
    );
  });

  testWidgets('the sleep row reads the compared-as value, with its caption', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(AgeLeverCard(block: snapshotBlock(), reveals: RevealRegistry())),
    );
    await tester.pump(const Duration(seconds: 1));
    final row = rowOf('sleep duration');
    final g = geometryIn(tester, row);
    expect(g.valuePainter.plainText, '7.0 h');
    expect(g.targetPainter!.plainText, 'low point 7 h');
    expect(
      find.descendant(
        of: row,
        matching: find.text(
          'Measured 6.3 h a night, counted as 7.0 h on the '
          'study’s self-report scale · average over the last 14 days',
        ),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('7 to 9'), findsNothing);
  });

  testWidgets('a withheld term shows the server message and Not counted', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(AgeLeverCard(block: withheldBlock(), reveals: RevealRegistry())),
    );
    final row = rowOf('fitness');
    expect(
      find.descendant(of: row, matching: find.text(kStaleWeightMessage)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.text('Not counted')),
      findsOneWidget,
    );
  });

  testWidgets('a term that was not counted never looks like a computed 0.0', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(AgeLeverCard(block: withheldBlock(), reveals: RevealRegistry())),
    );
    for (final term in <String>['fitness', 'regularity']) {
      final row = rowOf(term);
      expect(
        find.descendant(of: row, matching: find.byType(ZoneBar)),
        findsNothing,
        reason: '$term is drawn as a bar',
      );
      expect(
        find.descendant(of: row, matching: find.textContaining('0.0')),
        findsNothing,
      );
      expect(
        find.descendant(of: row, matching: find.text('years')),
        findsNothing,
      );
    }
    // The sleep term WAS computed and came to nothing: that one is a real 0.0.
    expect(
      find.descendant(
        of: rowOf('sleep duration'),
        matching: find.text('years'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('an excluded term shows its first sentence and Left out', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(AgeLeverCard(block: snapshotBlock(), reveals: RevealRegistry())),
    );
    final row = rowOf('regularity');
    expect(
      find.descendant(
        of: row,
        matching: find.text(
          'Sleep regularity is not one of the levers behind this number.',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.text('Left out')),
      findsOneWidget,
    );
    expect(find.textContaining('70,000 people'), findsNothing);
  });

  test('firstSentence keeps text verbatim up to the first full stop', () {
    expect(firstSentence('One. Two. Three.'), 'One.');
    expect(firstSentence('No stop here'), 'No stop here');
  });

  testWidgets('tapping any row opens that term', (tester) async {
    final opened = <String>[];
    await tester.pumpWidget(
      host(
        AgeLeverCard(
          block: snapshotBlock(),
          reveals: RevealRegistry(),
          onOpenLever: opened.add,
        ),
      ),
    );
    await tester.tap(rowOf('fitness'));
    await tester.tap(rowOf('sleep duration'));
    await tester.tap(rowOf('regularity'));
    expect(opened, <String>['fitness', 'sleep duration', 'regularity']);
  });

  testWidgets('each row is one semantics node with the reading in words', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      host(AgeLeverCard(block: snapshotBlock(), reveals: RevealRegistry())),
    );
    expect(
      find.bySemanticsLabel(
        'Fitness VO2max 43.0 millilitres per kilo per minute, minus 1.7 years',
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('it does not overflow at text scale 1.3', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: AgeLeverCard(
                block: snapshotBlock(),
                reveals: RevealRegistry(),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
