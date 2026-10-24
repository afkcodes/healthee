/// The `Beyond a single night` cards: a fortnight read against the one before.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/models/sleep_night.dart';
import 'package:healthee/data/models/sleep_page.dart';
import 'package:healthee/features/sleep/v02/trend_panels.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:healthee/shared/v02/key_number_card.dart';
import 'package:healthee/shared/v02/trend_card.dart';

import '../_sleep_stubs.dart';
import '_sleep_host.dart';

/// The snapshot's 30 nights with HRV set: the newest 14 to [recent], the 14
/// before to [earlier], cycling.
List<SleepNight> _nights(List<double> recent, List<double> earlier) {
  final json = loadJson(kSleepSnapshotPath);
  final nights = json['nights']! as List<Object?>;
  var i = 0;
  return SleepPage.fromJson(<String, Object?>{
    ...json,
    'nights': <Object?>[
      for (final night in nights)
        <String, Object?>{
          ...night! as Map<String, Object?>,
          'hrv_sleep_avg': i < 14
              ? recent[i++ % recent.length]
              : earlier[(i++ - 14) % earlier.length],
        },
    ],
  }).nights;
}

Future<void> _pump(WidgetTester tester, List<SleepNight> nights) async {
  await tester.pumpWidget(
    sleepPanelHost(
      SleepTrendPanel(
        trend: kSleepTrends.last,
        recent: nights.take(14).toList(),
        earlier: nights.skip(14).take(14).toList(),
        reveals: RevealRegistry(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Verdict _chip(WidgetTester tester) =>
    tester.widget<VerdictChip>(find.byType(VerdictChip)).verdict;

void main() {
  testWidgets('higher than the fortnight before is the better side', (
    tester,
  ) async {
    await _pump(tester, _nights(<double>[50], <double>[40, 42, 44, 46]));

    expect(find.text('50'), findsWidgets);
    expect(_chip(tester).words, '↑ 7 vs the fortnight before');
    expect(_chip(tester).tone, VerdictTone.better);
    // Band 41–44.5 from the fortnight before; no night of 50 sits inside it.
    expect(find.textContaining('0 of 14 nights'), findsOneWidget);
  });

  testWidgets('lower HRV is the worse side', (tester) async {
    await _pump(tester, _nights(<double>[40], <double>[50, 52, 54]));
    expect(_chip(tester).tone, VerdictTone.worse);
  });

  testWidgets('without seven earlier nights there is no band and no change', (
    tester,
  ) async {
    final nights = _nights(<double>[45], <double>[45]).take(20).toList();
    await _pump(tester, nights);

    expect(find.byType(VerdictChip), findsNothing);
    expect(find.textContaining('still being learned'), findsOneWidget);
    expect(find.text(kTrendLegend), findsNothing);
  });
}
