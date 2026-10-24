/// One program, in the Coach area's own layout: its ladder, its rules, the
/// evidence behind it, and what the coach watches.
///
/// ```text
///   back "Coach" · the program's title
///   intro            the program's own `why`, goal, hold and end notes
///   button           Start this program (a suggested program only)
///   ladder card      one numbered row per rung, the current one lit
///   Rules            five product rules, static copy
///   Why this         the evidence chip and the program's `why`
///   What I watch     the metric, the Sunday review, End plan
/// ```
///
/// A rung's state comes off the wire: `active` is the current rung, so a plan
/// the server adapted mid-run never says a week the screen counted itself.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthee/core/logging.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/data/challenges/commitment_repository.dart';
import 'package:healthee/data/challenges/health_program.dart';
import 'package:healthee/data/challenges/program_feed.dart';
import 'package:healthee/data/honesty/citations.dart';
import 'package:healthee/features/actions/v02/evidence_sheet.dart';
import 'package:healthee/features/actions/v02/program_evidence_card.dart';
import 'package:healthee/features/actions/v02/program_rules_card.dart';
import 'package:healthee/features/actions/v02/program_rungs_card.dart';
import 'package:healthee/features/actions/v02/program_watch_card.dart';
import 'package:healthee/shared/format/metric_names.dart';
import 'package:healthee/shared/server_action_button.dart';
import 'package:healthee/shared/states/account_async_view.dart';
import 'package:healthee/shared/states/cached_async_view.dart';
import 'package:healthee/shared/states/state_scaffold.dart';
import 'package:healthee/shared/v02/back_label_head.dart';
import 'package:healthee/shared/v02/detail_page.dart';

/// Heading over the ladder's rules.
const String kRulesHeading = 'Rules';

/// Heading over the evidence card.
const String kWhyHeading = 'Why this plan';

/// The same heading on an active-minutes plan, where the comparison is true.
const String kWhyMinutesHeading = 'Why this, not 9,000 steps';

/// Heading over the watch card.
const String kWatchHeading = 'What I watch';

/// One program, in full.
class ProgramDetailScreen extends ConsumerWidget {
  /// [id] is the server's row id.
  const ProgramDetailScreen({required this.id, super.key});

  /// Which program.
  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AccountAsyncView<CommitmentRepository>(
      value: ref.watch(commitmentRepositoryProvider),
      onRetry: () => ref.invalidate(commitmentRepositoryProvider),
      builder: (context, repository) => CachedAsyncView<ProgramFeed>(
        value: ref.watch(programFeedProvider),
        onRetry: () => ref.invalidate(programFeedProvider),
        builder: (context, feed) => switch (feed.find(id)) {
          final HealthProgram program => _Body(
            program: program,
            repository: repository,
            onChanged: () => ref.invalidate(commitmentRepositoryProvider),
          ),
          null => const DetailPage(
            title: 'Program unavailable',
            children: <Widget>[
              EmptyState(
                message: 'Program unavailable',
                hint: 'Refresh the program feed.',
              ),
            ],
          ),
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.program,
    required this.repository,
    required this.onChanged,
  });

  final HealthProgram program;
  final CommitmentRepository repository;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final citations = <String>{
      for (final rung in program.rungs) ...rung.citations,
    }.toList();
    final why = parseGrounded(program.why).prose.trim();
    final metric = program.rungs.isEmpty ? null : program.rungs.first;
    final intro = <String>[
      if (why.isNotEmpty) why,
      if (program.goal case final String goal) goal,
      if (program.holdReason case final String hold) 'On hold: $hold',
      if (program.endedReason case final String ended) 'Ended: $ended',
    ];
    return DetailPage(
      title: program.title,
      head: (context, onBack) => BackLabelHead(
        backLabel: 'Coach',
        title: program.title,
        onBack: onBack,
      ),
      children: <Widget>[
        for (final line in intro) ...<Widget>[
          Text(line, style: TypeLadder.body.copyWith(color: colors.ink2)),
          const SizedBox(height: Insets.sm),
        ],
        if (program.status == 'suggested') ...<Widget>[
          const SizedBox(height: Insets.md),
          ServerActionButton(
            label: 'Start this program',
            style: ActionButtonStyle.v02,
            full: true,
            action: () async {
              await repository.programAction(program.id, 'adopt');
              return null;
            },
            onSaved: onChanged,
          ),
        ],
        const SizedBox(height: Insets.lg),
        if (program.rungs.isNotEmpty) ...<Widget>[
          ProgramRungsCard(rungs: program.rungs),
          const SizedBox(height: Insets.section),
        ],
        const _Heading(kRulesHeading),
        const ProgramRulesCard(),
        const SizedBox(height: Insets.section),
        if (why.isNotEmpty) ...<Widget>[
          _Heading(
            metric?.metric == 'mvpa_min' ? kWhyMinutesHeading : kWhyHeading,
          ),
          ProgramEvidenceCard(
            why: program.why,
            noteId: citations.firstOrNull,
            onOpen: citations.isEmpty
                ? null
                : () => showEvidenceSheet(
                    context,
                    title: 'Behind this program',
                    prose: program.why,
                    grounding: groundingOf(program.why, alsoCites: citations),
                  ),
          ),
          const SizedBox(height: Insets.section),
        ],
        const _Heading(kWatchHeading),
        ProgramWatchCard(
          watchTitle: metric == null
              ? 'The strap'
              : '${metricTitle(metric.metric)}, ${metric.cadence}',
          onEnd: program.status == 'active' ? () => _end(context) : null,
        ),
      ],
    );
  }

  Future<void> _end(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await repository.programAction(program.id, 'abandon');
      onChanged();
    } on Object catch (error, stack) {
      AppLog.failure('program', 'ending a program', error, stack);
      messenger?.showSnackBar(
        const SnackBar(content: Text('Could not end the plan. Try again.')),
      );
    }
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Insets.md),
    child: Text(
      text,
      style: TypeLadder.title2.copyWith(color: context.colors.ink),
    ),
  );
}
