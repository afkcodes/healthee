import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/data/coach/ledger_models.dart';
import 'package:healthee/data/coach/ledger_repository.dart';
import 'package:healthee/features/coach/every_yes_screen.dart';
import 'package:healthee/features/coach/v02/ledger_bar.dart';
import 'package:healthee/features/coach/v02/ledger_entry_row.dart';

import '../_settings_harness.dart' show tallViewport;
import '../_workouts_host.dart' show loadSnapshot;

const String _path = '../../packages/contracts/snapshots/coach_ledger.json';

Map<String, Object?> _json() => loadSnapshot(_path);

Future<void> _open(
  WidgetTester tester,
  Map<String, Object?> Function(LedgerWindow) serve, {
  List<LedgerWindow>? asked,
}) async {
  tallViewport(tester);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        for (final w in LedgerWindow.values)
          coachLedgerProvider(w).overrideWith((ref) async {
            asked?.add(w);
            return CoachLedger.fromJson(serve(w));
          }),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const EveryYesScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('summary numbers come from the totals', (tester) async {
    await _open(tester, (_) => _json());
    expect(find.text('Every yes, checked'), findsOneWidget);
    expect(find.text('Coach'), findsOneWidget);
    expect(find.text('yeses'), findsOneWidget);
    expect(find.text('no proof'), findsOneWidget);
    // yeses 5? the response says ideas 41; yeses is the response's own field.
    final ledger = CoachLedger.fromJson(_json());
    expect(find.text('${ledger.yeses}'), findsWidgets);
    expect(find.text('2'), findsWidgets); // no_data 1 + uncheckable 1
    expect(find.textContaining('1 of 3'), findsOneWidget);
    expect(find.text('20 to 18 Oct'), findsNothing);
    expect(find.text('20 Sep to 18 Oct'), findsOneWidget);
  });

  test('the bar draws one segment per non-zero count, in proportion', () {
    final parts = LedgerBar.segments(
      const LedgerTotals(done: 2, missed: 5, noData: 1, uncheckable: 1),
    );
    expect(parts, <(int, LedgerVerdict)>[
      (2, LedgerVerdict.done),
      (5, LedgerVerdict.missed),
      (2, LedgerVerdict.noData),
    ]);
    expect(LedgerBar.segments(const LedgerTotals()), isEmpty);
  });

  testWidgets('weeks: header, yeses of ideas, entries and the quiet rows', (
    tester,
  ) async {
    await _open(tester, (_) {
      final json = _json();
      final weeks = (json['weeks']! as List).cast<Map<String, Object?>>();
      weeks[0] = {...weeks[0], 'yeses': 0, 'entries': <Object?>[]};
      return {...json, 'weeks': weeks};
    });
    expect(find.text('12 to 18 Oct'), findsOneWidget);
    expect(find.text('0 of 21'), findsOneWidget);
    expect(find.text('No yeses this week'), findsWidgets);
    expect(find.text('21 ideas skipped'), findsOneWidget);
    expect(find.text('5 to 11 Oct'), findsOneWidget);
    expect(find.text('4 of 20'), findsOneWidget);
    // A week with no ideas says so rather than "0 ideas skipped".
    expect(find.text('No ideas given'), findsWidgets);
    expect(find.text('0 ideas skipped'), findsNothing);
  });

  testWidgets('details: measurement from the response, else a neutral line', (
    tester,
  ) async {
    await _open(tester, (_) => _json());
    expect(find.text('1,578 steps'), findsOneWidget);
    expect(find.text('9h34'), findsOneWidget);
    expect(find.text('12 min'), findsOneWidget);
    expect(find.text(kLedgerNoReading), findsOneWidget);
    expect(find.text(kLedgerUncheckable), findsOneWidget);
    expect(find.text('8 Oct'), findsOneWidget);
  });

  testWidgets('one glyph per verdict', (tester) async {
    await _open(tester, (_) => _json());
    for (final (verdict, label) in <(LedgerVerdict, String)>[
      (LedgerVerdict.done, 'Done'),
      (LedgerVerdict.partial, 'Partly done'),
      (LedgerVerdict.missed, 'Missed'),
      (LedgerVerdict.noData, 'No reading'),
      (LedgerVerdict.uncheckable, 'Not checkable'),
    ]) {
      expect(
        find.byWidgetPredicate(
          (w) => w is VerdictGlyph && w.verdict == verdict,
        ),
        findsOneWidget,
        reason: label,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == label,
        ),
        findsOneWidget,
      );
    }
    expect(find.text('?'), findsNWidgets(2));
  });

  testWidgets('the pattern shows verbatim and hides on null', (tester) async {
    await _open(tester, (_) => _json());
    expect(find.text('What the pattern says'), findsOneWidget);
    expect(find.text('Your yeses come in bursts.'), findsOneWidget);
    await _open(tester, (_) => {..._json(), 'pattern': null});
    expect(find.text('What the pattern says'), findsNothing);
  });

  testWidgets('switching the window refetches for that window', (tester) async {
    final asked = <LedgerWindow>[];
    await _open(tester, (_) => _json(), asked: asked);
    expect(asked, <LedgerWindow>[LedgerWindow.month]);
    await tester.tap(find.text('Week'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(asked, <LedgerWindow>[
      LedgerWindow.month,
      LedgerWindow.week,
      LedgerWindow.all,
    ]);
  });

  testWidgets('an empty ledger says so honestly', (tester) async {
    await _open(
      tester,
      (_) => <String, Object?>{
        'window': 'month',
        'from': '2026-09-20',
        'to': '2026-10-18',
        'weeks': <Object?>[],
      },
    );
    expect(find.text('No yeses to check yet'), findsOneWidget);
    expect(find.text('What the pattern says'), findsNothing);
    expect(find.textContaining('Done rate'), findsNothing);
  });
}
