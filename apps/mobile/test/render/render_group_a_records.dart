/// Readings, insights and actions cases of the group A render harness. **Not a test**; see
/// `render_group_a.dart`.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/api/account_api.dart';
import 'package:healthee/data/api/cache_session.dart';
import 'package:healthee/data/challenges/challenge.dart';
import 'package:healthee/data/challenges/challenge_feed.dart';
import 'package:healthee/data/challenges/health_program.dart';
import 'package:healthee/data/coach/ledger_models.dart';
import 'package:healthee/data/coach/ledger_repository.dart';
import 'package:healthee/data/history/history_marker.dart';
import 'package:healthee/data/history/history_metric.dart';
import 'package:healthee/data/history/history_repository.dart';
import 'package:healthee/data/journal/journal_repository.dart';
import 'package:healthee/data/models/finding.dart';
import 'package:healthee/data/recommendations/recommendation_history.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/features/actions/challenge_detail_screen.dart';
import 'package:healthee/features/actions/program_detail_screen.dart';
import 'package:healthee/features/actions/recommendation_history_screen.dart';
import 'package:healthee/features/coach/coach_home_screen.dart';
import 'package:healthee/features/coach/every_yes_screen.dart';
import 'package:healthee/features/history/history_screen.dart';
import 'package:healthee/features/history/metric_explorer_screen.dart';
import 'package:healthee/features/insights/insights_screen.dart';
import 'package:healthee/features/insights/v02/finding_detail_screen.dart';
import 'package:healthee/features/journal/journal_screen.dart';

import '../_today_stubs.dart';
import '../features/_today_host.dart';
import '../features/coach/_coach_home_fakes.dart';
import 'render_group_a_support.dart';
import 'render_samples.dart';

/// Readings, Insights, the Journal and the Actions family.
List<GroupCase> recordCases(LocalStore Function() getStore) {
  Widget today(
    ThemeData t, {
    Widget? home,
    Map<String, Object?> Function(Map<String, Object?>)? mutate,
  }) => todayOn(getStore(), t, home: home, mutate: mutate);
  Widget screen(ThemeData t, Widget home) => today(t, home: pushed(home));

  return <GroupCase>[
    GroupCase(
      name: 'readings',
      route: '/history',
      data: 'today.json (every tile)',
      build: (t) => screen(t, const MetricExplorerScreen()),
    ),
    GroupCase(
      name: 'reading',
      route: '/history?metric=hrv_sleep_avg',
      data: 'sampleSeries(hrv_sleep_avg), no markers',
      build: (t) => today(
        t,
        home: ProviderScope(
          overrides: [
            for (final days in <int>[30, 90, 365, 1825]) ...[
              metricHistoryProvider(
                HistoryMetric.hrv,
                days,
              ).overrideWith((ref) async => sampleSeries('hrv_sleep_avg')),
              historyMarkersProvider(
                days,
              ).overrideWith((ref) async => const <HistoryMarker>[]),
            ],
          ],
          child: pushed(const HistoryScreen(initialMetric: 'hrv_sleep_avg')),
        ),
      ),
    ),
    GroupCase(
      name: 'finding',
      route: '/insight/<key>',
      data: 'today.json top_findings[0] (Caffeine and sleep)',
      build: (t) {
        final finding = Finding.fromJson(
          (loadTodayJson()['top_findings']! as List).first!
              as Map<String, Object?>,
        );
        return screen(
          t,
          FindingDetailScreen(routeKey: findingKey(finding), finding: finding),
        );
      },
    ),
    GroupCase(
      name: 'insights',
      route: '/insights',
      data: 'today.json top_findings; notable events empty',
      build: (t) => today(t, home: const InsightsScreen()),
    ),
    GroupCase(
      name: 'journal',
      route: '/journal',
      data: 'log_recent.json',
      build: (t) => today(
        t,
        home: ProviderScope(
          overrides: [
            journalRepositoryProvider.overrideWith(
              (ref) async =>
                  JournalRepository(Dio(), await CacheSession.capture(null)),
            ),
            journalFeedProvider.overrideWith(
              (ref) => Stream.value(stamped(journalFixture())),
            ),
          ],
          child: pushed(JournalScreen(now: now)),
        ),
      ),
    ),
    GroupCase(
      name: 'coach',
      route: '/actions (the Coach tab), review collapsed',
      data: 'hand fixtures shaped like coach_review.json and coach_ledger.json',
      build: (t) => today(t, home: _coachHome(shown: false)),
    ),
    GroupCase(
      name: 'coach-review',
      route: '/actions (the Coach tab), review open',
      data: 'hand fixtures shaped like coach_review.json and coach_ledger.json',
      build: (t) => today(t, home: _coachHome(shown: true)),
      beforeShot: _openReview,
    ),
    GroupCase(
      name: 'coach-large',
      route: '/actions at text scale 1.3, review open',
      data: 'as coach-review, large text',
      build: (t) => today(t, home: _coachHome(shown: true, large: true)),
      beforeShot: _openReview,
    ),
    GroupCase(
      name: 'recommendations',
      route: '/recommendations',
      data: 'recommendations.json (every window)',
      build: (t) => today(
        t,
        home: ProviderScope(
          overrides: [
            accountApiProvider.overrideWith((ref) => idleApi()),
            for (final days in <int>[30, 90, 180])
              recommendationHistoryProvider(
                days,
                0,
              ).overrideWith((ref) async => recommendationsFixture()),
          ],
          child: pushed(const RecommendationHistoryScreen()),
        ),
      ),
    ),
    GroupCase(
      name: 'challenge',
      route: '/challenge/33320',
      data: 'challenges.json active[0] (Seven days above 9,000)',
      build: (t) =>
          today(t, home: commitments(const ChallengeDetailScreen(id: 33320))),
    ),
    GroupCase(
      name: 'program',
      route: '/program/1304',
      data: 'programs.json active (8,000 steps a day)',
      build: (t) =>
          today(t, home: commitments(const ProgramDetailScreen(id: 1304))),
    ),
    GroupCase(
      name: 'program-large',
      route: '/program/1304 at text scale 1.3',
      data: 'programs.json active, large text',
      build: (t) => today(
        t,
        home: _largeText(commitments(const ProgramDetailScreen(id: 1304))),
      ),
    ),
    GroupCase(
      name: 'coach-ledger',
      route: '/coach-ledger',
      data: 'coach_ledger.json',
      build: (t) => today(t, home: _ledger(const EveryYesScreen())),
    ),
    GroupCase(
      name: 'coach-ledger-large',
      route: '/coach-ledger at text scale 1.3',
      data: 'coach_ledger.json, large text',
      build: (t) => today(t, home: _largeText(_ledger(const EveryYesScreen()))),
    ),
  ];
}

