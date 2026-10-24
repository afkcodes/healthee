/// Today's v02 charts PAINT, at the size they were really laid out to.
///
/// Two charts have already shipped at zero height in this repo because a test
/// only checked that the widget existed. `find.byType(V02Sparkline)` passes for
/// a chart inside a `SizedBox(height: 0)`, for a chart with an empty series, and
/// for a chart whose painter returned on its first line. So every assertion here
/// reads the **recorded canvas**: the chart is laid out on the real screen, its
/// painter is replayed at the size the layout gave it, and what it actually drew
/// is counted.
///
/// `test/shared/_chart_probe.dart` owns the recording helpers; `_v02_chart_probe`
/// owns the widget-level ones. This file is about the charts **as Today lays
/// them out**, which is the half neither of those can see.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/today/v02/mini_trend_panel.dart';
import 'package:healthee/shared/charts/h_stacked_sleep.dart';
import 'package:healthee/shared/charts/v02/v02_bar_chart.dart';
import 'package:healthee/shared/charts/v02/v02_bucket_chart.dart';
import 'package:healthee/shared/charts/v02/v02_linked_chart.dart';
import 'package:healthee/shared/charts/v02/v02_sparkline.dart';
import 'package:healthee/shared/v02/instruments/vo2max_rail.dart';

import '../_today_stubs.dart';
import '../shared/_chart_probe.dart';
import '../shared/_v02_chart_probe.dart';
import '_today_host.dart';

/// Replays a painter that IS the finder, rather than one inside it.
///
/// `paintedBy` and `paintedAt` both look for a `CustomPaint` **descending from**
/// what they are given. `Vo2maxRail` publishes a key on the
/// `CustomPaint` itself, so the descendant search finds nothing — this replays
/// the one that was found, at the size the layout gave it.
List<RecordedInvocation> replayKeyed(WidgetTester tester, Finder paint) {
  final widget = tester.widget<CustomPaint>(paint);
  final canvas = TestRecordingCanvas();
  widget.painter!.paint(canvas, tester.getSize(paint));
  return canvas.invocations;
}

void main() {
  late LocalStore store;

  setUp(() async {
    store = LocalStore.memory();
    await seedDevice(store);
  });
  tearDown(() async => store.close());

  Future<void> openToday(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(420, 14000)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(todayHost(store));
    await tester.pumpAndSettle();
  }

  group('the twin-panel sparklines', () {
    testWidgets('A SPARKLINE IS 30 px TALL AND DRAWS A PATH', (tester) async {
      await openToday(tester);
      final chart = find.byType(V02Sparkline).first;
      await reveal(tester, chart);

      expect(tester.getSize(chart).height, MiniTrendPanel.sparklineHeight);
      // Body + trace. A chart that drew one of the two lost half its ink.
      expect(countOf(paintedAt(tester, chart), #drawPath), greaterThan(0));
    });

    testWidgets('A SHORT SERIES DRAWS NOTHING AND KEEPS ITS SLOT', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(420, 14000)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        todayHost(
          store,
          server: todayView(
            mutate: (json) => <String, Object?>{
              ...json,
              'sparklines': <String, Object?>{
                ...json['sparklines']! as Map<String, Object?>,
                // One night is not a trend, and a line through one point is a
                // claim about a history that was never measured.
                'hrv_sleep_avg': const <Object?>[],
              },
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final chart = find.byType(V02Sparkline).first;
      await reveal(tester, chart);

      // The slot is the same 30 px, which is what stops the pair wobbling when
      // one half has no trend...
      expect(tester.getSize(chart).height, MiniTrendPanel.sparklineHeight);
      // ...and nothing is drawn in it. `V02Sparkline` returns a `ChartVoid`
      // rather than a flat line at the one value it has, because a line through
      // one point is a claim about a history that was never measured.
      expect(
        find.descendant(of: chart, matching: find.byType(CustomPaint)),
        findsNothing,
      );
    });
  });

  group('the full-width charts', () {
    testWidgets('THE LINKED CHART DRAWS BOTH PANES, AT REAL HEIGHT', (
      tester,
    ) async {
      await openToday(tester);
      final chart = find.byType(V02LinkedChart);
      await reveal(tester, chart);

      expect(paintSize(tester, chart).height, greaterThan(0));
      final painted = paintedAt(tester, chart);
      // Two traces plus their two bodies, at least. A single-pane "linked"
      // chart is a comparison the reader cannot make.
      expect(countOf(painted, #drawPath), greaterThanOrEqualTo(2));
    });

    testWidgets('THE STEP BUCKETS ARE COLUMNS WITH HEIGHT', (tester) async {
      await openToday(tester);
      final chart = find.byType(V02BucketChart);
      await reveal(tester, chart);

      expect(paintSize(tester, chart).height, greaterThan(0));
      final columns = rectsOf(paintedAt(tester, chart));
      expect(columns, isNotEmpty);
      expect(
        columns.where((rect) => rect.height > 0),
        isNotEmpty,
        reason: 'a bucket chart of zero-height columns is an empty axis',
      );
    });

    testWidgets('THE LOAD BARS ARE DRAWN AT THEIR LAID-OUT SIZE', (
      tester,
    ) async {
      await openToday(tester);
      final chart = find.byType(V02BarChart);
      await reveal(tester, chart);

      expect(paintSize(tester, chart).height, greaterThan(0));
      expect(
        rectsOf(paintedAt(tester, chart)).where((rect) => rect.height > 0),
        isNotEmpty,
      );
    });

    testWidgets('the seven-night stack fills its 108 px and draws seven bars', (
      tester,
    ) async {
      await openToday(tester);
      await reveal(tester, find.byType(HStackedSleep));

      final chart = find.byType(HStackedSleep);
      expect(tester.getSize(chart).height, 108);
      final painted = paintedBy(tester, chart);
      // Four stage segments a night, seven nights.
      expect(countOf(painted, #drawRect), 7 * 4);
      expect(
        rectsOf(painted).where((rect) => rect.height > 0),
        isNotEmpty,
        reason: 'a stacked bar of zero-height segments is an empty axis',
      );
    });
  });

  group('the hero instruments', () {
    testWidgets('THE VO2MAX RAIL PAINTS AT ITS LAID-OUT SIZE', (tester) async {
      await openToday(tester);
      final rail = find.byKey(Vo2maxRail.plotKey);
      await reveal(tester, rail);

      expect(tester.getSize(rail).height, greaterThan(0));
      expect(replayKeyed(tester, rail), isNotEmpty);
    });
  });

  group('reveal-once', () {
    testWidgets('A CHART DOES NOT REPLAY WHEN IT SCROLLS BACK', (tester) async {
      // The registry belongs to the screen's `State`, so a chart rebuilt by
      // `ListView.builder` starts finished. The observable is the painted
      // geometry at the first frame after the scroll: a replaying chart would be
      // part-drawn.
      await openToday(tester);
      await reveal(tester, find.byType(HStackedSleep));
      final before = rectsOf(paintedBy(tester, find.byType(HStackedSleep)));

      await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
      await tester.pump();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
      // ONE frame, deliberately: a chart that restarted its reveal would be at
      // progress 0 here and every bar would have zero height.
      await tester.pump();

      final after = rectsOf(paintedBy(tester, find.byType(HStackedSleep)));
      expect(after, hasLength(before.length));
      for (var i = 0; i < before.length; i++) {
        expect(
          after[i].height,
          moreOrLessEquals(before[i].height, epsilon: 0.01),
          reason: 'bar $i re-animated on scroll-back',
        );
      }
    });
  });
}
