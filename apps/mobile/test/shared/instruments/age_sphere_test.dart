/// The age sphere: the points are where the brief says, the look is even, the
/// colour is the owner's accent, and the motion stops when it should.
///
/// Geometry and brightness are asserted on the numbers the painter feeds to
/// `drawRawAtlas` (its [SphereFrame]), not on pixels: a pixel test would pass on
/// a sphere that drew the right look from the wrong data, and fail on a font
/// change.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/core/theme/appearance_variant.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/shared/v02/instruments/age_sphere.dart';
import 'package:healthee/shared/v02/instruments/age_sphere_lattice.dart';
import 'package:healthee/shared/v02/instruments/age_sphere_painter.dart';

/// Indigo's position in [AppearanceVariant.accentNames].
const int _indigo = 4;

/// Rings and sectors of the polar grid the distribution is binned into.
const int _rings = 8, _sectors = 16;

/// The angle the distribution is read at: the still angle, so it is the view a
/// withheld or reduced-motion owner actually sees.
const double _angle = kStillAngle;

const Key _scroller = Key('scroller');

ThemeData _theme(Brightness b, {int accent = 0}) =>
    AppTheme.customized(b, AppearanceVariant(accent: accent));

/// Pumps a sphere under [theme]; [reduced] is the platform's reduce-motion flag.
Future<void> _pump(
  WidgetTester tester, {
  Brightness brightness = Brightness.dark,
  double canvas = 330,
  bool reduced = false,
  bool withheld = false,
  int accent = 0,
  Widget? after,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: _theme(brightness, accent: accent),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          key: _scroller,
          child: Column(
            children: <Widget>[
              AgeSphere(
                canvas: canvas,
                withheld: withheld,
                centre: const Text('34.3'),
              ),
              ?after,
            ],
          ),
        ),
      ),
    ),
  );
  // Past the 950 ms entry, so what is left running is only the rotation.
  await tester.pump(const Duration(milliseconds: 1200));
}

AgeSpherePainter _painter(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.descendant(
      of: find.byType(AgeSphere),
      matching: find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is AgeSpherePainter,
      ),
    ),
  );
  return paint.painter! as AgeSpherePainter;
}

/// Whether the tree reaches idle inside a second. A ticking sphere never does.
Future<bool> _settles(WidgetTester tester) async {
  try {
    await tester.pumpAndSettle(
      const Duration(milliseconds: 33),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 1),
    );
    return true;
    // `pumpAndSettle`'s timeout is a `FlutterError` and is the observation.
    // ignore: avoid_catching_errors
  } on FlutterError {
    return false;
  }
}

int _alphaOf(int argb) => (argb >>> 24) & 0xFF;

/// Projected (x, y) of every lattice point at [angle], in unit radii.
List<Offset> _project(SphereLattice lattice, double angle) {
  const tilt = kSphereTiltDegrees * math.pi / 180;
  return <Offset>[
    for (int i = 0; i < lattice.count; i++)
      Offset(
        lattice.x[i] * math.cos(angle) + lattice.z[i] * math.sin(angle),
        lattice.y[i] * math.cos(tilt) -
            (-lattice.x[i] * math.sin(angle) + lattice.z[i] * math.cos(angle)) *
                math.sin(tilt),
      ),
  ];
}

