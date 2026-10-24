/// One challenge — `screens-actions.js::H.screens.challenge`, in Flutter.
///
/// ```text
///   header (detail)   "Your 7-day challenge" · the challenge's own title
///   badge             Active · <metric>
///   sleep-hero        Daily target · 9,000 steps · what it is a step up from
///   card              Your week · the counts, the track, today's standing
///   section           Make it fit your day → focus card + the evidence
///   two               Adjust target · End challenge
///   text-button       See previous outcomes
///   footer
/// ```
///
/// ## The seven-day grid is NOT drawn, and that is the honesty rule
///
/// The prototype's `.weekly-days` element shows one cell per day of the window
/// with the current one ringed. `/api/challenges` sends `hit_days`, `window` and
/// `streak` — **counts, not a per-day series** — so seven cells would need six
/// observations nobody sent. The card draws the counts the server did send. This
/// is the same call `today_body.dart` makes about a seven-night chart with two
/// nights in it.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:healthee/core/router.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/core/theme/type_scale.dart';
import 'package:healthee/data/challenges/challenge.dart';
import 'package:healthee/data/challenges/challenge_feed.dart';
import 'package:healthee/data/challenges/commitment_repository.dart';
import 'package:healthee/data/honesty/citations.dart';
import 'package:healthee/features/actions/v02/challenge_card.dart';
import 'package:healthee/features/actions/v02/evidence_sheet.dart';
import 'package:healthee/features/actions/v02/suggestion_card.dart';
import 'package:healthee/features/today/v02/today_header.dart';
import 'package:healthee/shared/challenge_outcome_card.dart';
import 'package:healthee/shared/format/metric_names.dart';
import 'package:healthee/shared/page_section.dart';
import 'package:healthee/shared/server_action_button.dart';
import 'package:healthee/shared/states/account_async_view.dart';
import 'package:healthee/shared/states/cached_async_view.dart';
import 'package:healthee/shared/states/state_scaffold.dart';
import 'package:healthee/shared/v02/controls.dart';
import 'package:healthee/shared/v02/detail_page.dart';
import 'package:healthee/shared/v02/panel_parts.dart';
import 'package:healthee/shared/v02/section_head.dart';
import 'package:healthee/shared/v02/surfaces.dart';
import 'package:solar_icons/solar_icons.dart';

/// The prototype's own heading over the progress card.
const String kWeekHeading = 'Your week';

/// Its section heading.
const String kFitHeading = 'Make it fit your day';

/// One challenge, in full.
class ChallengeDetailScreen extends ConsumerWidget {
  /// [id] is the server's row id.
  const ChallengeDetailScreen({required this.id, super.key});

  /// Which challenge.
  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AccountAsyncView<CommitmentRepository>(
      value: ref.watch(commitmentRepositoryProvider),
      onRetry: () => ref.invalidate(commitmentRepositoryProvider),
      builder: (context, repository) => CachedAsyncView<ChallengeFeed>(
        value: ref.watch(challengeFeedProvider),
        onRetry: () => ref.invalidate(challengeFeedProvider),
        builder: (context, feed) => switch (feed.find(id)) {
          final Challenge challenge => _Body(
            challenge: challenge,
            repository: repository,
            onChanged: () => ref.invalidate(commitmentRepositoryProvider),
          ),
          null => const DetailPage(
            title: 'Challenge unavailable',
            children: <Widget>[
              EmptyState(
                message: 'Challenge unavailable',
                hint: 'It may have moved out of the recent history.',
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
    required this.challenge,
    required this.repository,
    required this.onChanged,
  });

  final Challenge challenge;
  final CommitmentRepository repository;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final progress = challenge.progress;
    return ToneScope(
      tone: toneForCategory(challenge.metric.split('_').first),
      child: DetailPage(
        eyebrow: '${challenge.windowDays}-day challenge',
        title: challenge.title,
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: StatusBadge(
              '${_status(challenge.status)} · ${metricName(challenge.metric)}',
              accented: true,
            ),
          ),
          HeroReading(
            label: '${challenge.cadence == 'daily' ? 'Daily' : 'Window'} target',
            value: _trim(challenge.target),
            unit: progress?.unit,
            context_: challenge.why,
          ),
          if (progress != null) _Progress(challenge: challenge),
          const SizedBox(height: SectionHead.sectionGap),
          if (challenge.howTo case final String how) ...<Widget>[
            const SectionHead(title: kFitHeading),
            FocusCard(
              eyebrow: kFitHeading,
              title: Text(how),
              body: challenge.expectedOutcome == null
                  ? null
                  : Text(challenge.expectedOutcome!),
              footer: TextLink(
                label: 'The evidence behind it',
                icon: SolarIconsOutline.infoCircle,
                onPressed: () => showEvidenceSheet(
                  context,
                  title: 'Behind this challenge',
                  prose: challenge.why,
                  grounding: groundingOf(
                    challenge.why,
                    alsoCites: challenge.citations,
                  ),
                ),
              ),
            ),
            const SizedBox(height: SectionHead.sectionGap),
          ],
          if (challenge.outcome case final outcome) ...<Widget>[
            if (outcome != null) ChallengeOutcomeCard(outcome: outcome),
            if (outcome != null) const SizedBox(height: PageSpacing.block),
          ],
          _Controls(
            challenge: challenge,
            repository: repository,
            onChanged: onChanged,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextLink(
              label: 'Every yes, checked',
              onPressed: () => unawaited(context.push(Routes.coachLedger)),
            ),
          ),
          const DataFooter(),
        ],
      ),
    );
  }

  static String _status(String status) =>
      status.isEmpty ? status : status[0].toUpperCase() + status.substring(1);
}

/// `Your week` — the counts, the track and where today stands.
class _Progress extends StatelessWidget {
  const _Progress({required this.challenge});

