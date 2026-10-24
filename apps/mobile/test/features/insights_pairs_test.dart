/// The wording of a pairwise finding, and the two hero tiles it feeds.
///
/// Pure functions first (the wording and the strength bands are the claim, so
/// they are asserted without a widget), then the tiles: their content, their
/// colour, and the honest empty state each falls back to.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/core/theme/instrument_hues.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/data/models/biological_age.dart';
import 'package:healthee/data/models/finding.dart';
import 'package:healthee/features/insights/v02/pair_reading.dart';
import 'package:healthee/features/insights/v02/pattern_panels.dart';
import 'package:healthee/shared/charts/v02/diverging_bar.dart';
import 'package:healthee/shared/charts/v02/hatch.dart';
import 'package:healthee/shared/v02/reading_state.dart';

Finding _pair({
  String a = 'rhr_daily',
  String b = 'recovery_score',
  double r = -0.88,
  int? n = 67,
  int lag = 0,
}) => Finding(
  kind: 'pairwise_lag',
  metricA: a,
  metricB: b,
  eventKind: null,
  description: null,
  effectSize: r,
  effectMetric: 'rho',
  qValue: 0.001,
  nSamples: n,
  lagDays: lag,
  researchNoteIds: const <String>[],
);

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(
    body: SizedBox(
      width: 390,
      child: Padding(padding: const EdgeInsets.all(20), child: child),
    ),
  ),
);

HealtheeColors get _colors => AppTheme.light.extension<HealtheeColors>()!;

InstrumentHues get _hues => AppTheme.light.extension<InstrumentHues>()!;

/// The colour of the first span that starts [plain], found among every `Text`.
Color? _spanColour(WidgetTester tester, String plain) {
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    final span = text.textSpan;
    if (span != null && span.toPlainText().startsWith(plain)) {
      return (span as TextSpan).children
          ?.whereType<TextSpan>()
          .first
          .style
          ?.color;
    }
  }
  return null;
}

