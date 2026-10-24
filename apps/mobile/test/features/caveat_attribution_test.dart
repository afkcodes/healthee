/// **A caveat is attached to a number, or it is a claim about the wrong one.**
///
/// Two owner reports of 2026-08-06, one screen apart, and they are the same
/// defect seen from two sides:
///
///   * *"what are those * symbol in card"* — `CaveatMark` drew a bare asterisk
///     and nothing on the screen said what it meant. The file it lived in states
///     in its own docstring that a caveated value discloses **in words**; an
///     asterisk is not words, and only a reader who had opened that file could
///     have known.
///   * *"the caveat is sitting and its difficutlt to understand which caveat is
///     that pointing to"* — `ReadingView` drew the signpost as a SIBLING beneath
///     whatever its builder returned. On a screen of cards that put the sentence
///     in the **gutter**, closer to the card below it than to the one it
///     qualifies.
///
/// The second is the dangerous one. A disclosure attached to the wrong number is
/// not a weaker disclosure, it is a **misattributed** one: it can read as
/// qualifying a figure that is in fact unqualified, which is a new false claim
/// produced entirely by layout. `shared/states/caveat_scope.dart` carries the
/// fix; this file is the guard on it, and it is deliberately geometric rather
/// than structural — "the carrier is mounted" was already true while the owner
/// was looking at the bug.
///
/// It runs on **every screen that draws a caveated reading**, because the fix is
/// per-carrier and the orphaning was per-call-site.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/activity/activity_screen.dart';
import 'package:healthee/features/sleep/sleep_screen.dart';
import 'package:healthee/shared/instrument_module.dart';
import 'package:healthee/shared/metric_info/metric_info_sheet.dart';
import 'package:healthee/shared/states/state_scaffold.dart';
import 'package:healthee/shared/v02/age_orb_hero.dart';
import 'package:healthee/shared/v02/panel.dart';

import '../_sleep_stubs.dart';
import '_today_host.dart';

/// Whether [text] is a lone footnote glyph with no word attached.
///
/// Punctuation only, and short: `*` is the one the owner asked about, and
/// `†`/`‡` are the two a future author would reach for next.
bool isBareMark(String text) {
  final trimmed = text.trim();
  return trimmed.isNotEmpty &&
      trimmed.length <= 2 &&
      trimmed.split('').every((rune) => '*†‡'.contains(rune));
}

/// Every rect a caveat carrier occupies on the pumped screen.
///
/// A list of one since v02: `CaveatFoot` was the grid tile's carrier and both
/// the grid and the foot are deleted. Kept as a loop because "one carrier" is a
/// decision this file measures, not a fact about the language.
List<Rect> _carriers(WidgetTester tester) {
  // **The carrier is the ⓘ now, not a note under the number.** The sentence
  // moved into the sheet, but the claim this file makes did not: a disclosure
  // must be reachable from INSIDE the card whose reading it qualifies, because
  // one rendered as a sibling lands in the gutter between two cards and stops
  // naming which number it is about. A dot holding disclosures is that carrier,
  // and it is still measured against the same card bounds below.
  final dots = find.byType(MetricInfoDot);
  return <Rect>[
    for (var i = 0; i < tester.widgetList(dots).length; i++)
      if (tester
          .widget<MetricInfoDot>(dots.at(i))
          .detail
          .disclosures
          .isNotEmpty)
        tester.getRect(dots.at(i)),
  ];
}

/// Every rect a CARD occupies — the bounds a carrier has to be inside.
List<Rect> _cards(WidgetTester tester) => <Rect>[
  for (final type in <Finder>[
    find.byType(StateCard),
    find.byType(InstrumentModule),
    // v02's two carriers. `Panel` and `AgeOrbHero` read the same
    // `CaveatScope` that `InstrumentModule` does, so a Today card is measured
    // the same way a Sleep card is.
    find.byType(Panel),
    find.byType(AgeOrbHero),
  ])
    for (var i = 0; i < tester.widgetList(type).length; i++)
      tester.getRect(type.at(i)),
];

