/// What the workout screen must be true about, rather than what it contains.
///
/// Four claims, and each of them is one this rebuild could have broken:
///
///   * **A REFUSED FIGURE IS STILL REFUSED, WITH ITS REASON.**
///     `/api/activity/workout` is the app's only payload with no honesty
///     envelope, so the pre-v02 screen simply dropped a metric whose inputs were
///     missing and said nothing. `workout_readings.dart` names every one, and
///     `test/mutations.sh` breaks those sentences on purpose.
///   * **No source chip and no reference label on a card face.** The sweep
///     (`citation_sweep_test.dart`) reads `lib/` for the widget; this reads the
///     rendered strings, which is where a raw note id would surface.
///   * **The chart paints at the size it was laid out to**, at four handset
///     widths and never at Flutter's 800 px default.
///   * **The trace never draws a heart rate nobody measured** — the join is
///     monotone, holes break it, and the curve stays inside its samples.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/data/honesty/reading.dart';
import 'package:healthee/data/workouts/workout_readings.dart';
import 'package:healthee/features/workouts/v02/effort_cards.dart';
import 'package:healthee/features/workouts/workout_detail_screen.dart';
import 'package:healthee/shared/charts/v02/chart_curve.dart';
import 'package:healthee/shared/charts/v02/chart_scrub.dart';
import 'package:healthee/shared/charts/v02/series_painter.dart';
import 'package:healthee/shared/charts/v02/v02_line_chart.dart';
import 'package:healthee/shared/v02/surface_panels.dart' show SurfaceCard;
import 'package:healthee/shared/v02/withheld_panel.dart';

import '../history/_history_host.dart' show kPhoneWidths, textsOn, useRealFonts;
import '../shared/_v02_chart_probe.dart';
import '_workouts_host.dart';

/// `DetailPage`'s own page padding, both sides.
const double kPagePadding = Insets.gutter * 2;

/// `.card { padding: 20px }` with no border, both sides.
const double kCardPadding = SurfaceCard.padding * 2;

