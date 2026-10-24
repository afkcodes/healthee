/// The colour kit's chart grammar: goal bars, the flat sparkline, the band and
/// the one state-coloured dot, plus the signal strip, diverging bar and hatch.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/instrument_hues.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/shared/charts/chart_reference.dart';
import 'package:healthee/shared/charts/v02/column_painter.dart';
import 'package:healthee/shared/charts/v02/diverging_bar.dart';
import 'package:healthee/shared/charts/v02/hatch.dart';
import 'package:healthee/shared/charts/v02/series_painter.dart';
import 'package:healthee/shared/charts/v02/signal_spark.dart';
import 'package:healthee/shared/charts/v02/v02_bar_chart.dart';
import 'package:healthee/shared/charts/v02/v02_sparkline.dart';
import 'package:healthee/shared/usual_range.dart';
import 'package:healthee/shared/v02/reading_state.dart';

import '_chart_probe.dart';
import '_v02_chart_probe.dart';

const List<double?> _week = <double?>[
  8200,
  11400,
  6100,
  9800,
  12600,
  4300,
  6500,
];
const UsualRange _usual = UsualRange(low: 60, high: 70, days: 30);
const List<double?> _run = <double?>[62, 64, 66, 65, 68, 71, 75];

/// Paint stores 8-bit channels, so colours are compared as ARGB ints.
int _argb(Color c) => c.toARGB32();

HealtheeColors _colors(WidgetTester tester) => Theme.of(
  tester.element(find.byType(Scaffold)),
).extension<HealtheeColors>()!;

InstrumentHues _hues(WidgetTester tester) => Theme.of(
  tester.element(find.byType(Scaffold)),
).extension<InstrumentHues>()!;

