/// The biological-age screen: the order it reads in, and the sheets that hold
/// what it no longer prints.
///
/// What this suite exists to hold:
///
///   * **The order.** Nav, title, receipt line, sphere, ruler, the dropdown, the
///     calculation row, the footnote, and nothing else between them.
///   * **Each fact once.** The delta is the sphere's verdict, not also a line of
///     text; the levers are one summary when shut and rows when open, never both.
///   * **The calculation is the payload's arithmetic**, built from
///     `chronological_age` and `contributions[]`, never a sentence written in.
///   * **`excluded` is not `withheld`.** The excluded lever's paragraph ships
///     verbatim in its sheet, with no retry; a withheld lever's sheet carries the
///     refusal and the consequence.
///   * **A paused estimate is explained**, with no number, no ruler, and the
///     dropdown already open on the lever that is missing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/models/biological_age.dart';
import 'package:healthee/data/models/today_snapshot.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/today/body_screen.dart';
import 'package:healthee/features/today/v02/age_calculation_sheet.dart';
import 'package:healthee/features/today/v02/age_lever_row.dart';
import 'package:healthee/features/today/v02/age_lever_sheets.dart';
import 'package:healthee/features/today/v02/age_levers.dart';
import 'package:healthee/features/today/v02/age_screen_parts.dart';
import 'package:healthee/features/today/v02/what_moves_it.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:healthee/shared/v02/comparison_bars.dart';
import 'package:healthee/shared/v02/instruments/age_ruler.dart';
import 'package:healthee/shared/v02/instruments/age_sphere.dart';
import 'package:healthee/shared/v02/instruments/age_waterfall.dart';
import 'package:healthee/shared/v02/instruments/vo2max_rail.dart';
import 'package:solar_icons/solar_icons.dart';

import '../_bio_age_stubs.dart';
import '../_today_stubs.dart';
import '_settings_harness.dart' show tallViewport;
import '_today_host.dart';

/// The first sentence of the server's own exclusion paragraph.
const String _exclusionOpening =
    'Sleep regularity is not one of the levers behind this number.';

/// The server's first fitness caveat, opening words.
const String _fitnessCaveat = 'The fitness term measures your VO₂max estimate';

Map<String, Object?> Function(Map<String, Object?>) _derivedAt(String? at) =>
    (json) => <String, Object?>{
      ...json,
      'as_of': <String, Object?>{
        ...(json['as_of']! as Map<String, Object?>),
        'derived_at': at,
      },
    };

