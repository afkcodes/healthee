/// The sphere's two additions for breathing: a scale that follows a listenable,
/// and a hue read from the enclosing tone. With neither, it is the sphere it
/// always was.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/core/theme/instrument_hues.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/shared/v02/instruments/age_sphere.dart';
import 'package:healthee/shared/v02/instruments/age_sphere_painter.dart';

Future<void> _pump(
  WidgetTester tester, {
  ValueNotifier<double>? breath,
  bool useFamily = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: ToneScope(
          tone: Tone.stress,
          child: Center(
            child: AgeSphere(
              canvas: 300,
              breath: breath,
              useFamily: useFamily,
              centre: const Text('centre'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 1200));
}

AgeSpherePainter _painter(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(
              find.descendant(
                of: find.byType(AgeSphere),
                matching: find.byWidgetPredicate(
                  (w) => w is CustomPaint && w.painter is AgeSpherePainter,
                ),
              ),
            )
            .painter!
        as AgeSpherePainter;

Finder get _breathScale => find.descendant(
  of: find.byType(AgeSphere),
  matching: find.byWidgetPredicate(
    (w) => w is Transform && w.transform.storage[0] != 1,
  ),
);

void main() {
  testWidgets('with no breath nothing is scaled, as before', (tester) async {
    await _pump(tester);
    expect(_breathScale, findsNothing);
    expect(_painter(tester).accent, isNot(equals(_stress(tester))));
  });

  testWidgets('the dots follow the breath and the centre does not', (
    tester,
  ) async {
    final breath = ValueNotifier<double>(1);
    addTearDown(breath.dispose);
    await _pump(tester, breath: breath);
    final centre = tester.getSize(find.text('centre'));
    breath.value = 0.72;
    await tester.pump();
    expect(_breathScale, findsOneWidget);
    expect(tester.getSize(find.text('centre')), centre);
    final transform = tester.widget<Transform>(_breathScale);
    expect(transform.transform.storage[0], closeTo(0.72, 1e-9));
  });

  testWidgets('useFamily draws in the enclosing tone, not the accent', (
    tester,
  ) async {
    await _pump(tester, useFamily: true);
    expect(_painter(tester).accent, _stress(tester));
    expect(
      _painter(tester).accent,
      isNot(
        Theme.of(
          tester.element(find.byType(AgeSphere)),
        ).extension<HealtheeColors>()!.accent,
      ),
    );
  });
}

Color _stress(WidgetTester tester) => Theme.of(
  tester.element(find.byType(AgeSphere)),
).extension<InstrumentHues>()!.stress;
