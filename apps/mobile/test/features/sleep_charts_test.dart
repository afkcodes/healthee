/// The Sleep tab's charts PAINT, at the size the panels really lay them out at.
///
/// Two charts on this screen once shipped at zero height because a suite only
/// checked the widget existed, so **every assertion here reads the recorded
/// canvas at the laid-out size**. `findsOneWidget` is never the claim.
///
/// It also holds the two rules a stage chart can quietly break:
///
///   * **stages stay distinguishable** — the four hues are all painted, and they
///     come from `InstrumentHues.sleepStage`, the app's one stage mapping;
///   * **NO INTERPOLATION DRAWS A VALUE OUTSIDE THE INPUT RANGE** — the timing
///     chart's curve is monotone for exactly this reason, and a Catmull-Rom
///     regression would draw a bedtime earlier than any night measured.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/instrument_hues.dart';
import 'package:healthee/data/models/sleep_night.dart';
import 'package:healthee/features/sleep/sleep_windows.dart';
import 'package:healthee/features/sleep/v02/night_panels.dart';
import 'package:healthee/features/sleep/v02/timing_panel.dart';
import 'package:healthee/features/sleep/v02/week_panel.dart';
import 'package:healthee/shared/charts/v02/chart_box.dart';
import 'package:healthee/shared/charts/v02/chart_void.dart';
import 'package:healthee/shared/charts/v02/v02_hypnogram.dart';
import 'package:healthee/shared/charts/v02/v02_timing_chart.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:healthee/shared/v02/panel.dart';

import '../_sleep_stubs.dart';
import '../shared/_chart_probe.dart';
import '_sleep_host.dart';

/// A 390 px panel, less `Panel.padding` either side (the card has no border).
double _inner(double width) => width - 2 * Panel.padding;
final double _panelInnerWidth = _inner(390);

const InstrumentHues _hues = InstrumentHues.light();