void main() {
  group('the strength words', () {
    test('very strong from 0.8, strong from 0.6, moderate from 0.4', () {
      expect(strengthWord(-0.88), 'very strong');
      expect(strengthWord(0.8), 'very strong');
      expect(strengthWord(0.79), 'strong');
      expect(strengthWord(0.64), 'strong');
      expect(strengthWord(0.6), 'strong');
      expect(strengthWord(-0.57), 'moderate');
      expect(strengthWord(0.4), 'moderate');
      expect(strengthWord(0.39), 'weak');
    });

    test('the old bands keep both of their edges', () {
      // `findings_section.dart` says "closely" from 0.6 and "moderately" from
      // 0.4; the new words must not move either edge.
      expect(strengthWord(0.6), isNot('moderate'));
      expect(strengthWord(0.4), isNot('weak'));
    });

    test('the sign is a direction, in words and glyphs', () {
      expect(directionCaption(-0.88), 'Move opposite · very strong');
      expect(directionCaption(0.82), 'Move together · very strong');
      expect(directionGlyphs(-0.5), '↑↓');
      expect(directionGlyphs(0.5), '↑↑');
    });

    test('the sign is a real minus, two decimals, a plus on a positive', () {
      expect(signedR(-0.88), '−0.88');
      expect(signedR(0.82), '+0.82');
      expect(signedR(0.001), '0.00');
      expect(signedR(-0.004), '0.00');
    });
  });

  group('which finding is the strongest, and which are too few', () {
    test('the largest magnitude wins, whatever its sign', () {
      final strongest = strongestPair(<Finding>[
        _pair(r: 0.5),
        _pair(a: 'hrv_sleep_avg', r: -0.91),
        _pair(a: 'steps_total', r: 0.7),
      ]);
      expect(strongest!.metricA, 'hrv_sleep_avg');
    });

    test('a pair with too few days is never the strongest', () {
      expect(strongestPair(<Finding>[_pair(r: 0.99, n: 1)]), isNull);
      expect(isTooFew(_pair(n: 4)), isTrue);
      expect(isTooFew(_pair(n: 5)), isFalse);
    });

    test('an unknown count is not "few", and an event finding is no pair', () {
      expect(isTooFew(_pair(n: null)), isFalse);
      const event = Finding(
        kind: 'event_contrast',
        metricA: 'rhr_daily',
        metricB: null,
        eventKind: 'alcohol',
        description: null,
        effectSize: 0.9,
        effectMetric: 'd',
        qValue: null,
        nSamples: 30,
        lagDays: null,
        researchNoteIds: <String>[],
      );
      expect(isPair(event), isFalse);
      expect(strongestPair(<Finding>[event]), isNull);
    });

    test('the sentence is the direction in plain words, with the days', () {
      expect(pairSentence(_pair()), 'Lower RHR, higher recovery · 67 days');
      expect(
        pairSentence(_pair(a: 'hrv_sleep_avg', r: 0.82, n: 36)),
        'Higher HRV, higher recovery · 36 nights',
      );
      expect(pairSentence(_pair(n: null)), 'Lower RHR, higher recovery');
    });

    test('a lag is said as a lag', () {
      expect(laggedName(_pair(lag: 1)), 'Recovery next day');
      expect(laggedName(_pair(lag: 3)), 'Recovery 3 days later');
      expect(laggedName(_pair()), 'Recovery');
    });
  });

  group('the pattern hero tile', () {
    testWidgets('a pair draws its figure, its bar and its sentence', (
      tester,
    ) async {
      await tester.pumpWidget(_host(PatternHeroTile(finding: _pair())));

      expect(find.text('−0.88', findRichText: true), findsOneWidget);
      expect(find.text('Lower RHR, higher recovery · 67 days'), findsOneWidget);
      expect(find.text('Resting HR ↔ Recovery', findRichText: true), findsOne);
      expect(tester.widget<DivergingBar>(find.byType(DivergingBar)).r, -0.88);
    });

    testWidgets('each name is in its own domain colour, the arrow in ink2', (
      tester,
    ) async {
      await tester.pumpWidget(_host(PatternHeroTile(finding: _pair())));

      final label = tester
          .widgetList<Text>(find.byType(Text))
          .firstWhere(
            (t) => t.textSpan?.toPlainText() == 'Resting HR ↔ Recovery',
          );
      final spans = (label.textSpan! as TextSpan).children!
          .cast<TextSpan>()
          .toList();
      expect(spans.first.style?.color, _hues.heart);
      expect(spans.last.style?.color, isNot(_hues.heart));
    });

    testWidgets('with no pair it says so: hatched bar, no number', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const PatternHeroTile(finding: null)));

      expect(find.text('Not enough readings yet'), findsOneWidget);
      expect(find.byType(HatchStrip), findsOneWidget);
      expect(find.byType(DivergingBar), findsNothing);
      expect(find.textContaining('0.'), findsNothing);
    });
  });

  group('the fitness → age hero tile', () {
    BiologicalAge ageWith(double years) =>
        BiologicalAge.maybe(<String, Object?>{
          'biological_age': 40.0,
          'chronological_age': 35.0,
          'delta_years': years,
          'contributions': <Object?>[
            <String, Object?>{
              'term': 'fitness',
              'delta_years': years,
              'value': 33.3,
              'target': 46.5,
              'unit': 'mL/kg/min',
            },
          ],
        })!;

    Future<ReadingState> stateFor(WidgetTester tester, double years) async {
      await tester.pumpWidget(
        _host(AgeHeroTile(age: FitnessAge.from(ageWith(years)))),
      );
      return tester.widget<DivergingBar>(find.byType(DivergingBar)).state!;
    }

    testWidgets('older is alert, younger is fav, about the same is ink', (
      tester,
    ) async {
      expect(await stateFor(tester, 6.8), ReadingState.worse);
      expect(_spanColour(tester, '+6.8'), _colors.alert);

      expect(await stateFor(tester, -1.7), ReadingState.better);
      expect(_spanColour(tester, '−1.7'), _colors.fav);

      expect(await stateFor(tester, 0.2), ReadingState.usual);
      expect(_spanColour(tester, '+0.2'), _colors.ink);
    });

    testWidgets('it prints the years, the unit and the VO₂max against median', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(AgeHeroTile(age: FitnessAge.from(ageWith(6.8)))),
      );

      expect(find.text('+6.8 yrs', findRichText: true), findsOneWidget);
      expect(find.text('Fitness → age'), findsOneWidget);
      expect(find.text('VO₂max 33.3 vs 46.5 median'), findsOneWidget);
    });

    testWidgets('with no fitness lever it says so, and draws no number', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const AgeHeroTile(age: null)));

      expect(find.text('Not enough readings yet'), findsOneWidget);
      expect(find.byType(HatchStrip), findsOneWidget);
      expect(find.byType(DivergingBar), findsNothing);
    });

    test('a payload with no fitness term, or no years, is no lever', () {
      expect(FitnessAge.from(null), isNull);
      expect(
        FitnessAge.from(
          BiologicalAge.maybe(<String, Object?>{
            'biological_age': 40.0,
            'chronological_age': 35.0,
            'delta_years': 0.0,
            'contributions': <Object?>[
              <String, Object?>{'term': 'fitness', 'value': 33.3},
            ],
          }),
        ),
        isNull,
        reason: 'a lever with no years would be a number nobody computed',
      );
    });
  });
}
