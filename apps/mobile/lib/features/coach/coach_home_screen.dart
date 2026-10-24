/// The Coach tab: one weekly review, one job, and the record of the yeses.
///
/// Replaces the old Actions deck. The order is the design's
/// (`design/redesign-2026-10/04-coach-home.png`) and is a list of sections, so
/// a section is inserted with one line.
///
/// The chat is a different screen (`coach_screen.dart`, route `/coach`) and is
/// untouched. Nothing here is asked of the server until the owner opens the
/// weekly review.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthee/data/challenges/commitment_repository.dart';
import 'package:healthee/data/coach/ledger_repository.dart';
import 'package:healthee/data/store/store_provider.dart';
import 'package:healthee/features/coach/v02/home_job_section.dart';
import 'package:healthee/features/coach/v02/home_links_card.dart';
import 'package:healthee/features/coach/v02/home_record_section.dart';
import 'package:healthee/features/coach/v02/home_review_card.dart';
import 'package:healthee/features/coach/v02/todays_basics_section.dart';
import 'package:healthee/features/coach/v02/water_card.dart';
import 'package:healthee/shared/format/date_labels.dart';
import 'package:healthee/shared/instrument_screen.dart';
import 'package:healthee/shared/page_section.dart';
import 'package:healthee/shared/v02/data_footer.dart';
import 'package:healthee/shared/v02/past_day.dart';
import 'package:healthee/shared/v02/screen_head.dart';

/// The screen's title.
const String kCoachTitle = 'Coach';

/// What Coach cannot date.
const String kCoachPastTitle = 'No coach record for this day';

/// The Coach tab.
class CoachHomeScreen extends ConsumerWidget {
  /// [now] is injected by tests.
  const CoachHomeScreen({this.now, super.key});

  /// The instant freshness labels are measured against.
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) => InstrumentScreen(
    now: now,
    sections: coachHomeSections,
    onRefreshed: () {
      ref
        ..invalidate(commitmentRepositoryProvider)
        ..invalidate(challengeFeedProvider)
        ..invalidate(programFeedProvider)
        ..invalidate(coachLedgerProvider);
    },
  );
}

/// The ordered sections of one render.
List<PageSection> coachHomeSections(ScreenData data) {
  final past = data.view.isPast;
  return <PageSection>[
    PageSection(
      _CoachHead(pastLine: past ? data.view.line : null),
      gap: PageSpacing.panel,
    ),
    if (past)
      const PageSection(
        PastDayNotice(title: kCoachPastTitle, body: kPastDayReason),
      )
    else ...<PageSection>[
      const PageSection(WeeklyReviewCard(), gap: PageSpacing.block),
      const PageSection(CoachJobSection(), gap: PageSpacing.block),
      const PageSection(
        TodaysBasicsSection(water: WaterCard()),
        gap: PageSpacing.block,
      ),
      const PageSection(CoachRecordSection(), gap: PageSpacing.panel),
      const PageSection(CoachLinksCard(), gap: PageSpacing.block),
    ],
    const PageSection(DataFooter(), gap: 0),
  ];
}

class _CoachHead extends ConsumerWidget {
  const _CoachHead({this.pastLine});

  final String? pastLine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final program = ref.watch(programFeedProvider).value?.data.active;
    final weeks = program?.weeks;
    final week = program == null || weeks == null || weeks <= 0
        ? null
        : (program.settledRungs + 1).clamp(1, weeks);
    final date = pastLine ?? dayDateLine(ref.watch(todayProvider));
    return ScreenHead(
      eyebrow: week == null ? date : '$date · week $week of $weeks',
      title: kCoachTitle,
    );
  }
}
