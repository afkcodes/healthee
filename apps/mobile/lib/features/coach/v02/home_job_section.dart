/// "This week's job": the one thing the coach asked for, and what the strap says.
///
/// The job is the opened review's, or a coach job already in the challenge feed.
/// The dots are the ledger's verdicts for this job's challenge in the job's
/// week; the count beside the heading is those that are done.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/metric_hue.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/data/challenges/commitment_repository.dart';
import 'package:healthee/data/coach/job_source.dart';
import 'package:healthee/data/coach/ledger_models.dart';
import 'package:healthee/data/coach/ledger_repository.dart';
import 'package:healthee/data/coach/review_models.dart';
import 'package:healthee/data/coach/review_repository.dart';
import 'package:healthee/data/coach/review_week.dart';
import 'package:healthee/data/store/store_provider.dart';
import 'package:healthee/features/coach/v02/home_head.dart';
import 'package:healthee/features/coach/v02/job_actions.dart';
import 'package:healthee/features/coach/v02/job_week_dots.dart';
import 'package:healthee/shared/format/date_labels.dart';
import 'package:healthee/shared/format/metric_names.dart';
import 'package:healthee/shared/v02/surface_panels.dart';

/// The words on the domain chip.
String domainLabel(Tone tone) => switch (tone.canonical) {
  Tone.movement => 'Activity',
  Tone.sleep => 'Sleep',
  Tone.heart => 'Heart',
  Tone.load => 'Training',
  Tone.oxygen => 'Breathing',
  Tone.stress => 'Mind',
  Tone.recovery => 'Recovery',
  _ => 'Body',
};

/// The headline's two halves: the target, then unit and action.
///
/// ONE function for a job from the review and one from the challenge feed, so
/// they read the same. The unit is the job's own, else the metric's; the action
/// is the coach's words with only the first letter lower-cased.
({String number, String rest}) jobHeadlineParts(ReviewJob job) {
  final t = job.target;
  final number = t == t.roundToDouble() ? '${t.round()}' : '$t';
  final unit = job.unit.isNotEmpty ? job.unit : metricUnitWord(job.metric);
  final action = job.action.isEmpty
      ? ''
      : job.action[0].toLowerCase() + job.action.substring(1);
  return (
    number: number,
    rest: <String>[unit, action].where((p) => p.isNotEmpty).join(' '),
  );
}

/// `20 min brisk walk`.
String jobHeadline(ReviewJob job) {
  final parts = jobHeadlineParts(job);
  return '${parts.number} ${parts.rest}';
}

/// The said-so line when there is no job.
const String kNoJob =
    'No job yet. The weekly review writes one; open it above.';

/// The section.
class CoachJobSection extends ConsumerWidget {
  /// Reads the review, the feed, the ledger and today.
  const CoachJobSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayProvider);
    final review = ref.watch(coachReviewProvider).value;
    final feed = ref.watch(challengeFeedProvider).value?.data;
    final job = resolveJob(review, feed);
    if (job == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          CoachSectionHead.text(context, "This week's job"),
          SurfaceCard(
            child: Text(
              kNoJob,
              style: TypeLadder.body.copyWith(color: context.colors.ink2),
            ),
          ),
        ],
      );
    }
    final bounds = coachWeekBounds(DateTime.tryParse(today) ?? DateTime.now());
    final weekFrom = review != null && review.weekFrom.isNotEmpty
        ? review.weekFrom
        : bounds.from;
    final weekTo = review != null && review.weekTo.isNotEmpty
        ? review.weekTo
        : bounds.to;
    final ledger = ref.watch(coachLedgerProvider(LedgerWindow.month)).value;
    final entries = jobEntries(ledger, weekFrom, job.challengeId);
    final done = entries.where((e) => e.verdict == LedgerVerdict.done).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        CoachSectionHead.text(
          context,
          "This week's job",
          trailing: HeadCaption('$done of ${job.daysRequired} done'),
        ),
        JobCard(
          job: job,
          adopted: isAdopted(job, feed),
          weekFrom: weekFrom,
          weekTo: weekTo,
          today: today,
          entries: entries,
          todayLine: review?.todayLine,
        ),
      ],
    );
  }
}

