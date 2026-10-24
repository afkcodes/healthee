/// The four sleep checks: four readings, four published cutoffs, and NO TOTAL.
///
/// Each test is written so that **reverting the behaviour fails it**, not so
/// that today's shape passes:
///
///   * the cutoffs are asserted to come from the PAYLOAD, by moving them;
///   * the four are asserted never to be combined, by naming every shape a
///     combination would take;
///   * the midpoint is asserted not to be the raw ISO string the wire sends;
///   * the references and the citations are asserted to be **off the card's
///     face** and reachable from the ⓘ, which is where the owner put them.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/models/sleep_page.dart';
import 'package:healthee/features/sleep/v02/checks_panel.dart';
import 'package:healthee/features/sleep/v02/sleep_cutoffs.dart';
import 'package:healthee/shared/metric_info/metric_info_sheet.dart';
import 'package:healthee/shared/v02/key_number_card.dart';

import '../_sleep_stubs.dart';
import '_sleep_host.dart';

/// The four target strings the panel renders, in its own order.
List<String> _targets(SleepChecksPanel panel) => <String>[
  for (final check in panel.checks) check.target,
];

SleepChecksPanel _panel({
  SleepCutoffs? cutoffs,
  List<String> notes = const <String>[],
}) {
  final page = sleepPageFixture();
  return SleepChecksPanel(
    night: page.nights.first,
    cutoffs: cutoffs ?? page.cutoffs,
    notes: notes,
  );
}

