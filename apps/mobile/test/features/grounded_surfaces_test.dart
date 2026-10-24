/// No raw citation marker reaches the screen — **and the citation still does**.
///
/// The defect: the "Suggested today" card printed, literally,
///
/// > Since your recovery supports moderate movement **[recovery_readiness]**,
/// > consider taking a short walk … **[specificity_and_recovery]**.
///
/// Both halves are asserted here, on every surface that renders model prose,
/// because either one alone is satisfied by the wrong fix. A test that only
/// checked the bracket was gone would pass on **deleting the grounding**, which
/// is the outcome this product exists to prevent — a claim that loses its
/// evidence on the last hop is indistinguishable from a claim that never had
/// any.
///
/// Both directions are mutation-verified:
///
///   * the grounding dropped on the way to the ⓘ fails
///     `THE CITATION SURVIVES AS A SOURCE`;
///   * the raw string rendered instead of the parsed one fails
///     `NO RAW CITATION MARKER REACHES ANY SURFACE`.
///
/// **The sources are read out of the ⓘ, not off the card.** They used to be
/// drawn under the prose; the owner asked three times for them off the card
/// faces, and `citation_sweep_test.dart` now fails the build on any surface that
/// puts them back. So this suite opens the action row's ⓘ — which is also the
/// only way to prove the move did not simply delete them.
///
/// The surfaces driven are every field on the wire a model wrote: `/api/today`'s
/// `action`, and each recommendation's `action`, `expected_effect` and
/// `rationale`. The last is behind a disclosure, so the test opens it — a marker
/// hidden behind a tap is still a marker on screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/today/widgets/actions_section.dart';
import 'package:healthee/shared/metric_info/metric_info_sheet.dart';

import '../_today_stubs.dart';
import '_today_host.dart';

/// The snapshot with a citation marker in each of the four generated fields.
Map<String, Object?> _cited(Map<String, Object?> json) => <String, Object?>{
  ...json,
  'action':
      'Since your recovery supports moderate movement [recovery_readiness], '
      'take a short walk today [exercise_mortality].',
  'recommendations': <Map<String, Object?>>[
    {
      'id': 1,
      'action': 'Sleep earlier tonight [sleep_need_debt]',
      'expected_effect': 'About 30 minutes off your debt [sleep_need_debt]',
      'rationale':
          'Your debt is 120 minutes and it moved with your HRV '
          '[personal_finding:hrv_sleep_avg, sleep_need_debt].',
      'category': 'sleep',
      'evidence_grade': 3,
      'research_note_ids': <String>['sleep_need_debt'],
      'signal_source': 'sleep_debt',
      'adopted': null,
    },
  ],
};

/// Pumps Today with the cited payload and opens the rec's disclosure.
///
/// The disclosure is opened rather than left shut because a marker behind a tap
/// is still a marker on screen — and the open state is ASSERTED, so a tap that
/// silently missed cannot turn the leak tests into tests of an empty tree.
Future<void> _openTheCard(WidgetTester tester, LocalStore store) async {
  // Tall enough to hold the whole action card. `scrollUntilVisible` will happily
  // stop with a widget one pixel inside the viewport, and the tap then lands
  // outside the render tree.
  // Tall enough to hold the whole port with both disclosures open.
  // `scrollUntilVisible` will happily stop with a widget one pixel inside the
  // viewport, and the tap then lands outside the render tree.
  tester.view
    ..physicalSize = const Size(420, 14000)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(todayHost(store, server: todayView(mutate: _cited)));
  await tester.pumpAndSettle();
  // Legacy's actions block is collapsed twice over: the section, then the row.
  // Both are opened here, because a marker behind a tap is still a marker on
  // screen — and the open state is ASSERTED, so a tap that silently missed
  // cannot turn the leak tests into tests of an empty tree.
  await tester.tap(find.text('Suggested actions'));
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('Sleep earlier tonight'));
  await tester.pumpAndSettle();
  expect(
    find.textContaining('Your debt is 120 minutes'),
    findsOneWidget,
    reason: 'the disclosure must actually be open for these tests to mean much',
  );
}

/// Opens the action row's ⓘ, where the rec's sources now live.
///
/// The row's, not the block head's: the head grounds `/api/today`'s own daily
/// `action`, which is a different job's prose citing different notes.
Future<void> _openTheSources(WidgetTester tester, Type surface) async {
  final dots = find.descendant(
    of: find.byType(surface),
    matching: find.byType(MetricInfoDot),
  );
  expect(
    dots,
    findsWidgets,
    reason: 'the card lost its chips and gained no ⓘ — that is a deletion',
  );
  // The first inside the named surface. For `ActionsSection` that is the block
  // head's, which grounds the daily line; the rows' own come after it.
  // Scrolled to first: the page grew with the key numbers, and a dot left
  // under the pinned chapter bar takes no tap.
  await tester.ensureVisible(dots.first);
  await tester.pumpAndSettle();
  await tester.tap(dots.first);
  await tester.pumpAndSettle();
}

