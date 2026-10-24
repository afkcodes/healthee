import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/api/account_api.dart';
import 'package:healthee/data/api/cache_session.dart';
import 'package:healthee/data/challenges/slot_repository.dart';

import '../features/_workouts_host.dart' show loadSnapshot;

class _Api extends AccountApi {
  _Api(super.dio, super.session, this.reply);

  final Map<String, Object?> reply;
  final List<String> calls = <String>[];
  Map<String, Object?>? sent;

  @override
  Future<Map<String, Object?>> request(
    String path, {
    String method = 'GET',
    Map<String, Object?>? body,
    Duration? timeout,
    Map<String, Object?>? query,
  }) async {
    calls.add('$method $path');
    sent = body;
    return reply;
  }
}

void main() {
  const path = '../../packages/contracts/snapshots/challenge_slot.json';

  test('PATCHes only the slot and reads the challenge envelope', () async {
    final api = _Api(
      Dio(),
      await CacheSession.capture(null),
      loadSnapshot(path),
    );
    final challenge = await SlotRepository(api).setSlot(12, 'at 7:30 pm');
    expect(api.calls, <String>['PATCH /api/challenges/12/slot']);
    expect(api.sent, <String, Object?>{'slot': 'at 7:30 pm'});
    final wire = (loadSnapshot(path)['challenge']! as Map)['slot_text'];
    expect(challenge.slot, wire);
  });

  test('a body without the challenge is an error, not a silent success', () {
    expect(() async {
      final api = _Api(
        Dio(),
        await CacheSession.capture(null),
        <String, Object?>{'ok': true},
      );
      await SlotRepository(api).setSlot(1, 'x');
    }(), throwsFormatException);
  });
}