void main() {
  late LocalStore store;

  setUp(() async {
    store = LocalStore.memory();
    await seedDevice(store);
  });
  tearDown(() async => store.close());

  /// Pumps [home] tall enough that every card is laid out in one pass.
  ///
  /// A `ListView.builder` never builds a card it has not scrolled to, and a card
  /// that was never built cannot be measured — which would make this suite pass
  /// by seeing nothing.
  Future<void> pump(WidgetTester tester, Widget? home) async {
    tester.view
      ..physicalSize = const Size(420, 14000)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(todayHost(store, home: home));
    await tester.pumpAndSettle();
  }

  /// Each screen, and whether the committed payload gives it a caveated
  /// reading to place.
  ///
  /// The flag is an assertion in both directions, and that is the point. A
  /// `true` that goes false is a carrier that stopped drawing — the silent
  /// failure this whole layer exists to prevent, and the one the two geometric
  /// tests below pass vacuously through. A `false` that goes true is a screen
  /// that grew a disclosure nobody has looked at the placement of.
  ///
  /// Sleep is the `false`: `/api/sleep`'s blocks arrive `Present` on this
  /// fixture. It is still pumped, because the geometry check is what catches a
  /// carrier landing in the gutter the day one appears.
  final screens = <String, ({Widget? home, bool carries})>{
    'Today': (home: null, carries: true),
    'Sleep': (home: SleepScreen(now: kSleepNow), carries: false),
    'Activity': (home: const ActivityScreen(), carries: true),
  };

  for (final screen in screens.entries) {
    group(screen.key, () {
      testWidgets('NO BARE `*` REACHES THE SCREEN', (tester) async {
        await pump(tester, screen.value.home);

        final bare = <String>[
          for (final widget in tester.widgetList<Text>(find.byType(Text)))
            if (isBareMark(widget.data ?? '')) widget.data!,
        ];
        expect(
          bare,
          isEmpty,
          reason:
              '${screen.key} rendered ${bare.length} unlabelled mark(s): '
              '$bare',
        );
      });

      testWidgets('THE CARRIERS IT SHOULD HAVE ARE THE ONES IT HAS', (
        tester,
      ) async {
        // Without this the two assertions around it pass on a screen that has
        // no disclosures to place, which is the shape of a vacuous suite — and
        // it is exactly how a carrier that stopped drawing its note would slip
        // through: nothing would be misplaced, because nothing would be there.
        await pump(tester, screen.value.home);

        expect(
          _carriers(tester),
          screen.value.carries ? isNotEmpty : isEmpty,
          reason: screen.value.carries
              ? '${screen.key} draws no caveat carrier at all'
              : '${screen.key} grew a disclosure — check where it landed',
        );
      });

      testWidgets('EVERY CAVEAT CARRIER IS INSIDE THE CARD IT IS ABOUT', (
        tester,
      ) async {
        await pump(tester, screen.value.home);

        final cards = _cards(tester);
        for (final carrier in _carriers(tester)) {
          expect(
            cards.any(
              (card) =>
                  card.contains(carrier.topLeft) &&
                  card.contains(carrier.bottomRight - const Offset(0.5, 0.5)),
            ),
            isTrue,
            reason:
                'a caveat carrier at $carrier is in the gutter between two '
                'cards, not inside the one whose number it qualifies',
          );
        }
      });
    });
  }

  testWidgets('THE PREMISE — Today really does carry caveated readings', (
    tester,
  ) async {
    // Without this the two assertions above pass on a screen that has no
    // disclosures to place, which is the shape of a vacuous suite. The
    // biological-age block of the committed snapshot carries four.
    await pump(tester, null);
    expect(_carriers(tester), isNotEmpty);
    // The hero's own four are no longer a note on the card — they are the ⓘ's
    // payload — so the premise is read off the dot the hero built rather than
    // off a headline it no longer prints. Same four disclosures, one tap away;
    // `today_caveat_surface_test.dart` opens it and reads them in full.
    final dot = tester.widget<MetricInfoDot>(
      find.descendant(
        of: find.byType(AgeOrbHero),
        matching: find.byType(MetricInfoDot),
      ),
    );
    expect(dot.detail.disclosures, hasLength(4));
  });
}
