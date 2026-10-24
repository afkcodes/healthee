/// The weekly review row: collapsed until the owner opens it.
///
/// Opening is what asks the server (the first call in a week writes the review,
/// so it is slow and counts as a coach question). The result is held for the app
/// session, so closing and opening again asks nothing. Text is shown as the
/// coach wrote it: no number is picked out of a sentence and recoloured.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/data/coach/coach_client.dart';
import 'package:healthee/data/coach/review_models.dart';
import 'package:healthee/data/coach/review_repository.dart';
import 'package:healthee/data/coach/review_week.dart';
import 'package:healthee/data/store/store_provider.dart';
import 'package:healthee/shared/format/date_labels.dart';
import 'package:healthee/shared/format/date_range.dart';
import 'package:healthee/shared/skeletons/h_skeleton.dart';
import 'package:healthee/shared/states/state_scaffold.dart';
import 'package:healthee/shared/v02/surface_panels.dart';
import 'package:solar_icons/solar_icons.dart';

/// The line when the week had too few readings to write from.
const String kNoReview = 'Not enough readings this week to write a review yet.';

/// The footer's right side.
const String kKeptUntil = 'Kept until Sunday';

/// The footer's left side: just now when this call wrote it, else the weekday.
String writtenLine(CoachReview review) {
  if (!review.cached) {
    return 'Written just now, when you opened it';
  }
  final at = review.generatedAt;
  if (at == null) {
    return 'Written earlier this week';
  }
  const days = <String>[
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
    'Sunday', //
  ];
  return 'Written ${days[at.weekday - 1]}';
}

/// The row.
class WeeklyReviewCard extends ConsumerStatefulWidget {
  /// A collapsed review; [initiallyOpen] is for tests.
  const WeeklyReviewCard({this.initiallyOpen = false, super.key});

  /// Start expanded (and ask) rather than collapsed.
  final bool initiallyOpen;

  @override
  ConsumerState<WeeklyReviewCard> createState() => _WeeklyReviewCardState();
}

class _WeeklyReviewCardState extends ConsumerState<WeeklyReviewCard> {
  late bool _open = widget.initiallyOpen;

  @override
  void initState() {
    super.initState();
    if (_open) {
      unawaited(Future<void>.microtask(_ask));
    }
  }

  Future<void> _ask() => ref.read(coachReviewProvider.notifier).open();

  void _toggle() {
    setState(() => _open = !_open);
    if (_open) {
      unawaited(_ask());
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(coachReviewProvider);
    final review = state.value;
    final range = review != null && review.weekFrom.isNotEmpty
        ? dateRangeLabel(review.weekFrom, review.weekTo)
        : _guessRange(ref.watch(todayProvider));
    final colors = context.colors;
    return SurfaceCard(
      flush: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Semantics(
            button: true,
            expanded: _open,
            label: 'Weekly review',
            child: InkWell(
              onTap: _toggle,
              child: Padding(
                padding: const EdgeInsets.all(Insets.card),
                child: Row(
                  children: <Widget>[
                    Icon(
                      SolarIconsOutline.documentText,
                      size: 24,
                      color: colors.ink2,
                    ),
                    const SizedBox(width: Insets.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Weekly review',
                            style: TypeLadder.headline.copyWith(
                              color: colors.ink,
                            ),
                          ),
                          Text(
                            _open && review != null
                                ? range
                                : '$range · written when you open it',
                            style: TypeLadder.callout.copyWith(
                              color: colors.ink2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      _open
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 24,
                      color: colors.ink2,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.card,
                0,
                Insets.card,
                Insets.card,
              ),
              child: _Body(state: state),
            ),
        ],
      ),
    );
  }

  static String _guessRange(String today) {
    final bounds = coachWeekBounds(DateTime.tryParse(today) ?? DateTime.now());
    return dateRangeLabel(bounds.from, bounds.to);
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.state});

  final AsyncValue<CoachReview?> state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    if (state.isLoading) {
      return const _Skeleton();
    }
    final error = state.error;
    if (error != null) {
      if (error is CoachRefusal) {
        return _Refused(refusal: error);
      }
      return ErrorState(
        message: error is ReviewFailure
            ? error.message
            : 'The review could not be written. Try again.',
        onRetry: () =>
            unawaited(ref.read(coachReviewProvider.notifier).retry()),
      );
    }
    final review = state.value;
    if (review == null) {
      return const _Skeleton();
    }
    final text = review.review;
    if (text == null) {
      return Text(
        kNoReview,
        style: TypeLadder.body.copyWith(color: colors.ink2),
      );
    }
    final body = TypeLadder.headline.copyWith(
      color: colors.ink,
      fontWeight: FontWeight.w400,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(text, style: body),
        if (review.pattern case final String pattern) ...<Widget>[
          const SizedBox(height: Insets.md),
          Text(pattern, style: body),
        ],
        const SizedBox(height: Insets.lg),
        Divider(height: hairline, thickness: hairline, color: colors.line),
        const SizedBox(height: Insets.md),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: Insets.sm,
          runSpacing: Insets.xs,
          children: <Widget>[
            Text(
              writtenLine(review),
              style: TypeLadder.callout.copyWith(color: colors.ink2),
            ),
            Text(
              kKeptUntil,
              style: TypeLadder.callout.copyWith(color: colors.ink2),
            ),
          ],
        ),
      ],
    );
  }
}

class _Refused extends StatelessWidget {
  const _Refused({required this.refusal});

  final CoachRefusal refusal;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final reset = refusal.resetsAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          refusal.message,
          style: TypeLadder.body.copyWith(color: colors.ink),
        ),
        if (reset != null) ...<Widget>[
          const SizedBox(height: Insets.xs),
          Text(
            'Your window reopens ${shortDate(isoDay(reset.toLocal()))}.',
            style: TypeLadder.callout.copyWith(color: colors.ink2),
          ),
        ],
      ],
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Writing your review',
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        HSkeleton(height: 16),
        SizedBox(height: Insets.sm),
        HSkeleton(height: 16),
        SizedBox(height: Insets.sm),
        HSkeleton(height: 16, width: 220),
        SizedBox(height: Insets.md),
        HSkeleton(height: 16),
        SizedBox(height: Insets.sm),
        HSkeleton(height: 16, width: 160),
      ],
    ),
  );
}
