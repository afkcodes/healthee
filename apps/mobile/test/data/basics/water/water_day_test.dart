import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/api/server_snapshot.dart';
import 'package:healthee/data/basics/water/water_day.dart';
import 'package:healthee/data/basics/water/water_format.dart';
import 'package:healthee/data/basics/water/water_settings.dart';
import 'package:healthee/data/basics/water/water_settings_provider.dart';
import 'package:healthee/data/journal/journal_entry.dart';
import 'package:healthee/data/journal/journal_feed.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/data/store/store_provider.dart';

final DateTime _now = DateTime(2026, 10, 19, 15);

JournalEntry _water(
  int hour,
  int minute,
  double ml, {
  String? id,
  int day = 19,
}) => JournalEntry(
  type: 'water',
  at: DateTime(2026, 10, day, hour, minute).toUtc(),
  amount: ml,
  unit: 'ml',
  id: id ?? 'id-$day-$hour-$minute',
);

WaterDay _day(List<JournalEntry> entries, [List<WaterOp> ops = const []]) =>
    WaterDay.from(
      ServerSnapshot(
        JournalFeed(entries: entries, fastOpen: false),
        fetchedAt: DateTime(2026, 10, 19, 14),
      ),
      ops,
      _now,
    );

void main() {
  test('three glasses: total, fill and a time under each', () {
    final day = _day([
      _water(9, 10, 250),
      _water(11, 40, 250),
      _water(13, 5, 250),
    ]);
    expect(day.totalMl, 750);
    expect(day.filled, 3);
    expect(day.oneToOne, isTrue);
    expect(
      [for (var i = 0; i < 3; i++) day.timeLabel(i)],
      ['9:10', '11:40', '1:05'],
    );
  });

  test('a 500 ml entry fills two glasses and shows no times', () {
    final day = _day([_water(9, 10, 500)]);
    expect(day.filled, 2);
    expect(day.totalMl, 500);
    expect(day.oneToOne, isFalse);
    expect(day.timeLabel(0), isNull);
  });

  test('a partial glass is not counted as a glass', () {
    final day = _day([_water(9, 10, 250), _water(10, 0, 100)]);
    expect(day.totalMl, 350);
    expect(day.filled, 1);
    expect(day.timeLabel(0), isNull);
  });

  test('other days and other kinds are left out', () {
    final day = _day([
      _water(9, 10, 250, day: 18),
      JournalEntry(
        type: 'caffeine',
        at: DateTime(2026, 10, 19, 8).toUtc(),
        amount: 80,
      ),
      _water(9, 10, 250),
    ]);
    expect(day.totalMl, 250);
  });

  test('over the count simply keeps counting', () {
    final day = _day([for (var i = 0; i < 10; i++) _water(6 + i, 0, 250)]);
    expect(day.filled, 10);
  });

  test('a pending add shows at once; a removed id is hidden', () {
    final kept = _water(9, 10, 250, id: 'a');
    final gone = _water(10, 10, 250, id: 'b');
    final day = _day(
      [kept, gone],
      [
        WaterOp(serial: 1, added: WaterEntry(at: _now, ml: 250, pending: true)),
        const WaterOp(serial: 2, removedId: 'b'),
      ],
    );
    expect(day.totalMl, 500);
    expect(day.latest!.pending, isTrue);
  });

  test('a confirmed op is dropped once a fresh feed after it arrives', () {
    final op = const WaterOp(
      serial: 1,
      removedId: 'b',
    ).confirmed(DateTime(2026, 10, 19, 14, 30));
    final entries = [_water(9, 10, 250, id: 'b')];
    ServerSnapshot<JournalFeed> snap(DateTime at, {required bool stale}) =>
        ServerSnapshot(
          JournalFeed(entries: entries, fastOpen: false),
          fetchedAt: at,
          stale: stale,
        );
    expect(
      WaterDay.from(snap(DateTime(2026, 10, 19, 15), stale: true), [
        op,
      ], _now).totalMl,
      0,
    );
    expect(
      WaterDay.from(snap(DateTime(2026, 10, 19, 15), stale: false), [
        op,
      ], _now).totalMl,
      250,
    );
  });

  test('formatting', () {
    expect(groupedMl(2000), '2,000');
    expect(groupedMl(750), '750');
    expect(groupedMl(0), '0');
    expect(glassTime(DateTime(2026, 10, 19, 0, 5)), '12:05');
    expect(glassTime(DateTime(2026, 10, 19, 13, 5)), '1:05');
  });

  test('settings: default until set, and a stored value reads back', () {
    expect(WaterSettings.decode(null).target, 8);
    expect(WaterSettings.decode(null).isSet, isFalse);
    final stored = WaterSettings.decode(
      const WaterSettings(glasses: 6).encode(),
    );
    expect(stored.target, 6);
    expect(stored.isSet, isTrue);
    expect(() => WaterSettings.decode('{"glasses":21}'), throwsFormatException);
    expect(() => WaterSettings.decode('[]'), throwsFormatException);
  });

  test('the glass count survives a restart of the provider', () async {
    final store = LocalStore.memory();
    addTearDown(store.close);
    ProviderContainer open() => ProviderContainer(
      overrides: [localStoreProvider.overrideWithValue(store)],
    );
    final first = open();
    expect((await first.read(waterSettingsProvider.future)).isSet, isFalse);
    await first.read(waterSettingsProvider.notifier).setGlasses(12);
    first.dispose();
    final second = open();
    addTearDown(second.dispose);
    final read = await second.read(waterSettingsProvider.future);
    expect(read.glasses, 12);
    expect(
      () => second.read(waterSettingsProvider.notifier).setGlasses(0),
      throwsFormatException,
    );
  });

  test('the journal feed parses entry ids from the committed snapshot', () {
    final json =
        jsonDecode(
              File(
                '../../packages/contracts/snapshots/log_recent.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    final feed = JournalFeed.fromJson(json);
    final withId = feed.entries.where((e) => e.id != null).toList();
    expect(withId, isNotEmpty);
    expect(feed.entries.first.id, isNull);
    expect(withId.first.id, '63272462-0cce-4a33-a9f7-3c05124dcfb1');
  });
}
