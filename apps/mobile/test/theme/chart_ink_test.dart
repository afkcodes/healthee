/// The two quiet inks a chart draws with: the gridline and the reference line.
///
/// Both owner reports of 2026-08-06 are here: *"can we make the baseline line a
/// bit subtle in the charts as well gridlines are almost white"*. One of the two
/// was a genuine bug and the other was a judgement, and they are asserted
/// differently for that reason.
///
/// **The gridline was a bug.** `h_debt_bars`, `h_timing_chart` and
/// `h_stacked_sleep` each wrote `colors.line.withValues(alpha: 0.5)` — 0.7 in the
/// third — and `withValues` **replaces** the alpha instead of scaling it. That is
/// the exact mistake `chart_primitives.dart`'s `revealed()` exists to prevent,
/// one directory over. `line` is a 10% hairline, so on dark those gridlines were
/// white at 50% and 70%: five and seven times their intended weight, which is
/// what "almost white" was. On light they were near-black by the same multiple,
/// so neither theme was the one that worked.
///
/// **Nothing here pins a value.** Every assertion is a floor or a relationship,
/// because a pinned number fails the build when a value IMPROVES — the mistake
/// this repo has already made on `onAccent`. What is pinned is that the two
/// tokens are the roles they claim to be: `grid` is [HealtheeColors.line]
/// quieted and `reference` is [HealtheeColors.ink3] quieted, so neither can drift
/// into a hue nobody chose.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/shared/charts/chart_reference.dart';
import 'package:healthee/shared/charts/h_area.dart';
import 'package:healthee/shared/charts/h_stacked_sleep.dart';

import '../shared/_chart_probe.dart';

final Map<String, (HealtheeColors, ThemeData)> _themes =
    <String, (HealtheeColors, ThemeData)>{
      'light': (const HealtheeColors.light(), AppTheme.light),
      'dark': (const HealtheeColors.dark(), AppTheme.dark),
    };

/// WCAG relative luminance.
double _luminance(Color colour) {
  double channel(double value) => value <= 0.03928
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(colour.r) +
      0.7152 * channel(colour.g) +
      0.0722 * channel(colour.b);
}

/// WCAG contrast between two OPAQUE colours.
double _contrast(Color a, Color b) {
  final one = _luminance(a);
  final two = _luminance(b);
  return (math.max(one, two) + 0.05) / (math.min(one, two) + 0.05);
}

/// [ink] composited over [under], which is what the eye actually sees.
Color _over(Color ink, Color under) => Color.from(
  alpha: 1,
  red: ink.r * ink.a + under.r * (1 - ink.a),
  green: ink.g * ink.a + under.g * (1 - ink.a),
  blue: ink.b * ink.a + under.b * (1 - ink.a),
);

/// Whether two colours are the same hue at different alphas.
void _sameInk(
  Color quieter,
  Color louder,
  String reason, {
  double tol = 1 / 255,
}) {
  expect(quieter.r, closeTo(louder.r, tol), reason: reason);
  expect(quieter.g, closeTo(louder.g, tol), reason: reason);
  expect(quieter.b, closeTo(louder.b, tol), reason: reason);
}

