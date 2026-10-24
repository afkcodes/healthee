/// `Your trends`: a period cut against the one before, and the screen's switch.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/data/history/history_repository.dart';
import 'package:healthee/data/models/trend_point.dart';
import 'package:healthee/data/store/store_provider.dart';
import 'package:healthee/features/trends/trends_period.dart';
import 'package:healthee/features/trends/trends_screen.dart';
import 'package:healthee/shared/v02/trend_card.dart';

import '../history/_history_host.dart' show kToday;

/// One reading a day for [days] days ending on [kToday], value = 50 + i % 5.
List<TrendPoint> _daily(int days, {Set<int> skip = const <int>{}}) {
  final end = DateTime.utc(2026, 8, 4);
  return <TrendPoint>[
    for (var i = days - 1; i >= 0; i--)
      if (!skip.contains(i))
        TrendPoint(
          date: end
              .subtract(Duration(days: i))
              .toIso8601String()
              .substring(0, 10),
          value: 50.0 + i % 5,
        ),
  ];
}

void main() {
  group('cutting a period', () {
    test('a week is seven days ending on the day, and a gap stays a gap', () {
      final cut = cutPeriod(
        _daily(14, skip: <int>{2}),
        kToday,
        TrendPeriod.week,
      );
      expect(cut.values, hasLength(7));
      expect(cut.values[4], isNull, reason: 'two days before the end');
      expect(cut.values.last, 50);
      expect(cut.earlier, hasLength(7));
      expect(cut.captions, <String>['29 Jul', '4 Aug']);
    });

    test('six months is one mean per week', () {
      final cut = cutPeriod(_daily(364), kToday, TrendPeriod.halfYear);
      expect(cut.values, hasLength(26));
      // Each week holds i % 5 over seven consecutive days: mean of a 7-run.
      expect(cut.values.every((v) => v != null && v > 50 && v < 54), isTrue);
      expect(cut.earlier, hasLength(26));
    });

    test('a week with no day in it is a gap, not a zero', () {
      final cut = cutPeriod(
        _daily(28, skip: <int>{0, 1, 2, 3, 4, 5, 6}),
        kToday,
        TrendPeriod.week,
      );
      expect(cut.values.every((v) => v == null), isTrue);
    });
  });

  testWidgets('the switch re-reads the period', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          todayProvider.overrideWithValue(kToday),
          for (final spec in kTrendSpecs)
            for (final period in TrendPeriod.values)
              metricHistoryProvider(
                spec.metric,
                period.fetchDays,
              ).overrideWith((ref) async => _daily(period.fetchDays)),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const TrendsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TrendCard), findsWidgets);
    expect(find.text('average over 7 days'), findsWidgets);

    await tester.tap(find.text('6 months'));
    await tester.pumpAndSettle();
    expect(find.text('average over 26 weeks'), findsWidgets);
  });
}
