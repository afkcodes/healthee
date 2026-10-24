import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/coach/job_source.dart';
import 'package:healthee/data/coach/ledger_models.dart';
import 'package:healthee/data/coach/review_models.dart';
import 'package:healthee/features/coach/v02/home_job_section.dart';
import 'package:healthee/features/coach/v02/home_review_card.dart';
import 'package:healthee/features/coach/v02/job_week_dots.dart';

import '../_settings_harness.dart' show tallViewport;
import '_coach_home_fakes.dart';

/// The review row above the job, because the job comes from opening it.
Widget _both() => const Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: <Widget>[WeeklyReviewCard(), CoachJobSection()],
);

Future<CoachHost> _open(
  WidgetTester tester, {
  void Function(CoachHost host)? setup,
  bool openReview = true,
}) async {
  tallViewport(tester);
  final host = await CoachHost.create();
  setup?.call(host);
  await tester.pumpWidget(host.wrap(_both()));
  await tester.pumpAndSettle();
  if (openReview) {
    await tester.tap(find.text('Weekly review'));
    await tester.pumpAndSettle();
  }
  return host;
}

Finder _inDialog(String text) =>
    find.descendant(of: find.byType(AlertDialog), matching: find.text(text));

void main() {
  test('one headline for a job from the review and one from the feed', () {
    final fromReview = ReviewJob.tryParse(job())!;
    final fromFeed = ReviewJob.tryParse(<String, Object?>{
      ...job(action: 'Brisk walk'),
      'unit': '',
    })!;
    expect(jobHeadline(fromReview), '20 min brisk walk');
    expect(jobHeadline(fromFeed), jobHeadline(fromReview));
    // Through the feed's own conversion: no unit given, title capitalised.
    final bare = resolveJob(
      null,
      ChallengeFeedOf.active(challenge(12, days: 4, bare: true)),
    )!;
    expect(jobHeadline(bare), '20 min brisk walk');
  });

  group('the week of dots', () {
    final entries = <LedgerEntry>[
      ...week('2026-10-19', <int, String>{
        0: 'done',
        1: 'partial',
        2: 'missed',
        3: 'no_data',
        5: 'uncheckable',
      }).entries,
    ];

    test('each verdict, today with no verdict, and the future', () {
      expect(
        weekDots(weekFrom: '2026-10-19', today: '2026-10-23', entries: entries),
        <DotKind>[
          DotKind.done,
          DotKind.partial,
          DotKind.missed,
          DotKind.noProof,
          DotKind.today,
          DotKind.noProof,
          DotKind.empty,
        ],
      );
    });

    test('a verdict on today beats the ring', () {
      expect(
        weekDots(
          weekFrom: '2026-10-19',
          today: '2026-10-19',
          entries: entries,
        ).first,
        DotKind.done,
      );
    });

    test('a bad week start draws seven empty wells, not a crash', () {
      expect(
        weekDots(weekFrom: '', today: '2026-10-19', entries: entries),
        List<DotKind>.filled(7, DotKind.empty),
      );
    });
  });

  testWidgets('no job: the honest card, and no dots', (tester) async {
    await _open(tester, openReview: false);
    expect(find.text(kNoJob), findsOneWidget);
    expect(find.byType(DayDot), findsNothing);
    expect(find.text("I'm in"), findsNothing);
  });

  testWidgets('the job card reads the review: chip, headline, rules', (
    tester,
  ) async {
    await _open(tester, setup: (h) => h.today = '2026-10-23');
    expect(find.text("This week's job"), findsOneWidget);
    expect(find.text('Activity'), findsOneWidget);
    expect(find.text('ends Sun 25 Oct'), findsOneWidget);
    expect(find.text('20 min brisk walk', findRichText: true), findsOneWidget);
    expect(find.text('4 days out of 7'), findsOneWidget);
    expect(find.text('Counts'), findsOneWidget);
    expect(
      find.text('when the strap logs 15+ brisk minutes. No tap needed.'),
      findsOneWidget,
    );
    expect(
      find.text('after 10 pm, once your evening block ends.'),
      findsOneWidget,
    );
    expect(
      find.text('10 minutes. Half credit, streak survives.'),
      findsOneWidget,
    );
    expect(find.text('Today: 20 minutes.'), findsOneWidget);
  });

  testWidgets('no today line, no line', (tester) async {
    await _open(
      tester,
      setup: (h) => h.respond = (_) async => review(todayLine: null),
    );
    expect(find.text('Today: 20 minutes.'), findsNothing);
  });

  testWidgets('dots are the strap verdicts for THIS job; N of M counts done', (
    tester,
  ) async {
    await _open(
      tester,
      setup: (h) {
        h.today = '2026-10-23';
        h.served = (_) => ledger(
          weeks: <LedgerWeek>[
            week('2026-10-19', <int, String>{
              0: 'done',
              1: 'partial',
              2: 'missed',
              3: 'no_data',
            }),
            // Another challenge's done day must not light this job's dot.
            week('2026-10-19', <int, String>{4: 'done'}, ref: 99),
          ],
        );
      },
    );
    final kinds = tester
        .widgetList<DayDot>(find.byType(DayDot))
        .map((d) => d.kind)
        .toList();
    expect(kinds, <DotKind>[
      DotKind.done,
      DotKind.partial,
      DotKind.missed,
      DotKind.noProof,
      DotKind.today,
      DotKind.empty,
      DotKind.empty,
    ]);
    expect(find.text('1 of 4 done'), findsOneWidget);
  });

  testWidgets("I'm in adopts this job's challenge and nothing else", (
    tester,
  ) async {
    final host = await _open(tester);
    expect(find.text("I'm in"), findsOneWidget);
    expect(find.text('Change time'), findsOneWidget);
    expect(find.text('End plan'), findsNothing);
    await tester.tap(find.text("I'm in"));
    await tester.pumpAndSettle();
    expect(host.commitments.actions, <String>['adopt 12']);
    expect(host.slots.writes, isEmpty);
  });

  testWidgets('once running: Change time and a quiet End plan, no I\'m in', (
    tester,
  ) async {
    await _open(
      tester,
      setup: (h) => h.feed = ChallengeFeedOf.active(challenge(12, days: 4)),
    );
    expect(find.text("I'm in"), findsNothing);
    expect(find.text('Change time'), findsOneWidget);
    expect(find.text('End plan'), findsOneWidget);
  });

  testWidgets('Change time writes only the slot, as words', (tester) async {
    final host = await _open(tester);
    await tester.tap(find.text('Change time'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(host.slots.writes, <String>['12:at 7:00 pm']);
    expect(host.commitments.actions, isEmpty);
    expect(find.text('at 7:00 pm'), findsOneWidget);
    expect(find.text('20 min brisk walk', findRichText: true), findsOneWidget);
  });

  testWidgets('Change time, cancelled, writes nothing', (tester) async {
    final host = await _open(tester);
    await tester.tap(find.text('Change time'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(host.slots.writes, isEmpty);
  });

  testWidgets('End plan asks first; Keep plan abandons nothing', (
    tester,
  ) async {
    final host = await _open(
      tester,
      setup: (h) => h.feed = ChallengeFeedOf.active(challenge(12, days: 4)),
    );
    await tester.tap(find.text('End plan'));
    await tester.pumpAndSettle();
    expect(find.text('End this plan?'), findsOneWidget);
    await tester.tap(find.text('Keep plan'));
    await tester.pumpAndSettle();
    expect(host.commitments.actions, isEmpty);

    await tester.tap(find.text('End plan'));
    await tester.pumpAndSettle();
    await tester.tap(_inDialog('End plan'));
    await tester.pumpAndSettle();
    expect(host.commitments.actions, <String>['abandon 12']);
  });

  testWidgets('before the review is opened, a coach job in the feed shows', (
    tester,
  ) async {
    await _open(
      tester,
      openReview: false,
      setup: (h) => h.feed = ChallengeFeedOf.active(challenge(12, days: 4)),
    );
    expect(find.text('4 days out of 7'), findsOneWidget);
    expect(find.text('End plan'), findsOneWidget);
    expect(find.text(kNoJob), findsNothing);
  });
}
