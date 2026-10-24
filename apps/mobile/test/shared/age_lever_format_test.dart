import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/models/biological_age.dart';
import 'package:healthee/shared/format/age_lever_format.dart';
import 'package:healthee/shared/v02/key_number_card.dart';

AgeContribution _c(
  String term, {
  double? value,
  double? comparedAs,
  String? unit,
}) => AgeContribution(
  term: term,
  deltaYears: 0,
  value: value,
  target: null,
  unit: unit,
  method: null,
  comparedAs: comparedAs,
);

void main() {
  group('signedYears', () {
    test('uses a real minus, a plus, and no sign at zero', () {
      expect(signedYears(-1.7), '−1.7');
      expect(signedYears(2.1), '+2.1');
      expect(signedYears(0), '0.0');
      expect(signedYears(0.04), '0.0');
      expect(signedYears(-0.04), '0.0');
      expect(signedYears(-0.06), '−0.1');
    });

    test('honours digits', () {
      expect(signedYears(-1.234, digits: 2), '−1.23');
      expect(signedYears(0.004, digits: 2), '0.00');
      expect(signedYears(3, digits: 0), '+3');
    });

    test('the sign is its own span, pulled in by 0.14 em', () {
      const style = TextStyle(fontSize: 28);
      final span = signedYearsSpan(-1.7, style);
      expect(span.toPlainText(), '−1.7');
      final sign = span.children!.first as TextSpan;
      expect(sign.text, '−');
      expect(sign.style!.letterSpacing, closeTo(-0.14 * 28, 1e-9));
      expect(signedYearsSpan(0.04, style).toPlainText(), '0.0');
      expect(signedYearsSpan(0.04, style).children, isNull);
    });
  });

  group('leverValue', () {
    test('fitness is one decimal in mL/kg/min whatever the payload unit', () {
      final v = leverValue(_c('fitness', value: 43, unit: 'ml/kg/min VO2max'));
      expect((v.value, v.unit), ('43.0', 'mL/kg/min'));
    });

    test('sleep reads the compared-as value, in hours', () {
      final v = leverValue(_c('sleep duration', value: 6.3, comparedAs: 7));
      expect((v.value, v.unit), ('7.0', 'h'));
      final plain = leverValue(_c('sleep duration', value: 6.3));
      expect(plain.value, '6.3');
    });

    test('an unknown term keeps the payload unit', () {
      final v = leverValue(_c('steps', value: 8.25, unit: 'k/day'));
      expect((v.value, v.unit), ('8.3', 'k/day'));
    });
  });

  test('verdict thresholds sit at half a year', () {
    expect(verdictForDelta(-0.5), VerdictTone.better);
    expect(verdictForDelta(-0.49), VerdictTone.neutral);
    expect(verdictForDelta(0), VerdictTone.neutral);
    expect(verdictForDelta(0.49), VerdictTone.neutral);
    expect(verdictForDelta(0.5), VerdictTone.worse);
  });

  test('labels', () {
    expect(leverLabel('fitness'), 'Fitness · VO₂max');
    expect(leverLabel('sleep duration'), 'Sleep duration');
    expect(leverLabel('sleep_regularity'), 'Sleep duration');
    expect(leverLabel('body_mass'), 'Body mass');
    expect(leverShortName('sleep duration'), 'Sleep');
    expect(leverShortName('regularity'), 'Regularity');
  });
}
