import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/coach/ledger_models.dart';

import '../../features/_workouts_host.dart' show loadSnapshot;

const String _path = '../../packages/contracts/snapshots/coach_ledger.json';

void main() {
  final json = loadSnapshot(_path);

  test('the committed snapshot parses into typed models', () {
    final ledger = CoachLedger.fromJson(json);
    expect(ledger.window, 'month');
    expect(ledger.from, '2026-09-20');
    expect(ledger.ideasGiven, 41);
    expect(ledger.totals.done, 1);
    expect(ledger.totals.noProof, 2);
    expect(ledger.doneRate.provable, 3);
    expect(ledger.weeks, hasLength(5));
    expect(ledger.pattern, 'Your yeses come in bursts.');
    final entries = ledger.weeks[1].entries;
    expect(entries.map((e) => e.verdict), <LedgerVerdict>[
      LedgerVerdict.noData,
      LedgerVerdict.uncheckable,
      LedgerVerdict.missed,
      LedgerVerdict.done,
    ]);
    expect(entries[2].measured.text, '1,578 steps');
    expect(entries[0].measured.text, isNull);
  });

  test('an unknown verdict is no data, never done', () {
    expect(LedgerVerdict.parse('achieved'), LedgerVerdict.noData);
    expect(LedgerVerdict.parse(null), LedgerVerdict.noData);
    expect(LedgerVerdict.parse('done'), LedgerVerdict.done);
  });

  test('measured falls back to value and unit, and never invents', () {
    expect(const LedgerMeasured(value: 12, unit: 'min').text, '12 min');
    expect(const LedgerMeasured(value: 12.5).text, '12.5');
    expect(const LedgerMeasured().text, isNull);
    expect(LedgerMeasured.fromJson(null).text, isNull);
  });

  test('a null or blank pattern is null', () {
    expect(CoachLedger.fromJson({...json, 'pattern': null}).pattern, isNull);
    expect(CoachLedger.fromJson({...json, 'pattern': '  '}).pattern, isNull);
  });

  test('an empty response is an empty ledger', () {
    final ledger = CoachLedger.fromJson(<String, Object?>{});
    expect(ledger.isEmpty, isTrue);
    expect(ledger.totals.all, 0);
  });
}
