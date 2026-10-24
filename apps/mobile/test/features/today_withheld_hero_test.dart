/// A paused biological age is still a HERO, and it is never a number.
///
/// Owner reports, one card: *"today is there the bio age and all those are
/// missing"* (it collapsed to a dashed box plus the regularity essay), and
/// *"it should show the old one"*, which was answered with a dated held value
/// and is now answered the other way: **no number, and a stated reason.** The
/// brief for this step is explicit that a paused estimate shows no figure.
///
/// Everything asserted here is painted: the orb's rect, the hero's width, the
/// absence of any painter that could place a marker, and the absence of every
/// digit the live hero would have drawn.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/today/v02/age_paused.dart';
import 'package:healthee/features/today/v02/today_hero_withheld.dart';
import 'package:healthee/shared/metric_info/metric_info_sheet.dart';
import 'package:healthee/shared/v02/age_orb_hero.dart';
import 'package:healthee/shared/v02/instruments/age_ruler.dart';
import 'package:healthee/shared/v02/instruments/age_sphere.dart';
import 'package:healthee/shared/v02/withheld_panel.dart';

import '../_bio_age_stubs.dart';
import '../_today_stubs.dart';
import '_today_host.dart';

/// The regularity exclusion's opening, as the contract snapshot carries it.
const String kExclusionEssay = 'Scored on the same 70,000 people';

/// The payload the owner's phone actually receives: no number, a composite
/// withheld block with a stale weight, and the standing exclusion beside it.
Map<String, Object?> withheldAge(Map<String, Object?> json) =>
    pausedToday(absentTerms: <Map<String, Object?>>[staleWeightTerm()])(json);

void main() {
  late LocalStore store;

  setUp(() async {
    store = LocalStore.memory();
    await seedDevice(store);
  });
  tearDown(() async => store.close());

  void phone(WidgetTester tester) {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<void> pump(WidgetTester tester) async {
    phone(tester);
    await tester.pumpWidget(
      todayHost(store, server: todayView(mutate: withheldAge)),
    );
    await tester.pumpAndSettle();
  }

  group('the hero keeps its shape when the number is paused', () {
    testWidgets('SAME ORB, SAME TITLE, SAME WIDTH', (tester) async {
      phone(tester);
      await tester.pumpWidget(todayHost(store));
      await tester.pumpAndSettle();
      final live = tester.getRect(find.byType(AgeOrbHero));
      final liveOrb = tester.getRect(find.byType(AgeSphere));
      final liveTitle = tester.getRect(find.text(kAgeOrbTitle));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await pump(tester);

      expect(find.byType(TodayBioHeroWithheld), findsOneWidget);
      expect(
        find.byType(WithheldPanel),
        findsNothing,
        reason: 'the paused hero must not collapse into a dashed box',
      );
      final refused = tester.getRect(find.byType(AgeOrbHero));
      expect(refused.width, live.width);
      expect(refused.left, live.left);
      final orb = tester.getRect(find.byType(AgeSphere));
      expect(orb.size, liveOrb.size);
      expect(orb.left, liveOrb.left);
      expect(tester.getRect(find.text(kAgeOrbTitle)).left, liveTitle.left);
    });

    testWidgets('THE ESSAY IS NOT INLINE; THE SERVER REASON IS', (
      tester,
    ) async {
      await pump(tester);

      expect(find.textContaining(kExclusionEssay), findsNothing);
      expect(find.textContaining('silently assert you sit'), findsNothing);
      // The reason the old card hid behind the ⓘ is the card now.
      expect(find.text(kAgePausedTitle), findsOneWidget);
      expect(find.text(kStaleWeightMessage), findsOneWidget);
      expect(
        find.textContaining('Left out of this number: regularity'),
        findsOneWidget,
      );
    });

    testWidgets('NO NUMBER AND NO MARKER IS DRAWN', (tester) async {
      await pump(tester);

      expect(find.byType(AgeRuler), findsNothing);
      expect(find.text('YEARS'), findsNothing);
      expect(find.text('FITNESS'), findsNothing);
      expect(find.textContaining('years younger'), findsNothing);
      // The only digits in the hero are the stale-weight caption's.
      final digits = find.descendant(
        of: find.byType(AgeOrbHero),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              widget.data != null &&
              RegExp(r'^\d+(\.\d)?$').hasMatch(widget.data!),
        ),
      );
      expect(digits, findsNothing);
    });

    testWidgets('THE SPHERE DOES NOT TURN AROUND AN ABSENT NUMBER', (
      tester,
    ) async {
      phone(tester);
      await tester.pumpWidget(
        todayHost(
          store,
          server: todayView(mutate: withheldAge),
          reducedMotion: false,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(tester.widget<AgeSphere>(find.byType(AgeSphere)).withheld, isTrue);
      var settled = true;
      try {
        await tester.pumpAndSettle(
          const Duration(milliseconds: 33),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 1),
        );
      }
      // ignore: avoid_catching_errors
      on FlutterError {
        settled = false;
      }
      expect(settled, isTrue);
    });
  });

  group('the full explanation is behind the ⓘ', () {
    testWidgets('THE CONSEQUENCE, THE REMEDY AND THE EXCLUSION ARE ALL THERE', (
      tester,
    ) async {
      await pump(tester);

      await tester.tap(
        find.descendant(
          of: find.byType(AgeOrbHero),
          matching: find.byType(MetricInfoDot),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('silently assert you sit'), findsOneWidget);
      expect(find.textContaining(kExclusionEssay), findsOneWidget);
    });
  });
}
