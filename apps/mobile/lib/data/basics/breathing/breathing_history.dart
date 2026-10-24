/// What the plan needs from the 60-day local store: recent nights, the stress
/// series and the spans awake inside sleep.
///
/// There was no multi-night wake query, so this is it. Read once per plan
/// build; the plan builder itself is pure and takes these as arguments.
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:meta/meta.dart';

/// The strap's stress stream name in `strap_samples`.
const String kStressMetric = 'stress';

/// The strap's stage code for awake.
const int _awakeStage = 7;

/// How many nights the plan looks back over.
const int kPlanNights = 14;

/// How many days of stress the on-demand item looks back over.
const int kStressDays = 7;

/// One staged night: when the stages begin and when they end, as the strap
/// recorded them. Naps and records without stages are not nights here.
@immutable
class SleepNight {
  /// A night from [onset] to [wake].
  const SleepNight({required this.onset, required this.wake});

  /// First stage start.
  final DateTime onset;

  /// Last stage end.
  final DateTime wake;
}

/// One stress reading.
@immutable
class StressSample {
  /// A reading of [value] at [at].
  const StressSample(this.at, this.value);

  /// When the strap recorded it.
  final DateTime at;

  /// The strap's stress value.
  final double value;
}

/// A span the strap staged as awake.
@immutable
class AwakeSpan {
  /// A span from [start] to [end].
  const AwakeSpan(this.start, this.end);

  /// When it began.
  final DateTime start;

  /// When it ended.
  final DateTime end;

  /// Whether it overlaps `[from, to)`.
  bool overlaps(DateTime from, DateTime to) =>
      start.isBefore(to) && end.isAfter(from);
}

/// Everything read from the store for one plan.
@immutable
class BreathingHistory {
  /// History, newest night first.
  const BreathingHistory({
    this.nights = const [],
    this.stress = const [],
    this.awake = const [],
  });

  /// Up to [kPlanNights] staged nights, newest first.
  final List<SleepNight> nights;

  /// Stress readings from the last [kStressDays] days.
  final List<StressSample> stress;

  /// Awake spans inside those nights.
  final List<AwakeSpan> awake;
}

/// Reads the history as of [now].
///
/// Throws if the database fails; an empty store is an empty history.
Future<BreathingHistory> readBreathingHistory(
  LocalStore store,
  DateTime now,
) async {
  final since = now.subtract(const Duration(days: kPlanNights + 1));
  final sessions =
      await (store.select(store.sleepSessions)
            ..where(
              (row) =>
                  row.isNap.equals(false) &
                  row.startMs.isBiggerOrEqualValue(
                    since.millisecondsSinceEpoch,
                  ),
            )
            ..orderBy([(row) => OrderingTerm.desc(row.startMs)])
            ..limit(kPlanNights))
          .get();
  final nights = <SleepNight>[];
  final awake = <AwakeSpan>[];
  for (final session in sessions) {
    final stages = _stages(session.stagesJson);
    if (stages.isEmpty) continue;
    nights.add(SleepNight(onset: stages.first.$1, wake: stages.last.$2));
    awake.addAll([
      for (final s in stages)
        if (s.$3 == _awakeStage) AwakeSpan(s.$1, s.$2),
    ]);
  }
  final stressSince = now.subtract(const Duration(days: kStressDays));
  final rows =
      await (store.select(store.strapSamples)
            ..where(
              (row) =>
                  row.metric.equals(kStressMetric) &
                  row.tsMs.isBiggerOrEqualValue(
                    stressSince.millisecondsSinceEpoch,
                  ),
            )
            ..orderBy([(row) => OrderingTerm.asc(row.tsMs)]))
          .get();
  return BreathingHistory(
    nights: nights,
    awake: awake,
    stress: [
      for (final row in rows)
        StressSample(DateTime.fromMillisecondsSinceEpoch(row.tsMs), row.value),
    ],
  );
}

/// `[[startMs, endMs, type], ...]` as spans; a malformed entry is skipped, not
/// guessed at.
List<(DateTime, DateTime, int)> _stages(String json) {
  final decoded = jsonDecode(json);
  if (decoded is! List) return const [];
  return [
    for (final entry in decoded)
      if (entry is List && entry.length >= 3 && entry.every((v) => v is int))
        (
          DateTime.fromMillisecondsSinceEpoch(entry[0] as int),
          DateTime.fromMillisecondsSinceEpoch(entry[1] as int),
          entry[2] as int,
        ),
  ];
}