void main() {
  group('goal bars', () {
    final bars = find.byType(V02BarChart);
    const goal = ChartReference.convention(value: 8000, label: 'Goal 8,000');

    testWidgets('below the goal is 32%, at or above is full, no glow below', (
      tester,
    ) async {
      await pumpChart(
        tester,
        const V02BarChart(_week, progress: 1, target: goal),
        tone: Tone.movement,
        dark: false,
      );
      final columns = columnsOf(paintedAt(tester, bars));
      expect(columns.length, _week.length);
      for (var i = 0; i < _week.length; i++) {
        final met = _week[i]! >= 8000;
        expect(columns[i].$2.a, closeTo(met ? 1 : 0.32, 0.005), reason: '$i');
      }
    });

    testWidgets('a bar exactly on the goal counts as met', (tester) async {
      await pumpChart(
        tester,
        const V02BarChart(<double?>[8000, 7999], progress: 1, target: goal),
        tone: Tone.movement,
        dark: false,
      );
      final columns = columnsOf(paintedAt(tester, bars));
      expect(columns[0].$2.a, 1);
      expect(columns[1].$2.a, closeTo(0.32, 0.005));
    });

    testWidgets('dark glow only on goal-met bars', (tester) async {
      await pumpChart(
        tester,
        const V02BarChart(_week, progress: 1, target: goal),
        tone: Tone.movement,
      );
      final met = _week.where((v) => v! >= 8000).length;
      // One glow plus one bar per met bar, one bar per unmet bar.
      expect(countOf(paintedAt(tester, bars), #drawRRect), _week.length + met);
    });

    testWidgets('no target: emphasis bar full, others 0.42, never a glow', (
      tester,
    ) async {
      await pumpChart(
        tester,
        const V02BarChart(_week, progress: 1),
        tone: Tone.movement,
      );
      final calls = paintedAt(tester, bars);
      expect(countOf(calls, #drawRRect), _week.length);
      final columns = columnsOf(calls);
      expect(columns.last.$2.a, 1);
      expect(columns.first.$2.a, closeTo(0.42, 0.005));
    });

    test('the dimming constant is the kit\'s 32%', () {
      expect(ColumnPainter.belowGoalAlpha, 0.32);
    });
  });

  group('the sparkline', () {
    final spark = find.byType(V02Sparkline);

    testWidgets('is flat by default', (tester) async {
      await pumpChart(tester, const V02Sparkline(_run, progress: 1));
      expect(painterFor<SeriesPainter>(tester, spark).fill, isFalse);
    });

    testWidgets('draws the usual range as the band token behind the line', (
      tester,
    ) async {
      await pumpChart(
        tester,
        const V02Sparkline(_run, progress: 1, usual: _usual),
        dark: false,
      );
      final painter = painterFor<SeriesPainter>(tester, spark);
      expect(_argb(painter.bandColor!), _argb(_colors(tester).band));
      final calls = paintedAt(tester, spark);
      final bands = columnsOf(
        calls,
      ).where((c) => _argb(c.$2) == _argb(_colors(tester).band));
      expect(bands.length, 1);
      // The band is the first thing drawn, so the line sits on top of it.
      expect(
        calls.indexWhere((c) => c.invocation.memberName == #drawRRect),
        lessThan(calls.indexWhere((c) => c.invocation.memberName == #drawPath)),
      );
    });

    testWidgets('no usual range draws no band', (tester) async {
      await pumpChart(tester, const V02Sparkline(_run, progress: 1));
      expect(columnsOf(paintedAt(tester, spark)), isEmpty);
    });

    testWidgets('state tints only the newest dot; null keeps the family', (
      tester,
    ) async {
      await pumpChart(
        tester,
        const V02Sparkline(_run, progress: 1, state: ReadingState.worse),
        dark: false,
      );
      var painter = painterFor<SeriesPainter>(tester, spark);
      expect(painter.dotColor, _colors(tester).alert);
      expect(painter.ink.family, isNot(painter.dotColor));
      final dots = <Color>[
        for (final c in paintedAt(tester, spark))
          if (c.invocation.memberName == #drawCircle)
            (c.invocation.positionalArguments[2] as Paint).color,
      ];
      expect(_argb(dots.last), _argb(_colors(tester).alert));
      expect(
        dots.where((c) => _argb(c) == _argb(_colors(tester).alert)).length,
        1,
      );

      await pumpChart(tester, const V02Sparkline(_run, progress: 1));
      painter = painterFor<SeriesPainter>(tester, spark);
      expect(painter.dotColor, isNull);
    });
  });

  group('signal spark', () {
    final strip = find.byType(SignalSpark);
    Widget build(List<double?> v, ReadingState s, {UsualRange? usual}) =>
        SignalSpark(values: v, state: s, usual: usual);

    testWidgets('renders and draws the band, line and dot', (tester) async {
      await pumpChart(tester, build(_run, ReadingState.usual, usual: _usual));
      final calls = paintedAt(tester, strip);
      expect(countOf(calls, #drawPath), 1);
      expect(countOf(calls, #drawCircle), 1);
      expect(
        columnsOf(
          calls,
        ).where((c) => _argb(c.$2) == _argb(_colors(tester).band)).length,
        1,
      );
    });

    testWidgets('a gap breaks the run, it is never bridged', (tester) async {
      final holed = List<double?>.from(_run)..[3] = null;
      await pumpChart(tester, build(holed, ReadingState.usual));
      expect(countOf(paintedAt(tester, strip), #drawPath), 2);
    });

    testWidgets('fewer than two values draws the hatch, no line, no dot', (
      tester,
    ) async {
      await pumpChart(
        tester,
        build(const <double?>[68, null, null], ReadingState.noData),
      );
      final calls = paintedAt(tester, strip);
      expect(countOf(calls, #drawPath), 0);
      expect(countOf(calls, #drawCircle), 0);
      expect(countOf(calls, #drawLine), greaterThan(0));
    });

    testWidgets('the dot is the state colour; inside the range it is ink', (
      tester,
    ) async {
      Future<Color> dot(ReadingState s) async {
        await pumpChart(tester, build(_run, s), dark: false);
        return (paintedAt(tester, strip)
                    .lastWhere((c) => c.invocation.memberName == #drawCircle)
                    .invocation
                    .positionalArguments[2]
                as Paint)
            .color;
      }

      final better = await dot(ReadingState.better);
      final worse = await dot(ReadingState.worse);
      final watch = await dot(ReadingState.watch);
      final usual = await dot(ReadingState.usual);
      final c = _colors(tester);
      expect(_argb(better), _argb(c.fav));
      expect(_argb(worse), _argb(c.alert));
      expect(_argb(watch), _argb(c.unf));
      expect(_argb(usual), _argb(c.ink));
    });

    testWidgets('the line is the domain colour, whatever the state', (
      tester,
    ) async {
      await pumpChart(
        tester,
        build(_run, ReadingState.worse),
        tone: Tone.sleep,
      );
      final painter = painterFor<SignalSparkPainter>(tester, strip);
      final line =
          paintedAt(tester, strip)
                  .firstWhere((c) => c.invocation.memberName == #drawPath)
                  .invocation
                  .positionalArguments[1]
              as Paint;
      expect(_argb(line.color), _argb(painter.family));
      expect(_argb(line.color), isNot(_argb(_colors(tester).alert)));
    });
  });

  group('diverging bar', () {
    final bar = find.byType(DivergingBar);

    Future<List<(Rect, Color)>> fills(WidgetTester t, double r) async {
      await pumpChart(t, DivergingBar(r: r));
      final surface = _colors(t).surface2;
      return columnsOf(
        paintedAt(t, bar),
      ).where((c) => _argb(c.$2) != _argb(surface)).toList();
    }

    testWidgets('positive diverges right in the Strain hue', (tester) async {
      final marks = await fills(tester, 0.5);
      expect(marks.length, 1);
      expect(_argb(marks.single.$2), _argb(_hues(tester).strain));
      expect(
        marks.single.$1.left,
        closeTo(paintSize(tester, bar).width / 2, 0.01),
      );
    });

    testWidgets('negative diverges left in the Activity hue', (tester) async {
      final marks = await fills(tester, -0.5);
      expect(_argb(marks.single.$2), _argb(_hues(tester).movement));
      expect(
        marks.single.$1.right,
        closeTo(paintSize(tester, bar).width / 2, 0.01),
      );
    });

    testWidgets('length is the magnitude, clamped at one', (tester) async {
      final half = (await fills(tester, 0.5)).single.$1.width;
      final full = (await fills(tester, 3)).single.$1.width;
      expect(full, closeTo(half * 2, 0.01));
    });

    testWidgets('zero draws no bar', (tester) async {
      expect(await fills(tester, 0), isEmpty);
    });
  });

  group('hatch', () {
    test('draws diagonal lines in the given ink, clipped to the rect', () {
      final canvas = TestRecordingCanvas();
      paintHatch(
        canvas,
        const Rect.fromLTWH(0, 0, 40, 8),
        ink: const Color(0xFF123456),
      );
      final lines = linesOf(canvas.invocations);
      expect(lines, isNotEmpty);
      for (final (a, b) in lines) {
        expect(b.dx - a.dx, 8);
        expect(a.dy - b.dy, 8);
      }
      expect(
        canvas.invocations.any((c) => c.invocation.memberName == #clipRRect),
        isTrue,
      );
      final paint =
          canvas.invocations
                  .firstWhere((c) => c.invocation.memberName == #drawLine)
                  .invocation
                  .positionalArguments[2]
              as Paint;
      expect(_argb(paint.color), 0xFF123456);
    });

    test('a wider gap draws fewer lines', () {
      int count(double gap) {
        final canvas = TestRecordingCanvas();
        paintHatch(
          canvas,
          const Rect.fromLTWH(0, 0, 40, 8),
          ink: const Color(0xFF000000),
          gap: gap,
        );
        return linesOf(canvas.invocations).length;
      }

      expect(count(8), lessThan(count(4)));
    });
  });
}
