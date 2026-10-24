/// What `render_group_a.dart` shares: the two themes, the fixtures read off the
/// committed contract snapshots, and the one shape every case is described in.
///
/// **Not a test.** Sample data only: every payload here is a file under
/// `packages/contracts/snapshots` or an invented series from `render_samples`.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/core/theme/appearance_variant.dart';
import 'package:healthee/data/api/account_api.dart';
import 'package:healthee/data/api/cache_session.dart';
import 'package:healthee/data/api/server_snapshot.dart';
import 'package:healthee/data/challenges/challenge_feed.dart';
import 'package:healthee/data/challenges/challenge_outcome.dart';
import 'package:healthee/data/challenges/commitment_repository.dart';
import 'package:healthee/data/challenges/program_feed.dart';
import 'package:healthee/data/gps/recorded_route.dart';
import 'package:healthee/data/gps/route_summary.dart';
import 'package:healthee/data/journal/journal_feed.dart';
import 'package:healthee/data/models/recommendation.dart';
import 'package:healthee/data/recommendations/recommendation_history.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/data/store/store_provider.dart';
import 'package:healthee/data/store/view_date.dart';

import '../_today_stubs.dart';
import '../features/_today_host.dart';
import '../features/_workouts_host.dart' show loadSnapshot;
import 'render_samples.dart';

/// The two themes every screen is shot in: light Forest, dark espresso Forest.
final Map<String, ThemeData> groupThemes = <String, ThemeData>{
  'light': AppTheme.customized(
    Brightness.light,
    const AppearanceVariant(background: BackgroundVariant.espresso),
  ),
  'dark': AppTheme.customized(
    Brightness.dark,
    const AppearanceVariant(background: BackgroundVariant.espresso),
  ),
};

/// A phone's width; the height is a scroll long enough to build every row.
const Size tallSize = Size(390, 9000);

/// A phone's screen, for the sheets that open over a screen.
const Size screenSize = Size(390, 844);

const String _snapshots = '../../packages/contracts/snapshots';

/// A snapshot file by name.
Map<String, Object?> snap(String file) => loadSnapshot('$_snapshots/$file');

/// The challenge feed the snapshot carries.
ChallengeFeed challengeFeedFixture() =>
    ChallengeFeed.fromJson(snap('challenges.json'));

/// The programme feed the snapshot carries.
ProgramFeed programFeedFixture() => ProgramFeed.fromJson(snap('programs.json'));

/// The outcomes list the snapshot carries.
List<ChallengeOutcome> outcomesFixture() => <ChallengeOutcome>[
  for (final row in snap('challenge_outcomes.json')['outcomes']! as List)
    ChallengeOutcome.fromJson(row! as Map<String, Object?>),
];

/// The saved-route list the snapshot carries.
List<RouteSummary> routesFixture() => <RouteSummary>[
  for (final row in snap('gps_list.json')['tracks']! as List)
    RouteSummary.fromJson(row! as Map<String, Object?>),
];

/// The one recorded route the snapshot carries.
RecordedRoute routeFixture() => RecordedRoute.fromJson(snap('gps_detail.json'));

/// The journal feed the snapshot carries.
JournalFeed journalFixture() => JournalFeed.fromJson(snap('log_recent.json'));

/// The dated recommendations the snapshot carries.
List<DatedRecommendation> recommendationsFixture() => <DatedRecommendation>[
  for (final row in snap('recommendations.json')['recommendations']! as List)
    DatedRecommendation(
      (row! as Map<String, Object?>)['date']! as String,
      Recommendation.fromJson(row as Map<String, Object?>),
    ),
];

/// A snapshot stamped with the pinned clock, as a cached read would be.
ServerSnapshot<T> stamped<T>(T value) =>
    ServerSnapshot<T>(value, fetchedAt: now);

/// An account api over a dio that is never used.
Future<AccountApi> idleApi() async =>
    AccountApi(Dio(), await CacheSession.capture(null));

