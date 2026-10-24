/// `Bed and wake times`: one bar per night, and the bedtime spread.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/models/sleep_night.dart';
import 'package:healthee/data/models/sleep_page.dart';
import 'package:healthee/features/sleep/v02/bed_wake_week.dart';
import 'package:healthee/shared/reveal_once.dart';

import '../_sleep_stubs.dart';
import '_sleep_host.dart';

/// The snapshot's nights with local start and end clocks swapped in, newest
/// first; a null pair drops the session times.
List<SleepNight> _nights(List<(String, String)?> times) {
  final json = loadJson(kSleepSnapshotPath);
  final nights = json['nights']! as List<Object?>;
  return SleepPage.fromJson(<String, Object?>{
    ...json,
    'nights': <Object?>[
      for (var i = 0; i < times.length; i++)
        <String, Object?>{
          ...nights[i]! as Map<String, Object?>,
          'start_iso': times[i]?.$1,
          'end_iso': times[i]?.$2,
        },
    ],
  }).nights;
}

void main() {
  test('a bedtime before 18:00 runs back past the origin, not off the end', () {
    final week = bedWakeWeek(
      _nights(<(String, String)?>[
        (
          DateTime(2026, 7, 30, 17, 30).toIso8601String(),
          DateTime(2026, 7, 31, 1).toIso8601String(),
        ),
      ]),
    );
    expect(week.single.bed, closeTo(-0.5, 1e-9));
    expect(week.single.wake, closeTo(7, 1e-9));
  });

  testWidgets('the figure is the spread of bedtimes, and a gap says no data', (
    tester,
  ) async {
    final week = bedWakeWeek(
      _nights(<(String, String)?>[
        (
          DateTime(2026, 7, 31, 0, 30).toIso8601String(),
          DateTime(2026, 7, 31, 7, 30).toIso8601String(),
        ),
        null,
        (
          DateTime(2026, 7, 28, 22, 45).toIso8601String(),
          DateTime(2026, 7, 29, 6, 45).toIso8601String(),
        ),
      ]),
    );
    expect(week.where((n) => n.bed == null), hasLength(1));

    await tester.pumpWidget(
      sleepPanelHost(BedWakeWeekPanel(nights: week, reveals: RevealRegistry())),
    );
    await tester.pumpAndSettle();
    expect(find.text('1\u00A0h 45\u00A0min'), findsOneWidget);
    expect(find.text(kBedWakeLine), findsOneWidget);
  });
}
