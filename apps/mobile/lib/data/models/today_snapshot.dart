/// `GET /api/today`, typed — the whole Today screen in one model.
///
/// One model, parsed from the committed contract snapshot, exercising every part
/// of the pipeline: nested objects, lists, nullable fields, and all four honesty
/// states. `test/data/today_snapshot_golden_test.dart` parses
/// `packages/contracts/snapshots/today.json` **directly from the repo** — not a
/// copy — so a reviewed server-side shape change fails the mobile suite in the
/// same commit that makes it. That is the point of the file living where it does.
///
/// ## Every honesty-bearing block is a [Reading], and none of them decide it
///
/// The blocks go through [readingFrom], once, so a metric card and a VO₂max card
/// cannot end up disagreeing about what "withheld" means. A block the server
/// omitted entirely becomes a `Withheld` with the honest "we don't know why"
/// sentence rather than being dropped — an absence the UI never hears about is
/// the silence this whole design is against.
///
/// The fields that are NOT readings are the ones that are not claims about a
/// measurement: [action] (an un-warmed premium surface, not a withheld number),
/// [illnessFlag] (present or absent, never withheld), the series, and the lists.
/// Dressing any of those in a refusal card would tell the owner something is
/// wrong when nothing is.
library;

import 'package:healthee/data/honesty/disclosure.dart';
import 'package:healthee/data/honesty/envelope.dart';
import 'package:healthee/data/honesty/reading.dart';
import 'package:healthee/data/models/activity_today.dart';
import 'package:healthee/data/models/as_of.dart';
import 'package:healthee/data/models/bio_age_block.dart';
import 'package:healthee/data/models/biological_age.dart';
import 'package:healthee/data/models/data_health.dart';
import 'package:healthee/data/models/finding.dart';
import 'package:healthee/data/models/illness_flag.dart';
import 'package:healthee/data/models/last_sleep.dart';
import 'package:healthee/data/models/metric_card.dart';
import 'package:healthee/data/models/recommendation.dart';
import 'package:healthee/data/models/recovery_score.dart';
import 'package:healthee/data/models/recovery_signals.dart';
import 'package:healthee/data/models/routine.dart';
import 'package:healthee/data/models/sleep_debt.dart';
import 'package:healthee/data/models/sleep_health.dart';
import 'package:healthee/data/models/sleep_history.dart';
import 'package:healthee/data/models/strength.dart';
import 'package:healthee/data/models/today_series.dart';
import 'package:healthee/data/models/trend_point.dart';
import 'package:healthee/data/models/vo2max.dart';
import 'package:meta/meta.dart';

/// The Today page's whole payload.
@immutable
class TodaySnapshot {
  /// Builds a snapshot. Prefer [TodaySnapshot.fromJson].
  const TodaySnapshot({
    required this.date,
    required this.asOf,
    required this.action,
    required this.recovery,
    required this.recoverySignals,
    required this.metrics,
    required this.vo2max,
    required this.biologicalAge,
    required this.dataHealth,
    required this.illnessFlag,
    required this.lastSleep,
    required this.overnightVitals,
    required this.sleepHealth,
    required this.sleepDebt,
    required this.sleepHistory7d,
    required this.cardioLoad,
    required this.mvpa,
    required this.sparklines,
    required this.hourlyHeartRate,
    required this.hourlyStress,
    required this.stepBuckets,
    required this.strength,
    required this.routine,
    required this.findings,
    required this.recommendations,
    required this.bioAgeBlock,
  });

  /// Parses `GET /api/today`.
  factory TodaySnapshot.fromJson(Map<String, Object?> json) {
    return TodaySnapshot(
      date: json['date']! as String,
      asOf: AsOf.maybe(_block(json['as_of'])),
      action: json['action'] as String?,
      recovery: readingFrom(
        _block(json['recovery_score']),
        RecoveryScore.maybe,
      ),
      recoverySignals: readingFrom(
        _block(json['recovery']),
        RecoverySignals.maybe,
      ),
      metrics: [
        for (final entry in (json['metrics'] as List? ?? const []))
          if (entry is Map<String, Object?>) MetricCard.fromJson(entry),
      ],
      vo2max: readingFrom(_block(json['vo2max']), Vo2max.maybe),
      biologicalAge: readingFrom(
        _block(json['biological_age']),
        BiologicalAge.maybe,
      ),
      bioAgeBlock: BioAgeBlock.fromJson(json['biological_age']),
      dataHealth: switch (json['data_health']) {
        final Map<String, Object?> health => DataHealth.fromJson(health),
        _ => null,
      },
      illnessFlag: IllnessFlag.maybe(_block(json['illness_flag'])),
      lastSleep: readingFrom(_block(json['last_sleep']), LastSleep.maybe),
      overnightVitals: OvernightVitals.maybe(_block(json['last_sleep_extras'])),
      sleepHealth: readingFrom(_block(json['sleep_health']), SleepHealth.maybe),
      sleepDebt: readingFrom(_block(json['sleep_debt']), SleepDebt.maybe),
      sleepHistory7d: SleepNightSummary.listFrom(json['sleep_history_7d']),
      cardioLoad: readingFrom(_block(json['cardio_load']), CardioLoad.maybe),
      mvpa: readingFrom(_block(json['mvpa']), Mvpa.maybe),
      sparklines: _sparklines(json['sparklines']),
      hourlyHeartRate: HourPoint.listFrom(json['today_hr_series']),
      hourlyStress: HourPoint.listFrom(json['today_stress_series']),
      stepBuckets: StepBucket.listFrom(json['today_step_buckets']),
      strength: Strength.maybe(_block(json['strength'])),
      routine: Routine.fromJson(_block(json['routine'])),
      findings: [
        for (final entry in (json['top_findings'] as List? ?? const []))
          if (entry is Map<String, Object?>) Finding.fromJson(entry),
      ],
      recommendations: [
        for (final entry in (json['recommendations'] as List? ?? const []))
          if (entry is Map<String, Object?> && entry['action'] is String)
            Recommendation.fromJson(entry),
      ],
    );
  }

