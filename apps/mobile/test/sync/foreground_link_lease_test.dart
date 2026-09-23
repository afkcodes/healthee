/// A link that cannot take the strap still says when it last synced.
///
/// When the lease is held elsewhere, the link used to publish nothing. The
/// screen stayed on the controller's initial `Disconnected()`, which has no
/// sync date, and read "Nothing has been read from your strap yet" on a phone
/// that had synced seconds before.
library;

import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/data/sync/connection_state.dart';
import 'package:healthee/data/sync/device_lease.dart';
import 'package:healthee/data/sync/foreground_link.dart';

import '../ble/strap_client_test.dart' show clientFor, healthyStrap;
import '../pairing/_pairing_fakes.dart';

void main() {
  test(
    'THE LEASE IS HELD ELSEWHERE: the link rests on the stored sync date',
    () async {
      final directory = await Directory.systemTemp.createTemp('healthee-link');
      final store = LocalStore.at('${directory.path}/store.sqlite');
      addTearDown(() async {
        await store.close();
        await directory.delete(recursive: true);
      });
      // A live holder: this process, no UI stamp (a background sync).
      final until = DateTime.now()
          .add(DeviceLease.expiry)
          .millisecondsSinceEpoch;
      await store.customUpdate(
        'INSERT INTO sync_meta(name, value) VALUES (?, ?)',
        variables: [
          const Variable('strap_lease'),
          Variable('00000000-0000-0000-0000-000000000000:$until:$pid'),
        ],
        updates: {store.syncMeta},
      );

      final lastSync = DateTime(2026, 9, 23, 17, 54);
      final seen = <StrapConnection>[];
      final link = ForegroundLink(
        client: clientFor((_) => healthyStrap()),
        scanner: FakeStrapScanner(),
        lastCompleteSync: () async => lastSync,
        onState: seen.add,
        // The retry never fires here: only the first attempt is under test.
        schedule: (_, _) => Timer(const Duration(days: 1), () {})..cancel(),
        lease: DeviceLease(store),
      );
      addTearDown(link.dispose);

      await link.toForeground();

      expect(seen, isNotEmpty, reason: 'silence leaves "nothing read" up');
      expect(seen.whereType<Scanning>(), isEmpty);
      final rest = seen.last;
      expect(rest, isA<Disconnected>());
      expect((rest as Disconnected).lastCompleteSync, lastSync);
    },
  );
}
