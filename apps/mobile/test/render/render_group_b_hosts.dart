/// The hosts and fixtures behind `render_group_b.dart`. **Not a test.**
///
/// Everything here is a sample: the committed contract snapshots where one
/// exists, and obviously fake values (`example.test`, `C0:FF:EE:...`) where the
/// screen needs something typed. No real token, address, e-mail or reading.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthee/data/api/account_api.dart';
import 'package:healthee/data/api/cache_session.dart';
import 'package:healthee/data/api/credentials.dart';
import 'package:healthee/data/api/server_session.dart';
import 'package:healthee/data/auth/identity_providers.dart';
import 'package:healthee/data/background/background_preferences.dart';
import 'package:healthee/data/background/background_scheduler.dart';
import 'package:healthee/data/coach/coach_answer.dart';
import 'package:healthee/data/coach/coach_client.dart';
import 'package:healthee/data/coach/coach_history_store.dart';
import 'package:healthee/data/coach/coach_stream_event.dart';
import 'package:healthee/data/device/device_day.dart';
import 'package:healthee/data/device/device_metric.dart';
import 'package:healthee/data/device/device_repository.dart';
import 'package:healthee/data/honesty/device_absence.dart';
import 'package:healthee/data/honesty/reading.dart';
import 'package:healthee/data/models/entitlement.dart';
import 'package:healthee/data/notifications/notification_providers.dart';
import 'package:healthee/data/notifications/reminder_preferences.dart';
import 'package:healthee/data/pairing/paired_strap.dart';
import 'package:healthee/data/pairing/pairing_repository.dart';
import 'package:healthee/data/push/push_stamp.dart';
import 'package:healthee/data/push/push_stamp_provider.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/data/store/store_provider.dart';
import 'package:healthee/data/today_repository.dart';
import 'package:healthee/data/updates/update_check.dart';
import 'package:healthee/features/coach/coach_history_provider.dart';
import 'package:healthee/features/settings/app_version.dart';

import '../_today_stubs.dart';
import '../features/_settings_harness.dart' show dayWithSync, pairedStrap;
import '../features/_today_host.dart';
import '../pairing/_pairing_fakes.dart';
import '../pairing/_zepp_stub.dart';
import '../support/ask_as_stream.dart';

const String _snapshots = '../../packages/contracts/snapshots';

Map<String, Object?> _snapshot(String name) =>
    jsonDecode(File('$_snapshots/$name').readAsStringSync())
        as Map<String, Object?>;

/// The committed entitlement snapshot, with [used] of its 20 spent.
Entitlement entitlementWith({int used = 0, DateTime? resetsAt}) {
  final json = _snapshot('entitlement.json');
  final row =
      (json['included']! as List<Object?>).single! as Map<String, Object?>;
  return Entitlement.fromJson(<String, Object?>{
    ...json,
    'included': <Object?>[
      <String, Object?>{
        ...row,
        'used': used,
        'remaining': 20 - used,
        'resets_at': resetsAt?.toIso8601String(),
      },
    ],
  });
}

/// The `answer` event of the committed coach-stream snapshot.
CoachAnswer snapshotAnswer() {
  final events =
      jsonDecode(
            File('$_snapshots/coach_stream_events.json').readAsStringSync(),
          )
          as List<Object?>;
  for (final raw in events) {
    final event = raw! as Map<String, Object?>;
    if (event['event'] == 'answer') {
      return CoachAnswer.fromJson(event['data']! as Map<String, Object?>);
    }
  }
  throw StateError('no answer event in coach_stream_events.json');
}

/// A coach client that answers from a script, never from a server.
class ScriptedCoach with AskAsStream implements CoachClient {
  /// [balance] is every meter read; [answer] or [failure] is what a question
  /// gets; [hangs] makes the question stay in flight with its stages showing.
  ScriptedCoach({
    required this.balance,
    this.answer,
    this.failure,
    this.hangs = false,
  });

  final Entitlement balance;
  final CoachAnswer? answer;
  final Exception? failure;
  final bool hangs;

  @override
  Future<Entitlement> entitlement() async => balance;

  @override
  Future<CoachAnswer> ask(List<CoachTurn> messages, {String? topic}) async {
    if (failure case final Exception thrown) {
      throw thrown;
    }
    return answer!;
  }

  @override
  Stream<CoachStreamEvent> askStream(
    List<CoachTurn> messages, {
    String? topic,
  }) async* {
    if (hangs) {
      yield const CoachStageEvent(stage: CoachStage.context, round: 1);
      yield const CoachStageEvent(
        stage: CoachStage.tool,
        round: 2,
        detail: 'query_metric',
      );
      await Completer<void>().future;
    }
    yield CoachAnswerEvent(await ask(messages, topic: topic));
  }
}