/// [screen] with a route under it, so its back control is drawn.
Widget pushed(Widget screen) => Navigator(
  onGenerateInitialRoutes: (navigator, initial) => <Route<void>>[
    MaterialPageRoute<void>(builder: (_) => const SizedBox.shrink()),
    MaterialPageRoute<void>(builder: (_) => screen),
  ],
);

/// One screen to shoot, and what to say about it in the manifest.
class GroupCase {
  /// Builds a case.
  const GroupCase({
    required this.name,
    required this.route,
    required this.data,
    required this.build,
    this.size = tallSize,
    this.beforeShot,
    this.status = 'ok',
  });

  /// The prototype's page name.
  final String name;

  /// The route this screen answers to in the app.
  final String route;

  /// The fixture or stub it drew.
  final String data;

  /// Builds the app around the screen for a theme.
  final Widget Function(ThemeData theme) build;

  /// The viewport.
  final Size size;

  /// Runs once the screen has settled, to open a sheet or a dropdown.
  final Future<void> Function(WidgetTester tester)? beforeShot;

  /// The status the manifest starts from; the looking can only worsen it.
  final String status;
}

/// Today (or [home]) over [store] with the render samples behind it.
///
/// The committed snapshot carries a live illness flag; [mutate] edits it.
Widget todayOn(
  LocalStore store,
  ThemeData theme, {
  Widget? home,
  Map<String, Object?> Function(Map<String, Object?>)? mutate,
}) => todayHost(
  store,
  themeOverride: theme,
  server: todayView(mutate: mutate),
  history: sampleHistory(),
  sleep: sleepWithSampleNight(),
  home: home,
);

/// The snapshot with the illness flag taken off.
Map<String, Object?> noIllness(Map<String, Object?> json) => <String, Object?>{
  ...json,
  'illness_flag': null,
};

/// The Today payload of a first day: what a server can say before any history.
Map<String, Object?> firstDay(Map<String, Object?> json) => <String, Object?>{
  ...json,
  'illness_flag': null,
  'top_findings': const <Object?>[],
  'anomalies': const <Object?>[],
  'recommendations': const <Object?>[],
  'sleep_history_7d': const <Object?>[],
  'sparklines': const <String, Object?>{},
  for (final key in _blocksOfAnOldDay) key: null,
  'metrics': const <Object?>[],
  'today_hr_series': const <Object?>[],
  'today_stress_series': const <Object?>[],
  'today_step_buckets': const <Object?>[],
};

const List<String> _blocksOfAnOldDay = <String>[
  'biological_age',
  'recovery',
  'recovery_score',
  'last_sleep',
  'last_sleep_extras',
  'sleep_health',
  'sleep_debt',
  'cardio_load',
  'mvpa',
  'strength',
  'vo2max',
];

/// Pumps long enough for a sheet's slide-in to finish, without settling (the
/// screens under it never idle).
Future<void> letSheetRise(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// A view date pinned to the snapshot's own day.
class PinnedDay extends ViewDate {
  @override
  String build() => '2026-07-31';
}

/// [screen] read on the snapshot's own day (31 July) rather than the shared
/// host's 4 August, so nothing on it says "raised on 31 Jul, not on this day".
Widget onSnapshotDay(Widget screen) => ProviderScope(
  overrides: [
    todayProvider.overrideWithValue('2026-07-31'),
    viewDateProvider.overrideWith(PinnedDay.new),
  ],
  child: screen,
);

/// The feeds the Actions family reads, pinned to the committed snapshots.
Widget commitments(Widget screen) => ProviderScope(
  overrides: [
    challengeFeedProvider.overrideWith(
      (ref) => Stream.value(stamped(challengeFeedFixture())),
    ),
    programFeedProvider.overrideWith(
      (ref) => Stream.value(stamped(programFeedFixture())),
    ),
    challengeOutcomesProvider.overrideWith(
      (ref) => Stream.value(stamped(outcomesFixture())),
    ),
  ],
  child: pushed(screen),
);
