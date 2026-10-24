/// The orb is IN the hero, it TURNS there, and it STOPS when it leaves.
///
/// `age_sphere.dart` turns its dots slowly and stops under reduced
/// motion. What a widget test of it alone cannot prove is that Today wired it
/// up: a hero that dropped the orb would pass every one of those tests.
///
/// So this suite asks the screen. The observable is **whether the tree ever goes
/// idle**, which is the one thing a running ticker changes and the one thing a
/// presence check cannot see:
///
///   * with motion allowed, `pumpAndSettle` on Today times out — something is
///     animating, and the orb is the only ambient thing on the screen;
///   * scrolled far past the hero, it settles — the lazy list let it go.
///
/// Every other suite in this directory pumps `todayHost` with reduced motion on
/// for exactly this reason (see its docstring). This one turns it off.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/today/steps_plateau.dart';
import 'package:healthee/features/today/today_labels.dart';
import 'package:healthee/features/today/v02/today_key_numbers.dart';
import 'package:healthee/shared/metric_info/metric_info_sheet.dart';
import 'package:healthee/shared/v02/age_orb_hero.dart';
import 'package:healthee/shared/v02/instruments/age_sphere.dart';
import 'package:healthee/shared/v02/key_number_card.dart';

import '../_today_stubs.dart';
import '_today_host.dart';

/// Whether the tree reaches idle inside a second.
///
/// `pumpAndSettle` throws on a timeout and both it and `expectLater` are guarded
/// against overlapping, so the throw is caught here rather than matched — see
/// `test_async_utils.dart`. A `bool` is also the thing the assertion is about.
Future<bool> _settles(WidgetTester tester) async {
  try {
    await tester.pumpAndSettle(
      const Duration(milliseconds: 33),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 1),
    );
    return true;
  }
  // `pumpAndSettle`'s timeout IS a `FlutterError`, and that timeout is the
  // observation this helper exists to make. There is no exception form of it
  // to catch instead, and catching `Object` would swallow a real failure.
  // ignore: avoid_catching_errors
  on FlutterError {
    return false;
  }
}

