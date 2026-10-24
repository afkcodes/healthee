/// Today's "what to do tonight": the server's lever, or nothing at all.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/models/sleep_consistency.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/sleep/v02/tail_panels.dart';

import '../_sleep_stubs.dart';
import '_today_host.dart';

SleepConsistency _withLever() => SleepConsistency.fromJson(<String, Object?>{
  ...loadJson(kConsistencySnapshotPath),
  'tonight': const <String, Object?>{
    'title': 'Hold your bedtime',
    'lever': 'bedtime',
    'target_clock': '23:00',
    'action': 'Lights out by 23:00 tonight.',
  },
});

void main() {
  late LocalStore store;

  setUp(() async {
    store = LocalStore.memory();
    await seedDevice(store);
  });
  tearDown(() async => store.close());

  Future<void> pump(WidgetTester tester, SleepConsistency consistency) async {
    tester.view
      ..physicalSize = const Size(420, 14000)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(todayHost(store, consistency: consistency));
    await tester.pumpAndSettle();
  }

  testWidgets('the server lever is drawn under the three', (tester) async {
    await pump(tester, _withLever());
    expect(find.byType(TonightPanel), findsOneWidget);
    expect(find.text('Hold your bedtime'), findsOneWidget);
    expect(find.text('23:00'), findsOneWidget);
  });

  testWidgets('no lever, no card and no placeholder', (tester) async {
    await pump(tester, consistencyFixture());
    expect(find.byType(TonightPanel), findsNothing);
  });
}
