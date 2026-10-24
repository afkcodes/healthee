/// The Longer-patterns tiles: where the better and worse colours may appear on
/// Insights, and where they may not.
///
/// ```text
///   a pattern chip, polarity known    coloured      the metric moved against the owner's own past
///   a pattern chip, polarity neutral  NO COLOUR     burning more calories is not better
///   a pattern chip, metric unknown    NO TILE       unknown is unknown, never a default verdict
///   the newest dot                    judged        the latest reading against the usual range
/// ```
///
/// **The colourless cases are what this file is really about.** A screen that
/// tinted everything would teach the owner that colour here is decoration, and
/// then the chips where it is a claim would say nothing, so the neutral case is
/// asserted in both directions.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/core/theme/instrument_hues.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/data/models/trend_point.dart';
import 'package:healthee/features/insights/widgets/pattern_tile.dart';
import 'package:healthee/features/insights/widgets/trends_section.dart';
import 'package:healthee/shared/charts/v02/signal_spark.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:healthee/shared/v02/reading_chip.dart';
import 'package:healthee/shared/v02/reading_state.dart' show ReadingState;

/// A fourteen-day series that ends [delta] away from where it began.
List<TrendPoint> _series(double from, double delta, {double? last}) =>
    <TrendPoint>[
      for (var i = 0; i < 14; i++)
        TrendPoint(
          date: '2026-08-${(i + 1).toString().padLeft(2, '0')}',
          value: i == 13 && last != null
              ? last
              : from + delta * (i < 5 ? 0 : (i > 8 ? 1 : 0.5)),
        ),
    ];

MetricTrend _trend(String metric, double delta, {double? last}) =>
    MetricTrend.from(metric, _series(50, delta, last: last))!;

/// Every colour the widget under [finder] actually paints text in.
Set<Color> _textColours(WidgetTester tester, Finder finder) {
  return tester
      .widgetList<Text>(
        find.descendant(of: finder, matching: find.byType(Text)),
      )
      .map((text) => text.style?.color)
      .whereType<Color>()
      .toSet();
}

Widget _tile(MetricTrend trend, {ThemeData? theme}) => MaterialApp(
  theme: theme ?? AppTheme.light,
  home: Scaffold(
    body: SizedBox(
      width: 180,
      child: PatternTile(trend: trend, reveals: RevealRegistry()),
    ),
  ),
);

/// The state the tile's chip draws in.
ReadingState _chipState(WidgetTester tester) =>
    tester.widget<ReadingChip>(find.byType(ReadingChip)).state;

/// The verdict colours, read from the same theme the widget is rendered in.
({Color fav, Color unf, Color alert}) _verdicts() {
  final colors = AppTheme.light.extension<HealtheeColors>()!;
  return (fav: colors.fav, unf: colors.unf, alert: colors.alert);
}

