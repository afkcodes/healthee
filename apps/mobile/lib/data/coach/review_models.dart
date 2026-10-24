/// The weekly review, typed: `POST /api/coach/review`.
///
/// Parsed defensively. A missing or blank text is null and the screen says so
/// in words; a job without the challenge id the adopt endpoint takes is no job.
library;

String? _text(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;

/// The one job the coach set for the week.
class ReviewJob {
  /// Builds a job.
  const ReviewJob({
    required this.action,
    required this.metric,
    required this.target,
    required this.unit,
    required this.daysRequired,
    required this.challengeId,
    this.slot,
    this.floor,
    this.countsWhen,
  });

  /// Reads a job; null when the target, days or challenge id are missing.
  static ReviewJob? tryParse(Object? json) {
    if (json is! Map) {
      return null;
    }
    final target = json['target'];
    final days = json['days_required'];
    final id = json['challenge_id'];
    if (target is! num || days is! num || id is! num) {
      return null;
    }
    return ReviewJob(
      action: _text(json['action']) ?? '',
      metric: _text(json['metric']) ?? '',
      target: target.toDouble(),
      unit: _text(json['unit']) ?? '',
      daysRequired: days.toInt(),
      challengeId: id.toInt(),
      slot: _text(json['slot']),
      floor: _text(json['floor']),
      countsWhen: _text(json['counts_when']),
    );
  }

  /// One line, human: what to do.
  final String action;

  /// The calibration-table metric the strap checks.
  final String metric;

  /// The number to reach on a counted day.
  final double target;

  /// Its unit.
  final String unit;

  /// Days out of seven.
  final int daysRequired;

  /// The challenge row "I'm in" adopts.
  final int challengeId;

  /// When, verbatim from the coach.
  final String? slot;

  /// The bad-day version, verbatim.
  final String? floor;

  /// The rule the strap checks, verbatim.
  final String? countsWhen;

  /// The same job with another slot.
  ReviewJob withSlot(String slot) => ReviewJob(
    action: action,
    metric: metric,
    target: target,
    unit: unit,
    daysRequired: daysRequired,
    challengeId: challengeId,
    slot: slot,
    floor: floor,
    countsWhen: countsWhen,
  );
}

/// The whole response.
class CoachReview {
  /// Builds a review.
  const CoachReview({
    required this.weekFrom,
    required this.weekTo,
    required this.cached,
    this.week = '',
    this.review,
    this.pattern,
    this.job,
    this.todayLine,
    this.rationale,
    this.evidenceGrade,
    this.researchNoteIds = const <String>[],
    this.generatedAt,
  });

  /// Reads the response.
  factory CoachReview.fromJson(Map<String, Object?> json) => CoachReview(
    week: _text(json['week']) ?? '',
    weekFrom: _text(json['week_from']) ?? '',
    weekTo: _text(json['week_to']) ?? '',
    review: _text(json['review']),
    pattern: _text(json['pattern']),
    job: ReviewJob.tryParse(json['job']),
    todayLine: _text(json['today_line']),
    rationale: _text(json['rationale']),
    evidenceGrade: (json['evidence_grade'] as num?)?.toInt(),
    researchNoteIds: <String>[
      if (json['research_note_ids'] case final List<Object?> ids)
        for (final id in ids)
          if (id is String) id,
    ],
    generatedAt: DateTime.tryParse(
      json['generated_at'] as String? ?? '',
    )?.toLocal(),
    cached: json['cached'] == true,
  );

  /// `2026-W43`.
  final String week;

  /// Monday, ISO.
  final String weekFrom;

  /// Sunday, ISO.
  final String weekTo;

  /// The written review; null when there were too few readings.
  final String? review;

  /// The sentence about yeses and misses.
  final String? pattern;

  /// The week's job.
  final ReviewJob? job;

  /// The day's check-in line.
  final String? todayLine;

  /// The cited reasoning.
  final String? rationale;

  /// The evidence grade the server stored.
  final int? evidenceGrade;

  /// Notes the rationale cites.
  final List<String> researchNoteIds;

  /// When it was written.
  final DateTime? generatedAt;

  /// Whether this was read from storage rather than written for this call.
  final bool cached;

  /// The same review with the job's slot replaced.
  CoachReview withSlot(String slot) => CoachReview(
    week: week,
    weekFrom: weekFrom,
    weekTo: weekTo,
    review: review,
    pattern: pattern,
    job: job?.withSlot(slot),
    todayLine: todayLine,
    rationale: rationale,
    evidenceGrade: evidenceGrade,
    researchNoteIds: researchNoteIds,
    generatedAt: generatedAt,
    cached: cached,
  );
}
