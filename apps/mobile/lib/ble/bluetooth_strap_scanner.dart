/// [StrapScanner] over `flutter_blue_plus` and `permission_handler`.
///
/// Four gates in order, each with its own named failure, because "the scan
/// didn't work" is four different problems with four different remedies:
///
///   1. is there a BLE radio at all      → [BluetoothUnavailable]
///   2. do we have permission to scan    → [BluetoothPermissionDenied]
///   3. is the radio switched on         → [BluetoothOff]
///   4. did that MAC advertise           → [StrapNotInRange]
///
/// The order matters. Asking for permission before checking the radio exists
/// prompts an owner on an emulator for nothing; scanning before checking the
/// radio is on reports "not in range" about a strap sitting on the table.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:healthee/ble/strap_scanner.dart';
import 'package:healthee/core/logging.dart';
import 'package:healthee/data/pairing/pairing_exception.dart';
import 'package:healthee/data/pairing/pairing_failure.dart';
import 'package:permission_handler/permission_handler.dart';

/// Confirms a strap is advertising, using the real radio.
class BluetoothStrapScanner implements StrapScanner {
  /// The production scanner.
  const BluetoothStrapScanner({this.requestPermissions = true});
  final bool requestPermissions;

  @override
  Future<ScanOutcome> confirmInRange(
    String mac, {
    Duration window = kScanWindow,
  }) async {
    if (!await FlutterBluePlus.isSupported) {
      throw const PairingException(BluetoothUnavailable());
    }
    await _requirePermission();
    await _requireAdapterOn();

    // CoreBluetooth hands out a per-install UUID rather than the hardware
    // address, so on iOS there is nothing here a MAC could be compared against.
    // See [ScanNotPossibleHere].
    if (Platform.isIOS || Platform.isMacOS) {
      AppLog.info('pairing', 'scan skipped: this platform hides MAC addresses');
      return const ScanNotPossibleHere(
        'iOS never exposes a Bluetooth hardware address, so this step cannot '
        'check the MAC against what is nearby. The pairing is saved either way '
        'and the first sync will prove it.',
      );
    }

    return scanForStrap(mac, window);
  }

  /// Asks Android whether any app on this phone holds a live GATT connection to
  /// [mac], and subtracts the ones held by us.
  ///
  /// `systemDevices` is documented as "devices connected to by *any* app", which
  /// is exactly the question — the Zepp app holding the strap is the case
  /// [StrapHeldElsewhere] exists for. `withServices` is required on iOS and
  /// ignored on Android, and we have no service UUID we could honestly pass
  /// there, so iOS answers "no evidence" rather than a guess.
  ///
  /// ⚠ **Not yet confirmed against the real strap.** The API contract is clear
  /// and the call is on the failure path only, so the worst case is that this
  /// keeps returning false and the owner gets today's [StrapNotInRange] message.
  /// It has not been run against a Helio with the Zepp app connected.
  @override
  Future<bool> isConnectedElsewhere(String mac) async {
    if (!Platform.isAndroid) {
      return false;
    }
    final wanted = mac.toUpperCase();
    try {
      final system = await FlutterBluePlus.systemDevices(const <Guid>[]);
      final ours = FlutterBluePlus.connectedDevices
          .map((device) => device.remoteId.str.toUpperCase())
          .toSet();
      final held = system.any(
        (device) =>
            device.remoteId.str.toUpperCase() == wanted &&
            !ours.contains(wanted),
      );
      if (held) {
        AppLog.info(
          'pairing',
          'the strap is connected to another app on this phone',
        );
      }
      return held;
    } on FlutterBluePlusException catch (error, stackTrace) {
      // Never fatal: this only ever upgrades a message. A platform that will not
      // answer leaves the owner with [StrapNotInRange], which is still true.
      AppLog.failure(
        'pairing',
        'asking who holds the strap',
        error,
        stackTrace,
      );
      return false;
    }
  }