/// The ledger snapshot served for every window.
Widget _ledger(Widget screen) => ProviderScope(
  overrides: [
    for (final w in LedgerWindow.values)
      coachLedgerProvider(w).overrideWith(
        (ref) async => CoachLedger.fromJson(snap('coach_ledger.json')),
      ),
  ],
  child: pushed(screen),
);

/// [child] at the largest text size the design is checked at.
Widget _largeText(Widget child) => Builder(
  builder: (context) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: const TextScaler.linear(1.3)),
    child: child,
  ),
);

Future<void> _openReview(WidgetTester tester) async {
  await tester.tap(find.text('Weekly review'));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The Coach tab over fixtures: a suggested job, a plan, a month of record.
Widget _coachHome({required bool shown, bool large = false}) =>
    FutureBuilder<CoachHost>(
      future: CoachHost.create().then((h) => _fill(h)),
      builder: (context, snap) {
        final host = snap.data;
        if (host == null) {
          return const SizedBox.shrink();
        }
        return host.scope(
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(large ? 1.3 : 1)),
              child: const CoachHomeScreen(),
            ),
          ),
        );
      },
    );

CoachHost _fill(CoachHost host) => host
  ..today = todayDate
  ..respond = ((_) async => review(
    weekFrom: '2026-08-03',
    weekTo: '2026-08-09',
    text:
        'Straight talk. Sleep is mostly fixed: 6h53 a night, up from 4h47 '
        'two weeks before. Movement went the other way. Brisk minutes fell '
        '66, 43, 11, 4.',
    pattern:
        'You said yes to 9 things this month and the strap shows 2 done. '
        "So it's one job a week now, checked by the strap. Start tonight "
        'after 10.',
    todayLine: null,
  ))
  ..feed = ChallengeFeed(
    active: const <Challenge>[],
    suggested: <Challenge>[challenge(12, status: 'suggested', days: 4)],
    recent: const <Challenge>[],
    maxActive: 3,
  )
  ..program = HealthProgram(
    id: 3,
    title: 'The 4-week plan',
    why: 'Build up.',
    status: 'active',
    rungs: <Challenge>[
      challenge(1, status: 'locked'),
      challenge(2, status: 'locked'),
    ],
    settledRungs: 0,
    weeks: 4,
  )
  ..served = ((_) => ledger(
    weeks: <LedgerWeek>[
      week('2026-08-03', <int, String>{}),
      week('2026-07-27', <int, String>{}),
    ],
  ));
