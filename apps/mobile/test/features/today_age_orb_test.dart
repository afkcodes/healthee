/// Today's biological-age hero: on the page, one door, and nothing that the
/// Biological age screen already says.
///
/// Label and ⓘ, the sphere with the figure inside it, one Callout of what moved
/// the estimate, one Caption saying it is not clinical. No ruler, no stat
/// columns, no slider. A tap anywhere on it opens the Biological age screen.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/today/body_screen.dart';
import 'package:healthee/features/today/today_screen.dart';
import 'package:healthee/features/today/v02/today_hero.dart';
import 'package:healthee/shared/metric_info/metric_info_sheet.dart';
import 'package:healthee/shared/v02/age_orb_hero.dart';
import 'package:healthee/shared/v02/instruments/age_ruler.dart';
import 'package:healthee/shared/v02/instruments/age_sphere.dart';
import 'package:healthee/shared/v02/instruments/age_sphere_painter.dart';

import '../_bio_age_stubs.dart';
import '../_today_stubs.dart';
import '_hero_probe.dart';
import '_today_host.dart';

/// The committed payload's breakdown: fitness and sleep priced, regularity
/// never counted.
const String kPayloadBreakdown =
    'Fitness −1.7 years · Sleep 0.0 years · Regularity left out';

void main() {
  setUpAll(loadFigtree);
  late LocalStore store;

  setUp(() async {
    store = LocalStore.memory();
    await seedDevice(store);
  });
  tearDown(() async => store.close());

  void phone(WidgetTester tester, double width) {
    tester.view
      ..physicalSize = Size(width, 3000)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  for (final width in kPhoneWidths) {
    testWidgets('$width — the orb fits, and everything is inside the hero', (
      tester,
    ) async {
      phone(tester, width);
      await tester.pumpWidget(todayHost(store));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'no overflow at $width');

      final hero = tester.getRect(find.byType(AgeOrbHero));
      final orb = tester.getRect(find.byType(AgeSphere));
      final inner = hero.width - 2 * AgeOrbHero.side;
      expect(orb.width, closeTo(math.min(inner, AgeOrbHero.orbMax), 0.5));
      expect(orb.center.dx, closeTo(hero.center.dx, 0.5), reason: 'centred');
      final figure = tester.getRect(find.text('34.3'));
      expect(orb.contains(figure.center), isTrue);
      expect(
        figure.center.dx,
        closeTo(orb.center.dx, 0.5),
        reason: 'the number is centred in the sphere',
      );
      for (final part in <Finder>[
        find.descendant(
          of: find.byType(AgeOrbHero),
          matching: find.byType(MetricInfoDot),
        ),
        find.text(kPayloadBreakdown),
        find.text(kAgeNotClinical),
      ]) {
        final rect = tester.getRect(part);
        expect(hero.contains(rect.topLeft), isTrue, reason: '$part');
        expect(hero.contains(rect.bottomRight - const Offset(1, 1)), isTrue);
      }
    });

    for (final scale in <double>[1.3]) {
      testWidgets('$width at text scale $scale — nothing clips', (
        tester,
      ) async {
        phone(tester, width);
        await tester.pumpWidget(
          todayHost(
            store,
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: TodayScreen(now: now),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'no overflow');

        final hero = tester.getRect(find.byType(AgeOrbHero));
        final orb = tester.getRect(find.byType(AgeSphere));
        final figure = tester.getRect(find.text('34.3'));
        expect(orb.contains(figure.topLeft), isTrue, reason: 'figure in orb');
        expect(orb.contains(figure.bottomRight - const Offset(1, 1)), isTrue);
        for (final line in <Finder>[
          find.text(kPayloadBreakdown),
          find.text(kAgeNotClinical),
        ]) {
          final rect = tester.getRect(line);
          expect(hero.contains(rect.topLeft), isTrue);
          expect(hero.contains(rect.bottomRight - const Offset(1, 1)), isTrue);
          expect(rect.top, greaterThanOrEqualTo(orb.bottom - 1));
        }
      });
    }
  }

  testWidgets('the orb paints, and it paints no reading', (tester) async {
    phone(tester, 390);
    await tester.pumpWidget(todayHost(store));
    await tester.pumpAndSettle();
    final painter = tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(AgeSphere),
            matching: find.byType(CustomPaint),
          ),
        )
        .map((paint) => paint.painter)
        .whereType<AgeSpherePainter>()
        .single;
    // Decoration only: the painter is built from colours, never a value.
    expect(painter.shouldRepaint(painter), isFalse);
  });

  group('what the hero says', () {
    testWidgets('THE BREAKDOWN LINE IS THE PAYLOAD’S OWN TERMS', (
      tester,
    ) async {
      phone(tester, 390);
      await tester.pumpWidget(todayHost(store));
      await tester.pumpAndSettle();

      final bio = loadTodayJson()['biological_age']! as Map<String, Object?>;
      final terms = <String, double>{
        for (final c in bio['contributions']! as List<Object?>)
          (c! as Map<String, Object?>)['term']! as String:
              ((c as Map<String, Object?>)['delta_years']! as num).toDouble(),
      };
      // The fixture really does carry the two terms the line names.
      expect(terms['fitness'], -1.7);
      expect(terms['sleep duration']!.abs(), lessThan(0.05));
      expect(find.text(kPayloadBreakdown), findsOneWidget);
    });

    testWidgets('A CHANGED PAYLOAD CHANGES THE LINE', (tester) async {
      phone(tester, 390);
      await tester.pumpWidget(
        todayHost(
          store,
          server: todayView(
            mutate: (json) {
              final bio = json['biological_age']! as Map<String, Object?>;
              return <String, Object?>{
                ...json,
                'biological_age': <String, Object?>{
                  ...bio,
                  'contributions': <Object?>[
                    for (final c in bio['contributions']! as List<Object?>)
                      (c! as Map<String, Object?>)['term'] == 'fitness'
                          ? <String, Object?>{
                              ...(c as Map<String, Object?>),
                              'delta_years': 2.4,
                            }
                          : c,
                  ],
                },
              };
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Fitness +2.4 years'), findsOneWidget);
      expect(find.textContaining('−1.7'), findsNothing);
    });

    testWidgets('NO RULER, NO COLUMNS, NO SLIDER ON TODAY', (tester) async {
      phone(tester, 390);
      await tester.pumpWidget(todayHost(store));
      await tester.pumpAndSettle();

      expect(find.byType(AgeRuler), findsNothing);
      expect(find.text('AGAINST YOUR AGE'), findsNothing);
      expect(find.text('FITNESS'), findsNothing);
      expect(find.text('SLEEP'), findsNothing);
      expect(find.text('Younger'), findsNothing);
    });

    testWidgets('THE NOT-CLINICAL DISCLAIMER IS UNDER THE ESTIMATE', (
      tester,
    ) async {
      phone(tester, 390);
      await tester.pumpWidget(todayHost(store));
      await tester.pumpAndSettle();

      final line = tester.getRect(find.text(kAgeNotClinical));
      expect(line.top, greaterThan(tester.getRect(find.text('34.3')).bottom));
      expect(
        line.top,
        greaterThan(tester.getRect(find.text(kPayloadBreakdown)).top),
      );
      // The full disclaimer stays reachable behind the ⓘ.
      final model = tester
          .widget<AgeOrbHero>(find.byType(AgeOrbHero))
          .modelLabel!;
      expect(find.text(model), findsNothing, reason: 'off the face');
      await tester.tap(
        find.descendant(
          of: find.byType(AgeOrbHero),
          matching: find.byType(MetricInfoDot),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining(model), findsOneWidget);
    });

    testWidgets('A SHORT SERVER DISCLAIMER IS THE CAPTION, A LONG ONE IS NOT', (
      tester,
    ) async {
      final long = todayView().snapshot.biologicalAge.valueOrNull!;
      expect(long.disclaimer!.length, greaterThan(kAgeCaptionMaxChars));
      expect(TodayBioHero.captionOf(long), kAgeNotClinical);

      phone(tester, 390);
      await tester.pumpWidget(
        todayHost(
          store,
          server: todayView(
            mutate: (json) => <String, Object?>{
              ...json,
              'biological_age': <String, Object?>{
                ...json['biological_age']! as Map<String, Object?>,
                'disclaimer': 'Not a clinical age.',
              },
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Not a clinical age.'), findsOneWidget);
      expect(find.text(kAgeNotClinical), findsNothing);
    });

    testWidgets('ONE SEMANTICS LABEL SPEAKS THE WHOLE HERO', (tester) async {
      phone(tester, 390);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(todayHost(store));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel(
          'Biological age 34.3 years, 1.7 years younger than your age. '
          'Fitness minus 1.7 years, sleep 0.0 years, regularity left out. '
          'Opens the breakdown.',
        ),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('the hero is the door', () {
    testWidgets('A TAP ON THE SPHERE OPENS THE BIOLOGICAL AGE SCREEN', (
      tester,
    ) async {
      phone(tester, 390);
      await tester.pumpWidget(routedApp(store));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(AgeSphere));
      await tester.pumpAndSettle();
      expect(find.byType(BodyScreen), findsOneWidget);
    });

    testWidgets('AND SO DOES A TAP ON THE LINE UNDER IT', (tester) async {
      phone(tester, 390);
      await tester.pumpWidget(routedApp(store));
      await tester.pumpAndSettle();

      await tester.tap(find.text(kAgeNotClinical));
      await tester.pumpAndSettle();
      expect(find.byType(BodyScreen), findsOneWidget);
    });

    testWidgets('THE ⓘ OPENS ITS SHEET AND NOT THE SCREEN', (tester) async {
      phone(tester, 390);
      await tester.pumpWidget(routedApp(store));
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byType(AgeOrbHero),
          matching: find.byType(MetricInfoDot),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BodyScreen), findsNothing);
    });

    testWidgets('A PAUSED HERO IS THE SAME DOOR', (tester) async {
      phone(tester, 390);
      await tester.pumpWidget(
        routedApp(
          store,
          server: todayView(
            mutate: pausedToday(
              absentTerms: <Map<String, Object?>>[staleWeightTerm()],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(AgeSphere));
      await tester.pumpAndSettle();
      expect(find.byType(BodyScreen), findsOneWidget);
    });
  });
}
