/// What moved together, and the Effort and stress card.
///
/// The correlation rows spend two colours, and neither is a verdict: positive
/// is Strain blue, negative is Activity orange. Pairs with too few days draw a
/// grey chip and no bar. The Effort and stress figures are computed from the
/// hourly series and nothing else, and its chart draws what the spec says:
/// a dashed resting reference on the heart-rate lane and columns for stress.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/core/theme/instrument_hues.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/data/models/finding.dart';
import 'package:healthee/data/models/today_series.dart';
import 'package:healthee/features/insights/v02/effort_stress_card.dart';
import 'package:healthee/features/insights/v02/effort_stress_stats.dart';
import 'package:healthee/features/insights/v02/moved_together.dart';
import 'package:healthee/shared/charts/v02/diverging_bar.dart';
import 'package:healthee/shared/charts/v02/v02_linked_chart.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:healthee/shared/v02/reading_chip.dart';
import 'package:healthee/shared/v02/reading_state.dart';

import '../shared/_chart_probe.dart';
import '_citation_probe.dart';

Finding _f({
  String a = 'rhr_daily',
  String? b = 'recovery_score',
  String? event,
  required double r,
  int? n = 67,
  int lag = 0,
}) => Finding(
  kind: b == null ? 'event_contrast' : 'pairwise_lag',
  metricA: a,
  metricB: b,
  eventKind: event,
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
    body: SingleChildScrollView(
      child: SizedBox(
        width: 390,
        child: Padding(padding: const EdgeInsets.all(20), child: child),
      ),
    ),
  ),
);

HealtheeColors get _colors => AppTheme.light.extension<HealtheeColors>()!;

InstrumentHues get _hues => AppTheme.light.extension<InstrumentHues>()!;

/// The colour the signed figure [plain] is painted in.
Color? _figureColour(WidgetTester tester, String plain) {
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    final span = text.textSpan;
    if (span is TextSpan && span.toPlainText() == plain) {
      return span.style?.color;
    }
  }
  return null;
}

final List<Finding> _rows = <Finding>[
  _f(r: -0.88),
  _f(a: 'hrv_sleep_avg', r: 0.82, n: 36),
  _f(a: 'sleep_regularity_index', b: 'vo2max_estimate', r: 0.64, n: 47, lag: 1),
  _f(a: 'sleep_regularity_index', b: 'sleep_debt_min', r: -0.57, n: 54),
  _f(a: 'alcohol', b: 'sleep_score', r: 0.9, n: 1),
];

