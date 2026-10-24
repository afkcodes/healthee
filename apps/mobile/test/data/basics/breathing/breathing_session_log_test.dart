import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/api/cache_session.dart';
import 'package:healthee/data/api/credentials.dart';
import 'package:healthee/data/api/stored_server_session.dart';
import 'package:healthee/data/basics/breathing/breathing_session_log.dart';
import 'package:healthee/data/journal/journal_repository.dart';

import '../../../pairing/_pairing_fakes.dart';

void main() {
  late Dio dio;
  late BreathingSessionLog log;
  final requests = <RequestOptions>[];
  final at = DateTime.utc(2026, 10, 18, 22, 25);

  setUp(() async {
    requests.clear();
    dio = Dio(BaseOptions(baseUrl: 'https://test.example'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          handler.resolve(
            Response(
              requestOptions: options,
              data: {'ok': true},
              statusCode: 200,
            ),
          );
        },
      ),
    );
    final credentials = Credentials(FakeSecretStore());
    await credentials.setServerSession(
      baseUrl: 'https://test.example',
      token: 'a',
      kind: StoredCredentialKind.shared,
    );
    log = BreathingSessionLog(
      JournalRepository(dio, await CacheSession.capture(credentials)),
      now: () => at.subtract(const Duration(minutes: 1)),
    );
  });
  tearDown(() => dio.close());

  test(
    'minutesToLog: finishing logs the plan, ending early logs whole minutes',
    () {
      expect(
        minutesToLog(
          plannedMinutes: 10,
          finished: true,
          elapsed: const Duration(minutes: 10),
        ),
        10,
      );
      expect(
        minutesToLog(
          plannedMinutes: 10,
          finished: false,
          elapsed: const Duration(minutes: 3, seconds: 59),
        ),
        3,
      );
      expect(
        minutesToLog(
          plannedMinutes: 10,
          finished: false,
          elapsed: const Duration(seconds: 59),
        ),
        0,
      );
      expect(
        minutesToLog(
          plannedMinutes: 5,
          finished: false,
          elapsed: const Duration(minutes: 9),
        ),
        5,
      );
    },
  );

  test('logs a meditation entry with whole minutes', () async {
    expect(await log.logSession(10), isTrue);
    final body = requests.single.data as Map<String, Object?>;
    expect(body['type'], 'meditation');
    expect(body['minutes'], 10);
    expect(body['unit'], 'min');
  });

  test('zero minutes logs nothing', () async {
    expect(await log.logSession(0), isFalse);
    expect(
      await log.logOutcome(
        plannedMinutes: 10,
        finished: false,
        elapsed: const Duration(seconds: 40),
      ),
      isFalse,
    );
    expect(requests, isEmpty);
  });

  test('ending early logs what was done', () async {
    await log.logOutcome(
      plannedMinutes: 10,
      finished: false,
      elapsed: const Duration(minutes: 6, seconds: 10),
    );
    expect((requests.single.data as Map<String, Object?>)['minutes'], 6);
  });
}