  Future<void> _requirePermission() async {
    // Android 12+ splits Bluetooth into scan/connect, and the manifest declares
    // BLUETOOTH_SCAN with `neverForLocation` so scanning never asks for
    // location — which is what the permission message on screen promises.
    //
    // Android 11 and below have no BLUETOOTH_SCAN and gate BLE scanning behind
    // ACCESS_FINE_LOCATION instead. permission_handler reports the unsupported
    // permission as granted there, so this check passes and `startScan` is what
    // fails — which [scanForStrap] catches and reports as a permission problem
    // rather than as a strap that is not there. Asking for location up front on
    // every Android instead would break the promise for the majority to serve
    // the minority.
    final wanted = Platform.isAndroid
        ? <Permission>[Permission.bluetoothScan, Permission.bluetoothConnect]
        : <Permission>[Permission.bluetooth];

    final results = requestPermissions
        ? await wanted.request()
        : {
            for (final permission in wanted)
              permission: await permission.status,
          };
    final denied = results.entries.where((entry) => !entry.value.isGranted);
    if (denied.isEmpty) {
      return;
    }
    final permanently = denied.any((entry) => entry.value.isPermanentlyDenied);
    AppLog.warning(
      'pairing',
      'bluetooth scan permission denied (permanently: $permanently)',
    );
    throw PairingException(BluetoothPermissionDenied(permanently: permanently));
  }

  Future<void> _requireAdapterOn() async {
    // `unknown` is the state before the platform has reported in, so wait past
    // it rather than reading it as "off" and telling the owner to do something
    // they have already done.
    final state = await FlutterBluePlus.adapterState
        .firstWhere((state) => state != BluetoothAdapterState.unknown)
        .timeout(
          const Duration(seconds: 5),
          onTimeout: () => BluetoothAdapterState.unknown,
        );

    switch (state) {
      case BluetoothAdapterState.on:
      case BluetoothAdapterState.turningOn:
        return;
      case BluetoothAdapterState.unauthorized:
        throw const PairingException(
          BluetoothPermissionDenied(permanently: true),
        );
      case BluetoothAdapterState.unavailable:
        throw const PairingException(BluetoothUnavailable());
      case BluetoothAdapterState.off:
      case BluetoothAdapterState.turningOff:
      case BluetoothAdapterState.unknown:
        throw const PairingException(BluetoothOff());
    }
  }
}

/// Scans for [mac] for up to [window] and reports the first sighting.
///
/// Top-level so a test can drive it through a fake radio:
/// [BluetoothStrapScanner.confirmInRange] returns before scanning on the macOS
/// test host.
@visibleForTesting
Future<ScanOutcome> scanForStrap(String mac, Duration window) async {
  final wanted = mac.toUpperCase();
  final sighting = Completer<StrapSighted>();

  // `onScanResults`, never `scanResults`: the latter re-emits the PREVIOUS
  // scan's results to a new listener. From the second sync on, that stale
  // sighting completed this scan about 5 ms after `startScan`, which answered
  // "in range" from old evidence and sent `stopScan` before Android had
  // registered the scanner. Android drops such a stop (`stopLeScan(): Error
  // state, mScannerId=0`), and the LOW_LATENCY scan then ran for as long as the
  // process lived (test/ble/strap_scan_test.dart).
  final subscription = FlutterBluePlus.onScanResults.listen((results) {
    for (final result in results) {
      if (result.device.remoteId.str.toUpperCase() == wanted &&
          !sighting.isCompleted) {
        sighting.complete(
          StrapSighted(
            rssi: result.rssi,
            advertisedName: result.advertisementData.advName,
          ),
        );
      }
    }
  });

  try {
    await FlutterBluePlus.startScan(timeout: window);
    return await sighting.future.timeout(window + const Duration(seconds: 1));
  } on TimeoutException {
    AppLog.info(
      'pairing',
      'strap did not advertise within ${window.inSeconds}s',
    );
    throw PairingException(StrapNotInRange(seconds: window.inSeconds));
  } on FlutterBluePlusException catch (error) {
    // A scan that will not start is a permission problem far more often than
    // anything else — on Android 11 and below, the ACCESS_FINE_LOCATION case
    // described in the scanner's permission check lands exactly here.
    // Reporting it as "not in range" would blame the strap for something we
    // did not ask for.
    AppLog.warning(
      'pairing',
      'scan refused by the platform (${error.function})',
    );
    throw const PairingException(BluetoothPermissionDenied(permanently: false));
  } finally {
    // Both run whichever way this ends: a scan left running drains the battery
    // of a phone whose owner has moved on to another screen.
    await subscription.cancel();
    await FlutterBluePlus.stopScan();
  }
}