/// The ledger entries for [challengeId] in the week starting [weekFrom].
List<LedgerEntry> jobEntries(
  CoachLedger? ledger,
  String weekFrom,
  int challengeId,
) => <LedgerEntry>[
  if (ledger != null)
    for (final week in ledger.weeks)
      if (week.from == weekFrom)
        for (final entry in week.entries)
          if (entry.refId == challengeId) entry,
];

/// The card.
class JobCard extends StatelessWidget {
  /// Draws [job] for the week [weekFrom] to [weekTo].
  const JobCard({
    required this.job,
    required this.adopted,
    required this.weekFrom,
    required this.weekTo,
    required this.today,
    required this.entries,
    this.todayLine,
    super.key,
  });

  /// The job.
  final ReviewJob job;

  /// Whether it is running.
  final bool adopted;

  /// Monday, ISO.
  final String weekFrom;

  /// Sunday, ISO.
  final String weekTo;

  /// The owner's day, ISO.
  final String today;

  /// This job's ledger entries for the week.
  final List<LedgerEntry> entries;

  /// The coach's line for today.
  final String? todayLine;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final kinds = weekDots(weekFrom: weekFrom, today: today, entries: entries);
    return SurfaceCard(
      tone: toneFor(job.metric),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _TopLine(tone: toneFor(job.metric), weekTo: weekTo),
          const SizedBox(height: Insets.md),
          _Headline(job: job),
          const SizedBox(height: Insets.xs),
          Text(
            '${job.daysRequired} days out of 7',
            style: TypeLadder.headline.copyWith(color: colors.ink),
          ),
          const SizedBox(height: Insets.lg),
          JobWeekDots(kinds: kinds, todayIndex: _indexOf(weekFrom, today)),
          if (todayLine case final String line) ...<Widget>[
            const SizedBox(height: Insets.md),
            Text(line, style: TypeLadder.body.copyWith(color: colors.ink2)),
          ],
          const SizedBox(height: Insets.lg),
          Divider(height: hairline, thickness: hairline, color: colors.line),
          const SizedBox(height: Insets.md),
          if (job.countsWhen case final String text)
            _FactRow(label: 'Counts', text: text),
          if (job.slot case final String text)
            _FactRow(label: 'When', text: text),
          if (job.floor case final String text)
            _FactRow(label: 'Bad day', text: text),
          const SizedBox(height: Insets.md),
          JobActions(job: job, adopted: adopted),
        ],
      ),
    );
  }

  static int _indexOf(String weekFrom, String today) {
    final start = DateTime.tryParse(weekFrom);
    final day = DateTime.tryParse(today);
    if (start == null || day == null) {
      return -1;
    }
    final index = DateTime(
      day.year,
      day.month,
      day.day,
    ).difference(DateTime(start.year, start.month, start.day)).inDays;
    return index >= 0 && index < 7 ? index : -1;
  }
}

class _TopLine extends StatelessWidget {
  const _TopLine({required this.tone, required this.weekTo});

  final Tone tone;
  final String weekTo;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: <Widget>[
        DecoratedBox(
          decoration: BoxDecoration(
            color: context.familySoft,
            borderRadius: BorderRadius.circular(Radii.pill),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Insets.md,
              vertical: Insets.xs,
            ),
            child: Text(
              domainLabel(tone),
              style: TypeLadder.calloutStrong.copyWith(color: context.family),
            ),
          ),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            'ends Sun ${shortDate(weekTo)}',
            style: TypeLadder.callout.copyWith(color: colors.ink2),
          ),
        ),
      ],
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline({required this.job});

  final ReviewJob job;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (:number, :rest) = jobHeadlineParts(job);
    return Text.rich(
      TextSpan(
        children: <InlineSpan>[
          TextSpan(
            text: number,
            style: TypeLadder.metric.copyWith(color: colors.ink),
          ),
          if (rest.isNotEmpty)
            TextSpan(
              text: ' $rest',
              style: TypeLadder.title2.copyWith(
                color: colors.ink2,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TypeLadder.callout.copyWith(color: colors.ink2),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TypeLadder.callout.copyWith(color: colors.ink),
            ),
          ),
        ],
      ),
    );
  }
}
