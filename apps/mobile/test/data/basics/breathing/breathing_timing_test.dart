import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/basics/breathing/breathing_timing.dart';

int m(int h, int min) => h * 60 + min;

void main() {
  group('median wake', () {
    test('odd count takes the middle', () {
      expect(
        medianWakeMinute([m(7, 0), m(8, 14), m(9, 0), m(8, 0), m(10, 0)]),
        m(8, 14),
      );
    });

    test('even count averages the middle two, rounding half up', () {
      expect(
        medianWakeMinute([
          m(7, 0),
          m(8, 0),
          m(8, 1),
          m(9, 0),
          m(9, 30),
          m(6, 0),
        ]),
        m(8, 1),
      );
    });

    test('fewer than five nights gives nothing', () {
      expect(medianWakeMinute([m(7, 0), m(8, 0), m(9, 0), m(8, 30)]), isNull);
      expect(medianWakeMinute(const []), isNull);
    });

    test('values on either side of midnight order on one axis', () {
      // 23:50, 00:10, 00:20, 23:55, 00:05 sorted around noon: median is 00:05.
      expect(
        medianWakeMinute([m(23, 50), m(0, 10), m(0, 20), m(23, 55), m(0, 5)]),
        m(0, 5),
      );
    });
  });

  group('first quarter-hour at least 15 minutes after', () {
    test('boundaries', () {
      expect(firstQuarterHourAfter(m(8, 0)), m(8, 15));
      expect(firstQuarterHourAfter(m(8, 14)), m(8, 30));
      expect(firstQuarterHourAfter(m(8, 15)), m(8, 30));
      expect(firstQuarterHourAfter(m(8, 16)), m(8, 45));
      expect(firstQuarterHourAfter(m(8, 30)), m(8, 45));
    });

    test('wraps past midnight', () {
      expect(firstQuarterHourAfter(m(23, 50)), m(0, 15));
    });
  });

  group('lights-out range', () {
    test('spans midnight on one axis anchored at 18:00', () {
      final range = lightsOutRange([m(21, 43), m(23, 30), m(0, 40), m(4, 27)])!;
      expect(range.earliest, m(21, 43));
      expect(range.latest, m(4, 27));
      expect(range.nights, 4);
    });

    test('an evening-only range stays evening', () {
      final range = lightsOutRange([m(22, 0), m(23, 0), m(22, 30)])!;
      expect(range.earliest, m(22, 0));
      expect(range.latest, m(23, 0));
    });

    test('fewer than three nights gives nothing', () {
      expect(lightsOutRange([m(22, 0), m(23, 0)]), isNull);
    });
  });

  test('clock formatting', () {
    expect(formatClock(m(8, 14), meridiem: false), '8:14');
    expect(formatClock(m(21, 43)), '9:43 pm');
    expect(formatClock(m(4, 27)), '4:27 am');
    expect(formatClock(0), '12:00 am');
    expect(formatClock(m(12, 5)), '12:05 pm');
  });
}
