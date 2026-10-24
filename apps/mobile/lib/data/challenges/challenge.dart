import 'package:healthee/data/challenges/challenge_outcome.dart';
import 'package:healthee/data/challenges/challenge_progress.dart';
import 'package:healthee/data/honesty/citations.dart';

class Challenge {
  const Challenge({
    required this.id,
    required this.title,
    required this.why,
    required this.status,
    required this.metric,
    required this.target,
    required this.comparator,
    required this.cadence,
    required this.windowDays,
    required this.difficulty,
    required this.kind,
    required this.citations,
    this.howTo,
    this.expectedOutcome,
    this.progress,
    this.programId,
    this.outcome,
    this.adoptedAt,
    this.daysRequired,
    this.actionText,
    this.slot,
    this.floor,
    this.countsWhen,
  });

  factory Challenge.fromJson(Map<String, Object?> json) => Challenge(
    id: (json['id']! as num).toInt(),
    title: json['title']! as String,
    why: json['why']! as String,
    status: json['status']! as String,
    metric: json['metric']! as String,
    target: (json['target_value']! as num).toDouble(),
    comparator: json['comparator']! as String,
    cadence: json['cadence']! as String,
    windowDays: (json['window_days']! as num).toInt(),
    difficulty: json['difficulty']! as String,
    kind: json['kind']! as String,
    citations: [
      for (final id in json['research_note_ids'] as List<Object?>? ?? [])
        id! as String,
    ],
    howTo: json['how_to'] as String?,
    expectedOutcome: json['expected_outcome'] as String?,
    programId: (json['program_id'] as num?)?.toInt(),
    daysRequired: (json['days_required'] as num?)?.toInt(),
    actionText: json['action_text'] as String?,
    slot: json['slot_text'] as String?,
    floor: json['floor_text'] as String?,
    countsWhen: json['counts_when'] as String?,
    adoptedAt: DateTime.tryParse(
      json['adopted_at'] as String? ?? '',
    )?.toLocal(),
    outcome: json['outcome'] == null
        ? null
        : ChallengeOutcome.fromJson(json['outcome']! as Map<String, Object?>),
    progress: json['progress'] == null
        ? null
        : ChallengeProgress.fromJson(json['progress']! as Map<String, Object?>),
  );
  final int id;
  final String title;
  final String why;
  final String status;
  final String metric;
  final double target;
  final String comparator;
  final String cadence;
  final int windowDays;
  final String difficulty;
  final String kind;
  final List<String> citations;
  final String? howTo;
  final String? expectedOutcome;
  final ChallengeProgress? progress;
  final int? programId;
  final ChallengeOutcome? outcome;

  /// When the owner started this rung, if they have.
  final DateTime? adoptedAt;

  /// Days out of seven, set only on a coach job.
  final int? daysRequired;

  /// The coach's one-line action, set only on a coach job.
  final String? actionText;

  /// When the coach job is to be done.
  final String? slot;

  /// The coach job's bad-day version.
  final String? floor;

  /// The rule the strap checks for a coach job.
  final String? countsWhen;

  /// Everything backing this challenge's server-written prose: the inline
  /// `[note_id]` markers in **both** [title] and [why], merged with the
  /// [citations] the payload sent beside them.
  ///
  /// **[why] used to be left out of this, and out of the card's rendering.**
  /// The card drew it with a plain `Text`, so a challenge generated on the
  /// device printed `…the population curve [sleep_duration_mortality].
  /// Maintaining adequate rest aligns with consensus recommendations for
  /// adults [sleep_need_debt].` — raw markers on the face, and the notes they
  /// named reaching no ⓘ. `actions_v02_test.dart` has asserted for the
  /// suggestion card that *"a citation marker is rendered as a source, never
  /// printed"*; this widget was simply outside that gate.
  ///
  /// On the model rather than in a card because three surfaces draw a challenge
  /// — the v02 card, the pre-v02 card and Today's focus list — and one reader
  /// meeting the same commitment on two of them must not be shown two different
  /// sets of sources.
  Grounding get grounding =>
      groundingOf('$title\n\n$why', alsoCites: citations);
}