  /// The owner-local calendar date this snapshot describes, `YYYY-MM-DD`.
  final String date;

  /// Which day this answers for, and whether that is the owner's today.
  ///
  /// Null from a server that predates the block (`docs/AS_OF_DAY.md`), and read
  /// in exactly one place — `ScreenData.snapshot` — which decides for every screen
  /// whether this payload may be drawn under the day being read. A second reader
  /// would be a second opinion about which day a payload is about.
  final AsOf? asOf;

  /// The AI daily-action one-liner, or null until the nightly job has warmed it.
  ///
  /// `docs/APP_DESIGN.md` §3.1: null means "show nothing, never a spinner". It is
  /// deliberately NOT a [Reading] — an un-warmed action is not a withheld number,
  /// it is a premium surface that has nothing to say yet.
  final String? action;

  /// Recovery 0–100 with its per-factor breakdown.
  final Reading<RecoveryScore> recovery;

  /// The per-signal ladder behind that score — brief §5.1's signature chart.
  final Reading<RecoverySignals> recoverySignals;

  /// The metric cards, in server order.
  final List<MetricCard> metrics;

  /// The fitness headline. The payload most likely to be [Withheld] in real use.
  final Reading<Vo2max> vo2max;

  /// The motivational estimate. Usually [Caveated] — it carries its own tilts.
  final Reading<BiologicalAge> biologicalAge;

  /// The same block, kept whole on a day [biologicalAge] is withheld: the
  /// current contributions, caveats, research notes and each absent term's own
  /// reason. It never decides whether there is a number; [biologicalAge] does.
  final BioAgeBlock bioAgeBlock;

  /// The VO2max card's own refusal, or null when it is not refused. It
  /// explains a missing biological age when the server sent no block.
  Disclosure? get vo2maxWithheld => switch (vo2max) {
    Withheld<Vo2max>(:final disclosure) => disclosure,
    _ => null,
  };

  /// Per-feed freshness, or null when the payload omitted it.
  final DataHealth? dataHealth;

  /// The illness flag, or null when nothing is flagged. Outranks everything.
  final IllnessFlag? illnessFlag;

  /// Last night as the server staged it.
  final Reading<LastSleep> lastSleep;

  /// What the strap measured while the owner slept, or null when it measured
  /// nothing. Not a [Reading]: the server sends no honesty block for it, and
  /// inventing one would put words in its mouth.
  final OvernightVitals? overnightVitals;

  /// The four-dimension judgement. Never summed into one number in the UI.
  final Reading<SleepHealth> sleepHealth;

  /// The fortnight's accumulated shortfall.
  final Reading<SleepDebt> sleepDebt;

  /// Seven nights of stage totals, oldest first.
  final List<SleepNightSummary> sleepHistory7d;

  /// Today's training load against the owner's own 30-day baseline.
  final Reading<CardioLoad> cardioLoad;

  /// Moderate-to-vigorous minutes, today and this week.
  final Reading<Mvpa> mvpa;

  /// Fourteen days per metric, keyed by the metric's canonical id.
  final Map<String, List<TrendPoint>> sparklines;

  /// Today's heart rate, hourly.
  final List<HourPoint> hourlyHeartRate;

  /// Today's stress, hourly.
  final List<HourPoint> hourlyStress;

  /// Today's movement in 15-minute buckets — the Steps tile's bar strip.
  final List<StepBucket> stepBuckets;

  /// The week's strength training against its band, or null when the server
  /// sent no block. **Legacy surfaced this in one file and Today in none.**
  ///
  /// Not a [Reading]: there is no gate on it, and a week at zero minutes is a
  /// measurement rather than a refusal.
  final Strength? strength;

  /// What the owner logged or the strap recorded today. **Legacy surfaced this
  /// nowhere at all.** Never null; `Routine.isEmpty` decides whether it draws.
  final Routine routine;

  /// Correlations found in this owner's own data. Single-subject, observational.
  final List<Finding> findings;

  /// Today's cited actions, highest rank first.
  final List<Recommendation> recommendations;

  /// A metric card by its canonical id, or null when today has no such card.
  MetricCard? metric(String id) {
    for (final card in metrics) {
      if (card.metric == id) {
        return card;
      }
    }
    return null;
  }

  /// One sparkline by metric id. Empty when the payload carried none.
  List<TrendPoint> sparkline(String id) => sparklines[id] ?? const [];

  /// A missing block parses as an empty object, which [readingFrom] resolves to a
  /// `Withheld` carrying [unexplainedAbsenceMessage]. Returning `const {}` rather
  /// than throwing is the choice that keeps a partial payload renderable: one
  /// absent block should cost the owner that block, not the whole page.
  static Map<String, Object?> _block(Object? raw) =>
      raw is Map<String, Object?> ? raw : const <String, Object?>{};

  static Map<String, List<TrendPoint>> _sparklines(Object? raw) {
    if (raw is! Map<String, Object?>) {
      return const {};
    }
    return <String, List<TrendPoint>>{
      for (final entry in raw.entries)
        if (TrendPoint.listFrom(entry.value) case final series
            when series.isNotEmpty)
          entry.key: series,
    };
  }
}