void main() {
  group('a pattern chip spends colour only where it has a claim', () {
    testWidgets('HRV UP is the better colour, HRV DOWN the worse', (
      tester,
    ) async {
      await tester.pumpWidget(_tile(_trend('hrv_sleep_avg', 4)));
      await tester.pumpAndSettle();
      expect(_chipState(tester), ReadingState.better);
      expect(_textColours(tester, find.byType(ReadingChip)), {_verdicts().fav});

      await tester.pumpWidget(_tile(_trend('hrv_sleep_avg', -4)));
      await tester.pumpAndSettle();
      expect(_chipState(tester), ReadingState.worse);
      expect(_textColours(tester, find.byType(ReadingChip)), {
        _verdicts().alert,
      });
    });

    testWidgets('RESTING HR UP is the worse colour, DOWN the better', (
      tester,
    ) async {
      // Resting heart rate falling is the good news, and this is the assertion
      // that a sign-only implementation would get exactly backwards.
      await tester.pumpWidget(_tile(_trend('rhr_daily', 4)));
      await tester.pumpAndSettle();
      expect(_chipState(tester), ReadingState.worse);
      expect(_textColours(tester, find.byType(ReadingChip)), {
        _verdicts().alert,
      });

      await tester.pumpWidget(_tile(_trend('rhr_daily', -4)));
      await tester.pumpAndSettle();
      expect(_chipState(tester), ReadingState.better);
      expect(_textColours(tester, find.byType(ReadingChip)), {_verdicts().fav});
    });

    testWidgets('MUTATION: A POLARITY-0 METRIC RENDERS NO VERDICT COLOUR', (
      tester,
    ) async {
      // The load-bearing case. Calories are in the table at `neutral` on
      // purpose: burning more is not better and burning less is not worse.
      // Colouring this chip would teach the owner that every colour on the
      // screen is a judgement, after which the ones that are stop meaning
      // anything. Asserted in BOTH directions, because a sign-only
      // implementation passes one of them by accident.
      for (final delta in <double>[400, -400]) {
        await tester.pumpWidget(_tile(_trend('total_calories', delta)));
        await tester.pumpAndSettle();

        expect(
          _chipState(tester),
          ReadingState.usual,
          reason: 'a $delta kcal change is not a verdict',
        );
        final drawn = _textColours(tester, find.byType(PatternTile));
        expect(drawn, isNot(contains(_verdicts().fav)));
        expect(drawn, isNot(contains(_verdicts().alert)));
        expect(drawn, isNot(contains(_verdicts().unf)));
      }
    });

    testWidgets('a metric ABSENT from the table has no tile at all', (
      tester,
    ) async {
      // Unknown is unknown. A tile for it would need a label, a unit and a
      // polarity somebody never chose.
      await tester.pumpWidget(_tile(_trend('weight_kg', 3)));
      await tester.pumpAndSettle();

      expect(find.byType(ReadingChip), findsNothing);
      expect(patternSpecOf('weight_kg'), isNull);
    });

    testWidgets('a window that did not move says so, in the neutral state', (
      tester,
    ) async {
      await tester.pumpWidget(_tile(_trend('hrv_sleep_avg', 0)));
      await tester.pumpAndSettle();

      expect(find.text('No change over 14d'), findsOneWidget);
      expect(_chipState(tester), ReadingState.usual);
    });
  });

  group('the tile\'s sparkline', () {
    testWidgets('is laid out at PatternTile.sparkHeight, never collapsed', (
      tester,
    ) async {
      // Two charts have shipped at zero height in this repo because a test only
      // asked whether the widget existed.
      await tester.pumpWidget(_tile(_trend('hrv_sleep_avg', 4)));
      await tester.pumpAndSettle();

      expect(PatternTile.sparkHeight, greaterThan(0));
      expect(
        tester.getSize(find.byType(SignalSpark)).height,
        PatternTile.sparkHeight,
      );
    });
  });

  group('the newest dot judges the latest reading against the usual range', () {
    test('HRV well above its band is better; resting HR above it is worse', () {
      expect(
        dotStateOf(_trend('hrv_sleep_avg', 0, last: 80)),
        ReadingState.better,
      );
      expect(dotStateOf(_trend('rhr_daily', 0, last: 80)), ReadingState.worse);
      expect(
        dotStateOf(_trend('hrv_sleep_avg', 0, last: 20)),
        ReadingState.worse,
      );
    });

    test(
      'inside the band it is usual, and a neutral metric is never judged',
      () {
        expect(
          dotStateOf(_trend('hrv_sleep_avg', 0, last: 50)),
          ReadingState.usual,
        );
        expect(
          dotStateOf(_trend('total_calories', 0, last: 5000)),
          ReadingState.usual,
        );
      },
    );
  });

  group('the tile’s words', () {
    testWidgets('label in its domain colour, the window, mean and unit', (
      tester,
    ) async {
      await tester.pumpWidget(_tile(_trend('hrv_sleep_avg', 3)));
      await tester.pumpAndSettle();
      final hues = AppTheme.light.extension<InstrumentHues>()!;

      final label = tester.widget<Text>(find.text('Overnight HRV'));
      expect(label.style?.color, hues.heart);
      expect(find.text('14d avg'), findsOneWidget);
      expect(find.textContaining('ms', findRichText: true), findsOneWidget);
      expect(find.text('↑ 3.0 over 14d'), findsOneWidget);
    });

    testWidgets('each tile takes its own domain colour', (tester) async {
      final hues = AppTheme.light.extension<InstrumentHues>()!;
      final expected = <String, Color>{
        'sleep_regularity_index': hues.sleep,
        'steps_total': hues.movement,
        'total_calories': hues.movement,
        'rhr_daily': hues.heart,
      };
      for (final entry in expected.entries) {
        await tester.pumpWidget(_tile(_trend(entry.key, 1)));
        await tester.pumpAndSettle();
        final label = tester.widget<Text>(
          find.text(patternSpecOf(entry.key)!.label),
        );
        expect(label.style?.color, entry.value, reason: entry.key);
      }
    });

    test('mean, change and unit read as the kit prints them', () {
      final steps = _trend('steps_total', 363);
      expect(changeLabel(steps, 0), '↑ 363 over 14d');
      expect(changeLabel(_trend('steps_total', -363), 0), '↓ 363 over 14d');
      expect(patternSpecOf('sleep_health_score_4dim')!.unit, '/ 4');
    });
  });
}