/// Past conversations for the history screen: invented openers, fixed times.
List<CoachThreadSummary> sampleThreads() => <CoachThreadSummary>[
  CoachThreadSummary(
    id: 'sample-3',
    opening: 'How did I sleep this week?',
    startedAt: DateTime(2026, 8, 4, 8, 12),
    lastAt: DateTime(2026, 8, 4, 8, 15),
    turns: 4,
  ),
  CoachThreadSummary(
    id: 'sample-2',
    opening: 'Is my resting heart rate moving?',
    startedAt: DateTime(2026, 7, 29, 19, 3),
    lastAt: DateTime(2026, 7, 29, 19, 3),
    turns: 2,
  ),
  CoachThreadSummary(
    id: 'sample-1',
    opening: 'What does HRV tell me?',
    startedAt: DateTime(2026, 7, 21, 7, 40),
    lastAt: DateTime(2026, 7, 21, 7, 44),
    turns: 6,
  ),
];

/// [screen] (a coach screen) in [theme], with the coach's own client, the
/// stored conversations and the device store pinned at the root — where the
/// providers that depend on them are built — and the committed `today` snapshot
/// under it, which is where the coach's opening line is read.
Widget coachHost(
  ThemeData theme,
  Widget screen, {
  required CoachClient client,
  List<CoachThreadSummary> threads = const <CoachThreadSummary>[],
}) => ProviderScope(
  overrides: [
    coachClientProvider.overrideWithValue(client),
    coachThreadsProvider.overrideWith((ref) async => threads),
    localStoreProvider.overrideWith((ref) {
      final store = LocalStore.memory();
      ref.onDispose(store.close);
      return store;
    }),
  ],
  child: ProviderScope(
    overrides: [todaySnapshotProvider.overrideWith(todayIs(todayView()))],
    child: MaterialApp(theme: theme, home: screen),
  ),
);

/// The harness's synced day with a few streams the strap "recorded", so the
/// freshness and device screens show rows rather than only absences. The values
/// are the ones `seedDevice` writes; the times are relative to the wall clock
/// for the reason `dayWithSync` gives.
DeviceDay sampleDeviceDay() {
  final base = dayWithSync();
  final at = DateTime.now();
  const samples = <String, (double, int)>{
    'resting_hr': (61, 1),
    'hrv': (47, 3),
  };
  return DeviceDay(
    date: base.date,
    steps: const Present<int>(9264),
    distanceKm: const Present<double>(6.71),
    deviceCalories: const Present<int>(412),
    stepsReadAt: at.subtract(const Duration(minutes: 12)),
    heartRate: const Present<double>(68),
    heartRateSeries: base.heartRateSeries,
    lastNight: base.lastNight,
    metrics: <DeviceMetric>[
      for (final stream in kDeviceStreams)
        if (samples[stream.metric] case (final double value, final int n))
          DeviceMetric(
            stream: stream,
            reading: Present<double>(value),
            measuredAt: at.subtract(const Duration(hours: 2)),
            sampleCount: n,
          )
        else
          DeviceMetric(
            stream: stream,
            reading: notMeasured(stream.label.toLowerCase()),
            measuredAt: null,
            sampleCount: 0,
          ),
    ],
    workouts: base.workouts,
    sync: base.sync,
    batteryPercent: base.batteryPercent,
  );
}

/// [screen] (a settings-family screen) on the Today host's theme and stubs,
/// with the platform-backed providers those screens read pinned.
Widget settingsHost(
  LocalStore store,
  ThemeData theme,
  Widget screen, {
  PairedStrap? strap,
  bool signedIn = true,
}) => todayHost(
  store,
  themeOverride: theme,
  signedIn: signedIn,
  home: ProviderScope(
    overrides: [
      credentialsProvider.overrideWithValue(Credentials(FakeSecretStore())),
      pairingSummaryProvider.overrideWith(
        (ref) async => (strap: strap ?? pairedStrap, zeppRemembered: false),
      ),
      deviceDayProvider.overrideWith((ref) async => sampleDeviceDay()),
      appVersionProvider.overrideWith((ref) async => '0.0.0-sample'),
      updateStatusProvider.overrideWith((ref) async => const UpdateUnknown()),
      pushStampProvider.overrideWith((ref) async => const PushStamp.never()),
      accountApiProvider.overrideWith(
        (ref) async => AccountApi(Dio(), await CacheSession.capture(null)),
      ),
      reminderPreferencesProvider.overrideWith(
        (ref) async => const ReminderPreferences(),
      ),
      backgroundPreferencesProvider.overrideWith(
        (ref) async => const BackgroundPreferences(),
      ),
      backgroundLastRunProvider.overrideWith((ref) async => null),
    ],
    child: screen,
  ),
);

/// The pairing or sign-in [screen] over faked keystore, Zepp and radio.
Widget setupHost(ThemeData theme, Widget screen, {bool identity = false}) =>
    ProviderScope(
      overrides: [
        credentialsProvider.overrideWithValue(Credentials(FakeSecretStore())),
        identityAvailableProvider.overrideWithValue(identity),
        serverSessionProvider.overrideWith(
          (ref) async => const ServerSessionStatus.signedOut(),
        ),
        pairingRepositoryProvider.overrideWithValue(
          PairingRepository(
            credentials: Credentials(FakeSecretStore()),
            zepp: clientWith(happyPathAdapter()),
            scanner: FakeStrapScanner(),
          ),
        ),
      ],
      child: MaterialApp(theme: theme, home: screen),
    );