void main() {
  late LocalStore store;

  setUp(() => store = LocalStore.memory());
  tearDown(() => store.close());

  Future<void> open(
    WidgetTester tester, {
    Map<String, Object?> Function(Map<String, Object?>)? mutate,
  }) async {
    tallViewport(tester);
    await tester.pumpWidget(
      todayHost(
        store,
        server: todayView(mutate: mutate),
        home: BodyScreen(now: now),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  double top(WidgetTester tester, Finder finder) =>
      tester.getTopLeft(finder.first).dy;

  group('the order the screen reads in', () {
    testWidgets('NAV, TITLE, RECEIPT, SPHERE, RULER, DROPDOWN, ROW, FOOTNOTE', (
      tester,
    ) async {
      await open(tester);

      final positions = <double>[
        top(tester, find.byIcon(SolarIconsOutline.infoCircle)),
        top(tester, find.text(kBodyTitle)),
        top(tester, find.textContaining(kAgeEstimateLine)),
        top(tester, find.byType(AgeSphere)),
        top(tester, find.byType(AgeRuler)),
        top(tester, find.text('What moves it')),
        top(tester, find.text(kAgeCalculationRow)),
        top(tester, find.text(kAgeFootnote)),
      ];
      expect(positions, orderedEquals(<double>[...positions]..sort()));
      expect(positions.toSet(), hasLength(positions.length));
    });

    testWidgets('THE RECEIPT SAYS Updated today ON THE SAME LOCAL DAY', (
      tester,
    ) async {
      await open(tester, mutate: _derivedAt(now.toIso8601String()));
      expect(
        find.text('Estimate, not a clinical age · Updated today'),
        findsOneWidget,
      );
    });

    testWidgets('AND HOW OLD IT IS OTHERWISE, FLOORED', (tester) async {
      // The fixture's receipt is four days before the pinned clock.
      await open(tester);
      expect(
        find.text('Estimate, not a clinical age · Updated 4 d ago'),
        findsOneWidget,
      );
    });

    testWidgets('NO RECEIPT, NO "Updated"', (tester) async {
      await open(tester, mutate: _derivedAt(null));
      expect(find.text(kAgeEstimateLine), findsOneWidget);
      expect(find.textContaining('Updated'), findsNothing);
    });

    test('a receipt that is not a time is no receipt', () {
      expect(ageUpdatedLine('yesterday-ish', now), kAgeEstimateLine);
    });

    testWidgets('THE INFO BUTTON OPENS THE EXPLAINER WITH THE DISCLAIMER', (
      tester,
    ) async {
      await open(tester);
      await tapAndSettle(tester, find.byIcon(SolarIconsOutline.infoCircle));

      expect(find.text('Biological age (estimate)'), findsOneWidget);
      expect(
        find.textContaining('not a clinical or diagnostic age'),
        findsWidgets,
      );
      // The caveats are reachable here too.
      expect(find.textContaining(_fitnessCaveat), findsOneWidget);
    });
  });

  group('each fact is said once', () {
    testWidgets('THE DELTA IS THE SPHERE’S VERDICT, NOT ALSO A LINE', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('34.3'), findsOneWidget);
      expect(find.text('1.7 years younger'), findsOneWidget);
      // The ruler lights a span; it does not print the delta.
      expect(find.textContaining('1.7'), findsNWidgets(2));
    });

    testWidgets('SHUT, THE LEVERS ARE ONE LINE; OPEN, THEY ARE THE ROWS', (
      tester,
    ) async {
      await open(tester);
      expect(find.byKey(WhatMovesIt.summaryKey), findsOneWidget);
      expect(find.byKey(AgeLeverCard.cardKey), findsNothing);

      await tapAndSettle(tester, find.byKey(WhatMovesIt.headerKey));
      expect(find.byKey(WhatMovesIt.summaryKey), findsNothing);
      expect(find.byKey(AgeLeverCard.cardKey), findsOneWidget);
      expect(find.byKey(leverRowKey('fitness')), findsOneWidget);
      expect(find.byKey(leverRowKey('sleep duration')), findsOneWidget);
    });
  });

  group('the sheets hold what the screen no longer prints', () {
    testWidgets('A LEVER ROW OPENS ITS METHOD LINES AND ITS CAVEATS', (
      tester,
    ) async {
      await open(tester);
      await tapAndSettle(tester, find.byKey(WhatMovesIt.headerKey));
      await tapAndSettle(tester, find.byKey(leverRowKey('fitness')));

      expect(find.textContaining(kFitnessTermNote), findsOneWidget);
      expect(find.textContaining('Read by'), findsOneWidget);
      expect(find.textContaining('VO₂max estimate 43.0'), findsOneWidget);
      expect(find.textContaining('Age-model target 40.0'), findsOneWidget);
      expect(find.byType(Vo2maxRail), findsOneWidget);
      expect(find.textContaining(_fitnessCaveat), findsOneWidget);
      // Only the fitness caveats: the sleep one is the sleep lever's.
      expect(
        find.textContaining('Your sleep hours are translated'),
        findsNothing,
      );
    });

    testWidgets('THE SLEEP ROW OPENS THE TWO HOURS AND THE TRANSLATION', (
      tester,
    ) async {
      await open(tester);
      await tapAndSettle(tester, find.byKey(WhatMovesIt.headerKey));
      await tapAndSettle(tester, find.byKey(leverRowKey('sleep duration')));

      expect(find.textContaining(kSleepTermNote), findsOneWidget);
      expect(find.textContaining('6.3 h wearable average'), findsOneWidget);
      expect(find.textContaining('Compared as 7.0 h'), findsWidgets);
      expect(find.byType(ComparisonBars), findsOneWidget);
      expect(
        find.textContaining('Your sleep hours are translated'),
        findsOneWidget,
      );
      expect(find.textContaining(_fitnessCaveat), findsNothing);
    });

    testWidgets('THE EXCLUDED ROW SHIPS THE SERVER’S PARAGRAPH VERBATIM', (
      tester,
    ) async {
      await open(tester);
      await tapAndSettle(tester, find.byKey(WhatMovesIt.headerKey));
      await tapAndSettle(tester, find.byKey(leverRowKey('regularity')));

      // The row keeps the first sentence; the sheet has all of them.
      expect(find.textContaining(_exclusionOpening), findsWidgets);
      expect(
        find.textContaining('what we cannot honestly do is convert'),
        findsOneWidget,
      );
      expect(find.text('Still visible in Sleep'), findsOneWidget);
      // No retry: the owner can do nothing about this one.
      expect(find.widgetWithText(FilledButton, 'Try again'), findsNothing);
    });

    testWidgets('HOW THIS IS CALCULATED OPENS THE LADDER AND THE EQUATION', (
      tester,
    ) async {
      await open(tester);
      await tapAndSettle(tester, find.text(kAgeCalculationRow));

      expect(find.byType(AgeWaterfall), findsOneWidget);
      expect(
        find.text(
          '36 chronological years − 1.7 fitness + 0.0 sleep duration '
          '= 34.3 modelled years.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining(kConfidenceNote), findsOneWidget);
      expect(find.textContaining(_fitnessCaveat), findsOneWidget);
      // The note licensing the estimate is a source on this sheet.
      expect(find.textContaining('biological_age_estimate'), findsNothing);
    });

    test('the equation reads the contributions it was given', () {
      final age = BiologicalAge.maybe(
        loadTodayJson()['biological_age']! as Map<String, Object?>,
      )!;
      expect(ageEquation(age, 36), contains('− 1.7 fitness'));
      // A term the model stopped sending stops appearing, because the sentence
      // is a fold over the list rather than a template with two slots.
      const bare = BiologicalAge(
        biologicalAge: 34.3,
        chronologicalAge: 36,
        deltaYears: -1.7,
        contributions: <AgeContribution>[],
        disclaimer: null,
        researchNotes: <String>[],
      );
      expect(
        ageEquation(bare, 36),
        '36 chronological years = 34.3 modelled years.',
      );
    });

    test(
      'A WITHHELD LEVER’S SHEET CARRIES THE REFUSAL AND THE CONSEQUENCE',
      () {
        final snapshot = TodaySnapshot.fromJson(
          pausedToday(absentTerms: <Map<String, Object?>>[staleWeightTerm()])(
            loadTodayJson(),
          ),
        );
        final sheet = leverSheetFor(
          'fitness',
          block: snapshot.bioAgeBlock,
          caveats: const [],
        )!;
        final said = sheet.detail.disclosures.map((d) => d.message).toList();
        expect(said, contains(kStaleWeightMessage));
        expect(said, contains(kRequiredTermsMessage));
      },
    );

    test('a term the block does not name opens nothing', () {
      final snapshot = TodaySnapshot.fromJson(loadTodayJson());
      expect(
        leverSheetFor(
          'hydration',
          block: snapshot.bioAgeBlock,
          caveats: const [],
        ),
        isNull,
      );
    });
  });

  group('excluded is not counted twice', () {
    test('the caveats do not repeat the exclusion', () {
      final snapshot = TodaySnapshot.fromJson(loadTodayJson());
      final detail = BodyDetail(snapshot: snapshot, reveals: RevealRegistry());
      expect(detail.exclusions, hasLength(1));
      expect(detail.exclusions.single.message, contains(_exclusionOpening));
      // The three caveats stay; the exclusion that rode in with them does not.
      expect(detail.caveats, isNotEmpty);
      expect(detail.caveats, isNot(contains(detail.exclusions.single)));
    });

    test('THE COMPARISON SCALE COMES FROM THE DATA, NOT FROM AN AXIS', () {
      const bars = <ComparisonBar>[
        ComparisonBar('Wearable', 6.3, '6.3h'),
        ComparisonBar('Compared as', 7, '7.0h'),
      ];
      expect(ComparisonBars.scaleOf(bars), 7.0);
      expect(
        ComparisonBars.scaleOf(const <ComparisonBar>[
          ComparisonBar('Wearable', null, '—'),
        ]),
        isNull,
      );
    });
  });
}
