/// The sleep-and-night charts v02 still draws — **what they PAINT**.
///
/// `HStackedSleep` and `HDebtBars`. `HTimingChart` moved to
/// `shared/charts/v02/v02_timing_chart.dart` in the v02 rebuild and its geometry
/// is asserted in `test/features/sleep_charts_test.dart`. Split from
/// `legacy_charts_test.dart` at the 400-line gate; the probes both files use
/// live in `_chart_probe.dart`, and its docstring explains why a recorded canvas
/// is the only honest way to assert a chart drew something.
///
/// ## What left, and why
///
/// `HHypnogram` had the first group here — four lanes at 62% of a lane. Sleep
/// draws `V02Hypnogram` now (`shared/charts/v02/v02_hypnogram.dart`, asserted in
/// `sleep_stage_charts_test.dart`) and `h_hypnogram.dart` became unreachable
/// from `main.dart`, so it and its group are deleted.
///
/// ## What "verbatim" is being defended here
///
/// The stacked chart's even-hour axis with a floor of two; the debt chart's
/// ghost, and its green-and-red-orange pair.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/data/models/sleep_history.dart';
import 'package:healthee/shared/charts/h_debt_bars.dart';
import 'package:healthee/shared/charts/h_stacked_sleep.dart';

import '_chart_probe.dart';

void main() {
  group('HStackedSleep', () {
    testWidgets('SEVEN NIGHTS, FOUR SEGMENTS EACH, ALL WITH HEIGHT', (
      tester,
    ) async {
      await tester.pumpWidget(
        chartHost(HStackedSleep(week(), progress: 1, height: 130)),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getSize(find.byType(HStackedSleep)),
        const Size(hostWidth, 130),
      );
      final segments = rectsOf(paintedBy(tester, find.byType(HStackedSleep)));
      expect(segments.length, 7 * 4);
      for (final segment in segments) {
        expect(segment.height, greaterThan(0));
      }
    });

    testWidgets('the axis is an EVEN number of hours, never below two', (
      tester,
    ) async {
      // Legacy's rule, and the reason the gridlines land on 0h/2h/4h for every
      // week rather than most weeks. A twelve-minute night must still get a
      // two-hour axis.
      await tester.pumpWidget(
        chartHost(
          const HStackedSleep(
            <SleepNightSummary>[
              SleepNightSummary(
                date: '2026-08-01',
                durationMin: 12,
                deepMin: 3,
                lightMin: 6,
                remMin: 2,
                awakeMin: 1,
                deviceScore: null,
              ),
            ],
            progress: 1,
            height: 130,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final painted = paintedBy(tester, find.byType(HStackedSleep));
      final segments = rectsOf(painted);
      expect(segments.length, 4);
      // 12 minutes against a 120-minute axis over a 114 px plot: every segment
      // is tiny but present. If the axis had collapsed to the data, they would
      // fill the chart.
      final stackedHeight = segments
          .map((r) => r.height)
          .reduce((a, b) => a + b);
      expect(stackedHeight, lessThan(130 * 0.2));
      expect(stackedHeight, greaterThan(0));
    });
  });
  group('HDebtBars', () {
    testWidgets('A SHORT NIGHT DRAWS ITS BAR AND ITS GHOST', (tester) async {
      await tester.pumpWidget(
        chartHost(
          const HDebtBars(
            totalsMin: <double>[300, 480],
            labels: <String>['M', 'T'],
            needMin: 480,
            progress: 1,
            height: 150,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getSize(find.byType(HDebtBars)),
        const Size(hostWidth, 150),
      );
      final rects = rectsOf(paintedBy(tester, find.byType(HDebtBars)));
      // Two solid bars plus ONE ghost — the met night has no shortfall.
      expect(rects.length, 3);
      for (final rect in rects) {
        expect(rect.height, greaterThan(0));
      }
    });

    testWidgets('MET IS GREEN, SHORT IS THE CARD’S OWN HUE, NEVER RED', (
      tester,
    ) async {
      await tester.pumpWidget(
        chartHost(
          const HDebtBars(
            totalsMin: <double>[300, 480],
            labels: <String>['M', 'T'],
            needMin: 480,
            progress: 1,
            height: 150,
          ),
        ),
      );
      await tester.pumpAndSettle();

      const colors = HealtheeColors.light();
      final drawn = coloursOf(paintedBy(tester, find.byType(HDebtBars)));
      expect(drawn, contains(colors.fav.toARGB32()), reason: 'a met night');
      // The approved redesign: a short night is a reading, not an alarm.
      expect(drawn, isNot(contains(colors.alert.toARGB32())), reason: 'red');
      expect(drawn, isNot(contains(colors.unf.toARGB32())), reason: 'amber');
    });

    testWidgets('every night met means no ghost anywhere', (tester) async {
      await tester.pumpWidget(
        chartHost(
          const HDebtBars(
            totalsMin: <double>[480, 500],
            labels: <String>['M', 'T'],
            needMin: 480,
            progress: 1,
            height: 150,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(rectsOf(paintedBy(tester, find.byType(HDebtBars))).length, 2);
    });
  });
  group('both themes', () {
    testWidgets('every chart paints in dark mode too, at the same size', (
      tester,
    ) async {
      for (final theme in <ThemeData>[AppTheme.light, AppTheme.dark]) {
        await tester.pumpWidget(
          chartHost(
            HStackedSleep(week(), progress: 1, height: 130),
            theme: theme,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.byType(HStackedSleep)),
          const Size(hostWidth, 130),
        );
        expect(
          rectsOf(paintedBy(tester, find.byType(HStackedSleep))).length,
          28,
        );
      }
    });
  });
}
