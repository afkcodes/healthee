import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/basics/breathing/breathing_history.dart';
import 'package:healthee/data/store/local_store.dart';

void main() {
  late LocalStore store;
  final now = DateTime(2026, 10, 18, 9);
  setUp(() => store = LocalStore.memory());
  tearDown(() => store.close());

  Future<void> session(
    DateTime start,
    DateTime end, {
    bool nap = false,
    String? stages,
  }) => store
      .into(store.sleepSessions)
      .insert(
        SleepSessionsCompanion.insert(
          startMs: Value(start.millisecondsSinceEpoch),
          day: '2026-10-17',
          isNap: nap,
          sleepStartMin: 0,
          sleepEndMin: 0,
          avgHr: 0,
          score: 0,
          remMin: 0,
          lightMin: 0,
          deepMin: 0,
          wakeMin: 0,
          stagesJson:
              stages ??
              '[[${start.millisecondsSinceEpoch},${end.millisecondsSinceEpoch},4]]',
        ),
      );

  Future<void> sample(String metric, DateTime at, double value) => store
      .into(store.strapSamples)
      .insert(
        StrapSamplesCompanion.insert(
          metric: metric,
          tsMs: at.millisecondsSinceEpoch,
          day: '2026-10-17',
          value: value,
        ),
      );

  test('an empty store is an empty history', () async {
    final history = await readBreathingHistory(store, now);
    expect(history.nights, isEmpty);
    expect(history.stress, isEmpty);
  });

  test(
    'nights come from staged main sleep, newest first, naps excluded',
    () async {
      await session(DateTime(2026, 10, 16, 23), DateTime(2026, 10, 17, 7));
      await session(
        DateTime(2026, 10, 17, 23, 30),
        DateTime(2026, 10, 18, 7, 20),
      );
      await session(
        DateTime(2026, 10, 17, 14),
        DateTime(2026, 10, 17, 14, 30),
        nap: true,
      );
      await session(
        DateTime(2026, 10, 15, 23),
        DateTime(2026, 10, 16, 7),
        stages: '[]',
      );
      final history = await readBreathingHistory(store, now);
      expect(history.nights.length, 2);
      expect(history.nights.first.onset, DateTime(2026, 10, 17, 23, 30));
      expect(history.nights.first.wake, DateTime(2026, 10, 18, 7, 20));
    },
  );

  test('awake stages become awake spans', () async {
    final a = DateTime(2026, 10, 18, 4, 10);
    final b = DateTime(2026, 10, 18, 4, 40);
    final start = DateTime(2026, 10, 17, 23);
    final end = DateTime(2026, 10, 18, 7);
    await session(
      start,
      end,
      stages:
          '[[${start.millisecondsSinceEpoch},${a.millisecondsSinceEpoch},4],'
          '[${a.millisecondsSinceEpoch},${b.millisecondsSinceEpoch},7],'
          '[${b.millisecondsSinceEpoch},${end.millisecondsSinceEpoch},5]]',
    );
    final history = await readBreathingHistory(store, now);
    expect(history.awake.single.start, a);
    expect(history.awake.single.end, b);
  });

  test('only stress from the last seven days, not other metrics', () async {
    await sample(kStressMetric, DateTime(2026, 10, 17, 4), 33);
    await sample(kStressMetric, DateTime(2026, 10, 1, 4), 80);
    await sample('hr', DateTime(2026, 10, 17, 4), 60);
    final history = await readBreathingHistory(store, now);
    expect(history.stress.single.value, 33);
  });

  test('a malformed stage entry is skipped, not guessed', () async {
    final start = DateTime(2026, 10, 17, 23);
    await session(
      start,
      start,
      stages:
          '[[1,2],"x",[${start.millisecondsSinceEpoch},${start.millisecondsSinceEpoch + 60000},4]]',
    );
    final history = await readBreathingHistory(store, now);
    expect(history.nights.length, 1);
  });
}
