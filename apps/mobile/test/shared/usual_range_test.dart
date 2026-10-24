/// The one definition of "your usual": the middle half of the 14 days before.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/data/models/trend_point.dart';
import 'package:healthee/shared/usual_range.dart';
import 'package:healthee/shared/v02/range_bar.dart';

import '_chart_probe.dart';

List<TrendPoint> _days(String lastDay, List<double> values) {
  final end = DateTime.parse(lastDay);
  return <TrendPoint>[
    for (var i = 0; i < values.length; i++)
      TrendPoint(
        date: end
            .subtract(Duration(days: values.length - 1 - i))
            .toIso8601String()
            .substring(0, 10),
        value: values[i],
      ),
  ];
}

void main() {
  group('usualRangeOf', () {
    test('is the 25th to 75th percentile, linearly interpolated', () {
      // Sorted 1..8: positions 1.75 and 5.25 → 2.75 and 6.25.
      final range = usualRangeOf(<double>[8, 1, 7, 2, 6, 3, 5, 4])!;
      expect(range.low, closeTo(2.75, 1e-9));
      expect(range.high, closeTo(6.25, 1e-9));
      expect(range.days, 8);
    });

    test('fewer than seven readings make no band', () {
      expect(usualRangeOf(<double>[1, 2, 3, 4, 5, 6]), isNull);
      expect(usualRangeOf(<double>[1, 2, 3, 4, 5, 6, 7]), isNotNull);
    });

    test('a value that is not a number is not a reading', () {
      expect(usualRangeOf(<double>[1, 2, 3, 4, 5, 6, double.nan]), isNull);
    });

    test('one odd day does not stretch the band', () {
      final calm = usualRangeOf(<double>[50, 52, 54, 55, 56, 58, 60, 61])!;
      final spiked = usualRangeOf(<double>[50, 52, 54, 55, 56, 58, 60, 99])!;
      expect(spiked.high - calm.high, lessThan(1));
    });
  });

  group('sideOf', () {
    const range = UsualRange(low: 55, high: 72, days: 14);
    test('the edges are inside', () {
      expect(range.sideOf(55), UsualSide.within);
      expect(range.sideOf(72), UsualSide.within);
      expect(range.sideOf(54.9), UsualSide.below);
      expect(range.sideOf(72.1), UsualSide.above);
    });

    test('the verdicts read as the owner reads them', () {
      expect(UsualSide.below.words, 'Below your usual');
      expect(UsualSide.within.words, 'In your usual range');
      expect(UsualSide.above.words, 'Above your usual');
    });
  });

  group('windowBefore', () {
    test('takes the 14 days before the day and never the day itself', () {
      final points = _days('2026-10-11', <double>[
        for (var i = 1; i <= 20; i++) i.toDouble(),
      ]);
      final window = windowBefore(points, '2026-10-11').toList();
      // 20 is 2026-10-11 itself; 19 back to 6 are the 14 days before it.
      expect(window, <double>[for (var i = 6; i <= 19; i++) i.toDouble()]);
    });

    test('a missing day is absent, not zero', () {
      final points = _days('2026-10-10', <double>[5, 6, 7])..removeAt(1);
      expect(windowBefore(points, '2026-10-11'), <double>[5, 7]);
    });
  });

  group('RangeBar', () {
    Future<List<RecordedInvocation>> paint(
      WidgetTester tester, {
      required double value,
      UsualRange? band,
    }) async {
      await tester.pumpWidget(
        chartHost(
          RangeBar(
            value: value,
            min: 0,
            max: 100,
            band: band,
            startLabel: '0',
            endLabel: '100',
            usualLabel: 'usual 55 to 72',
            pendingLabel: 'learning your usual',
            semanticLabel: 'Recovery $value',
          ),
          theme: AppTheme.light,
        ),
      );
      // The bar's own painter, at the size the bar laid it out to.
      final bar = find.descendant(
        of: find.byType(RangeBar),
        matching: find.byType(CustomPaint),
      );
      final canvas = TestRecordingCanvas();
      tester
          .widget<CustomPaint>(bar.first)
          .painter!
          .paint(canvas, tester.getSize(bar.first));
      return canvas.invocations;
    }

    testWidgets('the band and the mark sit where the numbers say', (
      tester,
    ) async {
      final painted = await paint(
        tester,
        value: 51,
        band: const UsualRange(low: 55, high: 72, days: 14),
      );
      final shapes = rrectsOf(painted);
      // Track, band, the mark's ring and the mark.
      expect(shapes, hasLength(4));
      final width = shapes.first.width;
      final band = shapes[1];
      expect(band.left, moreOrLessEquals(width * 0.55, epsilon: 0.5));
      expect(band.right, moreOrLessEquals(width * 0.72, epsilon: 0.5));
      expect(
        shapes.last.center.dx,
        moreOrLessEquals(width * 0.51, epsilon: 0.5),
      );
      expect(find.text('usual 55 to 72'), findsOneWidget);
      expect(find.text('learning your usual'), findsNothing);
    });

    testWidgets('a reading past the end is held at the end', (tester) async {
      final shapes = rrectsOf(await paint(tester, value: 140));
      final width = shapes.first.width;
      expect(shapes.last.right, lessThanOrEqualTo(width + 0.01));
    });

    testWidgets('with no band it says it is learning, and draws no band', (
      tester,
    ) async {
      final shapes = rrectsOf(await paint(tester, value: 51));
      expect(shapes, hasLength(3));
      expect(find.text('learning your usual'), findsOneWidget);
      expect(find.text('usual 55 to 72'), findsNothing);
    });

    testWidgets('a screen reader hears one sentence', (tester) async {
      await paint(tester, value: 51);
      expect(find.bySemanticsLabel('Recovery 51.0'), findsOneWidget);
    });
  });
}
