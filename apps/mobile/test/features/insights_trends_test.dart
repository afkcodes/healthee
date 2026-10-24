/// Where `fav`/`unf` may appear on Insights, and — the part that matters —
/// where they may not.
///
/// The owner asked for improving and degrading to be visible in colour. It is a
/// good ask and it does not apply uniformly, so the screen splits it:
///
/// ```text
///   a pattern chip, polarity known    coloured      the metric moved against the owner's own past
///   a pattern chip, polarity neutral  NO COLOUR     burning more calories is not better
///   a pattern chip, metric unknown    NO COLOUR     unknown is unknown, never a default verdict
///   a finding, any state              SIGN-BLIND    a correlation's sign is a direction, not a verdict
/// ```
///
/// **The colourless cases are what this file is really about.** A screen that
/// tinted everything would teach the owner that colour here is decoration, and
/// then the two rows where it is a claim would say nothing — so the neutral case
/// is mutation-tested rather than merely asserted, and the finding case is
/// enumerated over every kind of finding the payload can carry.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/data/models/finding.dart';
import 'package:healthee/data/models/trend_point.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/insights/insights_screen.dart';
import 'package:healthee/features/insights/insights_sections.dart';
import 'package:healthee/features/insights/widgets/pattern_tile.dart';
import 'package:healthee/features/insights/widgets/trends_section.dart';
import 'package:healthee/shared/findings_section.dart';
import 'package:healthee/shared/format/metric_polarity.dart';

import '../_today_stubs.dart';
import '_today_host.dart';

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

