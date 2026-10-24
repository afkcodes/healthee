/// The biological-age screen when the estimate is paused: it is explained, with
/// no number and no ruler, the dropdown is already open on the lever that is
/// missing, and the server's sentence is said once, in the notice, rather than
/// again in the withheld lever's row.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/today/body_screen.dart';
import 'package:healthee/features/today/v02/age_calculation_sheet.dart';
import 'package:healthee/features/today/v02/age_lever_row.dart';
import 'package:healthee/features/today/v02/age_levers.dart';
import 'package:healthee/features/today/v02/age_paused.dart';
import 'package:healthee/features/today/v02/age_screen_parts.dart';
import 'package:healthee/features/today/v02/what_moves_it.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:healthee/shared/v02/instruments/age_ruler.dart';
import 'package:healthee/shared/v02/instruments/age_sphere.dart';
import 'package:healthee/shared/v02/instruments/age_waterfall.dart';
import 'package:solar_icons/solar_icons.dart';

import '../_bio_age_stubs.dart';
import '../_today_stubs.dart';
import '_settings_harness.dart' show tallViewport;
import '_today_host.dart';

/// The server's first fitness caveat, opening words.
const String _fitnessCaveat = 'The fitness term measures your VO₂max estimate';

void main() {
  late LocalStore store;

  setUp(() => store = LocalStore.memory());
  tearDown(() => store.close());

  Future<void> openPaused(WidgetTester tester) async {
    tallViewport(tester);
    await tester.pumpWidget(
      todayHost(
        store,
        server: todayView(
          mutate: pausedToday(
            absentTerms: <Map<String, Object?>>[staleWeightTerm()],
          ),
        ),
        home: BodyScreen(now: now),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  group('a paused estimate', () {
    testWidgets('SAYS WHY, WITH NO NUMBER AND NO RULER', (tester) async {
      await openPaused(tester);

      expect(find.text(kAgePausedTitle), findsOneWidget);
      expect(find.textContaining('Log a weight and it returns'), findsWidgets);
      expect(find.text('34.3'), findsNothing);
      expect(find.byType(AgeRuler), findsNothing);
      expect(tester.widget<AgeSphere>(find.byType(AgeSphere)).withheld, isTrue);
    });

    testWidgets(
      'THE SERVER SENTENCE IS SAID ONCE, NOT AGAIN IN THE LEVER ROW',
      (tester) async {
        await openPaused(tester);

        // Above the card, in the notice: the reason in the server's own words.
        expect(find.text(kStaleWeightMessage), findsOneWidget);
        // In the withheld row: only that it is not counted, and where to look.
        final row = find.byKey(leverRowKey('fitness'));
        expect(
          find.descendant(of: row, matching: find.text('Not counted')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: row, matching: find.text(kReasonAbove)),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: row,
            matching: find.textContaining('Log a weight'),
          ),
          findsNothing,
        );
      },
    );

    testWidgets('A SCREEN WITH NO NOTICE KEEPS THE SENTENCE IN THE ROW', (
      tester,
    ) async {
      // The card on its own (no notice above it) is the only place the reason
      // can be read, so it still says it.
      tallViewport(tester);
      final block = todayView(
        mutate: pausedToday(
          absentTerms: <Map<String, Object?>>[staleWeightTerm()],
        ),
      ).snapshot.bioAgeBlock;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: AgeLeverCard(block: block, reveals: RevealRegistry()),
            ),
          ),
        ),
      );
      expect(find.text(kStaleWeightMessage), findsOneWidget);
      expect(find.text(kReasonAbove), findsNothing);
    });

    testWidgets('OPENS THE DROPDOWN ON THE SLEEP ROW AND THE MISSING FITNESS', (
      tester,
    ) async {
      await openPaused(tester);

      expect(find.byKey(WhatMovesIt.summaryKey), findsNothing);
      expect(find.byKey(leverRowKey('sleep duration')), findsOneWidget);
      expect(find.text('Not counted'), findsOneWidget);
      // The absent term is words, with no zone bar and no invented zero.
      expect(find.byKey(leverRowKey('fitness')), findsOneWidget);
      expect(find.text('-1.7'), findsNothing);
    });

    testWidgets('STILL NAMES WHAT IS EXCLUDED, AND THE CAVEATS REACH THE ⓘ', (
      tester,
    ) async {
      await openPaused(tester);
      expect(find.textContaining('Left out'), findsWidgets);

      final detail = tester.widget<BodyDetail>(find.byType(BodyDetail));
      expect(detail.caveats, hasLength(3));
      await tapAndSettle(tester, find.byIcon(SolarIconsOutline.infoCircle));
      expect(find.textContaining(_fitnessCaveat), findsOneWidget);
    });

    testWidgets('THE CALCULATION ROW HAS NO LADDER TO DRAW', (tester) async {
      await openPaused(tester);
      await tapAndSettle(tester, find.text(kAgeCalculationRow));

      expect(find.byType(AgeWaterfall), findsNothing);
      expect(find.textContaining(kConfidenceNote), findsOneWidget);
    });
  });
}