void main() {
  late LocalStore store;

  setUp(() async {
    store = LocalStore.memory();
    await seedDevice(store);
  });
  tearDown(() async => store.close());

  /// A phone-sized viewport, so the hero can actually be scrolled off it.
  void phone(WidgetTester tester) {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  /// Tall enough that the `ListView.builder` builds the whole port in one pass.
  void tall(WidgetTester tester) {
    tester.view
      ..physicalSize = const Size(420, 14000)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('THE SPHERE IS INSIDE THE HERO, AROUND THE FIGURE', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(todayHost(store));
    await tester.pumpAndSettle();

    expect(find.byType(AgeOrbHero), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AgeOrbHero),
        matching: find.byType(AgeSphere),
      ),
      findsOneWidget,
      reason: 'the orb belongs around the figure, not somewhere near it',
    );
    // The figure is laid out inside the orb's own box.
    final halo = tester.getRect(find.byType(AgeSphere));
    final figure = tester.getRect(find.text('34.3'));
    expect(halo.contains(figure.center), isTrue);
  });

  testWidgets('IT RUNS ON SCREEN, AND PAUSES WHEN IT SCROLLS AWAY', (
    tester,
  ) async {
    // The observable is whether the tree can ever go idle. A 30 fps ambient
    // field makes `pumpAndSettle` time out, and nothing else on Today animates
    // forever — every other reveal is once-and-done. So: it must NOT settle
    // while the hero is on screen, and it must settle once the hero is not.
    //
    // That is a stronger check than "a ticker exists", which is true of the
    // pull-to-refresh indicator too.
    phone(tester);
    await tester.pumpWidget(todayHost(store, reducedMotion: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      await _settles(tester),
      isFalse,
      reason: 'the orb is not turning, so the hero is a still image',
    );

    // Off screen: the lazy list drops the hero, and its ticker with it.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
    await tester.pump();

    expect(
      await _settles(tester),
      isTrue,
      reason: 'an orb that keeps turning off screen is frames of nothing',
    );
  });

  testWidgets('REDUCED MOTION STOPS IT DEAD, ON THE REAL SCREEN', (
    tester,
  ) async {
    // The accessibility path, asked of the screen rather than of the widget:
    // under reduced motion the tree SETTLES, which a live 30 fps field makes
    // impossible. Every other suite in this directory depends on it.
    phone(tester);
    await tester.pumpWidget(todayHost(store));
    await tester.pumpAndSettle();

    expect(find.byType(AgeSphere), findsOneWidget);
  });

  group('what the hero says about the estimate', () {
    testWidgets('the figure, the delta and the terms are the server’s', (
      tester,
    ) async {
      phone(tester);
      await tester.pumpWidget(todayHost(store));
      await tester.pumpAndSettle();

      expect(find.text('34.3'), findsOneWidget);
      expect(find.text('1.7 years younger'), findsOneWidget);
      expect(find.textContaining('Fitness −1.7 years'), findsOneWidget);
      // The sign is its own span, pulled in against the digits (a plain string
      // leaves a gap after U+2212).
      final line = tester.widget<Text>(
        find.descendant(
          of: find.byType(AgeOrbHero),
          matching: find.textContaining('Fitness −1.7 years'),
        ),
      );
      final signs = <TextSpan>[];
      line.textSpan!.visitChildren((span) {
        if (span is TextSpan && span.text == '−') {
          signs.add(span);
        }
        return true;
      });
      expect(signs, isNotEmpty);
      expect(
        signs.first.style!.letterSpacing,
        lessThan(0),
        reason: 'the minus is tightened, not left at the font default',
      );
      // The model line is ALWAYS reachable: an estimate that does not say what
      // made it is the failure the whole tier system exists to stop. It moved
      // off the card into the eyebrow's ⓘ, so this opens the ⓘ and reads it
      // there — the claim is that the owner can get to the sentence, not that
      // it is printed in nine-point grey under the contributions.
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

    testWidgets('NO DELTA MEANS NO SENTENCE ABOUT ONE', (tester) async {
      // Rather than "0.0 years below" about an age nothing compared.
      phone(tester);
      await tester.pumpWidget(
        todayHost(
          store,
          server: todayView(
            mutate: (json) => <String, Object?>{
              ...json,
              'biological_age': <String, Object?>{
                ...json['biological_age']! as Map<String, Object?>,
                'delta_years': null,
                'chronological_age': null,
              },
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('34.3'), findsOneWidget);
      expect(find.textContaining('years younger'), findsNothing);
      expect(find.textContaining('your age'), findsNothing);
    });
  });

  group('the three key numbers', () {
    testWidgets('A CARD WITH NO READING IS NAMED, HELD AND VISIBLY EMPTY', (
      tester,
    ) async {
      // Never a blank and never a zero: `—` with `Not measured.` under it, in a
      // card that keeps its slot so the stack does not change shape.
      tall(tester);
      await tester.pumpWidget(
        todayHost(
          store,
          server: todayView(
            mutate: (json) => <String, Object?>{
              ...json,
              'metrics': const <Object?>[],
              'recovery_score': null,
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final cards = find.byType(KeyNumberCard);
      expect(cards, findsNWidgets(3));
      final empty = find.byWidgetPredicate(
        (widget) =>
            widget is KeyNumberCard &&
            widget.value == '—' &&
            widget.lead == 'Not measured.',
      );
      // Recovery and movement have no reading in this payload.
      expect(empty, findsNWidgets(2));
      expect(find.byType(TodayKeyNumbers), findsOneWidget);
    });

    testWidgets('THE STEP TARGET IS THE NOTE’S BAND, NEVER A GUESS', (
      tester,
    ) async {
      // **The claim inverted for a reason, and the reason is the note.**
      // `/api/today` still carries no step target, and for as long as nothing
      // supplied one this tile drew no meter — correctly, because a denominator
      // the app invents is exactly how `~7,500/day` shipped in a `metric_info`
      // string the citation validator cannot see, under-targeting this owner by
      // 2,500 steps a day.
      //
      // `steps_plateau.dart` supplies one now, and it is DERIVED: the age-banded
      // plateau `steps_mortality` publishes, whose top is 10,000 under 60 and
      // 8,000 at or over it. The card may name it because the band is the
      // note's, and `steps_plateau_test.dart` asserts the transcription against
      // the note file itself.
      tall(tester);
      await tester.pumpWidget(todayHost(store));
      await tester.pumpAndSettle();

      final movement = tester.widget<KeyNumberCard>(
        find.byWidgetPredicate(
          (widget) => widget is KeyNumberCard && widget.name == 'Movement',
        ),
      );
      // The fixture's owner is 32, so the band's top is the under-60 one.
      expect(movement.line, contains('the ${commaGrouped(10000)} plateau'));
    });

    testWidgets('AN UNKNOWN AGE MEANS NO BAND, AND SO NO METER', (
      tester,
    ) async {
      // The half that keeps the above honest. An owner whose age nothing has
      // read is not an owner who is under 60, so there is no band to draw
      // against and the tile goes back to a number with no denominator.
      expect(stepsPlateauTop(null), isNull);
      expect(stepsPlateauTop(double.nan), isNull);
      expect(stepsPlateauTop(32), kStepsPlateauTopUnder60);
      expect(stepsPlateauTop(60), kStepsPlateauTopFrom60);
      expect(stepsPlateauTop(59.9), kStepsPlateauTopUnder60);
    });

    testWidgets('AND THE CARD ITSELF NAMES NO PLATEAU FOR AN OWNER WITH NO AGE', (
      tester,
    ) async {
      // **The function's rule, asserted where it is spent.** The unit test
      // above proves `stepsPlateauTop` refuses; this proves the card asks it.
      // A card that hard-coded 10,000 would agree with the derived answer for
      // every owner under 60 — including this suite's own fixture, who is 36 —
      // so the only owner who can tell the two apart is one with no age at all.
      tall(tester);
      await tester.pumpWidget(
        todayHost(
          store,
          server: todayView(
            mutate: (json) => <String, Object?>{
              ...json,
              'biological_age': <String, Object?>{
                ...json['biological_age']! as Map<String, Object?>,
                'chronological_age': null,
              },
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final movement = tester.widget<KeyNumberCard>(
        find.byWidgetPredicate(
          (widget) => widget is KeyNumberCard && widget.name == 'Movement',
        ),
      );
      expect(
        movement.line,
        isNull,
        reason: 'no band was published, so there is no plateau to name',
      );
      expect(
        movement.lead,
        isNull,
        reason: 'and no "to go" against a denominator nobody supplied',
      );
    });
  });
}