Future<void> _pump(
  WidgetTester tester, {
  Map<String, Object?> Function(Map<String, Object?> json)? mutate,
  double width = 390,
}) async {
  tester.view
    ..physicalSize = Size(width, 5000)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    workoutsHost(
      const WorkoutDetailScreen(start: kWorkoutStart),
      detail: workoutFixture(mutate: mutate),
      width: width,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  useRealFonts();

  group('a refused figure says so, and says why', () {
    testWidgets('no HRmax withholds the zones inside the zones card', (
      tester,
    ) async {
      await _pump(tester, mutate: withoutHrmax);
      expect(find.byType(WithheldPanel), findsOneWidget);
      expect(find.text(kZonesLabel), findsWidgets);
      expect(
        find.text(
          'Zone minutes are cut against an HRmax estimate, and the server sent '
          'none for this session.',
        ),
        findsOneWidget,
      );
      // And no bars were drawn against a scale that does not exist.
      expect(find.text('Zone 1'), findsNothing);
    });

    testWidgets('no samples withholds the trace, and keeps the card', (
      tester,
    ) async {
      await _pump(tester, mutate: withoutSamples);
      expect(
        find.text(
          'No heart-rate samples fell inside this session. A workout summary '
          'can reach the server before the minutes behind it do.',
        ),
        findsOneWidget,
      );
      // The average and the peak came off the summary row, so they stay.
      expect(find.text('Average heart rate'), findsOneWidget);
      expect(find.byType(V02LineChart), findsNothing);
    });

    testWidgets('a dropped stat leaves no cell, and gains a named line', (
      tester,
    ) async {
      await _pump(tester, mutate: withoutMetric('trimp'));
      // The cell is gone rather than dashed: `stat_block.dart` refuses to
      // invent a placeholder.
      expect(find.text('TRIMP load'), findsNothing);
      expect(find.text('36.9'), findsNothing);
      // And the refusal names the same quantity the cell would have.
      expect(
        find.textContaining(
          'TRIMP load — A session load needs your HRmax, your resting heart '
          'rate and your sex on the server',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a session with no distance keeps its duration', (
      tester,
    ) async {
      await _pump(
        tester,
        mutate: (json) => <String, Object?>{
          ...json,
          'workout': <String, Object?>{
            ...json['workout']! as Map<String, Object?>,
            'distance_m': null,
          },
        },
      );
      // `StatBlock` draws its figure and unit as one rich span.
      expect(textsOn(tester), contains('30\u00A0min'));
      expect(
        find.textContaining(
          'Distance — The strap recorded no distance for this session',
        ),
        findsOneWidget,
      );
    });

    test('every refusal carries a reason id AND a sentence to read', () {
      // The emptiest payload the wire can produce: a summary row and nothing
      // derived from it. Every getter must refuse, and none may refuse mutely.
      final readings = WorkoutReadings(
        workoutFixture(
          mutate: (json) => <String, Object?>{
            ...withoutSamples(withoutHrmax(json)),
            'metrics': const <String, Object?>{},
            'zones': const <Object?>[],
            'workout': <String, Object?>{
              ...json['workout']! as Map<String, Object?>,
              'distance_m': null,
              'duration_min': null,
              'calories': null,
              'avg_hr': null,
              'max_hr': null,
            },
          },
        ),
      );
      final refusals = <Reading<Object>>[
        readings.distanceKm,
        readings.durationMin,
        readings.pace,
        readings.speed,
        readings.avgHr,
        readings.maxHr,
        readings.heartRate,
        readings.zones,
        readings.trimp,
        readings.calories,
        readings.hrDrift,
        readings.avgPercentHrmax,
        readings.maxPercentHrmax,
      ];
      for (final reading in refusals) {
        expect(reading, isA<Withheld<Object>>());
        final disclosure = (reading as Withheld<Object>).disclosure;
        expect(disclosure.reason, isNotEmpty);
        // A sentence, not a shrug — and never the wire id in the prose.
        expect(disclosure.message.length, greaterThan(30));
        expect(disclosure.message, isNot(contains('_')));
        expect(disclosure.message.endsWith('.'), isTrue);
      }
    });

    test('THE SERVER\'S OWN REASON WINS OVER THE ONE RECONSTRUCTED HERE', () {
      // The point of `metrics_withheld` (`docs/BACKEND_GAPS_FROM_UI.md` B6), and
      // TRIMP is the case that proves it. Its gate turns on a resting heart rate
      // and the owner's sex; neither is on this payload, so this file could only
      // ever name all four inputs and hope. The server names the one that failed.
      final readings = WorkoutReadings(
        workoutFixture(
          mutate: (json) => <String, Object?>{
            ...json,
            'metrics': <String, Object?>{
              ...json['metrics']! as Map<String, Object?>,
            }..remove('trimp'),
            'metrics_withheld': const <String, Object?>{
              'trimp': <String, Object?>{
                'reason': 'resting_hr_unavailable',
                'message':
                    'A session load is measured against your resting heart '
                    'rate, and there was none on file for this session.',
              },
            },
          },
        ),
      );
      final refused = readings.trimp;
      expect(refused, isA<Withheld<double>>());
      final disclosure = (refused as Withheld<double>).disclosure;
      expect(disclosure.reason, 'resting_hr_unavailable');
      expect(disclosure.message, contains('resting heart rate'));
      // And the local four-input sentence is NOT what reached the screen.
      expect(disclosure.message, isNot(contains('your sex')));
    });

    test('a payload with no envelope still explains itself', () {
      // An installed app meets servers it did not ship with. The local reasons
      // are the fallback, and deleting them with the defect would have traded
      // one silence for another.
      final readings = WorkoutReadings(
        workoutFixture(
          mutate: (json) => <String, Object?>{
            ...json,
            'metrics': <String, Object?>{
              ...json['metrics']! as Map<String, Object?>,
            }..remove('trimp'),
          },
        ),
      );
      final disclosure = (readings.trimp as Withheld<double>).disclosure;
      expect(disclosure.reason, 'trimp_inputs_missing');
      expect(disclosure.message, contains('resting heart rate'));
    });
  });

  group('nothing on a card face is a source chip', () {
    testWidgets('no raw note id, no bracket marker, no reference label', (
      tester,
    ) async {
      await _pump(tester);
      for (final said in textsOn(tester)) {
        expect(said, isNot(contains('cardio_load_trimp')));
        expect(said, isNot(contains('[')));
        expect(
          said.startsWith('Reference'),
          isFalse,
          reason: '"$said" is the label the owner asked us to remove',
        );
      }
    });
  });

  group('the trace is drawn at its real size, and only over measurements', () {
    testWidgets('the plot fills the card at every handset width', (
      tester,
    ) async {
      for (final width in kPhoneWidths) {
        await _pump(tester, width: width);
        final chart = find.byType(V02LineChart);
        final widget = tester.widget<V02LineChart>(chart);
        expect(
          paintSize(tester, chart).width,
          moreOrLessEquals(width - kPagePadding - kCardPadding, epsilon: 0.5),
          reason: 'the plot is narrower than the card at $width',
        );
        expect(
          tester.getSize(chart).height,
          moreOrLessEquals(widget.slotHeight, epsilon: 0.5),
        );
        // Present and painting nothing is the failure two sleep charts
        // shipped with, and it is invisible to a `findsOneWidget`.
        expect(
          paintSize(tester, chart).height,
          greaterThan(120),
          reason: 'the plot has no height to draw in at $width',
        );
      }
    });

    testWidgets('a series too short to draw keeps its slot', (tester) async {
      await _pump(tester, mutate: firstSamples(1));
      final chart = find.byType(V02LineChart);
      final widget = tester.widget<V02LineChart>(chart);
      expect(
        tester.getSize(chart).height,
        moreOrLessEquals(widget.slotHeight, epsilon: 0.5),
      );
      expect(widget.slotHeight, widget.height + ChartScrub.readoutHeight);
    });

    testWidgets('A GAP BREAKS THE LINE RATHER THAN BRIDGING IT', (
      tester,
    ) async {
      await _pump(tester, mutate: withGap(10, 13));
      final painter = painterFor<SeriesPainter>(
        tester,
        find.byType(V02LineChart),
      );
      expect(painter.values.sublist(10, 13), <double?>[null, null, null]);
      expect(seriesRuns(painter.values).length, 2);
    });

    testWidgets('the join is the one that cannot overshoot its samples', (
      tester,
    ) async {
      await _pump(tester);
      expect(
        painterFor<SeriesPainter>(tester, find.byType(V02LineChart)).curve,
        SeriesCurve.monotone,
      );
    });

    test('the curve stays inside the session it was drawn from', () {
      final values = EffortCard.minuteSeries(workoutFixture().heartRate);
      final measured = values.whereType<double>().toList();
      final low = measured.reduce(math.min);
      final high = measured.reduce(math.max);
      // Values as the y axis, so `top` is the lowest beat the curve draws and
      // `bottom` the highest. Neither may leave the samples.
      final bounds = monotonePath(<Offset>[
        for (var i = 0; i < values.length; i++)
          if (values[i] case final double value) Offset(i * 10.0, value),
      ]).getBounds();
      expect(bounds.top, greaterThanOrEqualTo(low - 1e-3));
      expect(bounds.bottom, lessThanOrEqualTo(high + 1e-3));
    });
  });

  group('the layout holds at a phone width', () {
    testWidgets('nothing overflows at 320, 360, 390 or 414', (tester) async {
      for (final width in kPhoneWidths) {
        await _pump(tester, width: width);
        expect(
          tester.takeException(),
          isNull,
          reason: 'the workout screen overflows at $width',
        );
      }
    });
  });
}