void main() {
  group('point count', () {
    for (final canvas in <double>[330, 300]) {
      test('N follows 0.1 R squared, 1.2 times that in light, at $canvas', () {
        final r = 0.425 * canvas;
        final dark = (0.1 * r * r).round();
        expect(sphereDotCount(canvas, dark: true), dark);
        expect(sphereDotCount(canvas, dark: false), (1.2 * dark).round());
      });
    }

    test('the brief\'s own figure: about 1967 dark dots at 330', () {
      expect(sphereDotCount(330, dark: true), 1967);
      expect(sphereDotCount(300, dark: true), 1626);
    });

    testWidgets('the painter draws exactly that many', (tester) async {
      await _pump(tester);
      expect(_painter(tester).frame.count, 1967);
      await _pump(tester, brightness: Brightness.light);
      expect(_painter(tester).frame.count, 2360);
    });
  });

  group('lattice', () {
    test('the same N is the same ball, point for point', () {
      final a = SphereLattice.build(500);
      final b = SphereLattice.build(500);
      expect(identical(a, b), isFalse);
      expect(b.x, orderedEquals(a.x));
      expect(b.y, orderedEquals(a.y));
      expect(b.z, orderedEquals(a.z));
      expect(b.sparkle, orderedEquals(a.sparkle));
      expect(
        identical(SphereLattice.forCount(500), SphereLattice.forCount(500)),
        isTrue,
      );
    });

    test('every point sits in the 0.90 to 1.00 shell', () {
      final l = SphereLattice.forCount(1967);
      for (int i = 0; i < l.count; i++) {
        final len = math.sqrt(
          l.x[i] * l.x[i] + l.y[i] * l.y[i] + l.z[i] * l.z[i],
        );
        expect(len, inInclusiveRange(0.90 - 1e-6, 1.0 + 1e-6));
      }
    });

    test('6 percent sparkle, give or take a point, and the set is stable', () {
      final l = SphereLattice.forCount(1967);
      final n = l.sparkle.fold<int>(0, (a, b) => a + b);
      expect((n - 0.06 * 1967).abs(), lessThanOrEqualTo(1));
      expect(SphereLattice.forCount(1967).sparkle, orderedEquals(l.sparkle));
    });
  });

  group('distribution', () {
    // The threshold. A scatter of independent random points has a Poisson count
    // in each cell, so a cell's coefficient of variation is 1 / sqrt(mean).
    // Clumps and holes make a lattice at least that uneven, so "no worse than
    // random" is the least that "even" can mean; a jittered Fibonacci lattice
    // beats it comfortably: measured at 0.6 rad the ratio to the Poisson CV is
    // 0.74 in the innermost ring (18 points) and 0.39 to 0.65 in the rest, so a
    // real clump or hole fails and the 8 x 16 grid is not noisy enough to flake.
    test('no clumps or holes: each ring is no lumpier than random', () {
      final l = SphereLattice.forCount(1967);
      final counts = List.generate(_rings, (_) => List.filled(_sectors, 0));
      for (final p in _project(l, _angle)) {
        final rho = p.distance;
        final ring = math.min(_rings - 1, (rho * _rings).floor());
        final sector =
            ((math.atan2(p.dy, p.dx) + math.pi) / (2 * math.pi) * _sectors)
                .floor() %
            _sectors;
        counts[ring][sector]++;
      }
      for (int r = 0; r < _rings; r++) {
        final cells = counts[r];
        final mean = cells.reduce((a, b) => a + b) / _sectors;
        final variance =
            cells.map((c) => (c - mean) * (c - mean)).reduce((a, b) => a + b) /
            _sectors;
        final cv = math.sqrt(variance) / mean;
        expect(
          cv,
          lessThan(1 / math.sqrt(mean)),
          reason: 'ring $r: mean $mean per cell, CV $cv',
        );
      }
    });

    test('it reads as a ball: the rim is denser than the centre', () {
      final l = SphereLattice.forCount(1967);
      final rings = List.filled(_rings, 0);
      for (final p in _project(l, _angle)) {
        rings[math.min(_rings - 1, (p.distance * _rings).floor())]++;
      }
      // Counts per unit area: ring k spans (k/8)..((k+1)/8), area ~ 2k+1.
      double density(int k) => rings[k] / (2 * k + 1);
      expect(density(_rings - 1), greaterThan(1.5 * density(0)));
      expect(density(_rings - 2), greaterThan(density(1)));
    });
  });

  group('alpha', () {
    test('behind the number is dimmer than the rim, at the same depth', () {
      for (final t in <double>[0.3, 0.6, 0.9]) {
        final centre = sphereDotAlpha(t, 0.05, 0.4, dark: true);
        final rim = sphereDotAlpha(t, 0.98, 0.4, dark: true);
        expect(centre, lessThan(rim * 0.5), reason: 't=$t');
      }
    });

    test('front is brighter than back, at the same place', () {
      for (final rho in <double>[0.05, 0.5, 0.98]) {
        expect(
          sphereDotAlpha(1, rho, 0.4, dark: true),
          greaterThan(sphereDotAlpha(0, rho, 0.4, dark: true)),
        );
      }
    });

    testWidgets('and the painted colours agree with the formula', (
      tester,
    ) async {
      await _pump(tester);
      final frame = _painter(tester).frame;
      final l = SphereLattice.forCount(frame.count);
      final points = _project(l, _angle);
      var centre = 0.0, centreN = 0, rim = 0.0, rimN = 0;
      for (int i = 0; i < frame.count; i++) {
        if (l.sparkle[i] == 1) continue;
        final a = _alphaOf(frame.colors[i]) / 255;
        if (points[i].distance < 0.15) {
          centre += a;
          centreN++;
        } else if (points[i].distance > 0.9) {
          rim += a;
          rimN++;
        }
      }
      expect(centreN, greaterThan(0));
      expect(rimN, greaterThan(0));
      expect(centre / centreN, lessThan(rim / rimN));
    });
  });

  group('colour', () {
    testWidgets('the atlas is tinted with the Indigo accent, nothing else', (
      tester,
    ) async {
      await _pump(tester, accent: _indigo);
      final indigo = _theme(
        Brightness.dark,
        accent: _indigo,
      ).extension<HealtheeColors>()!;
      final forest = _theme(Brightness.dark).extension<HealtheeColors>()!;
      expect(indigo.accent, isNot(forest.accent));
      final rgb = indigo.accent.toARGB32() & 0xFFFFFF;
      final frame = _painter(tester).frame;
      for (int i = 0; i < frame.count; i++) {
        expect(frame.colors[i] & 0xFFFFFF, rgb);
      }
      // The verdict colours do not follow the accent.
      expect(indigo.fav, forest.fav);
      expect(indigo.unf, forest.unf);
    });
  });

  group('motion', () {
    testWidgets('reduced motion: no ticker, still at 0.6 rad', (tester) async {
      await _pump(tester, reduced: true);
      expect(await _settles(tester), isTrue);
      expect(_painter(tester).angle.value, kStillAngle);
    });

    testWidgets('motion on: it turns, and does not settle on screen', (
      tester,
    ) async {
      await _pump(tester);
      expect(await _settles(tester), isFalse);
      expect(_painter(tester).angle.value, isNot(kStillAngle));
    });

    testWidgets('scrolled far away it settles, and resumes without a jump', (
      tester,
    ) async {
      await _pump(tester, after: const SizedBox(height: 5000));
      expect(await _settles(tester), isFalse);

      final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
      scroll.position.jumpTo(3000);
      await tester.pump();
      expect(await _settles(tester), isTrue);
      final parked = _painter(tester).angle.value;

      scroll.position.jumpTo(0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final resumed = _painter(tester).angle.value;
      expect(resumed, greaterThanOrEqualTo(parked));
      // 100 ms of a 120 s turn is 0.005 rad: nothing like a jump.
      expect(resumed - parked, lessThan(0.05));
      expect(await _settles(tester), isFalse);
    });

    testWidgets('the app leaving the foreground pauses it', (tester) async {
      await _pump(tester);
      expect(await _settles(tester), isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(await _settles(tester), isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(await _settles(tester), isFalse);
    });
  });

  group('withheld', () {
    testWidgets('never rotates, still at 0.6', (tester) async {
      await _pump(tester, withheld: true);
      expect(await _settles(tester), isTrue);
      expect(_painter(tester).angle.value, kStillAngle);
    });

    testWidgets('every alpha is 0.35 of the live one', (tester) async {
      await _pump(tester, reduced: true);
      final live = List<int>.of(_painter(tester).frame.colors);
      await _pump(tester, withheld: true, reduced: true);
      final dim = _painter(tester).frame.colors;
      expect(dim.length, live.length);
      for (int i = 0; i < live.length; i++) {
        expect(
          (_alphaOf(dim[i]) - _alphaOf(live[i]) * kWithheldAlpha).abs(),
          lessThanOrEqualTo(1),
          reason: 'point $i',
        );
      }
    });
  });

  group('light', () {
    testWidgets('lays ink over the page: no glow, no additive blend', (
      tester,
    ) async {
      await _pump(tester, brightness: Brightness.light);
      expect(_painter(tester).dark, isFalse);
    });
  });
}
