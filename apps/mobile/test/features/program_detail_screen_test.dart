import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/data/api/account_api.dart';
import 'package:healthee/data/api/cache_session.dart';
import 'package:healthee/data/api/server_snapshot.dart';
import 'package:healthee/data/challenges/challenge.dart';
import 'package:healthee/data/challenges/challenge_progress.dart';
import 'package:healthee/data/challenges/commitment_repository.dart';
import 'package:healthee/data/challenges/health_program.dart';
import 'package:healthee/data/challenges/program_feed.dart';
import 'package:healthee/features/actions/program_detail_screen.dart';
import 'package:healthee/features/actions/v02/program_evidence_card.dart';
import 'package:healthee/features/actions/v02/program_rules_card.dart';
import 'package:healthee/features/actions/v02/program_rungs_card.dart';

import '_settings_harness.dart' show tallViewport;

class _Repo extends CommitmentRepository {
  _Repo(super.api);
  final List<String> calls = <String>[];

  @override
  Future<void> programAction(int id, String action) async =>
      calls.add('$id:$action');
}

Challenge _rung(int id, String status, {double target = 80}) => Challenge(
  id: id,
  title: 'Rung $id',
  why: 'Because.',
  status: status,
  metric: 'mvpa_min',
  target: target,
  comparator: '>=',
  cadence: 'weekly',
  windowDays: 7,
  difficulty: 'standard',
  kind: 'standard',
  citations: const <String>['mvpa_minutes_mortality'],
  adoptedAt: status == 'locked' ? null : DateTime(2026, 10, 19, 12),
);

HealthProgram _program(String status) => HealthProgram(
  id: 7,
  title: 'Back to 150',
  why:
      'Going from about 30 to 150 minutes is the steepest part '
      '[mvpa_minutes_mortality].',
  status: status,
  rungs: <Challenge>[_rung(1, 'active'), _rung(2, 'locked', target: 100)],
  settledRungs: 0,
  goal: 'Reach 150 active minutes a week',
);

Future<_Repo> _open(WidgetTester tester, String status) async {
  tallViewport(tester);
  final repo = _Repo(AccountApi(Dio(), await CacheSession.capture(null)));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        commitmentRepositoryProvider.overrideWith((ref) async => repo),
        programFeedProvider.overrideWith(
          (ref) => Stream.value(
            ServerSnapshot<ProgramFeed>(
              ProgramFeed(
                active: status == 'active' ? _program(status) : null,
                suggested: status == 'suggested'
                    ? <HealthProgram>[_program(status)]
                    : const <HealthProgram>[],
                recent: const <HealthProgram>[],
              ),
              fetchedAt: DateTime(2026, 10, 18),
            ),
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const ProgramDetailScreen(id: 7),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  testWidgets('sections run in order and carry only the program fields', (
    tester,
  ) async {
    await _open(tester, 'active');
    double y(Finder f) => tester.getTopLeft(f.first).dy;
    final order = <Finder>[
      find.text('Back to 150'),
      find.text('80 min'),
      find.text(kRulesHeading),
      find.text(kWhyMinutesHeading),
      find.text(kWatchHeading),
    ];
    for (var i = 1; i < order.length; i++) {
      expect(y(order[i]), greaterThan(y(order[i - 1])), reason: '$i');
    }
    // Intro is the program's own words, markers stripped.
    expect(find.textContaining('Reach 150 active minutes'), findsOneWidget);
    expect(find.textContaining('[mvpa'), findsNothing);
    expect(find.text(kThisWeek), findsOneWidget);
    expect(find.text('locked'), findsOneWidget);
    expect(find.text('100 min'), findsOneWidget);
    expect(find.text('Weekly · 19 to 25 Oct'), findsOneWidget);
    expect(kProgramRules, hasLength(5));
    expect(find.textContaining('Miss a week, repeat it.'), findsOneWidget);
  });

  testWidgets('the evidence chip uses the real id and its real grade', (
    tester,
  ) async {
    await _open(tester, 'active');
    expect(find.text('Established · mvpa_minutes_mortality'), findsOneWidget);
    expect(evidenceChipText('not_a_real_note'), 'not_a_real_note');
  });

  testWidgets('End plan asks first, and only a yes abandons', (tester) async {
    final repo = await _open(tester, 'active');
    await tester.tap(find.text('End plan'));
    await tester.pumpAndSettle();
    expect(find.text('End this plan?'), findsOneWidget);
    await tester.tap(find.text('Keep plan'));
    await tester.pumpAndSettle();
    expect(repo.calls, isEmpty);
    await tester.tap(find.text('End plan'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'End plan'));
    await tester.pumpAndSettle();
    expect(repo.calls, <String>['7:abandon']);
  });

  testWidgets('a suggested program offers Start and no End plan', (
    tester,
  ) async {
    final repo = await _open(tester, 'suggested');
    expect(find.text('End plan'), findsNothing);
    await tester.tap(find.text('Start this program'));
    await tester.pumpAndSettle();
    expect(repo.calls, <String>['7:adopt']);
  });

  test('a rung whose progress carries an empty unit still names its unit', () {
    const steps = Challenge(
      id: 1,
      title: 'Rung 3',
      why: 'x',
      status: 'active',
      metric: 'steps_total',
      target: 8900,
      comparator: '>=',
      cadence: 'daily',
      windowDays: 7,
      difficulty: 'standard',
      kind: 'standard',
      citations: <String>[],
      progress: ChallengeProgress(
        cadence: 'daily',
        target: 8900,
        daysLeft: 3,
        unit: '',
      ),
    );
    expect(rungHeadline(steps), '8,900 steps');
    expect(rungHeadline(_rung(2, 'locked')), '80 min');
  });
}
