/// A scan must answer from THIS scan's results, never the last one's.
///
/// `FlutterBluePlus.scanResults` re-emits the previous scan's results to a new
/// listener. The preflight scan listened to it, so from the second sync on, the
/// old sighting of the strap completed the scan about 5 ms after `startScan`.
/// That had two effects:
///
///   * "in range" was answered from a stale sighting;
///   * `stopScan` reached Android before it had registered the scanner
///     (`stopLeScan(): Error state, mScannerId=0`). The stop was dropped, so a
///     LOW_LATENCY scan kept running for as long as the process lived. One was
///     measured at 20 minutes and still going.
///
/// The fake platform below stands in for Android. It answers a scan only when
/// told to, so a sighting that arrives without one can only be a replay.
library;

import 'dart:async';

import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/ble/bluetooth_strap_scanner.dart';
import 'package:healthee/ble/strap_scanner.dart';
import 'package:healthee/data/pairing/pairing_exception.dart';
import 'package:healthee/data/pairing/pairing_failure.dart';

const _mac = 'DB:51:58:C2:0C:D8';
const _window = Duration(milliseconds: 200);

final class _FakeRadio extends FlutterBluePlusPlatform {
  final _responses = StreamController<BmScanResponse>.broadcast();
  final calls = <String>[];

  /// Whether the strap answers the next scan.
  bool strapAdvertising = true;

  @override
  Stream<BmScanResponse> get onScanResponse => _responses.stream;

  @override
  Future<bool> startScan(BmScanSettings request) async {
    calls.add('start');
    if (strapAdvertising) {
      // Delivered after startScan returns, as a real radio does.
      Timer(const Duration(milliseconds: 20), () {
        calls.add('result');
        _responses.add(
          BmScanResponse(
            advertisements: [
              BmScanAdvertisement(
                remoteId: const DeviceIdentifier(_mac),
                platformName: 'Helio Strap',
                advName: 'Helio Strap',
                connectable: true,
                txPowerLevel: null,
                appearance: null,
                manufacturerData: const {},
                serviceData: const {},
                serviceUuids: const [],
                rssi: -60,
              ),
            ],
            success: true,
            errorCode: 0,
            errorString: '',
          ),
        );
      });
    }
    return true;
  }

  @override
  Future<bool> stopScan(BmStopScanRequest request) async {
    calls.add('stop');
    return true;
  }
}

void main() {
  late _FakeRadio radio;

  setUp(() {
    radio = _FakeRadio();
    FlutterBluePlusPlatform.instance = radio;
  });

  test('a strap that answers the scan is sighted', () async {
    final outcome = await scanForStrap(_mac, _window);
    expect(outcome, isA<StrapSighted>());
    expect(radio.calls, ['start', 'result', 'stop']);
  });

  test("THE LAST SCAN'S SIGHTING IS NOT EVIDENCE: a strap that has gone quiet "
      'is reported not in range', () async {
    await scanForStrap(_mac, _window);

    radio.strapAdvertising = false;
    await expectLater(
      scanForStrap(_mac, _window),
      throwsA(
        isA<PairingException>().having(
          (e) => e.failure,
          'failure',
          isA<StrapNotInRange>(),
        ),
      ),
    );
  });

  test(
    'the scan is not stopped before this scan has reported anything',
    () async {
      await scanForStrap(_mac, _window);
      radio.calls.clear();

      // The strap answers again, 20 ms after the start. A replay completes the
      // scan first and asks for the stop before this scan has reported
      // anything: the stop-before-registration race Android drops.
      await scanForStrap(_mac, _window);
      expect(radio.calls, ['start', 'result', 'stop']);
    },
  );
}
