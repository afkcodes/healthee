import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/shared/v02/instruments/zone_bar.dart';

const double _w = 300;

Future<ZoneBarGeometry> _pump(
  WidgetTester tester, {
  double value = 43,
  double low = 20,
  double high = 60,
  ZoneShape shape = ZoneShape.rising,
  double? target = 40,
  String? targetLabel = 'target',
  String? lowLabel = '20',
  String? highLabel = '60',
  double dpr = 3,
  double progress = 1,
  double textScale = 1,
}) async {
  tester.view
    ..physicalSize = const Size(400, 400) * dpr
    ..devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(
          devicePixelRatio: dpr,
          textScaler: TextScaler.linear(textScale),
        ),
        child: Material(
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: _w,
              child: ZoneBar(
                value: value,
                low: low,
                high: high,
                shape: shape,
                target: target,
                targetLabel: targetLabel,
                valueText: value.toStringAsFixed(1),
                unitText: 'u',
                lowLabel: lowLabel,
                highLabel: highLabel,
                progress: progress,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  final paint = tester.widget<CustomPaint>(find.byKey(ZoneBar.plotKey));
  return (paint.painter! as ZoneBarPainter).geometry;
}

void main() {
  testWidgets('ten segments, three px apart, six tall', (tester) async {
    final g = await _pump(tester);
    expect(g.segments, hasLength(10));
    for (var i = 1; i < 10; i++) {
      expect(
        g.segments[i].left - g.segments[i - 1].right,
        closeTo(kZoneGap, 1 / 3 + 1e-9),
      );
    }
    expect(g.segments.first.left, 0);
    expect(g.segments.last.right, closeTo(_w, 1 / 3));
    expect(g.segments.first.height, kZoneBarHeight);
  });

  for (final dpr in <double>[2.625, 3]) {
    testWidgets('segment edges sit on physical pixels at dpr $dpr', (t) async {
      final g = await _pump(t, dpr: dpr);
      for (final r in g.segments) {
        for (final edge in <double>[r.left, r.right]) {
          final px = edge * dpr;
          expect((px - px.roundToDouble()).abs(), lessThan(1e-6));
        }
      }
    });
  }

  testWidgets('rising ramp is monotonic from faint to strong', (tester) async {
    final g = await _pump(tester);
    for (var i = 1; i < 10; i++) {
      expect(g.alphas[i], greaterThan(g.alphas[i - 1]));
    }
    expect(g.alphas.first, greaterThanOrEqualTo(kZoneAlphaFloor));
    expect(g.alphas.last, lessThanOrEqualTo(1));
  });

  testWidgets('peak ramp is strongest at the target and falls faster right', (
    tester,
  ) async {
    final g = await _pump(
      tester,
      value: 7,
      low: 4,
      high: 10,
      shape: ZoneShape.peak,
      target: 7,
    );
    final best = g.alphas.indexOf(g.alphas.reduce((a, b) => a > b ? a : b));
    // Segment centres at 4.3, 4.9, ..., so 7 sits between segments 4 and 5.
    expect(best, anyOf(4, 5));
    expect(g.alphas.first, lessThan(g.alphas[best]));
    expect(g.alphas.last, lessThan(g.alphas[best]));
    expect(
      zoneGoodness(x: 5.5, low: 4, high: 10, shape: ZoneShape.peak, target: 7),
      closeTo(0.5, 1e-9),
    );
    expect(
      zoneGoodness(x: 8.5, low: 4, high: 10, shape: ZoneShape.peak, target: 7),
      closeTo(0, 1e-9),
    );
    expect(
      zoneGoodness(x: 4, low: 4, high: 10, shape: ZoneShape.peak, target: 7),
      0,
    );
  });

  test('the scale widens in whole units only to hold the value', () {
    expect(zoneDomain(20, 60, 43), (low: 20.0, high: 60.0));
    expect(zoneDomain(20, 60, 61.2), (low: 20.0, high: 62.0));
    expect(zoneDomain(20, 60, 18.4), (low: 18.0, high: 60.0));
    expect(zoneDomain(4, 10, 3.5), (low: 3.0, high: 10.0));
  });

  testWidgets('the marker sits at the value and slides with progress', (
    tester,
  ) async {
    final g = await _pump(tester, value: 40);
    expect(g.markerX, closeTo(_w / 2, 1e-9));
    final half = await _pump(tester, value: 40, progress: 0.5);
    expect(half.markerX, closeTo(_w / 4, 1e-9));
    final start = await _pump(tester, value: 40, progress: 0);
    expect(start.markerX, 0);
  });

  testWidgets('the value label stays inside the bar at both ends', (
    tester,
  ) async {
    final low = await _pump(tester, value: 20, target: null);
    expect(low.valueOffset.dx, 0);
    final high = await _pump(tester, value: 60, target: null);
    expect(high.valueOffset.dx + high.valuePainter.width, closeTo(_w, 1e-9));
  });

  testWidgets('target tick and label are centred, label clamped', (
    tester,
  ) async {
    final g = await _pump(tester, target: 40);
    expect(g.tickX, closeTo(_w / 2, 1e-9));
    final c = g.targetOffset!.dx + g.targetPainter!.width / 2;
    expect(c, closeTo(_w / 2, 1e-9));
    final edge = await _pump(tester, target: 20, lowLabel: null);
    expect(edge.targetOffset!.dx, 0);
  });

  testWidgets('an end label within 12 px of the target label is dropped', (
    tester,
  ) async {
    final near = await _pump(
      tester,
      target: 22,
      targetLabel: 'a long target label',
    );
    expect(near.lowPainter, isNull);
    expect(near.highPainter, isNotNull);
    final far = await _pump(tester, target: 40);
    expect(far.lowPainter, isNotNull);
    expect(far.highPainter, isNotNull);
  });

  testWidgets('it does not clip at text scale 1.3', (tester) async {
    final base = await _pump(tester);
    final big = await _pump(tester, textScale: 1.3);
    expect(big.height, greaterThan(base.height));
    expect(tester.getSize(find.byKey(ZoneBar.plotKey)).height, big.height);
  });
}
