/// The one duration format. Known values, and the two joins that must hold:
/// U+00A0 between a figure and its unit, U+2212 for a negative.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/shared/format/duration.dart';

void main() {
  group('durationText', () {
    test('known values', () {
      expect(durationText(421), '7 h 1 min');
      expect(durationText(480), '8 h');
      expect(durationText(45), '45 min');
      expect(durationText(0), '0 min');
      expect(durationText(61), '1 h 1 min');
    });

    test('rounds to a whole minute before splitting', () {
      expect(durationText(59.6), '1 h');
      expect(durationText(59.4), '59 min');
    });

    test('a negative takes U+2212 on the whole, never a hyphen', () {
      expect(durationText(-30), '−30 min');
      expect(durationText(-65), '−1 h 5 min');
      expect(durationText(-30).contains('-'), isFalse);
    });

    test('never emits a thin space or a bare ASCII gap before a unit', () {
      final text = durationText(421);
      expect(text.contains(' '), isFalse);
      expect(text.contains('7 h'), isFalse);
      expect(text.contains('1 min'), isFalse);
    });
  });

  group('hoursText', () {
    test('whole hours have no decimal, others take one', () {
      expect(hoursText(4), '4 h');
      expect(hoursText(10), '10 h');
      expect(hoursText(7.5), '7.5 h');
      expect(hoursText(6.33), '6.3 h');
    });

    test('a negative takes U+2212', () {
      expect(hoursText(-1.5), '−1.5 h');
    });
  });
}
