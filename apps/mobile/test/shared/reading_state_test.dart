/// The colour kit's rule 4, one row per case: how a reading is judged.
///
/// Inside the range is neutral. Green is earned by being better than usual,
/// red by being worse; a best-inside-range metric is yellow on either side; a
/// reading with no range says so, and one with no value is "No reading".
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/honesty/reading.dart';
import 'package:healthee/data/models/metric_card.dart';
import 'package:healthee/shared/usual_range.dart';
import 'package:healthee/shared/v02/reading_state.dart';

void main() {
  const usual = UsualRange(low: 44, high: 57, days: 30);
  Judgement of(
    double? v,
    Polarity p, {
    double? goal,
    UsualRange? range = usual,
  }) => judge(value: v, usual: range, polarity: p, goal: goal);

  group('inside the range is neutral, never green', () {
    for (final p in Polarity.values.where((p) => p != Polarity.goal)) {
      test('$p', () {
        expect(of(50, p), const Judgement(ReadingState.usual, 'Usual'));
      });
    }
  });

  test('higher is better: above is better, below is worse', () {
    expect(of(60, Polarity.higherBetter).state, ReadingState.better);
    expect(of(40, Polarity.higherBetter).state, ReadingState.worse);
    expect(of(40, Polarity.higherBetter).words, '↓ Below usual');
  });

  test('lower is better: below is better, above is worse', () {
    expect(of(40, Polarity.lowerBetter).state, ReadingState.better);
    expect(of(60, Polarity.lowerBetter).state, ReadingState.worse);
    expect(of(60, Polarity.lowerBetter).words, '↑ Above usual');
  });

  test('best inside the range is watch on either side, not good or bad', () {
    expect(of(60, Polarity.insideRange).state, ReadingState.watch);
    expect(of(40, Polarity.insideRange).state, ReadingState.watch);
    expect(of(60, Polarity.insideRange).words, '↑ Outside usual');
  });

  test('no judgement outside the range spends no colour', () {
    expect(of(60, Polarity.neutral).state, ReadingState.usual);
    expect(of(60, Polarity.neutral).words, '↑ Above usual');
  });

  test('a goal is met or short by a count', () {
    expect(of(6000, Polarity.goal, goal: 6000).words, 'Goal met');
    expect(of(6000, Polarity.goal, goal: 6000).state, ReadingState.better);
    expect(of(4, Polarity.goal, goal: 150).words, '146 to go');
    expect(of(4, Polarity.goal, goal: 150).state, ReadingState.worse);
  });

  test('no range yet is not a verdict; no value is no reading', () {
    expect(
      of(50, Polarity.higherBetter, range: null),
      const Judgement(ReadingState.usual, 'No trend yet'),
    );
    expect(
      of(null, Polarity.higherBetter),
      const Judgement(ReadingState.noData, 'No reading'),
    );
  });

  test("the usual range is the server's median ± sd, or none", () {
    MetricCard card(double? m, double? sd) => MetricCard(
      metric: 'x',
      label: 'X',
      reading: const Present<double>(1),
      unit: null,
      median30d: m,
      sd30d: sd,
      z: null,
      anomalous: false,
    );
    expect(usualOfCard(card(55, 2.7))!.low, closeTo(52.3, 1e-9));
    expect(usualOfCard(card(55, 2.7))!.high, closeTo(57.7, 1e-9));
    expect(usualOfCard(card(null, 2.7)), isNull);
    expect(usualOfCard(card(55, 0)), isNull);
  });

  test('polarity by metric id', () {
    expect(polarityOf('hrv_sleep_avg'), Polarity.higherBetter);
    expect(polarityOf('rhr_daily'), Polarity.lowerBetter);
    expect(polarityOf('spo2_overnight'), Polarity.insideRange);
    expect(polarityOf('mvpa_min'), Polarity.goal);
    expect(polarityOf('nothing_known'), Polarity.neutral);
  });
}
