/// Fakes and a host for the Coach home tests. **Not a test.**
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:go_router/go_router.dart';
import 'package:healthee/core/routes.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/data/api/account_api.dart';
import 'package:healthee/data/api/cache_session.dart';
import 'package:healthee/data/api/server_snapshot.dart';
import 'package:healthee/data/basics/breathing/breathing_done.dart';
import 'package:healthee/data/basics/breathing/breathing_plan.dart';
import 'package:healthee/data/basics/breathing/breathing_plan_provider.dart';
import 'package:healthee/data/basics/water/water_controller.dart';
import 'package:healthee/data/challenges/challenge.dart';
import 'package:healthee/data/challenges/challenge_feed.dart';
import 'package:healthee/data/challenges/commitment_repository.dart';
import 'package:healthee/data/challenges/health_program.dart';
import 'package:healthee/data/challenges/program_feed.dart';
import 'package:healthee/data/challenges/slot_repository.dart';
import 'package:healthee/data/coach/ledger_models.dart';
import 'package:healthee/data/coach/ledger_repository.dart';
import 'package:healthee/data/coach/review_models.dart';
import 'package:healthee/data/coach/review_repository.dart';
import 'package:healthee/data/journal/journal_entry.dart';
import 'package:healthee/data/journal/journal_feed.dart';
import 'package:healthee/data/journal/journal_repository.dart';
import 'package:healthee/data/store/store_provider.dart';

import '_breathing_fakes.dart';

/// The owner's day in these tests: a Monday.
const String kToday = '2026-10-19';

/// Overrides that keep the two "Today's basics" cards off the store and the
/// network: a fixed breathing plan, and an empty water feed.
List<Override> basicsOverrides(
  BreathingPlan plan, [
  Set<BreathingItemKind> done = const <BreathingItemKind>{},
]) => [
  breathingPlanProvider.overrideWith((ref) async => plan),
  breathingDoneProvider.overrideWith(() => FixedBreathingDone({...done})),
  // The water card reads the journal feed; an empty one keeps the home
  // tests off the network.
  waterClockProvider.overrideWithValue(() => DateTime(2026, 10, 19, 15)),
  journalFeedProvider.overrideWith(
    (ref) => Stream.value(
      ServerSnapshot(
        const JournalFeed(entries: <JournalEntry>[], fastOpen: false),
        fetchedAt: DateTime(2026),
      ),
    ),
  ),
];

/// [child] with only the basics stubbed.
Widget stubbedBasics(Widget child) => ProviderScope(
  overrides: basicsOverrides(defaultBreathingPlan()),
  child: child,
);

/// A review as the server would send it, with overrides.
CoachReview review({
  String? text = 'Straight talk. Brisk minutes fell to 66.',
  String? pattern = 'You say yes on Mondays and miss by Thursday.',
  bool cached = false,
  bool withJob = true,
  String? todayLine = 'Today: 20 minutes.',
  DateTime? generatedAt,
  String weekFrom = '2026-10-19',
  String weekTo = '2026-10-25',
}) => CoachReview.fromJson(<String, Object?>{
  'week': '2026-W43',
  'week_from': weekFrom,
  'week_to': weekTo,
  'review': text,
  'pattern': pattern,
  'job': withJob ? job() : null,
  'today_line': todayLine,
  'rationale': null,
  'evidence_grade': 3,
  'research_note_ids': <String>[],
  'generated_at': (generatedAt ?? DateTime.utc(2026, 10, 19, 9, 30))
      .toIso8601String(),
  'cached': cached,
});

/// The job block of a response.
Map<String, Object?> job({String action = 'brisk walk'}) => <String, Object?>{
  'action': action,
  'challenge_id': 12,
  'counts_when': 'when the strap logs 15+ brisk minutes. No tap needed.',
  'days_required': 4,
  'floor': '10 minutes. Half credit, streak survives.',
  'metric': 'mvpa_min',
  'slot': 'after 10 pm, once your evening block ends.',
  'target': 20.0,
  'unit': 'min',
};

/// A ledger week with entries for challenge 12 on the given days.
LedgerWeek week(
  String from,
  Map<int, String> verdictByDay, {
  int ideas = 21,
  int ref = 12,
}) {
  final start = DateTime.parse(from);
  return LedgerWeek.fromJson(<String, Object?>{
    'from': from,
    'to': '2026-10-25',
    'ideas_given': ideas,
    'yeses': verdictByDay.length,
    'entries': <Object?>[
      for (final e in verdictByDay.entries)
        <String, Object?>{
          'date': DateTime(
            start.year,
            start.month,
            start.day + e.key,
          ).toIso8601String().substring(0, 10),
          'title': 'Brisk walk',
          'verdict': e.value,
          'measured': <String, Object?>{},
          'source': 'challenge',
          'ref_id': ref,
        },
    ],
  });
}

/// A ledger.
CoachLedger ledger({
  List<LedgerWeek> weeks = const <LedgerWeek>[],
  int ideas = 84,
  int yeses = 9,
  int done = 2,
  int missed = 5,
  int noData = 1,
  int uncheckable = 1,
}) => CoachLedger(
  window: 'month',
  from: '2026-09-21',
  to: '2026-10-19',
  ideasGiven: ideas,
  yeses: yeses,
  totals: LedgerTotals(
    done: done,
    missed: missed,
    noData: noData,
    uncheckable: uncheckable,
  ),
  doneRate: const DoneRate(done: 2, provable: 7),
  weeks: weeks,
);