/// Every string this frame is drawing, from every `Text` in the tree.
Iterable<String> _rendered(WidgetTester tester) sync* {
  for (final widget in tester.widgetList<Text>(find.byType(Text))) {
    final data = widget.data;
    if (data != null) {
      yield data;
    }
  }
}

void main() {
  late LocalStore store;

  setUp(() async {
    store = LocalStore.memory();
    await seedDevice(store);
  });
  tearDown(() async => store.close());

  testWidgets('NO RAW CITATION MARKER REACHES ANY SURFACE', (tester) async {
    await _openTheCard(tester, store);

    for (final line in _rendered(tester)) {
      expect(
        line,
        isNot(contains('[recovery_readiness]')),
        reason: 'the daily action printed its markers: "$line"',
      );
      expect(line, isNot(contains('[sleep_need_debt]')));
      expect(line, isNot(contains('[exercise_mortality]')));
      expect(line, isNot(contains('[personal_finding:')));
    }
  });

  testWidgets('THE CITATION SURVIVES AS A SOURCE', (tester) async {
    // The other half, and the one a bracket-only test would let through. The
    // chip carries the corpus's own NAME, so this also pins the id → name
    // resolution: `sleep_need_debt` is never what the owner reads.
    await _openTheCard(tester, store);
    // Nothing on the card's face, and everything in the sheet behind its ⓘ.
    expect(find.text('Sleep need & cumulative sleep debt'), findsNothing);
    await _openTheSources(tester, ActionRow);

    expect(find.text('Sleep need & cumulative sleep debt'), findsWidgets);
    for (final line in _rendered(tester)) {
      expect(
        line,
        isNot('sleep_need_debt'),
        reason: 'a chip is a name, not an id',
      );
      expect(line, isNot('recovery_readiness'));
    }
  });

  testWidgets('THE DAILY LINE’S OWN SOURCES ARE NOT THE REC’S', (tester) async {
    // Two pieces of prose written by two jobs. Folding them into one sheet
    // would say a recommendation was backed by a note it never named.
    await _openTheCard(tester, store);
    await _openTheSources(tester, ActionsSection);

    expect(find.text('Daily Recovery / Readiness'), findsWidgets);
    expect(find.text('Minimum exercise dose and mortality'), findsWidgets);
    expect(
      find.text('Sleep need & cumulative sleep debt'),
      findsNothing,
      reason: 'the daily line never cited it',
    );
  });

  testWidgets('A PERSONAL FINDING IS NOT DRESSED AS RESEARCH', (tester) async {
    await _openTheCard(tester, store);
    await _openTheSources(tester, ActionRow);

    expect(
      find.text('your own data · overnight HRV'),
      findsOneWidget,
      reason: 'an n-of-1 correlation may not wear a research chip',
    );
    expect(
      find.textContaining('never what caused what'),
      findsWidgets,
      reason: 'the framing travels with the claim, not with one screen',
    );
  });

  testWidgets('the sentence reads as a sentence once the markers are gone', (
    tester,
  ) async {
    await _openTheCard(tester, store);

    expect(
      find.text(
        'Since your recovery supports moderate movement, take a short walk '
        'today.',
      ),
      findsOneWidget,
      reason: 'no double space, no space before the comma or the full stop',
    );
  });

  testWidgets('AN UNRESOLVABLE MARKER IS LOUD, NOT QUIETLY DELETED', (
    tester,
  ) async {
    await tester.pumpWidget(
      todayHost(
        store,
        server: todayView(
          mutate: (json) => <String, Object?>{
            ...json,
            'action': 'Walk today [see the sleep tab].',
            'recommendations': const <Object?>[],
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await reveal(tester, find.textContaining('Walk today'));

    expect(
      find.text('Walk today [see the sleep tab].'),
      findsOneWidget,
      reason:
          'we cannot tell what it was meant to be, so we do not edit it out',
    );
    // This payload carries no recommendations, so the only ⓘ in the block is
    // the head's — the one grounding the daily line under test.
    // And the notice reaches the ⓘ. A marker we could not read is our failure,
    // not a fact about the owner's body: it is carried, never dropped on the
    // way into the sheet.
    expect(find.textContaining('no source we can resolve'), findsNothing);
    await _openTheSources(tester, ActionsSection);
    expect(find.textContaining('no source we can resolve'), findsOneWidget);
  });
}