  final Challenge challenge;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final progress = challenge.progress!;
    final filled = ChallengeCard.fraction(progress);
    final standing = ChallengeCard.standing(challenge);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  kWeekHeading,
                  style: TypeScale.rowTitle.copyWith(color: colors.ink),
                ),
              ),
              Text(
                '${progress.daysLeft} days left',
                style: TypeScale.tinyLabel.copyWith(color: colors.ink2),
              ),
            ],
          ),
          if (standing case final String line) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              line,
              style: TypeScale.small.copyWith(color: colors.ink2),
            ),
          ],
          if (filled case final double value) ...<Widget>[
            const SizedBox(height: 16),
            ProgressTrack(fraction: value),
          ],
          if (progress.todayValue case final double today) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              'Today · ${_trim(today)} ${progress.unit}',
              style: TypeScale.tinyLabel.copyWith(color: colors.ink2),
            ),
          ],
          if (progress.streak case final int streak) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              'Current streak · $streak days',
              style: TypeScale.tinyLabel.copyWith(color: colors.ink2),
            ),
          ],
          if (progress.protectedToday) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              'Today is protected for recovery.',
              style: TypeScale.tinyLabel.copyWith(color: colors.ink2),
            ),
          ],
          if (progress.breached) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              'The cap has been exceeded in this window.',
              style: TypeScale.tinyLabel.copyWith(color: colors.ink2),
            ),
          ],
          if (progress.adaptationReason case final String why) ...<Widget>[
            const SizedBox(height: 8),
            Text(why, style: TypeScale.tinyLabel.copyWith(color: colors.ink2)),
          ],
        ],
      ),
    );
  }
}

/// `.two` — the two secondary controls the prototype puts under the card.
class _Controls extends StatelessWidget {
  const _Controls({
    required this.challenge,
    required this.repository,
    required this.onChanged,
  });

  final Challenge challenge;
  final CommitmentRepository repository;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final direction = challenge.progress?.adaptationDirection;
    final controls = <Widget>[
      if (challenge.status == 'suggested')
        _action('Start challenge', 'adopt', full: true),
      if (challenge.status == 'active') ...<Widget>[
        if (direction != null && direction != 'withheld')
          _action('Adjust target', 'adapt'),
        _action('End challenge', 'abandon'),
      ],
    ];
    if (controls.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: PageSpacing.block),
      child: controls.length == 1
          ? controls.single
          : Row(
              children: <Widget>[
                Expanded(child: controls.first),
                const SizedBox(width: 12),
                Expanded(child: controls.last),
              ],
            ),
    );
  }

  Widget _action(String label, String action, {bool full = false}) =>
      ServerActionButton(
        label: label,
        full: full,
        style: ActionButtonStyle.v02,
        action: () async {
          await repository.challengeAction(challenge.id, action);
          return null;
        },
        onSaved: onChanged,
      );
}

String _trim(double value) =>
    value == value.roundToDouble() ? '${value.round()}' : '$value';
