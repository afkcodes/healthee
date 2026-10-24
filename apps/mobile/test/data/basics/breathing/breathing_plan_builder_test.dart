import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/basics/breathing/breathing_history.dart';
import 'package:healthee/data/basics/breathing/breathing_pattern.dart';
import 'package:healthee/data/basics/breathing/breathing_plan.dart';
import 'package:healthee/data/basics/breathing/breathing_plan_builder.dart';
import 'package:healthee/data/basics/breathing/breathing_settings.dart';
import 'package:healthee/shared/usual_range.dart';

/// A Sunday morning.
final DateTime now = DateTime(2026, 10, 18, 9, 0);

/// [count] nights ending [daysAgo] days back, sleeping [onset] to [wake].
List<SleepNight> nights(
  int count, {
  (int, int) onset = (23, 0),
  (int, int) wake = (7, 0),
}) => [
  for (var i = 0; i < count; i++)
    SleepNight(
      onset: DateTime(2026, 10, 17 - i, onset.$1, onset.$2),
      wake: DateTime(2026, 10, 18 - i, wake.$1, wake.$2),
    ),
];

BreathingPlan build({
  List<SleepNight> sleep = const [],
  List<StressSample> stress = const [],
  List<AwakeSpan> awake = const [],
  BreathingSettings settings = const BreathingSettings(),
  double? hrv,
  UsualRange? usual,
}) => buildBreathingPlan(
  now: now,
  history: BreathingHistory(nights: sleep, stress: stress, awake: awake),
  settings: settings,
  hrv: hrv,
  hrvUsual: usual,
);

const UsualRange usual = UsualRange(low: 44, high: 57, days: 30);

