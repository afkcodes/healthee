import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/routes.dart';
import 'package:healthee/core/tabs.dart';
import 'package:healthee/data/challenges/challenge.dart';
import 'package:healthee/data/challenges/health_program.dart';
import 'package:healthee/data/coach/ledger_models.dart';
import 'package:healthee/data/coach/ledger_repository.dart';
import 'package:healthee/features/coach/coach_home_screen.dart';
import 'package:healthee/features/coach/v02/home_links_card.dart';
import 'package:healthee/features/coach/v02/home_record_section.dart';

import '../../_today_stubs.dart';
import '../_screen_data.dart';
import '../_settings_harness.dart' show tallViewport;
import '_coach_home_fakes.dart';

Challenge _rung(int id, double target) => Challenge(
  id: id,
  title: 'Rung $id',
  why: 'Because.',
  status: 'locked',
  metric: 'mvpa_min',
  target: target,
  comparator: '>=',
  cadence: 'weekly',
  windowDays: 7,
  difficulty: 'standard',
  kind: 'threshold',
  citations: const <String>[],
);

HealthProgram _plan({int? weeks = 4, int settled = 0}) => HealthProgram(
  id: 3,
  title: 'The 4-week plan',
  why: 'Build up.',
  status: 'active',
  rungs: <Challenge>[_rung(1, 80), _rung(2, 150)],
  settledRungs: settled,
  weeks: weeks,
);

Future<CoachHost> _pump(
  WidgetTester tester,
  Widget child, {
  void Function(CoachHost host)? setup,
}) async {
  tallViewport(tester);
  final host = await CoachHost.create();
  setup?.call(host);
  await tester.pumpWidget(host.wrap(child));
  await tester.pumpAndSettle();
  return host;
}

void main() {
  group('your record', () {
    testWidgets('four numbers from the ledger, month first', (tester) async {
      final host = await _pump(tester, const CoachRecordSection());
      expect(find.text('Your record'), findsOneWidget);
      for (final text in <String>[
        '84', 'ideas given', //
        '9', 'you said yes',
        '2', 'done',
        '5', 'missed',
      ]) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      expect(host.asked, <LedgerWindow>[LedgerWindow.month]);
    });

    testWidgets('Week asks for the week window', (tester) async {
      final host = await _pump(tester, const CoachRecordSection());
      await tester.tap(find.text('Week'));
      await tester.pumpAndSettle();
      expect(host.asked, contains(LedgerWindow.week));
    });

    testWidgets('caption: could not be checked, then last week', (
      tester,
    ) async {
      await _pump(
        tester,
        const CoachRecordSection(),
        setup: (h) => h.served = (_) => ledger(
          weeks: <LedgerWeek>[
            week('2026-10-19', <int, String>{0: 'done'}),
            week('2026-10-12', <int, String>{}),
          ],
        ),
      );
      expect(
        find.text("2 couldn't be checked. Last week: 21 ideas, 0 yeses."),
        findsOneWidget,
      );
    });

    testWidgets('no last week in the ledger: that sentence is omitted', (
      tester,
    ) async {
      await _pump(
        tester,
        const CoachRecordSection(),
        setup: (h) => h.served = (_) => ledger(
          weeks: <LedgerWeek>[
            week('2026-10-19', <int, String>{0: 'done'}),
          ],
        ),
      );
      expect(find.text("2 couldn't be checked."), findsOneWidget);
      expect(find.textContaining('Last week'), findsNothing);
    });

    testWidgets('nothing unchecked and no last week: no caption at all', (
      tester,
    ) async {
      await _pump(
        tester,
        const CoachRecordSection(),
        setup: (h) => h.served = (_) => ledger(noData: 0, uncheckable: 0),
      );
      expect(find.textContaining("couldn't"), findsNothing);
      expect(find.textContaining('Last week'), findsNothing);
    });

    test('singular words', () {
      final l = ledger(
        noData: 1,
        uncheckable: 0,
        weeks: <LedgerWeek>[
          week('2026-10-12', <int, String>{0: 'done'}, ideas: 1),
        ],
      );
      expect(
        recordCaption(l, '2026-10-19'),
        "1 couldn't be checked. Last week: 1 idea, 1 yes.",
      );
    });
  });

  group('the link list', () {
    testWidgets('Every yes, checked opens the ledger', (tester) async {
      final host = await _pump(tester, const CoachLinksCard());
      expect(find.text('What the strap saw for each one'), findsOneWidget);
      await tester.tap(find.text('Every yes, checked'));
      await tester.pumpAndSettle();
      expect(host.visited, <String>[Routes.coachLedger]);
    });

    testWidgets('no program: its row is hidden', (tester) async {
      await _pump(tester, const CoachLinksCard());
      expect(find.text('The 4-week plan'), findsNothing);
      expect(find.text('Journal'), findsOneWidget);
    });

    testWidgets('a program row is built from its own rungs and opens it', (
      tester,
    ) async {
      final host = await _pump(
        tester,
        const CoachLinksCard(),
        setup: (h) => h.program = _plan(),
      );
      expect(find.text('The 4-week plan'), findsOneWidget);
      expect(find.text('80 to 150 active minutes a week'), findsOneWidget);
      await tester.tap(find.text('The 4-week plan'));
      await tester.pumpAndSettle();
      expect(host.visited, <String>['${Routes.program}/3']);
    });

    test('equal first and last targets read as one value', () {
      final plan = HealthProgram(
        id: 4,
        title: 'Hold',
        why: 'Hold.',
        status: 'active',
        rungs: <Challenge>[_rung(1, 20), _rung(2, 20)],
        settledRungs: 0,
      );
      expect(programDetail(plan), '20 active minutes a week');
      expect(programDetail(_plan()), '80 to 150 active minutes a week');
    });

    testWidgets('Journal opens the journal', (tester) async {
      final host = await _pump(tester, const CoachLinksCard());
      await tester.tap(find.text('Water and breathing land here too'));
      await tester.pumpAndSettle();
      expect(host.visited, <String>[Routes.journal]);
    });
  });

  group('the screen', () {
    test('sections come in the design order', () {
      final sections = coachHomeSections(screenData(server: todayView()));
      expect(
        sections.map((s) => s.child.runtimeType.toString()).toList(),
        <String>[
          '_CoachHead',
          'WeeklyReviewCard',
          'CoachJobSection',
          'TodaysBasicsSection',
          'CoachRecordSection',
          'CoachLinksCard',
          'DataFooter',
        ],
      );
    });

    test('the tab is Coach, on the route deep links already use', () {
      expect(kAppTabs.last.label, 'Coach');
      expect(kAppTabs.last.route, Routes.actions);
      expect(kAppTabs.map((t) => t.label), isNot(contains('Actions')));
    });
  });
}
