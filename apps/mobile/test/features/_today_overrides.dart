/// The provider overrides every Today-hosted widget test shares.
///
/// Split out of `_today_host.dart` at the 400-line gate (Standards section 1):
/// the host builds the app around a screen, this pins everything that screen
/// would otherwise reach a socket or the keystore for.
///
/// Not a `*_test.dart` file, so it is never run as a suite.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/api/account_api.dart';
import 'package:healthee/data/api/cache_session.dart';
import 'package:healthee/data/api/server_session.dart';
import 'package:healthee/data/api/server_snapshot.dart';
import 'package:healthee/data/challenges/challenge_feed.dart';
import 'package:healthee/data/challenges/commitment_repository.dart';
import 'package:healthee/data/challenges/health_program.dart';
import 'package:healthee/data/challenges/program_feed.dart';
import 'package:healthee/data/coach/ledger_models.dart';
import 'package:healthee/data/coach/ledger_repository.dart';
import 'package:healthee/data/gps/gps_recorder.dart';
import 'package:healthee/data/gps/gps_recording_state.dart';
import 'package:healthee/data/history/dated_history.dart';
import 'package:healthee/data/insights/notable_event.dart';
import 'package:healthee/data/models/sleep_consistency.dart';
import 'package:healthee/data/models/sleep_insight.dart';
import 'package:healthee/data/models/sleep_page.dart';
import 'package:healthee/data/models/today_view.dart';
import 'package:healthee/data/models/trend_point.dart';
import 'package:healthee/data/notifications/notify_completions.dart';
import 'package:healthee/data/pairing/paired_strap.dart';
import 'package:healthee/data/pairing/pairing_repository.dart';
import 'package:healthee/data/profile/health_profile.dart';
import 'package:healthee/data/profile/profile_repository.dart';
import 'package:healthee/data/sleep_repository.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/data/store/store_provider.dart';
import 'package:healthee/data/store/view_date.dart';
import 'package:healthee/data/sync/connection_state.dart';
import 'package:healthee/data/sync/sync_controller.dart';
import 'package:healthee/data/today_repository.dart';
import 'package:healthee/data/updates/update_check.dart';
import 'package:healthee/features/settings/app_version.dart';

import '../_sleep_stubs.dart';
import '../_today_stubs.dart';
import 'coach/_breathing_fakes.dart' show defaultBreathingPlan;
import 'coach/_coach_home_fakes.dart' show basicsOverrides;