void main() {
  late LocalStore store;

  setUp(() async {
    store = LocalStore.memory();
    await seedDevice(store);
  });
  tearDown(() async => store.close());

  group('the polarity table', () {
    test('legacy\'s six polarities, ported verbatim', () {
      expect(polarityOf('hrv_sleep_avg'), MetricPolarity.higherIsBetter);
      expect(polarityOf('rhr_daily'), MetricPolarity.lowerIsBetter);
      expect(
        polarityOf('sleep_regularity_index'),
        MetricPolarity.higherIsBetter,
      );
      expect(polarityOf('sleep_score'), MetricPolarity.higherIsBetter);
      expect(
        polarityOf('sleep_health_score_4dim'),
        MetricPolarity.higherIsBetter,
      );
      expect(polarityOf('total_calories'), MetricPolarity.neutral);
    });

    test('an unknown metric has NO polarity, and null is not neutral', () {
      // Two different facts: one is a gap somebody should close, the other is a
      // decision. They agree on the answer and must not be conflated in the code.
      expect(polarityOf('vo2max_estimate'), isNull);
      expect(polarityOf('total_calories'), isNot(isNull));
    });

    test('a +1 metric is favourable UP and unfavourable DOWN', () {
      expect(verdictFor('hrv_sleep_avg', 3.2), TrendVerdict.favourable);
      expect(verdictFor('hrv_sleep_avg', -3.2), TrendVerdict.unfavourable);
    });

    test('a -1 metric is the reverse', () {
      // Resting heart rate falling is the good news, and this is the assertion
      // that a sign-only implementation would get exactly backwards.
      expect(verdictFor('rhr_daily', -4), TrendVerdict.favourable);
      expect(verdictFor('rhr_daily', 4), TrendVerdict.unfavourable);
    });

    test('a NEUTRAL metric has no verdict in either direction', () {
      expect(verdictFor('total_calories', 400), TrendVerdict.none);
      expect(verdictFor('total_calories', -400), TrendVerdict.none);
    });

    test('an unknown metric has no verdict in either direction', () {
      expect(verdictFor('weight_kg', 2), TrendVerdict.none);
      expect(verdictFor('weight_kg', -2), TrendVerdict.none);
    });

    test('a window that did not move is not an improvement', () {
      expect(verdictFor('hrv_sleep_avg', 0), TrendVerdict.none);
    });

    test('one point is a reading, not a trend', () {
      expect(MetricTrend.from('hrv_sleep_avg', const []), isNull);
      expect(
        MetricTrend.from('hrv_sleep_avg', [
          const TrendPoint(date: '2026-08-01', value: 47),
        ]),
        isNull,
      );
    });
  });

  group('NO FINDING TURNS ITS SIGN INTO A VERDICT', () {
    // Enumerated over every kind of finding the payload can carry, and over both
    // signs of the coefficient, because the sign is exactly what a well-meaning
    // change would reach for. `q`-corrected or not, 105 days of one person's
    // history cannot support "this is good for you".
    //
    // ## Why this is no longer "spends no fav and no unf"
    //
    // It was, until 2026-08-05. Legacy is now the design specification, and
    // legacy's `cHrv` and `cReady` ARE its green — the same value as `fav`. So a
    // finding about HRV legitimately paints its metric's hue in the colour that
    // also means "improving", and "no fav anywhere" became unassertable without
    // failing the port for being faithful (`palette.dart` has the decision).
    //
    // What replaced it is stronger, not weaker: **flip the sign and nothing may
    // change colour.** A row that encoded a verdict would have to differ, and no
    // amount of hue-sharing can hide that. It is also mutation-proof in a way the
    // old assertion was not — the old one passed for a row that was simply grey.
    final kinds = <String, Map<String, Object?>>{
      'a pairwise correlation': <String, Object?>{
        'kind': 'pairwise_lag',
        'metric_a': 'hrv_sleep_avg',
        'metric_b': 'recovery_score',
        'effect_metric': 'spearman_r',
        'q_value': 0.0001,
        'n_samples': 105,
        'lag_days': 0,
      },
      'a lagged correlation': <String, Object?>{
        'kind': 'pairwise_lag',
        'metric_a': 'caffeine',
        'metric_b': 'sleep_health_score_4dim',
        'effect_metric': 'rho',
        'q_value': 0.03,
        'n_samples': 24,
        'lag_days': 0,
      },
      'an event finding': <String, Object?>{
        'kind': 'event_contrast',
        'metric_a': 'rhr_daily',
        'event_kind': 'alcohol',
        'n_samples': 30,
      },
    };

    Future<Set<Color>> colours(WidgetTester tester, Finding finding) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: FindingsSection(findings: <Finding>[finding])),
        ),
      );
      await tester.pumpAndSettle();
      return _textColours(tester, find.byType(FindingsSection));
    }

    for (final entry in kinds.entries) {
      testWidgets('${entry.key} reads the same in both directions', (
        tester,
      ) async {
        final positive = await colours(
          tester,
          Finding.fromJson(<String, Object?>{
            ...entry.value,
            'effect_size': 0.51,
          }),
        );
        final negative = await colours(
          tester,
          Finding.fromJson(<String, Object?>{
            ...entry.value,
            'effect_size': -0.51,
          }),
        );
        expect(
          positive,
          isNotEmpty,
          reason: '${entry.key} drew no text at all',
        );
        expect(
          negative,
          equals(positive),
          reason:
              '${entry.key}: the sign of a coefficient is a direction, not a '
              'verdict, and nothing on the row may change colour with it',
        );
      });
    }

    testWidgets('a finding with no effect size at all still draws', (
      tester,
    ) async {
      final drawn = await colours(
        tester,
        Finding.fromJson(const <String, Object?>{
          'kind': 'pairwise_lag',
          'metric_a': 'steps_total',
          'metric_b': 'sleep_score',
          'n_samples': 40,
        }),
      );
      expect(drawn, isNotEmpty);
    });
  });

  group('the screen', () {
    testWidgets('draws a trend for each tracked metric the payload carries', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(420, 6000)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(todayHost(store, home: const InsightsScreen()));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Longer patterns'));

      // The prototype's own heading for this block, and one panel per metric
      // the payload carried a window for.
      expect(find.text('Longer patterns'), findsOneWidget);
      for (final spec in kPatternSpecs) {
        expect(find.text(spec.label), findsOneWidget, reason: spec.metric);
      }
      expect(find.text('your usual range'), findsOneWidget);
      expect(find.text('outside, worse'), findsOneWidget);
      expect(find.text('better'), findsOneWidget);
    });

    test('the screen reads ONE list, not a second copy of the table', () {
      // A metric the screen drew that the table cannot judge would be a
      // colourless row nobody chose, and the mismatch would be invisible.
      for (final metric in kTrendMetrics) {
        expect(
          polarityOf(metric),
          isNotNull,
          reason: '$metric is offered as a trend with no polarity behind it',
        );
      }
      for (final spec in kPatternSpecs) {
        expect(
          kTrendMetrics,
          contains(spec.metric),
          reason: '${spec.metric} has a tile and no place in the one list',
        );
      }
    });

    testWidgets('no trend windows at all is an honest empty state', (
      tester,
    ) async {
      await tester.pumpWidget(
        todayHost(
          store,
          home: const InsightsScreen(),
          server: todayView(
            mutate: (Map<String, Object?> json) {
              final stripped = Map<String, Object?>.from(json);
              stripped['sparklines'] = const <String, Object?>{};
              return stripped;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // No windows draws NOTHING — not an empty-state card under a heading.
      // A heading over nothing reads as breakage; `insights_sections.dart`
      // drops the heading with the panels, which is v02's rule for every
      // block on every redesigned screen.
      expect(find.text('Longer patterns'), findsNothing);
      expect(find.byType(PatternTile), findsNothing);
    });

    test('trendsOf drops a metric with fewer than two points', () {
      final trends = trendsOf(<String, List<TrendPoint>>{
        'hrv_sleep_avg': [const TrendPoint(date: '2026-08-01', value: 47)],
        'rhr_daily': _series(55, -2),
        // Tracked elsewhere, and not one of the six tiles.
        'sleep_score': _series(70, 2),
      });

      expect(trends.map((trend) => trend.metric), <String>['rhr_daily']);
    });
  });
}
