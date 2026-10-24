/// Today's three key numbers on the real screen: their labels, their night,
/// both themes, and what each says against the owner's own usual.
///
/// ## What this file used to be
///
/// The suite for the three v02 summary tiles, and before that for legacy's
/// six-cell grid. The redesign the owner approved (`proposal.js`, `#p-today`)
/// replaced the tiles with three full-width cards that each draw a range bar
/// against the owner's usual (`usual_range.dart`). The tiles' claims that still
/// hold (the three labels, the server's night, both themes) carried over.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/data/history/dated_history.dart';
import 'package:healthee/data/models/sleep_page.dart';
import 'package:healthee/data/models/trend_point.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/today/v02/today_key_numbers.dart';
import 'package:healthee/shared/v02/key_number_card.dart';
import 'package:healthee/shared/v02/steps_bar.dart';

import '../_sleep_stubs.dart';
import '_today_host.dart';

/// The 14 days before the snapshot's 31 July, invented.
DatedHistory _history({List<double>? recovery, List<double>? steps}) {
  final end = DateTime.utc(2026, 7, 31);
  List<TrendPoint> series(List<double> values) => <TrendPoint>[
    for (var i = 0; i < values.length; i++)
      TrendPoint(
        date: end
            .subtract(Duration(days: values.length - i))
            .toIso8601String()
            .substring(0, 10),
        value: values[i],
      ),
  ];
  return DatedHistory(
    days: 90,
    series: <String, List<TrendPoint>>{
      'recovery_score': series(recovery ?? List<double>.filled(14, 65)),
      'steps_total': series(steps ?? List<double>.filled(14, 6000)),
    },
  );
}

/// The snapshot's Sleep page with every night before the newest at [minutes].
SleepPage _nightsAt(double minutes) {
  final json = loadJson(kSleepSnapshotPath);
  final nights = json['nights']! as List<Object?>;
  return SleepPage.fromJson(<String, Object?>{
    ...json,
    'nights': <Object?>[
      nights.first,
      for (final Object? night in nights.skip(1))
        <String, Object?>{
          ...night! as Map<String, Object?>,
          'tst_min': minutes,
        },
    ],
  });
}

KeyNumberCard _card(WidgetTester tester, String name) =>
    tester.widget<KeyNumberCard>(
      find.byWidgetPredicate((w) => w is KeyNumberCard && w.name == name),
    );

void main() {
  late LocalStore store;

  setUp(() async {
    store = LocalStore.memory();
    await seedDevice(store);
  });
  tearDown(() async => store.close());

  Future<void> pump(
    WidgetTester tester, {
    DatedHistory? history,
    SleepPage? sleep,
    ThemeData? theme,
  }) async {
    tester.view
      ..physicalSize = const Size(420, 14000)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      todayHost(store, history: history, sleep: sleep, themeOverride: theme),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('THREE CARDS, BY THE PROTOTYPE\'S OWN LABELS', (tester) async {
    await pump(tester);
    expect(find.byType(TodayKeyNumbers), findsOneWidget);
    for (final name in <String>['Recovery', 'Sleep', 'Movement']) {
      expect(_card(tester, name).name, name);
    }
  });

  testWidgets('the sleep card reads the SERVER night the judgements came from', (
    tester,
  ) async {
    // `last_sleep.duration_min` is 380 in the contract snapshot; the strap row
    // the store was seeded with is a different night.
    await pump(tester);
    expect(_card(tester, 'Sleep').value, '6\u00A0h 20\u00A0min');
  });

  testWidgets('renders in BOTH themes', (tester) async {
    for (final theme in <ThemeData>[AppTheme.light, AppTheme.dark]) {
      await pump(tester, history: _history(), theme: theme);
      expect(tester.takeException(), isNull);
      expect(find.byType(KeyNumberCard), findsNWidgets(3));
    }
  });

  testWidgets('ABOVE THE BAND IS SAID, AND IN THE BETTER INK', (tester) async {
    // The snapshot's recovery is 72; these 14 mornings put the band at 60–70.
    await pump(
      tester,
      history: _history(
        recovery: <double>[
          61,
          72,
          58,
          66,
          70,
          55,
          63,
          74,
          59,
          68,
          64,
          57,
          71,
          62,
        ],
      ),
    );
    final recovery = _card(tester, 'Recovery');
    expect(recovery.verdict?.words, 'Above your usual');
    expect(recovery.verdict?.tone, VerdictTone.better);
    expect(find.text('usual 60 to 70'), findsOneWidget);
    expect(recovery.line, 'You started higher than most of your mornings.');
  });

  testWidgets('BELOW THE BAND IS THE ONLY AMBER', (tester) async {
    await pump(
      tester,
      history: _history(recovery: List<double>.generate(14, (i) => 80.0 + i)),
    );
    final recovery = _card(tester, 'Recovery');
    expect(recovery.verdict?.words, 'Below your usual');
    expect(recovery.verdict?.tone, VerdictTone.worse);
  });

  testWidgets('WITH TOO FEW DAYS THERE IS NO VERDICT, AND THE BAR SAYS WHY', (
    tester,
  ) async {
    // The host's default history is empty: no recovery or step days at all.
    await pump(tester);
    expect(_card(tester, 'Recovery').verdict, isNull);
    expect(find.text(kLearningUsual), findsNWidgets(2));
  });

  testWidgets('A DAY STILL RUNNING GETS NO STEP VERDICT', (tester) async {
    // A morning's count against whole days would read "Below your usual"
    // every morning. The snapshot is the owner's today.
    await pump(tester, history: _history());
    final movement = _card(tester, 'Movement');
    expect(movement.verdict?.words, 'So far today');
    expect(movement.verdict?.tone, VerdictTone.neutral);
    expect(find.textContaining("by day's end"), findsOneWidget);
  });

  testWidgets('LESS SLEEP THAN USUAL IS THE WORSE SIDE', (tester) async {
    await pump(tester, sleep: _nightsAt(480));
    final sleep = _card(tester, 'Sleep');
    expect(sleep.verdict?.words, 'Below your usual');
    expect(sleep.verdict?.tone, VerdictTone.worse);
  });

  testWidgets('MORE SLEEP THAN USUAL IS SAID, BUT NOT SCORED BETTER', (
    tester,
  ) async {
    // Long sleep is its own question, so above the band is neutral ink.
    await pump(tester, sleep: _nightsAt(300));
    final sleep = _card(tester, 'Sleep');
    expect(sleep.verdict?.words, 'Above your usual');
    expect(sleep.verdict?.tone, VerdictTone.neutral);
  });

  testWidgets('a band whose ends round alike says "about"', (tester) async {
    // Every earlier night in the snapshot is 380 minutes.
    await pump(tester);
    expect(find.text('usual about 6\u00A0h 20\u00A0min'), findsOneWidget);
  });
}