void main() {
  for (final entry in _themes.entries) {
    final theme = entry.key;
    final colors = entry.value.$1;
    final material = entry.value.$2;

    group('$theme — the tokens are roles, quieted', () {
      test('GRID IS `ink`, QUIETER — never a colour of its own', () {
        // The colour kit draws the gridline as the ink at 6% (dark: pure white
        // at 6%, 10/255 off F5F5F7), not as the hairline.
        _sameInk(
          colors.grid,
          colors.ink,
          'grid must be the ink quieted',
          tol: 11 / 255,
        );
        expect(
          colors.grid.a,
          lessThan(0.10),
          reason: 'a rule inside a plot recedes behind the card edge',
        );
      });

      test('GRID IS STILL THERE — structure, not absence', () {
        // The failure in the other direction. A gridline nobody can see is a
        // chart with no scale, and "subtle" was never "gone".
        expect(colors.grid.a, greaterThan(0.02));
        expect(
          _contrast(_over(colors.grid, colors.surface), colors.surface),
          greaterThan(1.02),
        );
      });

      test('THE GRID IS THE QUIETEST INK ON THE CHART', () {
        final grid = _contrast(
          _over(colors.grid, colors.surface),
          colors.surface,
        );
        final reference = _contrast(
          _over(colors.reference, colors.surface),
          colors.surface,
        );
        expect(
          grid,
          lessThan(reference),
          reason: 'structure must sit under the line a series is read against',
        );
      });

      test('REFERENCE IS `ink2`, QUIETER — the owner’s "a bit subtle"', () {
        _sameInk(
          colors.reference,
          colors.ink2,
          'the reference is ink2 quieted',
        );
        expect(colors.reference.a, lessThan(1));
        expect(
          colors.reference.a,
          greaterThan(colors.grid.a),
          reason: 'a claim about a number outranks the grid behind it',
        );
      });

      test('REFERENCE IS CLEARLY VISIBLE — "quieter", not "gone"', () {
        expect(
          _contrast(_over(colors.reference, colors.surface), colors.surface),
          greaterThan(1.5),
        );
      });

      test('THE CAPTION DID NOT FOLLOW THE LINE DOWN, and that is measured', () {
        // `chart_reference.dart` records why: these are 9 px caps. At the
        // reference's own alpha the same text lands near 2:1. A hairline may sit
        // at the edge of perception; a word a reader has to read may not.
        expect(
          _contrast(colors.ink2, colors.surface),
          greaterThanOrEqualTo(4.5),
          reason:
              'caption text is ink2 at the floor (ink3 is axes/disabled '
              'only and cannot be text)',
        );
        expect(
          _contrast(_over(colors.reference, colors.surface), colors.surface),
          lessThan(_contrast(colors.ink2, colors.surface)),
          reason: 'the line still recedes behind the words naming it',
        );
      });
    });

    group('$theme — what the painters actually draw', () {
      testWidgets('a reference line is painted in `reference`, not in ink2', (
        tester,
      ) async {
        await tester.pumpWidget(
          chartHost(
            const HArea(
              <double>[60, 64, 71, 66, 62],
              color: Color(0xFF1F6F54),
              progress: 1,
              height: 52,
              references: <ChartReference>[
                ChartReference.personalBaseline(value: 56, label: 'resting 56'),
              ],
            ),
            theme: material,
          ),
        );
        await tester.pumpAndSettle();

        final painted = coloursOf(paintedBy(tester, find.byType(HArea)));
        expect(painted, contains(colors.reference.toARGB32()));
        expect(
          painted,
          isNot(contains(colors.ink2.toARGB32())),
          reason: 'opaque ink2 is what the owner asked us to quieten',
        );
      });

      testWidgets('a gridline is painted in `grid`, not in a scaled `line`', (
        tester,
      ) async {
        await tester.pumpWidget(
          chartHost(
            HStackedSleep(week(), progress: 1, height: 130),
            theme: material,
          ),
        );
        await tester.pumpAndSettle();

        final painted = coloursOf(
          paintedBy(tester, find.byType(HStackedSleep)),
        );
        expect(painted, contains(colors.grid.toARGB32()));
        // The two values this file exists to keep out of the app.
        expect(
          painted,
          isNot(contains(colors.line.withValues(alpha: 0.7).toARGB32())),
          reason: 'this is the "almost white" the owner reported',
        );
        // The 0.5 half of this pair retired on 2026-09-06 and the reason is
        // worth writing down: v02's `--line` is OPAQUE, so `line` at alpha 0.5
        // is no longer a mistake — it is exactly what `grid` is. The mistake
        // that replaces it is the louder one the prototype's own CSS invites
        // (`.gridline { stroke: var(--line) }`): the undimmed hairline, drawn
        // at full strength inside a plot.
        expect(
          painted,
          isNot(contains(colors.line.toARGB32())),
          reason: 'the undimmed hairline is the v02-shaped version of the bug',
        );
      });
    });
  }

  test('NO CHART DERIVES ITS OWN RULE FROM `line`', () {
    // The defect was not a bad number, it was three painters each doing the
    // arithmetic. `withValues` replaces the alpha it is handed, so every one of
    // those three was wrong by the same factor and none of them looked wrong in
    // a diff. One token, or the next chart makes the same mistake.
    final offenders = <String>[
      for (final file in Directory(
        'lib/shared/charts',
      ).listSync().whereType<File>())
        if (RegExp(r'colors\.line2?\.withValues\(').hasMatch(
          // Comments are where the defect is DESCRIBED, at three of these
          // sites. Stripping them is what keeps this a scan for code.
          file.readAsStringSync().replaceAll(RegExp(r'//[^\n]*'), ''),
        ))
          file.path,
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'these derive a rule from the hairline instead of naming '
          '`colors.grid`: $offenders',
    );
  });
}
