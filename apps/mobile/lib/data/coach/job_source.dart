/// Where the week's job comes from before and after the review is opened.
library;

import 'package:healthee/data/challenges/challenge.dart';
import 'package:healthee/data/challenges/challenge_feed.dart';
import 'package:healthee/data/coach/review_models.dart';

/// The job to show.
///
/// The opened review's job wins. Until then, a coach job already sitting in the
/// challenge feed (a challenge row whose `days_required` is set), active first
/// and suggested second. Neither: null, and the screen says so.
ReviewJob? resolveJob(CoachReview? review, ChallengeFeed? feed) {
  final held = review?.job;
  if (held != null) {
    return held;
  }
  if (feed == null) {
    return null;
  }
  for (final challenge in <Challenge>[...feed.active, ...feed.suggested]) {
    final job = _fromChallenge(challenge);
    if (job != null) {
      return job;
    }
  }
  return null;
}

/// Whether the job's challenge is running.
bool isAdopted(ReviewJob job, ChallengeFeed? feed) =>
    feed != null && feed.active.any((c) => c.id == job.challengeId);

ReviewJob? _fromChallenge(Challenge challenge) {
  final days = challenge.daysRequired;
  if (days == null) {
    return null;
  }
  return ReviewJob(
    action: challenge.actionText ?? challenge.title,
    metric: challenge.metric,
    target: challenge.target,
    unit: challenge.progress?.unit ?? '',
    daysRequired: days,
    challengeId: challenge.id,
    slot: challenge.slot,
    floor: challenge.floor,
    countsWhen: challenge.countsWhen,
  );
}
