import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/data/sync/device_lease.dart';

void main() {
  test(
    'two database connections cannot own the strap together; expired owner cannot release successor',
    () async {
      final directory = await Directory.systemTemp.createTemp('healthee-lease');
      final a = LocalStore.at('${directory.path}/store.sqlite');
      final b = LocalStore.at('${directory.path}/store.sqlite');
      var now = DateTime.utc(2026, 1, 1);
      final first = DeviceLease(a, now: () => now);
      final second = DeviceLease(b, now: () => now);
      final third = DeviceLease(a, now: () => now);
      addTearDown(() async {
        await first.release();
        await second.release();
        await third.release();
        await a.close();
        await b.close();
        await directory.delete(recursive: true);
      });
      expect(await first.acquire(), isTrue);
      expect(await second.acquire(), isFalse);
      now = now.add(DeviceLease.expiry + const Duration(seconds: 1));
      expect(await second.acquire(), isTrue);
      await first.release();
      expect(await third.acquire(), isFalse);
      await second.release();
      expect(await third.acquire(), isTrue);
    },
  );

  /// A pid that is certainly not running: start a process, wait for it to exit,
  /// and use its number. Inventing a large integer would only probably be dead.
  Future<int> deadPid() async {
    final ghost = await Process.start('true', const <String>[]);
    await ghost.exitCode;
    return ghost.pid;
  }

  Future<LocalStore> freshStore() async {
    final directory = await Directory.systemTemp.createTemp('healthee-lease');
    final store = LocalStore.at('${directory.path}/store.sqlite');
    addTearDown(() async {
      await store.close();
      await directory.delete(recursive: true);
    });
    return store;
  }

  /// Writes a lease row by hand, so the owner can be somebody else entirely.
  Future<void> plant(LocalStore store, String value) => store.customUpdate(
    'INSERT INTO sync_meta(name, value) VALUES (?, ?) '
    'ON CONFLICT(name) DO UPDATE SET value = excluded.value',
    variables: [const Variable('strap_lease'), Variable(value)],
    updates: {store.syncMeta},
  );

  group('A LEASE IS ONLY ALIVE WHILE ITS OWNER IS', () {
    test('a lease held by a dead process is taken at once, not in 30 minutes', () async {
      final store = await freshStore();
      final now = DateTime.utc(2026, 1, 1);
      // Expiring half an hour from now — under the old rule this was simply
      // unavailable, and the owner was told to wait for a connection that had
      // already died with its process.
      final until = now.add(DeviceLease.expiry).millisecondsSinceEpoch;
      await plant(store, '00000000-0000-0000-0000-000000000000:$until:${await deadPid()}');

      final lease = DeviceLease(store, now: () => now);
      addTearDown(lease.release);
      expect(
        await lease.acquire(),
        isTrue,
        reason: 'the recorded process no longer exists, so nothing holds it',
      );
    });

    test(
      'a lease held by a LIVE process is respected until it expires',
      () async {
        final store = await freshStore();
        var now = DateTime.utc(2026, 1, 1);
        final until = now.add(DeviceLease.expiry).millisecondsSinceEpoch;
        // This test's own process, which is emphatically running.
        await plant(store, '00000000-0000-0000-0000-000000000000:$until:$pid');

        final lease = DeviceLease(store, now: () => now);
        addTearDown(lease.release);
        expect(
          await lease.acquire(),
          isFalse,
          reason: 'a busy owner that missed a heartbeat must not be robbed',
        );
        now = now.add(DeviceLease.expiry + const Duration(seconds: 1));
        expect(
          await lease.acquire(),
          isTrue,
          reason: 'the timeout still ends it',
        );
      },
    );

    test('a UI-isolate row in this live process is respected by an isolate that '
        'is not the UI one', () async {
      // This file never calls `DeviceLease.markUiIsolate()`, so it runs as a
      // background isolate would. Such an isolate cannot tell whether the UI
      // isolate that wrote the row is still running, so it waits (only a
      // NEW UI isolate may reclaim; see device_lease_ui_isolate_test.dart).
      final store = await freshStore();
      final now = DateTime.utc(2026, 1, 1);
      final until = now.add(DeviceLease.expiry).millisecondsSinceEpoch;
      await plant(
        store,
        '00000000-0000-0000-0000-000000000000:$until:$pid:some-ui-isolate',
      );

      final lease = DeviceLease(store, now: () => now);
      addTearDown(lease.release);
      expect(await lease.acquire(), isFalse);
    });

    test(
      'a row written before pids were recorded is reclaimed, not waited out',
      () async {
        final store = await freshStore();
        final now = DateTime.utc(2026, 1, 1);
        final until = now.add(DeviceLease.expiry).millisecondsSinceEpoch;
        // The old two-field shape, unexpired. Nothing running can have written
        // it: two builds of one package cannot run together, and installing the
        // build that reads this killed the one that wrote it.
        await plant(store, '00000000-0000-0000-0000-000000000000:$until');

        final lease = DeviceLease(store, now: () => now);
        addTearDown(lease.release);
        expect(
          await lease.acquire(),
          isTrue,
          reason: 'the writer of a pid-less row cannot still be alive',
        );
      },
    );
  });
}