/// The overrides that keep a widget test off the network and off the keystore,
/// wrapped around [child].
///
/// A wrapper rather than a returned override list, for the reason
/// `_today_stubs.dart` already records: `Override` is not exported by
/// `flutter_riverpod`, and reaching past that boundary to save a parameter is not
/// worth it. Extracted on its second use (Standards §1) — a second copy of these
/// is a second chance to forget one, which surfaces as "pumpAndSettle timed out"
/// rather than as anything about the test.
Widget todayScoped(
  LocalStore store, {
  required Widget child,
  StrapConnection? connection,
  SyncController? sync,
  TodayView? server,
  bool serverUnreachable = false,
  bool signedIn = true,
  bool paired = false,
  SleepPage? sleep,
  SleepConsistency? consistency,
  HealthProfile? profile,
  bool profileFails = false,
  List<HealthProgram> suggestedPrograms = const [],
  DatedHistory? history,
}) {
  return ProviderScope(
    overrides: [
      // The profile, ALWAYS pinned: the paused-age notice reads it, and the real
      // provider reaches the account api, which a test host has no socket for.
      // Defaults to the committed contract snapshot; [profileFails] is the
      // "profile could not be read" case.
      profileRepositoryProvider.overrideWith(
        (ref) async => ProfileRepository(
          AccountApi(Dio(), await CacheSession.capture(null)),
        ),
      ),
      healthProfileProvider.overrideWith(
        (ref) async => profileFails
            ? throw StateError('no profile')
            : profile ?? profileFixture(),
      ),
      challengeFeedProvider.overrideWith(
        (ref) => Stream.value(
          ServerSnapshot(
            const ChallengeFeed(
              active: [],
              suggested: [],
              recent: [],
              maxActive: 3,
            ),
            fetchedAt: now,
          ),
        ),
      ),
      programFeedProvider.overrideWith(
        (ref) => Stream.value(
          ServerSnapshot(
            ProgramFeed(
              active: null,
              suggested: suggestedPrograms,
              recent: const [],
            ),
            fetchedAt: now,
          ),
        ),
      ),
      // The Coach tab reads the ledger the moment it is on screen; without a
      // stub the real client never answers and its loading state never settles.
      for (final window in LedgerWindow.values)
        coachLedgerProvider(window).overrideWith(
          (ref) async => const CoachLedger(
            window: 'month',
            from: '',
            to: '',
            ideasGiven: 0,
            yeses: 0,
            totals: LedgerTotals(),
            doneRate: DoneRate(done: 0, provable: 0),
            weeks: <LedgerWeek>[],
          ),
        ),
      // The Coach tab also draws Today's basics (breathing plan, water card off
      // the journal feed); unstubbed they never settle.
      ...basicsOverrides(defaultBreathingPlan()),
      notifyCompletionsProvider().overrideWith((ref) async {}),
      notableEventsProvider.overrideWith(
        (ref) => Stream.value(ServerSnapshot(<NotableEvent>[], fetchedAt: now)),
      ),
      gpsRecorderProvider.overrideWith(FixedGps.new),
      commitmentRepositoryProvider.overrideWith(
        (ref) async => CommitmentRepository(
          AccountApi(Dio(), await CacheSession.capture(null)),
        ),
      ),
      localStoreProvider.overrideWithValue(store),
      todayProvider.overrideWithValue(todayDate),
      syncControllerProvider.overrideWith(
        () => sync ?? FixedConnection(connection ?? const Disconnected()),
      ),
      serverSessionProvider.overrideWith(
        (ref) async => signedIn
            ? const ServerSessionStatus(
                signedIn: true,
                baseUrl: 'https://healthee.example.com',
              )
            : const ServerSessionStatus.signedOut(),
      ),
      // **The override answers PER DAY, exactly as the endpoint does.** A fixed
      // payload dated today would be no answer at all on a past day now — the
      // shell drops a payload that is about a different day than the one being
      // read — and the screen would sit on its loading card forever, which reads
      // in a widget test as `pumpAndSettle timed out` and says nothing about why.
      //
      // A `server` handed in explicitly still wins whole: a test that built its
      // own payload is asserting something about THAT payload.
      todaySnapshotProvider.overrideWith(
        serverUnreachable
            ? todayUnreachable()
            : (server != null
                  ? todayIs(server)
                  : (ref) async => todayViewFor(
                      ref.watch(viewDateProvider),
                      today: todayDate,
                    )),
      ),
      // Settings is reachable from Today now, and its About row reads a platform
      // channel a test host never answers — which would leave that read's own
      // deadline pending after any test that navigated there.
      appVersionProvider.overrideWith((ref) async => null),
      // Same reason as the version above, twice over: the update check reads that
      // same platform channel AND reaches GitHub. A widget test must do neither,
      // and the read's own 3 s deadline would be left pending behind every test
      // that draws About.
      updateStatusProvider.overrideWith((ref) async => const UpdateUnknown()),
      // The batched dated series, ALWAYS pinned. The real provider is only
      // watched on a past day, but on a past day it reaches a socket — and an
      // unpinned read there leaves a spinner running that `pumpAndSettle` waits
      // on forever, which reads as a broken test rather than as a missing
      // override. Empty by default: a suite about what a screen DECIDES does
      // not need readings, and a suite about the panels passes its own.
      datedHistoryProvider.overrideWith(
        (ref) async => serverUnreachable
            ? throw StateError('no server')
            : history ??
                  const DatedHistory(
                    days: 90,
                    series: <String, List<TrendPoint>>{},
                  ),
      ),
      // Sleep reads three payloads of its own — `/api/sleep`,
      // `/api/sleep/consistency` and `/api/sleep/insight`. All three are
      // pinned for the same reason the Today one is: an unpinned provider
      // reaches for a socket and fails as "pumpAndSettle timed out", which
      // says nothing about the test. The insight defaults to LOCKED so no
      // suite leaves a spinner running that `pumpAndSettle` will wait on.
      sleepPageProvider.overrideWith(
        (ref) async => serverUnreachable
            ? throw StateError('no server')
            : sleep ?? sleepPageFixture(),
      ),
      sleepConsistencyProvider.overrideWith(
        (ref) async => serverUnreachable
            ? throw StateError('no server')
            : consistency ?? consistencyFixture(),
      ),
      sleepInsightProvider.overrideWith(
        (ref) async => const SleepInsight.locked(),
      ),
      if (paired)
        pairingSummaryProvider.overrideWith(
          (ref) async => (
            strap: const PairedStrap(
              mac: 'C0:FF:EE:00:00:01',
              authKey: '000102030405060708090a0b0c0d0e0f',
            ),
            zeppRemembered: false,
          ),
        ),
    ],
    child: child,
  );
}

/// The day every Today-hosted test pins as "today".
const String todayDate = '2026-08-04';

/// The clock every Today-hosted test pins.
final DateTime now = DateTime(2026, 8, 4, 9, 30);

/// Where the committed profile snapshot is, relative to `apps/mobile`.
const String kProfileSnapshotPath =
    '../../packages/contracts/snapshots/profile.json';

/// The committed `GET /api/profile` snapshot, parsed. [mutate] edits the JSON
/// first, so a case asks "no weight" or "weight 41 days old" without building
/// a payload around the change.
HealthProfile profileFixture({
  Map<String, Object?> Function(Map<String, Object?> json)? mutate,
}) {
  final json =
      jsonDecode(File(kProfileSnapshotPath).readAsStringSync())
          as Map<String, Object?>;
  return HealthProfile.fromJson(mutate == null ? json : mutate(json));
}

/// A controller pinned to one state, so each case can be rendered on its own.
///
/// Public because Settings watches `syncControllerProvider` too now (its strap
/// row draws a Stop while a sync is running), so a second suite needs the same
/// override — and the real controller reaches for a radio and a platform store
/// the moment anything watches it.
class FixedConnection extends SyncController {
  /// [_state] is what `build` returns, forever.
  FixedConnection(this._state);

  final StrapConnection _state;

  @override
  StrapConnection build() => _state;
}

/// GPS acquisition has its own scripted suite; screen tests never open hardware.
class FixedGps extends GpsRecorder {
  @override
  Future<GpsRecordingState> build() async => const GpsRecordingState();
}