void main() {
  group('morning', () {
    test('time is the first quarter-hour 15 minutes after the median wake', () {
      final plan = build(sleep: nights(6, wake: (8, 14)));
      final morning = plan.item(BreathingItemKind.morning)!;
      expect(morning.minuteOfDay, 8 * 60 + 30);
      expect(morning.timeIsDefault, isFalse);
      expect(morning.reason, startsWith('You wake around 8:14.'));
      expect(morning.pattern, kSteady);
      expect(morning.minutes, 5);
    });

    test('fewer than five nights uses the default and claims nothing', () {
      final plan = build(sleep: nights(4, wake: (8, 14)));
      final morning = plan.item(BreathingItemKind.morning)!;
      expect(morning.minuteOfDay, 480);
      expect(morning.timeIsDefault, isTrue);
      expect(morning.reason, 'Not enough nights yet to time this.');
    });

    test('the default time is the owner set one', () {
      final plan = build(
        settings: const BreathingSettings(morningDefaultMinute: 450),
      );
      expect(plan.item(BreathingItemKind.morning)!.minuteOfDay, 450);
    });

    test('HRV sentence: just under, over, within, far under', () {
      String reason(double hrv) => build(
        sleep: nights(6, wake: (8, 14)),
        hrv: hrv,
        usual: usual,
      ).item(BreathingItemKind.morning)!.reason;
      expect(
        reason(43.9),
        'You wake around 8:14. This morning HRV was 43.9, '
        'just under your usual 44 to 57.',
      );
      expect(reason(57.5), endsWith('just over your usual 44 to 57.'));
      expect(reason(50), endsWith('within your usual 44 to 57.'));
      expect(reason(30), endsWith('under your usual 44 to 57.'));
      expect(reason(30), isNot(contains('just')));
    });

    test('HRV sentence is dropped when either input is missing', () {
      for (final plan in [
        build(sleep: nights(6), hrv: 50),
        build(sleep: nights(6), usual: usual),
      ]) {
        expect(
          plan.item(BreathingItemKind.morning)!.reason,
          'You wake around 7:00.',
        );
      }
    });
  });

  test('midday is fixed at 14:00 and says it is not in our base', () {
    final midday = build().item(BreathingItemKind.midday)!;
    expect(midday.minuteOfDay, 840);
    expect(midday.pattern, kBox);
    expect(midday.minutes, 4);
    expect(
      midday.reason,
      'An afternoon reset. Not in our evidence base, '
      'so keep it only if it helps you.',
    );
  });

  test('midday with a cited pattern does not say it is uncited', () {
    final plan = build(
      settings: const BreathingSettings(
        patternOverrides: {BreathingItemKind.midday: 'steady'},
      ),
    );
    final midday = plan.item(BreathingItemKind.midday)!;
    expect(midday.reason, 'An afternoon reset.');
    expect(midday.pattern, kSteady);
  });

  group('night', () {
    test('uses the free-from time and the circular lights-out range', () {
      final plan = build(
        sleep: [
          for (final (i, onset) in [
            (21, 43),
            (23, 30),
            (0, 40),
            (4, 27),
          ].indexed)
            SleepNight(
              onset: DateTime(2026, 10, 17 - i, onset.$1, onset.$2),
              wake: DateTime(2026, 10, 18 - i, 9),
            ),
        ],
      );
      final night = plan.item(BreathingItemKind.night)!;
      expect(night.minuteOfDay, 22 * 60 + 15);
      expect(night.pattern, kLongExhale);
      expect(night.minutes, 10);
      expect(
        night.reason,
        'Right after your free time. Lights-out swung from 9:43 pm to '
        '4:27 am over 4 nights. This gives the night one fixed point.',
      );
    });

    test('fewer than three nights drops the range sentence', () {
      final night = build(sleep: nights(2)).item(BreathingItemKind.night)!;
      expect(night.reason, 'Right after your free time.');
    });

    test('free-from time is the owner setting', () {
      final plan = build(
        settings: const BreathingSettings(nightFreeFromMinute: 1290),
      );
      expect(plan.item(BreathingItemKind.night)!.minuteOfDay, 1290);
    });
  });

  group('on demand', () {
    StressSample at(int day, int hour, double value) =>
        StressSample(DateTime(2026, 10, day, hour, 30), value);

    test('present at 30, absent at 29', () {
      expect(
        build(stress: [at(17, 4, 30)]).item(BreathingItemKind.onDemand),
        isNotNull,
      );
      expect(
        build(stress: [at(17, 4, 29)]).item(BreathingItemKind.onDemand),
        isNull,
      );
    });

    test('absent outside midnight to six', () {
      expect(
        build(stress: [at(17, 6, 80)]).item(BreathingItemKind.onDemand),
        isNull,
      );
      expect(
        build(stress: [at(17, 14, 80)]).item(BreathingItemKind.onDemand),
        isNull,
      );
      expect(
        build(stress: [at(17, 0, 40)]).item(BreathingItemKind.onDemand),
        isNotNull,
      );
    });

    test('absent when the high reading is older than seven days', () {
      expect(
        build(stress: [at(11, 4, 80)]).item(BreathingItemKind.onDemand),
        isNull,
      );
      expect(
        build(stress: [at(12, 4, 80)]).item(BreathingItemKind.onDemand),
        isNotNull,
      );
    });

    test('absent with no stress series at all', () {
      expect(build().item(BreathingItemKind.onDemand), isNull);
      expect(build().items.length, 3);
    });

    test(
      'lay awake is claimed only when a session shows awake in that hour',
      () {
        final awake = AwakeSpan(
          DateTime(2026, 10, 17, 4, 10),
          DateTime(2026, 10, 17, 4, 50),
        );
        final withAwake = build(
          stress: [at(17, 4, 33)],
          awake: [awake],
        ).item(BreathingItemKind.onDemand)!;
        expect(
          withAwake.reason,
          'Stress hit 33 between 4 and 5 am yesterday while you lay awake. '
          'No reminder, open it from the lock screen.',
        );
        final without = build(
          stress: [at(17, 4, 33)],
        ).item(BreathingItemKind.onDemand)!;
        expect(without.reason, isNot(contains('awake')));
        expect(
          without.reason,
          startsWith('Stress hit 33 between 4 and 5 am yesterday.'),
        );
        final elsewhere = build(
          stress: [at(17, 4, 33)],
          awake: [
            AwakeSpan(DateTime(2026, 10, 17, 2), DateTime(2026, 10, 17, 3)),
          ],
        ).item(BreathingItemKind.onDemand)!;
        expect(elsewhere.reason, isNot(contains('awake')));
      },
    );

    test('the peak value and its weekday', () {
      final item = build(
        stress: [at(14, 3, 41), at(17, 4, 33)],
      ).item(BreathingItemKind.onDemand)!;
      expect(
        item.reason,
        startsWith('Stress hit 41 between 3 and 4 am on Wednesday'),
      );
      expect(item.minuteOfDay, isNull);
      expect(item.pattern, kLongExhale);
      expect(item.minutes, 5);
      expect(item.kind.reminderId, isNull);
    });

    test('a reading from this morning says so', () {
      final item = build(
        stress: [at(18, 5, 35)],
      ).item(BreathingItemKind.onDemand)!;
      expect(item.reason, contains('between 5 and 6 am this morning'));
    });
  });

  group('totals', () {
    test('morning, midday and night; on demand excluded', () {
      final plan = build(stress: [StressSample(DateTime(2026, 10, 17, 4), 40)]);
      expect(plan.items.length, 4);
      expect(plan.totalMinutesPerDay, 19);
    });

    test('only enabled items count', () {
      final plan = build(
        settings: const BreathingSettings(off: {BreathingItemKind.midday}),
      );
      expect(plan.totalMinutesPerDay, 15);
      expect(plan.item(BreathingItemKind.midday)!.enabled, isFalse);
    });
  });

  test('a custom pattern chosen for an item is used', () {
    final custom = BreathPattern.custom(
      inSeconds: 3,
      hold1Seconds: 0,
      outSeconds: 7,
      hold2Seconds: 0,
    );
    final plan = build(
      settings: BreathingSettings(
        custom: custom,
        patternOverrides: const {BreathingItemKind.night: 'custom'},
      ),
    );
    expect(plan.item(BreathingItemKind.night)!.pattern, custom);
  });

  group('structured reasons', () {
    test('the owner numbers are bold and the spans join to the reason', () {
      final plan = build(
        sleep: nights(6, wake: (8, 14)),
        hrv: 43.9,
        usual: usual,
        stress: [StressSample(DateTime(2026, 10, 17, 4, 30), 33)],
      );
      for (final item in plan.items) {
        expect(item.reasonParts.map((s) => s.text).join(), item.reason);
      }
      List<String> bold(BreathingItemKind k) => [
        for (final s in plan.item(k)!.reasonParts)
          if (s.bold) s.text,
      ];
      expect(bold(BreathingItemKind.morning), ['8:14', '43.9']);
      expect(bold(BreathingItemKind.night), ['11:00 pm to 11:00 pm']);
      expect(bold(BreathingItemKind.onDemand), ['33']);
      expect(bold(BreathingItemKind.midday), isEmpty);
    });

    test('nights used and the age of the stress come from the data', () {
      final plan = build(
        sleep: nights(9),
        stress: [StressSample(DateTime(2026, 10, 15, 4, 30), 40)],
      );
      expect(plan.nightsUsed, 9);
      expect(plan.stressDaysAgo, 3);
      final bare = build();
      expect(bare.nightsUsed, 0);
      expect(bare.stressDaysAgo, isNull);
    });
  });
}
