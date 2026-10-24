/// The biological-age ruler, measured on what it paints: tick positions on
/// whole physical pixels, the lit span, the needle and its gap, and which
/// labels survive a collision. Painter calls are recorded, not goldened.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/shared/v02/instruments/age_ruler.dart';

import '../_chart_probe.dart';
import '_instrument_probe.dart';

/// The dark theme's colours, to compare what was painted against.
final HealtheeColors _dark = AppTheme.dark.extension<HealtheeColors>()!;

/// Lays the ruler out at [width] and [dpr] and records one paint.
Future<List<RecordedInvocation>> _paint(
  WidgetTester tester, {
  required double estimate,
  double actual = 36,
  double width = 390,
  double dpr = 3,
  double progress = 1,
  bool light = false,
}) async {
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    instrumentHost(
      AgeRuler(estimate: estimate, actual: actual, progress: progress),
      width: width,
      light: light,
    ),
  );
  return paintedAt(tester, find.byKey(AgeRuler.plotKey));
}

/// The colour a recorded draw call used.
int _colourOf(RecordedInvocation call) =>
    (call.invocation.positionalArguments[1] as Paint).color.toARGB32();

/// The tick draw calls: every `drawRect` up to and including the last tick.
List<RecordedInvocation> _ticks(
  List<RecordedInvocation> painted,
  int intervals,
) => painted
    .where((c) => c.invocation.memberName == #drawRect)
    .take(intervals + 1)
    .toList();

Rect _rect(RecordedInvocation call) =>
    call.invocation.positionalArguments[0] as Rect;

void main() {
  group('tick geometry', () {
    for (final width in <double>[320, 350, 390]) {
      for (final dpr in <double>[1, 2, 2.625, 3]) {
        testWidgets('width $width at dpr $dpr: 65 ticks on whole pixels', (
          tester,
        ) async {
          final painted = await _paint(
            tester,
            estimate: 34.3,
            width: width,
            dpr: dpr,
          );
          final ticks = _ticks(painted, 64);
          expect(ticks, hasLength(65));
          final rects = ticks.map(_rect).toList();
          final gap = rects[1].left - rects[0].left;
          expect(gap * dpr, closeTo((gap * dpr).roundToDouble(), 1e-6));
          for (var i = 0; i < rects.length; i++) {
            expect(
              rects[i].left * dpr,
              closeTo((rects[i].left * dpr).roundToDouble(), 1e-6),
              reason: 'tick $i is off a physical pixel',
            );
            expect(rects[i].width, closeTo(rects[0].width, 1e-6));
            if (i > 0) {
              expect(
                rects[i].left - rects[i - 1].left,
                closeTo(gap, 1e-6),
                reason: 'gap before tick $i differs',
              );
            }
          }
          // Centred to within half a physical pixel either way.
          final leftMargin = rects.first.left;
          final rightMargin = width - rects.last.right;
          expect(
            (leftMargin - rightMargin).abs(),
            lessThanOrEqualTo(1 / dpr + 1e-6),
          );
          expect(leftMargin, greaterThanOrEqualTo(0));
          expect(rightMargin, greaterThanOrEqualTo(0));
        });
      }
    }

    testWidgets('whole years are 16 tall, quarters 10, on one centre axis', (
      tester,
    ) async {
      final painted = await _paint(tester, estimate: 34.3);
      final rects = _ticks(painted, 64).map(_rect).toList();
      for (var i = 0; i < rects.length; i++) {
        expect(rects[i].height, i % 4 == 0 ? 16 : 10);
        expect(rects[i].center.dy, closeTo(kAgeRulerAxisY, 1 / 3));
      }
    });

    testWidgets('the ruler is the 92 px it declares', (tester) async {
      await _paint(tester, estimate: 34.3);
      expect(
        tester.getSize(find.byKey(AgeRuler.plotKey)).height,
        AgeRuler.height,
      );
    });
  });

  group('domain', () {
    test('34.3 against 36 is 28 to 44 with 64 gaps', () {
      final s = AgeRulerScale(estimate: 34.3, actual: 36);
      expect((s.low, s.high, s.intervals), (28.0, 44.0, 64));
    });

    test('an estimate below the base domain widens low by whole years', () {
      final s = AgeRulerScale(estimate: 26.2, actual: 36);
      expect(s.low, lessThan(26.2));
      expect(s.low, s.low.roundToDouble());
      expect(26.2 - s.low, greaterThanOrEqualTo(1));
      expect(s.high, 44);
    });

    test('an estimate above the base domain widens high', () {
      final s = AgeRulerScale(estimate: 47, actual: 36);
      expect(s.high, greaterThan(47));
      expect(s.high, s.high.roundToDouble());
      expect(s.low, 28);
    });
  });

  group('the lit span', () {
    testWidgets('34.3 to 36 lights the 8 ticks 34.25..36 in fav', (
      tester,
    ) async {
      final ticks = _ticks(await _paint(tester, estimate: 34.3), 64);
      final lit = <int>[
        for (var i = 0; i < ticks.length; i++)
          if (_colourOf(ticks[i]) == _dark.fav.toARGB32()) i,
      ];
      expect(lit, <int>[for (var i = 25; i <= 32; i++) i]);
      expect(lit.length, 8);
    });

    testWidgets('older is alert', (tester) async {
      final ticks = _ticks(await _paint(tester, estimate: 38.1), 64);
      final lit = ticks.where((t) => _colourOf(t) == _dark.alert.toARGB32());
      // 36 (index 32) to 38 (index 40), 38.1 rounds to the 38 tick.
      expect(lit.length, 9);
      expect(ticks.any((t) => _colourOf(t) == _dark.fav.toARGB32()), isFalse);
    });

    testWidgets('within half a year is ink2, neither fav nor alert', (
      tester,
    ) async {
      final ticks = _ticks(await _paint(tester, estimate: 36.3), 64);
      final lit = ticks.where((t) => _colourOf(t) == _dark.ink2.toARGB32());
      // 36.3 rounds to the 36.25 tick; 36 and 36.25 are lit.
      expect(lit.length, 2);
      expect(ticks.any((t) => _colourOf(t) == _dark.fav.toARGB32()), isFalse);
      expect(ticks.any((t) => _colourOf(t) == _dark.unf.toARGB32()), isFalse);
      expect(ticks.any((t) => _colourOf(t) == _dark.alert.toARGB32()), isFalse);
    });

    testWidgets('the grey ticks do not move or change with progress', (
      tester,
    ) async {
      final done = await _paint(tester, estimate: 34.3);
      final start = await _paint(tester, estimate: 34.3, progress: 0);
      final grey = _dark.ink.withValues(alpha: 0.22).toARGB32();
      List<Rect> greyOf(List<RecordedInvocation> p) =>
          _ticks(p, 64).where((t) => _colourOf(t) == grey).map(_rect).toList();
      final atEnd = greyOf(done);
      final atStart = greyOf(start);
      // Every grey tick at the end is still grey, in place, at the start.
      expect(atStart, containsAll(atEnd));
      // At progress 0 only the actual age's tick is lit.
      expect(atStart.length, 64);
    });
  });

  group('the needle', () {
    testWidgets('is 3 x 30 at the estimate, with a bg gap cut round it', (
      tester,
    ) async {
      final painted = await _paint(tester, estimate: 34.3);
      final rrects = painted
          .where((c) => c.invocation.memberName == #drawRRect)
          .toList();
      expect(rrects, hasLength(1));
      final needle = rrects.single.invocation.positionalArguments[0] as RRect;
      expect(needle.width, 3);
      expect(needle.height, 30);
      expect(needle.blRadiusX, 1.5);
      final ticks = _ticks(painted, 64).map(_rect).toList();
      final spacing = ticks[1].left - ticks[0].left;
      final exact =
          ticks.first.left + (34.3 - 28) * 4 * spacing + ticks.first.width / 2;
      expect(needle.center.dx, closeTo(exact, 0.5 / 3));
      expect(needle.left * 3, closeTo((needle.left * 3).roundToDouble(), 1e-6));
      expect(needle.center.dy, closeTo(kAgeRulerAxisY, 1 / 3));

      final gap = painted
          .where((c) => c.invocation.memberName == #drawRect)
          .map(_rect)
          .firstWhere((r) => r.width == 7);
      expect(gap.center.dx, closeTo(needle.center.dx, 1e-6));
      final order = painted.map((c) => c.invocation.memberName).toList();
      expect(
        painted.indexWhere((c) => c.invocation.memberName == #drawRRect),
        greaterThan(order.lastIndexOf(#drawRect)),
        reason: 'the needle must be drawn after the bg gap and every tick',
      );
      expect(
        coloursOf(painted),
        containsAll(<int>[_dark.bg.toARGB32(), _dark.ink.toARGB32()]),
      );
    });

    testWidgets('starts on the actual age at progress 0', (tester) async {
      final painted = await _paint(tester, estimate: 34.3, progress: 0);
      final needle =
          painted
                  .firstWhere((c) => c.invocation.memberName == #drawRRect)
                  .invocation
                  .positionalArguments[0]
              as RRect;
      final ticks = _ticks(painted, 64).map(_rect).toList();
      expect(needle.center.dx, closeTo(ticks[32].center.dx, 0.5 / 3));
    });
  });

  group('labels', () {
    testWidgets('five labels at 390: two above, three below', (tester) async {
      final glyphs = glyphRectsOf(await _paint(tester, estimate: 34.3));
      expect(glyphs, hasLength(5));
      expect(glyphs.where((g) => g.top == 0), hasLength(2));
      final below = glyphs.where((g) => g.top > kAgeRulerAxisY).toList();
      expect(below, hasLength(3));
    });

    testWidgets('"your age" is centred on the actual age and never hidden', (
      tester,
    ) async {
      final painted = await _paint(tester, estimate: 34.3);
      final ticks = _ticks(painted, 64).map(_rect).toList();
      final you = glyphRectsOf(painted).firstWhere(
        (g) => g.top == kAgeRulerBottomRowY,
        orElse: () => fail('no "your age" caption on the bottom row'),
      );
      expect(you.center.dx, closeTo(ticks[32].center.dx, 1));
    });

    testWidgets('an end value that would collide with "your age" is hidden', (
      tester,
    ) async {
      // Widened to 19..44, so the caption sits at 68% and crowds the 44.
      // (The test engine sets text in Ahem, 12 px a character, so "your age"
      // is wider here than on a phone and the collision comes at 260.)
      final painted = await _paint(tester, estimate: 20, width: 260, dpr: 2);
      final glyphs = glyphRectsOf(painted);
      expect(glyphs, hasLength(4));
      final you = glyphs.firstWhere((g) => g.top == kAgeRulerBottomRowY);
      for (final g in glyphs.where((g) => g.top > kAgeRulerAxisY)) {
        if (g != you) {
          expect(g.inflate(0).overlaps(you.inflate(8)), isFalse);
        }
      }
    });

    testWidgets('Younger and Older are both hidden when they would collide', (
      tester,
    ) async {
      final glyphs = glyphRectsOf(
        await _paint(tester, estimate: 34.3, width: 60, dpr: 3),
      );
      expect(glyphs.where((g) => g.top == 0), isEmpty);
      expect(
        glyphs.where((g) => g.top > kAgeRulerAxisY),
        isNotEmpty,
        reason: '"your age" is never hidden',
      );
    });

    testWidgets('no label is set below 11 px', (tester) async {
      final glyphs = glyphRectsOf(await _paint(tester, estimate: 34.3));
      for (final g in glyphs) {
        expect(g.height, greaterThanOrEqualTo(14));
      }
    });
  });

  group('formatting and semantics', () {
    test('ages are whole or one decimal', () {
      expect(formatAge(36), '36');
      expect(formatAge(36.04), '36');
      expect(formatAge(34.3), '34.3');
    });

    testWidgets('the default label names the estimate, scale and actual age', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _paint(tester, estimate: 34.3);
      expect(
        find.bySemanticsLabel(
          'Biological age 34.3 on a scale from 28 to 44. '
          'Your actual age is 36.',
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('can be excluded from semantics for a hero that owns it', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        instrumentHost(
          const AgeRuler(
            estimate: 34.3,
            actual: 36,
            excludeFromSemantics: true,
          ),
        ),
      );
      expect(find.bySemanticsLabel(RegExp('Biological age')), findsNothing);
      handle.dispose();
    });
  });
}
