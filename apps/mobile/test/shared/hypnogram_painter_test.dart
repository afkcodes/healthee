/// The night chart's ink: blocks that fill their level and meet edge to edge,
/// a dotted hairline only where the level changes, and awake as a short cap.
///
/// Every claim reads the recorded canvas at the laid-out size, the way
/// `sleep_charts_test.dart` does: what the painter really drew, not that a
/// widget exists.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/models/last_sleep.dart';
import 'package:healthee/shared/charts/v02/hypnogram_painter.dart';
import 'package:healthee/shared/charts/v02/v02_hypnogram.dart';

import '_chart_probe.dart';

/// A short invented night: stage and minutes, in order.
const List<(String, int)> _night = <(String, int)>[
  ('light', 20),
  ('deep', 40),
  ('light', 30),
  ('rem', 15),
  ('awake', 4),
  ('light', 50),
  ('rem', 1),
  ('light', 25),
  ('deep', 30),
  ('light', 15),
];

List<SleepStageSpan> _spans(List<(String, int)> night) {
  var at = 0.0;
  return <SleepStageSpan>[
    for (final (String stage, int minutes) in night)
      SleepStageSpan(
        stage: stage,
        startOffsetMin: at,
        endOffsetMin: at += minutes,
        durationMin: minutes.toDouble(),
      ),
  ];
}

/// Every `drawLine` as (from, to), in the order it was drawn.
List<(Offset, Offset)> _linesOf(List<RecordedInvocation> painted) =>
    <(Offset, Offset)>[
      for (final call in painted)
        if (call.invocation.memberName == #drawLine)
          (
            call.invocation.positionalArguments[0] as Offset,
            call.invocation.positionalArguments[1] as Offset,
          ),
    ];

Future<List<RecordedInvocation>> _paint(
  WidgetTester tester, {
  double progress = 1,
  List<(String, int)> night = _night,
}) async {
  await tester.pumpWidget(
    chartHost(V02Hypnogram(_spans(night), progress: progress, height: 156)),
  );
  return paintedBy(tester, find.byType(V02Hypnogram));
}

void main() {
  testWidgets('one block per span, each starting where the last ended', (
    tester,
  ) async {
    final blocks = rrectsOf(await _paint(tester));
    expect(blocks, hasLength(_night.length));
    for (var i = 1; i < blocks.length; i++) {
      // Edge to edge: no gap, no overlap beyond the narrowest block a one-minute
      // bout is widened to.
      expect(
        blocks[i].left,
        moreOrLessEquals(
          blocks[i - 1].right,
          epsilon: HypnogramPainter.minBlockWidth,
        ),
        reason: 'block $i does not meet block ${i - 1}',
      );
    }
  });

  testWidgets('each stage has its own level, and awake is a short cap above', (
    tester,
  ) async {
    final blocks = rrectsOf(await _paint(tester));
    Rect first(String stage) =>
        blocks[_night.indexWhere((entry) => entry.$1 == stage)];
    final awake = first('awake');
    final rem = first('rem');
    final light = first('light');
    final deep = first('deep');
    expect(awake.top, lessThan(rem.top));
    expect(rem.top, lessThan(light.top));
    expect(light.top, lessThan(deep.top));
    expect(rem.height, moreOrLessEquals(light.height));
    expect(deep.height, moreOrLessEquals(light.height));
    expect(
      awake.height,
      moreOrLessEquals(light.height * HypnogramPainter.awakeFraction),
    );
    // Levels do not overlap: the gap between them is the painter's own.
    expect(rem.top - awake.bottom, moreOrLessEquals(HypnogramPainter.levelGap));
  });

  testWidgets(
    'a one-minute bout is still drawn, and no wider than it must be',
    (tester) async {
      final blocks = rrectsOf(await _paint(tester));
      final bout = blocks[_night.indexOf(('rem', 1))];
      expect(bout.width, greaterThanOrEqualTo(HypnogramPainter.minBlockWidth));
      expect(bout.width, lessThan(4));
    },
  );

  testWidgets('joins are dotted hairlines only where the level changes', (
    tester,
  ) async {
    final painted = await _paint(
      tester,
      night: const <(String, int)>[('rem', 30), ('rem', 30), ('deep', 30)],
    );
    final blocks = rrectsOf(painted);
    final lines = _linesOf(painted);
    // REM to REM is no change: the only join is REM to deep, which crosses
    // the Light level's height (at a moment Light holds no block).
    expect(lines, isNotEmpty);
    final x = blocks[2].left;
    for (final (from, to) in lines) {
      expect(from.dx, moreOrLessEquals(x), reason: 'a join away from a change');
      expect(to.dx, moreOrLessEquals(x));
      expect((to.dy - from.dy).abs(), lessThanOrEqualTo(HypnogramPainter.dash));
      // Between the two levels and no further: never across a block.
      expect(from.dy, greaterThanOrEqualTo(blocks[1].bottom - 0.01));
      expect(to.dy, lessThanOrEqualTo(blocks[2].top + 0.01));
    }
    // Several dashes across that height: dotted, not one solid riser.
    expect(lines.length, greaterThan(1));
  });

  testWidgets('joins are drawn under the blocks', (tester) async {
    final painted = await _paint(tester);
    final members = painted.map((call) => call.invocation.memberName).toList();
    expect(
      members.lastIndexOf(#drawLine),
      lessThan(members.indexOf(#drawRRect)),
    );
  });

  testWidgets('the reveal sweeps along the night', (tester) async {
    final full = rrectsOf(await _paint(tester));
    final half = rrectsOf(await _paint(tester, progress: 0.5));
    expect(half.length, lessThan(full.length));
    expect(half, isNotEmpty);
    final plotRight = full.last.right;
    for (final block in half) {
      expect(block.right, lessThanOrEqualTo(plotRight / 2 + 0.5));
      // Heights do not grow with the reveal; only the reach does.
      expect(block.height, greaterThan(1));
    }
  });
}