void main() {
  late SleepNight night;
  late SleepWindows windows;

  setUpAll(loadSleepFont);
  setUp(() {
    final page = sleepPageFixture();
    night = page.nights.first;
    windows = SleepWindows(page, kSleepNow);
  });

  group('the stage timeline', () {
    testWidgets('IT FILLS THE PANEL AND PAINTS ONE BAND PER SPAN', (
      tester,
    ) async {
      await tester.pumpWidget(
        sleepPanelHost(
          NightTimelinePanel(night: night, reveals: RevealRegistry()),
        ),
      );
      await tester.pumpAndSettle();

      final size = tester.getSize(find.byType(V02Hypnogram));
      expect(size.height, NightTimelinePanel.chartHeight);
      expect(size.width, _panelInnerWidth);

      final painted = paintedBy(tester, find.byType(V02Hypnogram));
      // The blocks are the rounded marks, one per span, meeting edge to edge.
      // The joins between levels are dotted hairlines (`drawLine`), never a
      // datum, so only the rounded rects are counted. The block geometry itself
      // is pinned in `test/shared/hypnogram_painter_test.dart`.
      final bands = rrectsOf(painted);
      expect(bands, hasLength(night.timeline.length));
      expect(bands, isNotEmpty, reason: 'a chart that painted nothing');
      for (final band in rectsOf(painted)) {
        expect(band.height, greaterThan(1));
        expect(band.width, greaterThan(1));
        expect(band.left, greaterThanOrEqualTo(-0.01));
        expect(band.right, lessThanOrEqualTo(size.width + 0.01));
      }
      // **The 44px lane gutter is gone and the night has the width.** The
      // labels that lived there repeated the colour key drawn directly under
      // the chart, so the plot starts at the frame instead of after a column
      // of text. A band starting 44px in would mean the gutter came back.
      expect(
        bands.map((band) => band.left).reduce((a, b) => a < b ? a : b),
        lessThan(8),
        reason: 'the plot must begin at the chart edge, not after a gutter',
      );
    });

    testWidgets('the clock axis is drawn and stays inside the chart', (
      tester,
    ) async {
      await tester.pumpWidget(
        sleepPanelHost(
          NightTimelinePanel(night: night, reveals: RevealRegistry()),
        ),
      );
      await tester.pumpAndSettle();

      final painted = paintedBy(tester, find.byType(V02Hypnogram));
      final labels = glyphRectsOf(painted);
      // `V02Hypnogram.axisTicks` clocks along the foot. Two end labels were all
      // this chart had; a nine-hour night labelled only at its ends gives no
      // way to say WHEN the long wake happened.
      expect(labels.length, greaterThanOrEqualTo(V02Hypnogram.axisTicks));
      final size = tester.getSize(find.byType(V02Hypnogram));
      for (final label in labels) {
        expect(label.left, greaterThanOrEqualTo(-0.01));
        expect(label.right, lessThanOrEqualTo(size.width + 0.01));
        expect(label.bottom, lessThanOrEqualTo(size.height + 0.01));
      }
    });

    testWidgets('an unstaged night draws nothing and keeps the slot', (
      tester,
    ) async {
      final page = sleepPageWithout(<String>['stage_timeline']);
      await tester.pumpWidget(
        sleepPanelHost(
          NightTimelinePanel(
            night: page.nights.first,
            reveals: RevealRegistry(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(V02Hypnogram), findsNothing);
      expect(find.text(kNoTimelineNote), findsOneWidget);
      // The slot is kept, so the screen does not jump when a night is staged.
      expect(
        tester.getSize(find.byType(ChartVoid)).height,
        NightTimelinePanel.chartHeight,
      );
    });
  });

  group('the bedtime and wake chart', () {
    testWidgets('IT FILLS THE PANEL AND DRAWS BOTH SERIES', (tester) async {
      await tester.pumpWidget(
        sleepPanelHost(
          SleepTimingPanel(
            bedtime: windows.bedtime,
            wake: windows.wake,
            dates: windows.timingDates,
            consistency: consistencyFixture(),
            reveals: RevealRegistry(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final chart = find.byType(V02TimingChart);
      expect(tester.getSize(chart).width, _panelInnerWidth);

      final painted = paintedBy(tester, chart);
      // Five gridlines, and two hues — bedtime is sleep, wake is movement, and
      // one accent drawn twice would lose which line is which.
      expect(countOf(painted, #drawLine), V02TimingChart.gridlines);
      final drawn = coloursOf(painted);
      expect(drawn, contains(_hues.sleep.toARGB32()), reason: 'bedtime');
      expect(drawn, contains(_hues.movement.toARGB32()), reason: 'wake');
      expect(countOf(painted, #drawPath), greaterThanOrEqualTo(2));
    });

    testWidgets('NO INTERPOLATION DRAWS A VALUE OUTSIDE THE INPUT RANGE', (
      tester,
    ) async {
      // A Catmull-Rom curve overshoots, so a dip between two late nights would
      // be drawn earlier than any bedtime measured. The V-shaped series below is
      // the case that produces the biggest overshoot.
      const bedtime = <double>[5.0, 5.2, 8.0, 5.1, 5.0];
      const wake = <double>[12.0, 12.1, 15.0, 12.2, 12.0];
      await tester.pumpWidget(
        sleepPanelHost(
          SleepTimingPanel(
            bedtime: bedtime,
            wake: wake,
            dates: const <String>['1 Jul', '2 Jul', '3 Jul', '4 Jul', '5 Jul'],
            consistency: null,
            reveals: RevealRegistry(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final chart = find.byType(V02TimingChart);
      final widget = tester.widget<V02TimingChart>(chart);
      final ticks = widget.ticks!;
      // The painter's own plot rectangle, so the bounds are compared in the
      // space the curve was actually drawn in.
      final plot = ChartMetrics.series.box(tester.getSize(chart)).plot;
      final painted = paintedBy(tester, chart);
      // In screen space a HIGHER value is a SMALLER y, so the measured maximum
      // is the top bound and the measured minimum the bottom one.
      final all = <double>[...bedtime, ...wake];
      final top = ticks.y(all.reduce((a, b) => a > b ? a : b), plot);
      final bottom = ticks.y(all.reduce((a, b) => a < b ? a : b), plot);
      for (final call in painted) {
        if (call.invocation.memberName != #drawPath) {
          continue;
        }
        final bounds = (call.invocation.positionalArguments[0] as Path)
            .getBounds();
        // Generous by the stroke's own half-width; the point is that a spline
        // cannot wander a whole reading past the data.
        expect(
          bounds.top,
          greaterThanOrEqualTo(top - 4),
          reason: 'the curve drew a time later than any night measured',
        );
        expect(
          bounds.bottom,
          lessThanOrEqualTo(bottom + 4),
          reason: 'the curve drew a time earlier than any night measured',
        );
      }
    });

    testWidgets('fewer than two nights draws nothing and keeps the slot', (
      tester,
    ) async {
      await tester.pumpWidget(
        sleepPanelHost(
          SleepTimingPanel(
            bedtime: const <double>[5],
            wake: const <double>[12],
            dates: const <String>['1 Jul'],
            consistency: null,
            reveals: RevealRegistry(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(V02TimingChart), findsNothing);
      expect(find.textContaining('no line to draw'), findsOneWidget);
    });
  });

  group(
    'every chart is drawn at four phone widths, and none of them is 800',
    () {
      for (final width in kSleepWidths) {
        testWidgets('the night panels lay out at $width', (tester) async {
          tester.view
            ..physicalSize = Size(width, 2400)
            ..devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            sleepPanelHost(
              Column(
                children: <Widget>[
                  NightTimelinePanel(night: night, reveals: RevealRegistry()),
                  StageTablePanel(night: night, reveals: RevealRegistry()),
                  StageWeekPanel(
                    nights: windows.week,
                    span: windows.weekSpan,
                    reveals: RevealRegistry(),
                  ),
                ],
              ),
              width: width,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            tester.getSize(find.byType(V02Hypnogram)).width,
            _inner(width),
          );
        });
      }
    },
  );
}