void main() {
  group('cutoffs come off the wire, not out of the widget', () {
    test('the snapshot values render as the prototype’s own strings', () {
      expect(_targets(_panel()), <String>[
        '7–9 hours',
        'At least 85%',
        '70 or above',
        'Midpoint 02:00–04:00',
      ]);
    });

    test('MUTATION — MOVE THE SERVER’S CUTOFFS AND ALL FOUR STRINGS MOVE', () {
      // The assertion that makes the one above mean something. With four
      // literals back in the widget this passes for nobody: the panel would
      // keep printing `7–9 hours` beside a check scored against 6–8, and
      // nothing would fail. That is the second-definition-of-science failure
      // CLAUDE.md names.
      final moved = _panel(
        cutoffs: SleepCutoffs.maybe(const <String, Object?>{
          'duration_hours': <double>[6, 8],
          'efficiency_min': 0.9,
          'timing_hour_band': <int>[1, 3],
          'sri_min': 75.0,
        }),
      );
      expect(_targets(moved), <String>[
        '6–8 hours',
        'At least 90%',
        '75 or above',
        'Midpoint 01:00–03:00',
      ]);
    });

    test('the distance sentence moves with the cutoff too', () {
      // The words under a check are arithmetic on the two numbers on the row.
      // A sentence that named a fixed 7 hours beside a 6-hour cutoff would be
      // the same failure one line lower.
      final bands = SleepBands(
        SleepCutoffs.maybe(const <String, Object?>{
          'duration_hours': <double>[6, 8],
        }),
      );
      expect(
        bands.durationDetail(300),
        '60 minutes below the 6-hour lower reference.',
      );
      expect(
        bands.durationDetail(600),
        '120 minutes above the 8-hour upper reference.',
      );
      expect(bands.durationDetail(420), 'Within the duration reference.');
      expect(bands.durationDetail(null), 'No duration recorded.');
    });

    test('the efficiency floor is read as a FRACTION, not a percentage', () {
      // The wire sends `0.85`. A server that ever sent `85` would be read as
      // 8500%, so the conversion is asserted against the committed snapshot.
      final raw =
          loadJson(kSleepSnapshotPath)['cutoffs']! as Map<String, Object?>;
      expect((raw['efficiency_min']! as num).toDouble(), lessThanOrEqualTo(1));
      expect(SleepBands(sleepPageFixture().cutoffs).efficiencyMinPct, 85);
    });
  });

  group('THE FOUR ARE NEVER SUMMED', () {
    testWidgets('four rows, four cutoffs, and not one total', (tester) async {
      await loadSleepFont();
      await tester.pumpWidget(sleepPanelHost(_panel()));
      await tester.pumpAndSettle();

      for (final name in <String>[
        'Duration',
        'Efficiency',
        'Regularity · SRI',
        'Timing',
      ]) {
        expect(find.text(name), findsOneWidget, reason: name);
      }
      for (final target in _targets(_panel())) {
        expect(find.text(target), findsOneWidget, reason: target);
      }
      // Every shape a combination would take. The payload's own `score` is 3 on
      // this fixture, so `3` in any of these dresses would be the four blended.
      for (final composite in <String>[
        '3',
        '3 / 4',
        '/ 4',
        '3/4',
        '75%',
        '0.75',
        '3 of 4',
      ]) {
        expect(
          find.text(composite),
          findsNothing,
          reason: '"$composite" would be the four checks blended into one',
        );
      }
    });

    test('MUTATION — the payload DOES carry a count, and it is refused', () {
      // Without this the test above passes for a screen that never had the
      // number to draw.
      expect(
        sleepPageFixture().nights.first.healthScore.valueOrNull,
        isNotNull,
      );
    });
  });

  group('an unscored check is never drawn as a pass', () {
    testWidgets('a check the server did not score draws no verdict', (
      tester,
    ) async {
      await loadSleepFont();
      Future<int> chips(SleepChecksPanel panel) async {
        await tester.pumpWidget(sleepPanelHost(panel));
        await tester.pumpAndSettle();
        return find.byType(VerdictChip).evaluate().length;
      }

      final scored = await chips(_panel());
      final night = sleepPageWithout(<String>['point_duration']).nights.first;
      final unscored = await chips(
        SleepChecksPanel(
          night: night,
          cutoffs: sleepPageFixture().cutoffs,
          notes: const <String>[],
        ),
      );
      expect(unscored, scored - 1);
    });
  });

  group('the timing row shows a clock, not a timestamp', () {
    test('MUTATION — the raw ISO instant does not reach the row', () {
      // `midpoint_local` arrives as `2026-07-31T02:45:00+05:30` and a row that
      // printed it verbatim would ellipsize a timestamp where a clock belongs.
      final page = sleepPageFixture();
      expect(
        page.nights.first.midpointLocal.valueOrNull,
        contains('T'),
        reason: 'the wire really does send a full instant',
      );
      final timing = _panel().checks[3];
      expect(timing.name, 'Timing');
      expect(timing.reading, '02:45');
      expect(timing.reading, isNot(contains('T')));
      expect(timing.reading, isNot(contains('+')));
    });

    test('the OWNER’s clock face survives, not the test host’s', () {
      // The string is sliced rather than parsed. `DateTime.parse` would return
      // the same instant in the host's zone — a different clock face — and on a
      // phone set to UTC a 02:45 midpoint would read 21:15 the evening before.
      final parsed = DateTime.parse('2026-07-31T02:45:00+05:30');
      expect(
        '${parsed.hour}'.padLeft(2, '0'),
        isNot('02'),
        reason: 'the test host is not on +05:30, so parsing WOULD change it',
      );
      expect(SleepBands.midpointHour('2026-07-31T02:45:00+05:30'), 2.75);
    });

    test('an unreadable midpoint draws a dash rather than echoing itself', () {
      final night = sleepPageWithout(<String>['midpoint_local']).nights.first;
      final panel = SleepChecksPanel(
        night: night,
        cutoffs: null,
        notes: const <String>[],
      );
      expect(panel.checks[3].reading, isNull);
      expect(panel.checks[3].detail, 'No midpoint recorded.');
    });
  });

  group('references and citations live behind the ⓘ, not on the card', () {
    testWidgets('the four references are in the sheet’s detail, not the face', (
      tester,
    ) async {
      await loadSleepFont();
      final page = sleepPageFixture();
      expect(page.researchNotes, isNotEmpty);
      await tester.pumpWidget(
        sleepPanelHost(_panel(notes: page.researchNotes)),
      );
      await tester.pumpAndSettle();

      // The card has the door.
      expect(
        find.descendant(
          of: find.byType(SleepChecksPanel),
          matching: find.byType(MetricInfoDot),
        ),
        findsOneWidget,
      );
      // And the reference labels the ⓘ carries are not painted on it.
      for (final reference in <String>[
        'Duration — 7–9 hours',
        'Efficiency — At least 85%',
      ]) {
        expect(find.text(reference), findsNothing, reason: reference);
      }
      // Nor is a raw note id anywhere on the face.
      for (final id in page.researchNotes) {
        expect(find.textContaining(id), findsNothing, reason: id);
      }
    });

    testWidgets('opening the ⓘ resolves the ids to readable source names', (
      tester,
    ) async {
      await loadSleepFont();
      final page = sleepPageFixture();
      await tester.pumpWidget(
        sleepPanelHost(_panel(notes: page.researchNotes)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(MetricInfoDot));
      await tester.pumpAndSettle();

      expect(
        find.text('Sleep duration and all-cause mortality'),
        findsOneWidget,
      );
      expect(find.text('Sleep Regularity Index (SRI)'), findsOneWidget);
      // The id itself never reaches a surface, open or closed.
      expect(find.textContaining('sleep_duration_mortality'), findsNothing);
    });
  });

  group('a check with no reading is neither a pass nor a failure', () {
    testWidgets('the mark is neutral and the row says what is missing', (
      tester,
    ) async {
      await loadSleepFont();
      final page = sleepPageWithout(<String>[
        'efficiency_pct',
        'point_efficiency',
      ]);
      await tester.pumpWidget(
        sleepPanelHost(
          SleepChecksPanel(
            night: page.nights.first,
            cutoffs: page.cutoffs,
            notes: const <String>[],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No efficiency recorded.'), findsOneWidget);
      // EXACTLY two ticks. The snapshot passes three of the four and the one
      // taken away is one of them, so a third tick would mean the row with no
      // reading had been scored — a judgement made out of nothing, which is the
      // defect this whole layer exists to make impossible.
      final ticks = tester
          .widgetList<VerdictChip>(find.byType(VerdictChip))
          .where((chip) => chip.verdict.tone == VerdictTone.neutral)
          .length;
      expect(ticks, 2);
    });
  });
}
