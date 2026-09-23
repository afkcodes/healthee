/// A UI isolate that has been replaced holds nothing.
///
/// Back destroys the Activity and its FlutterEngine, but Android keeps the
/// process alive. Reopening starts a NEW UI isolate in the SAME process. The
/// old isolate's lease row was never deleted: its release is async, and the
/// engine was gone before it ran. The pid check read "same process, so alive",
/// and the new isolate waited out the 30-minute expiry. Meanwhile it said
/// "Nothing has been read from your strap yet", ten seconds after a sync.
///
/// Only the isolate that runs `main()` is the UI one, and a process hosts one
/// at a time. So a same-process row stamped by a different UI isolate is dead.
/// This file runs as the UI isolate; device_lease_test.dart runs as a
/// background one.
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/data/sync/device_lease.dart';

void main() {
  setUpAll(DeviceLease.markUiIsolate);

  Future<LocalStore> freshStore() async {
    final directory = await Directory.systemTemp.createTemp('healthee-lease');
    final store = LocalStore.at('${directory.path}/store.sqlite');
    addTearDown(() async {
      await store.close();
      await directory.delete(recursive: true);
    });
    return store;
  }

  Future<void> plant(LocalStore store, String value) => store.customUpdate(
    'INSERT INTO sync_meta(name, value) VALUES (?, ?) '
    'ON CONFLICT(name) DO UPDATE SET value = excluded.value',
    variables: [const Variable('strap_lease'), Variable(value)],
    updates: {store.syncMeta},
  );

  final now = DateTime.utc(2026, 1, 1);
  final until = now.add(DeviceLease.expiry).millisecondsSinceEpoch;

  test('A REPLACED UI ISOLATE HOLDS NOTHING: its row in this process is '
      'reclaimed at once', () async {
    final store = await freshStore();
    await plant(
      store,
      '00000000-0000-0000-0000-000000000000:$until:$pid:the-previous-ui',
    );

    final lease = DeviceLease(store, now: () => now);
    addTearDown(lease.release);
    expect(await lease.acquire(), isTrue);
  });

  test('two leases inside this UI isolate still exclude each other', () async {
    // The foreground link and a sync run both take a lease in the UI isolate.
    // Being the UI isolate must not let one rob the other.
    final store = await freshStore();
    final first = DeviceLease(store, now: () => now);
    final second = DeviceLease(store, now: () => now);
    addTearDown(() async {
      await first.release();
      await second.release();
    });
    expect(await first.acquire(), isTrue);
    expect(await second.acquire(), isFalse);
  });

  test('this UI isolate stamps the rows it writes', () async {
    // Unstamped, the NEXT UI isolate in this process could not tell the row
    // from a background one, and would wait again.
    final store = await freshStore();
    final lease = DeviceLease(store, now: () => now);
    addTearDown(lease.release);
    expect(await lease.acquire(), isTrue);
    final row = await store
        .customSelect("SELECT value FROM sync_meta WHERE name = 'strap_lease'")
        .getSingle();
    final fields = row.read<String>('value').split(':');
    expect(fields, hasLength(4));
    expect(fields[2], '$pid');
    expect(fields[3], isNotEmpty);
  });

  test('main() declares the UI isolate', () {
    // Without this line no row is ever stamped and the fix above never runs.
    expect(
      File('lib/main.dart').readAsStringSync(),
      contains('DeviceLease.markUiIsolate();'),
    );
  });

  test('a background isolate in this process is still respected', () async {
    // No UI stamp: WorkManager's isolate, which may be mid-sync right now.
    final store = await freshStore();
    await plant(store, '00000000-0000-0000-0000-000000000000:$until:$pid');

    final lease = DeviceLease(store, now: () => now);
    addTearDown(lease.release);
    expect(await lease.acquire(), isFalse);
  });
}