void main() {
  group('what moved together', () {
    testWidgets('positive is Strain blue, negative Activity orange', (
      tester,
    ) async {
      await tester.pumpWidget(_host(MovedTogetherCard(findings: _rows)));

      expect(_figureColour(tester, '−0.88'), _hues.movement);
      expect(_figureColour(tester, '−0.57'), _hues.movement);
      expect(_figureColour(tester, '+0.82'), _hues.strain);
      expect(_figureColour(tester, '+0.64'), _hues.strain);
    });

    testWidgets('no row takes a verdict colour for its sign', (tester) async {
      await tester.pumpWidget(_host(MovedTogetherCard(findings: _rows)));

      final used = <Color?>{
        for (final text in tester.widgetList<Text>(find.byType(Text)))
          text.style?.color,
        for (final text in tester.widgetList<Text>(find.byType(Text)))
          if (text.textSpan is TextSpan)
            (text.textSpan! as TextSpan).style?.color,
      };
      expect(used, isNot(contains(_colors.fav)));
      expect(used, isNot(contains(_colors.alert)));
      expect(used, isNot(contains(_colors.unf)));
    });

    testWidgets('one bar per drawn row, each at its own r', (tester) async {
      await tester.pumpWidget(_host(MovedTogetherCard(findings: _rows)));

      final bars = tester
          .widgetList<DivergingBar>(find.byType(DivergingBar))
          .map((b) => b.r)
          .toList();
      expect(bars, <double>[-0.88, 0.82, 0.64, -0.57]);
    });

    testWidgets('the caption carries direction and strength, then the days', (
      tester,
    ) async {
      await tester.pumpWidget(_host(MovedTogetherCard(findings: _rows)));

      expect(find.text('Move opposite · very strong'), findsOneWidget);
      expect(find.text('Move together · very strong'), findsOneWidget);
      expect(find.text('Move together · strong'), findsOneWidget);
      expect(find.text('Move opposite · moderate'), findsOneWidget);
      expect(find.text('67 days'), findsOneWidget);
      expect(find.text('36 nights'), findsOneWidget);
    });

    testWidgets('names carry the direction glyph and the lag', (tester) async {
      await tester.pumpWidget(_host(MovedTogetherCard(findings: _rows)));

      expect(find.text('Resting HR ↑↓ Recovery'), findsOneWidget);
      expect(find.text('HRV ↑↑ Recovery'), findsOneWidget);
      expect(find.text('Sleep regularity ↑↑ VO₂max next day'), findsOneWidget);
    });

    testWidgets('a pair with one entry is a grey chip and NO BAR', (
      tester,
    ) async {
      await tester.pumpWidget(_host(MovedTogetherCard(findings: _rows)));

      final chip = find.byType(ReadingChip);
      expect(chip, findsOneWidget);
      expect(find.text('1 entry · too few'), findsOneWidget);
      expect(tester.widget<ReadingChip>(chip).state, ReadingState.noData);
      final decoration = tester.widget<DecoratedBox>(
        find.descendant(of: chip, matching: find.byType(DecoratedBox)),
      );
      expect(
        (decoration.decoration as ShapeDecoration).color,
        _colors.surface2,
      );
      // The too-few row is the last, and its r is not printed at all.
      expect(_figureColour(tester, '+0.90'), isNull);
      final row = find.ancestor(
        of: chip,
        matching: find.byType(MovedTogetherRow),
      );
      expect(
        find.descendant(of: row, matching: find.byType(DivergingBar)),
        findsNothing,
      );
    });

    testWidgets('an event finding is named and counted, never put on r', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          MovedTogetherCard(
            findings: <Finding>[
              _f(a: 'rhr_daily', b: null, event: 'alcohol', r: 0.9, n: 30),
            ],
          ),
        ),
      );

      expect(find.text('Resting HR ↔ Alcohol'), findsOneWidget);
      expect(find.byType(DivergingBar), findsNothing);
      expect(find.text('Compared across 30 days'), findsOneWidget);
    });

    testWidgets('the footnote keeps the single-subject framing on the face', (
      tester,
    ) async {
      await tester.pumpWidget(_host(MovedTogetherCard(findings: _rows)));

      expect(
        find.text('Observed in your history, not cause and effect.'),
        findsOneWidget,
      );
    });

    testWidgets('each row keeps its ⓘ, so the arithmetic is one tap away', (
      tester,
    ) async {
      await tester.pumpWidget(_host(MovedTogetherCard(findings: _rows)));

      expect(find.byType(MovedTogetherRow), findsNWidgets(5));
      expect(dotIn(find.byType(MovedTogetherCard)), findsNWidgets(5));
      // And it opens the statistic, not a source the finding does not have.
      await tester.tap(dotIn(find.byType(MovedTogetherCard)).first);
      await tester.pumpAndSettle();
      expect(find.textContaining('rho = -0.88'), findsOneWidget);
      expect(
        find.textContaining('not that either one caused the other'),
        findsOneWidget,
      );
    });

    testWidgets('no findings draws nothing at all', (tester) async {
      await tester.pumpWidget(_host(const MovedTogetherCard(findings: [])));

      expect(find.byType(MovedTogetherRow), findsNothing);
      expect(find.text(kObservedFootnote), findsNothing);
    });
  });

  group('the Effort and stress figures', () {
    const hr = <HourPoint>[
      HourPoint(hour: 0, average: 60, minimum: 55, maximum: 70, count: 10),
      HourPoint(hour: 1, average: 80, minimum: 60, maximum: 90, count: 10),
      HourPoint(hour: 2, average: 70, minimum: null, maximum: null, count: 10),
    ];
    const stress = <HourPoint>[
      HourPoint(hour: 0, average: 10, minimum: null, maximum: null, count: 4),
      HourPoint(hour: 1, average: 33, minimum: null, maximum: null, count: 4),
      HourPoint(hour: 2, average: 20, minimum: null, maximum: null, count: 4),
    ];

    test('the range is the lowest low to the highest high', () {
      expect(EffortStressStats(hr, stress).heartRangeLabel, '55–90');
    });

    test('peak is the highest hour and the average is the mean of hours', () {
      final stats = EffortStressStats(hr, stress);
      expect(stats.peakStress, 33);
      expect(stats.averageStress, closeTo(21, 1e-9));
    });

    test('no samples is no figure, never zero', () {
      final stats = EffortStressStats(const <HourPoint>[], const <HourPoint>[]);
      expect(stats.heartRangeLabel, isNull);
      expect(stats.peakStress, isNull);
      expect(stats.averageStress, isNull);
    });

    test('the window runs from the first hour to the sync that ended it', () {
      expect(
        syncedWindow(hr, lastSync: DateTime(2026, 10, 18, 2, 41)),
        '00:00 to 02:41',
      );
    });

    test('a sync outside the last hour is not claimed as its end', () {
      expect(
        syncedWindow(hr, lastSync: DateTime(2026, 10, 18, 9, 3)),
        '00:00 to 02:00',
      );
      expect(syncedWindow(hr), '00:00 to 02:00');
      expect(syncedWindow(const <HourPoint>[]), isEmpty);
    });
  });

  group('the Effort and stress chart', () {
    HourPoint hour(int h, double v) =>
        HourPoint(hour: h, average: v, minimum: null, maximum: null, count: 1);

    testWidgets(
      'heart rate is a line with a dashed reference, stress columns',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: SingleChildScrollView(
                child: EffortStressCard(
                  heartRate: <HourPoint>[
                    for (var h = 0; h < 8; h++) hour(h, 60.0 + h * 4),
                  ],
                  stress: <HourPoint>[
                    for (var h = 0; h < 8; h++) hour(h, 10.0 + h * 3),
                  ],
                  reveals: RevealRegistry(),
                  restingHr: 57,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final calls = paintedBy(tester, find.byType(V02LinkedChart));
        expect(
          countOf(calls, #drawRRect),
          greaterThanOrEqualTo(8),
          reason: 'one column per stress hour',
        );
        expect(
          countOf(calls, #drawPath),
          greaterThan(0),
          reason: 'the HR line',
        );
        // The reference is a run of short dashes, so many more lines than the
        // gridlines alone.
        expect(countOf(calls, #drawLine), greaterThan(12));
        expect(find.text('Heart rate'), findsOneWidget);
        expect(find.text('Peak-hour stress'), findsOneWidget);
        expect(find.text('Avg stress'), findsOneWidget);
      },
    );
  });
}
