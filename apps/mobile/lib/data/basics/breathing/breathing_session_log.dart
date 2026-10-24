/// Writes a finished or ended-early breathing session to the journal as
/// meditation, through the same repository the log sheet uses.
library;

import 'package:healthee/data/journal/journal_repository.dart';
import 'package:healthee/data/journal/log_draft.dart';
import 'package:healthee/data/journal/log_kind.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'breathing_session_log.g.dart';

/// The whole minutes to log: the full plan when finished, otherwise the whole
/// minutes actually elapsed (capped at the plan). Zero means log nothing.
int minutesToLog({
  required int plannedMinutes,
  required bool finished,
  required Duration elapsed,
}) {
  if (finished) return plannedMinutes;
  return elapsed.inMinutes.clamp(0, plannedMinutes);
}

/// Logs breathing sessions.
class BreathingSessionLog {
  /// Logs through [repository]; [now] is injectable for tests.
  BreathingSessionLog(this.repository, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  /// The shared journal repository.
  final JournalRepository repository;
  final DateTime Function() _now;

  /// Logs [minutes] of meditation ending now. Does nothing for 0 or less and
  /// returns whether an entry was written. A server refusal throws.
  Future<bool> logSession(int minutes) async {
    if (minutes <= 0) return false;
    await repository.save(
      LogDraft(
        kind: LogKind.meditation,
        at: _now(),
        amount: minutes.toDouble(),
      ),
    );
    return true;
  }

  /// Applies the finish and early-end rules, then logs.
  Future<bool> logOutcome({
    required int plannedMinutes,
    required bool finished,
    required Duration elapsed,
  }) => logSession(
    minutesToLog(
      plannedMinutes: plannedMinutes,
      finished: finished,
      elapsed: elapsed,
    ),
  );
}

/// The session log bound to the current account's journal.
@riverpod
Future<BreathingSessionLog> breathingSessionLog(Ref ref) async =>
    BreathingSessionLog(await ref.watch(journalRepositoryProvider.future));
