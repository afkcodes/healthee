/// Today, rendered from real stored strap rows AND the real contract snapshot.
///
/// Two sources, exercised the same way they run: the store is a genuine
/// in-memory SQLite database seeded through the writer a sync uses, and the
/// server payload is `packages/contracts/snapshots/today.json` read from the
/// repo. `now` is injected, because a suite that reads the wall clock fails once
/// a day at midnight and passes on the retry.
///
/// This half is about **what the screen draws when it has data**. The refusals,
/// the unreachable server and the never-synced phone are `today_refusals_test.dart`;
/// the section ORDER is `today_order_test.dart`; the six tiles are
/// `today_tiles_test.dart`. What is left here is the handful of claims that need
/// the whole screen standing up.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/today/v02/mini_trend_panel.dart';
import 'package:healthee/shared/v02/meters.dart';

import '../_today_stubs.dart';
import '_text_probe.dart' show textOf;
import '_today_host.dart';

/// A viewport tall enough that a `ListView.builder` builds the whole port.
void _tall(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(420, 14000)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  late LocalStore store;

  setUp(() => store = LocalStore.memory());
  tearDown(() async => store.close());

  group('what the server made of it', () {
    setUp(() => seedDevice(store));

    testWidgets(
      'A BASELINE REACHES THE SCREEN WITH THE SPREAD IT IS MEASURED IN',
      (tester) async {
        // `docs/BACKEND_GAPS_FROM_UI.md` B4. The centre alone is a point, and a
        // reading one unit above it means something different against a tight
        // window than against a scattered one — which is the whole content of the
        // `z` the same payload quotes. The σ is the server's own `sd_30d`, never
        // recomputed here.
        _tall(tester);
        await tester.pumpWidget(todayHost(store));
        await tester.pumpAndSettle();

        final panel = find.byWidgetPredicate(
          (widget) =>
              widget is MiniTrendPanel && widget.title == 'Resting heart',
        );
        expect(panel, findsOneWidget);
        final words = textOf(tester, panel).join(' ');
        expect(words, contains('baseline'));
        expect(
          words,
          contains('±'),
          reason:
              'a baseline with no spread is a point, and B4 exists to fix that',
        );
      },
    );

    testWidgets('recovery ships its per-factor breakdown, never alone', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(todayHost(store));
      await tester.pumpAndSettle();

      // `feedback_no_composite_score`: the components are the licence, and they
      // are beside the number rather than behind a tap. The overnight estimate
      // and what is left of today are 72 and 36 in the contract snapshot, and
      // that split is exactly what must survive the redesign.
      expect(find.text('72'), findsWidgets);
      expect(find.textContaining('36 / 100 remaining'), findsOneWidget);
      for (final factor in <String>[
        'HRV',
        'Resting HR',
        'Sleep',
        'Breathing',
      ]) {
        expect(
          find.text(factor),
          findsWidgets,
          reason: '$factor is a factor row on the recovery card',
        );
      }
      // The contract snapshot scores `sleep` WITHOUT sending its minutes, and
      // no surface invents them: legacy printed `0.0h / 8h` there, a claim that
      // the owner slept nothing.
      expect(find.text('0\u00A0min / 8\u00A0h'), findsNothing);
    });

    testWidgets('AN UNSCORED FACTOR DRAWS NO BAR, NOT A BAR OF ZERO', (
      tester,
    ) async {
      // A factor the model did not score and a factor it scored zero are
      // different claims, and an empty track next to a zero-width fill is the
      // same picture — so the fill has to be ABSENT, not empty. The em dash in
      // the reading column says which of the two this is; the missing
      // `FractionallySizedBox` is what makes the bar agree with it.
      _tall(tester);
      await tester.pumpWidget(
        todayHost(
          store,
          server: todayView(
            mutate: (json) {
              final score = json['recovery_score']! as Map<String, Object?>;
              final factors = score['factors']! as Map<String, Object?>;
              return <String, Object?>{
                ...json,
                'recovery_score': <String, Object?>{
                  ...score,
                  'factors': <String, Object?>{
                    ...factors,
                    // Scored by the model, but with no sub-score on the wire.
                    'sleep': const <String, Object?>{},
                  },
                },
              };
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final bars = find.byType(FactorBars);
      expect(bars, findsOneWidget);
      final rows = tester.widget<FactorBars>(bars).factors;
      final scored = rows.where((factor) => factor.fraction != null).length;
      expect(scored, rows.length - 1, reason: 'one factor lost its sub-score');
      expect(
        // By key, not by type: the reference tick is a `FractionallySizedBox`
        // too, so counting the type counted ticks as fills and would have
        // passed for the wrong reason.
        find.descendant(of: bars, matching: find.byKey(FactorBars.fillKey)),
        findsNWidgets(scored),
        reason: 'an unscored factor drew a fill anyway',
      );
      expect(
        find.descendant(of: bars, matching: find.text('—')),
        findsOneWidget,
      );
    });

    testWidgets('THE ILLNESS FLAG COMES BEFORE EVERY NUMBER IT OVERRIDES', (
      tester,
    ) async {
      // Legacy references `illness_flag` in NO file. It is kept anyway — brief
      // §4.1 makes it deterministic and outranking — and it is kept above
      // everything a number can be read from.
      _tall(tester);
      await tester.pumpWidget(todayHost(store));
      await tester.pumpAndSettle();

      expect(find.text('POSSIBLE EARLY SIGNAL'), findsOneWidget);
      expect(find.textContaining('Possible early signal'), findsOneWidget);
      // The deltas come from the SERVER's calibrated sentence and only from there —
      // with the baseline WINDOW named, which `[[respiratory_rate_normal]]` Coach
      // Directive 1 requires because that note ships three of them. The banner used to
      // print a second, client-side copy of the same number with the window dropped;
      // that copy is gone (audit C4) and this asserts the surviving one is the qualified
      // one, not that a delta appears somewhere.
      expect(
        find.textContaining('Breathing rate +2.4 bpm vs your 14-day baseline'),
        findsOneWidget,
      );
      expect(
        find.textContaining('vs your baseline.'),
        findsNothing,
        reason: 'the unqualified client-side restatement is back',
      );
      final flagY = tester.getTopLeft(find.text('POSSIBLE EARLY SIGNAL')).dy;
      for (final below in <Finder>[
        find.text('Recovery, explained'),
        find.text('Resting heart'),
        find.text('Heart rate & stress'),
      ]) {
        expect(
          tester.getTopLeft(below.first).dy,
          greaterThan(flagY),
          reason: 'nothing on this screen may be read before the flag',
        );
      }
    });

    testWidgets("the guidance sentence renders verbatim, in legacy's own card", (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(todayHost(store));
      await tester.pumpAndSettle();

      // An active flag OVERRIDES this string on the server. Re-wording it in the
      // app would re-word a safety message.
      expect(
        find.textContaining('An illness signal is active'),
        findsOneWidget,
      );
    });

    testWidgets(
      'the suggested actions block is collapsed, as legacy leaves it',
      (tester) async {
        _tall(tester);
        await tester.pumpWidget(todayHost(store));
        await tester.pumpAndSettle();

        expect(find.text('Suggested actions'), findsOneWidget);
        expect(find.text('1 way to improve today'), findsOneWidget);
        // Collapsed: the one thing on Today a model wrote is not what the screen
        // opens with.
        expect(find.text('Sleep earlier tonight'), findsNothing);

        await tester.tap(find.text('Suggested actions'));
        await tester.pumpAndSettle();
        expect(find.text('Sleep earlier tonight'), findsOneWidget);
      },
    );
  });

  group('what the API sends that legacy never drew', () {
    setUp(() => seedDevice(store));

    testWidgets('STRENGTH IS ON SCREEN, WITH ITS BAND', (tester) async {
      _tall(tester);
      await tester.pumpWidget(todayHost(store));
      await tester.pumpAndSettle();

      expect(find.text('Strength'), findsOneWidget);
      // The reference moved off the card's face and behind its ⓘ — the owner
      // asked for exactly that. It is still a BAND wherever it is drawn: the
      // evidence stops improving above 60 minutes, so it may not read
      // `60 min/week`. `card_provenance_test.dart` opens the sheet and proves
      // the band is reachable there.
      expect(find.textContaining('Reference: 30–60 min/week'), findsNothing);
      expect(find.text('45'), findsWidgets);
    });

    testWidgets(
      "today's logged sessions are on screen, each naming its source",
      (tester) async {
        _tall(tester);
        await tester.pumpWidget(todayHost(store));
        await tester.pumpAndSettle();

        expect(find.text('Daily journal'), findsOneWidget);
        expect(find.text('Outdoor run'), findsOneWidget);
        expect(find.text('30 min · strap'), findsOneWidget);
        expect(find.text('Meditation'), findsWidgets);
      },
    );

    testWidgets('A DAY WITH NOTHING LOGGED DRAWS NO CARD AT ALL', (
      tester,
    ) async {
      // The rule, and the `anomalies` cautionary case: an empty field renders
      // nothing — no heading, no zero state, no placeholder.
      _tall(tester);
      await tester.pumpWidget(
        todayHost(
          store,
          server: todayView(
            mutate: (json) => <String, Object?>{
              ...json,
              'routine': const <String, Object?>{
                'open_fast': null,
                'meditation_today': <String, Object?>{'count': 0, 'minutes': 0},
                'workouts': <Object?>[],
                'logs_summary': <String, Object?>{},
              },
              'strength': null,
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Daily journal'), findsNothing);
      expect(find.text('Strength'), findsNothing);
      // And no empty-state sentence in their place.
      expect(find.textContaining('Nothing logged'), findsNothing);
    });

    testWidgets('NO RAW IDENTIFIER REACHES ANY SURFACE ON TODAY', (
      tester,
    ) async {
      // The port's third sanctioned difference: citations resolve to readable
      // source names. This is the whole-screen sweep behind it — a metric id, a
      // note id or a citation marker printed at a person is a log line where a
      // name belongs, and `grounded_surfaces_test.dart` only drives the four
      // generated fields.
      _tall(tester);
      await tester.pumpWidget(todayHost(store));
      await tester.pumpAndSettle();
      // Both disclosures open, so nothing is merely un-built.
      await tester.tap(find.text('Suggested actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Sleep earlier tonight'));
      await tester.pumpAndSettle();

      final snake = RegExp(r'\b[a-z0-9]+(_[a-z0-9]+)+\b');
      for (final widget in tester.widgetList<Text>(find.byType(Text))) {
        final line = widget.data;
        if (line == null) {
          continue;
        }
        expect(
          snake.hasMatch(line),
          isFalse,
          reason: 'a raw identifier reached the screen: "$line"',
        );
        expect(
          line.contains('['),
          isFalse,
          reason: 'a citation marker reached the screen: "$line"',
        );
      }
    });

    testWidgets('NEITHER pai NOR anomalies GETS A SECTION', (tester) async {
      // `pai` is null on this account and `read/today.py:83` sets `anomalies` to
      // `[]` unconditionally — the real data is behind a separate, premium-gated
      // `/api/notable`. A heading that can never have content under it is dead
      // code, so neither is drawn at all.
      _tall(tester);
      await tester.pumpWidget(todayHost(store));
      await tester.pumpAndSettle();

      for (final absent in <String>['PAI', 'Anomalies', 'ANOMALIES']) {
        expect(find.textContaining(absent), findsNothing);
      }
    });

    testWidgets('ON THE REAL PAYLOAD, HRV HAS NONE AND NAMES NONE', (
      tester,
    ) async {
      // Moved here from `vitals_thresholds_test.dart`, which was deleted with
      // legacy's vitals cards. This half was never about those cards: it is
      // about `MiniTrendPanel`, which is live, and it is what the owner's phone
      // renders today.
      //
      // Not a hypothetical: the committed contract snapshot carries no HRV
      // recovery signal, and `hrv_sleep_avg` has no metric card on any payload.
      //
      // The v02 panel says how many nights are on the line and stops there. It
      // does NOT compute a median of those nights and call it a baseline —
      // `today_facts.dart` records why that would be a second definition of the
      // owner's normal, arriving as a helpful-looking last resort.
      _tall(tester);
      await tester.pumpWidget(todayHost(store));
      await tester.pumpAndSettle();

      final panel = find.byWidgetPredicate(
        (widget) => widget is MiniTrendPanel && widget.title == 'Overnight HRV',
      );
      await reveal(tester, panel);

      final words = textOf(tester, panel).join(' ').toLowerCase();
      // On this payload the FIGURE is withheld too — `hrv_sleep_avg` has no
      // metric card and the ladder carries no HRV marker — so the panel shows
      // the server's own reason where the number goes. That is the contract:
      // a hole that says why it is a hole, never a blank.
      expect(words, contains('the server did not say why'));
      expect(
        words,
        isNot(contains('baseline')),
        reason: 'a baseline the server did not send may not be named',
      );
    });
  });
}