/// A challenge row for the feed.
Challenge challenge(
  int id, {
  String status = 'active',
  int? days,
  bool bare = false,
}) => Challenge(
  id: id,
  title: 'Brisk walk',
  why: 'Because.',
  status: status,
  metric: 'mvpa_min',
  target: 20,
  comparator: '>=',
  cadence: 'daily',
  windowDays: 7,
  difficulty: 'standard',
  kind: 'threshold',
  citations: const <String>[],
  daysRequired: days,
  slot: 'after 10 pm',
  floor: '10 minutes',
  countsWhen: 'when the strap logs 15 minutes',
);

/// A review repository that counts and answers from [respond].
class FakeReviewRepository extends ReviewRepository {
  /// Answers with [respond].
  FakeReviewRepository(super.api, this.respond);

  /// What each call returns or throws.
  final Future<CoachReview> Function(int call) respond;

  /// Calls made.
  int calls = 0;

  @override
  Future<CoachReview> generate() => respond(++calls);
}

/// Records adopt, abandon and adapt.
class FakeCommitments extends CommitmentRepository {
  /// Builds the fake.
  FakeCommitments(super.api);

  /// `adopt 12`, `abandon 12`.
  final List<String> actions = <String>[];

  @override
  Future<void> challengeAction(int id, String action) async =>
      actions.add('$action $id');
}

/// Records slot writes.
class FakeSlots extends SlotRepository {
  /// Builds the fake.
  FakeSlots(super.api);

  /// `12:at 7:00 pm`.
  final List<String> writes = <String>[];

  @override
  Future<Challenge> setSlot(int id, String slot) async {
    writes.add('$id:$slot');
    return challenge(id, days: 4);
  }
}

/// Everything a Coach home test holds on to.
class CoachHost {
  /// Builds a host over [api].
  CoachHost(this.api);

  /// The idle client.
  final AccountApi api;

  /// Review repository behaviour.
  Future<CoachReview> Function(int call) respond = (_) async => review();

  /// The review repository.
  late final FakeReviewRepository reviews = FakeReviewRepository(
    api,
    (call) => respond(call),
  );

  /// Commitments.
  late final FakeCommitments commitments = FakeCommitments(api);

  /// Slots.
  late final FakeSlots slots = FakeSlots(api);

  /// Challenges served.
  ChallengeFeed feed = const ChallengeFeed(
    active: <Challenge>[],
    suggested: <Challenge>[],
    recent: <Challenge>[],
    maxActive: 3,
  );

  /// The program served.
  HealthProgram? program;

  /// The ledger served per window.
  CoachLedger Function(LedgerWindow) served = (_) => ledger();

  /// The owner's day.
  String today = kToday;

  /// The breathing plan the card shows.
  BreathingPlan breathingPlan = defaultBreathingPlan();

  /// The plan items done today.
  Set<BreathingItemKind> breathingDone = <BreathingItemKind>{};

  /// Windows asked for.
  final List<LedgerWindow> asked = <LedgerWindow>[];

  /// Where the router went.
  final List<String> visited = <String>[];

  /// A host with an idle account client.
  static Future<CoachHost> create() async =>
      CoachHost(AccountApi(Dio(), await CacheSession.capture(null)));

  /// [child] under every override, in a real router that records pushes.
  Widget wrap(Widget child, {double textScale = 1}) {
    final router = GoRouter(
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: SingleChildScrollView(
              child: Padding(padding: const EdgeInsets.all(16), child: child),
            ),
          ),
        ),
        for (final path in <String>[
          Routes.coachLedger,
          Routes.journal,
          '${Routes.program}/:id',
        ])
          GoRoute(
            path: path,
            builder: (context, state) {
              visited.add(state.uri.toString());
              return const Scaffold(body: Text('pushed'));
            },
          ),
      ],
    );
    return scope(
      MaterialApp.router(
        theme: AppTheme.light,
        routerConfig: router,
        builder: (context, page) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: page!,
        ),
      ),
    );
  }

  /// [child] under every override.
  Widget scope(Widget child) {
    return ProviderScope(
      overrides: [
        todayProvider.overrideWithValue(today),
        ...basicsOverrides(breathingPlan, breathingDone),
        reviewRepositoryProvider.overrideWith((ref) async => reviews),
        // Overridden so it lives in THIS scope and reads the fake above.
        coachReviewProvider.overrideWith(CoachReviewNotifier.new),
        commitmentRepositoryProvider.overrideWith((ref) async => commitments),
        slotRepositoryProvider.overrideWith((ref) async => slots),
        challengeFeedProvider.overrideWith(
          (ref) =>
              Stream.value(ServerSnapshot(feed, fetchedAt: DateTime(2026))),
        ),
        programFeedProvider.overrideWith(
          (ref) => Stream.value(
            ServerSnapshot(
              ProgramFeed(
                active: program,
                suggested: const <HealthProgram>[],
                recent: const <HealthProgram>[],
              ),
              fetchedAt: DateTime(2026),
            ),
          ),
        ),
        for (final w in LedgerWindow.values)
          coachLedgerProvider(w).overrideWith((ref) async {
            asked.add(w);
            return served(w);
          }),
      ],
      child: child,
    );
  }
}

/// Feeds with one challenge in a given state.
abstract final class ChallengeFeedOf {
  /// [c] running.
  static ChallengeFeed active(Challenge c) => ChallengeFeed(
    active: <Challenge>[c],
    suggested: const <Challenge>[],
    recent: const <Challenge>[],
    maxActive: 3,
  );
}
