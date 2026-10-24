/// Logging and undoing glasses, optimistically.
///
/// A tap changes the picture at once and the server is asked in the
/// background. A failure puts the picture back and returns a sentence to show.
/// A confirmed tap stays laid over the feed until a feed read taken after it
/// arrives, so a cached copy cannot flash the old count back.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthee/core/logging.dart';
import 'package:healthee/data/basics/water/water_day.dart';
import 'package:healthee/data/basics/water/water_settings.dart';
import 'package:healthee/data/journal/journal_repository.dart';
import 'package:healthee/data/journal/log_draft.dart';
import 'package:healthee/data/journal/log_kind.dart';

/// The clock the day is cut by. Tests pin it.
final waterClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// The taps in flight or not yet in the feed.
class WaterController extends Notifier<List<WaterOp>> {
  int _serial = 0;

  @override
  List<WaterOp> build() => const [];

  /// Logs one glass. Returns a sentence on failure, null on success.
  Future<String?> addGlass() async {
    final now = ref.read(waterClockProvider)();
    final op = WaterOp(
      serial: ++_serial,
      added: WaterEntry(at: now, ml: kGlassMl, pending: true),
    );
    state = [...state, op];
    try {
      final repository = await ref.read(journalRepositoryProvider.future);
      await repository.save(
        LogDraft(kind: LogKind.water, at: now, amount: kGlassMl.toDouble()),
      );
      _settle(op);
      return null;
    } on Object catch (error, stack) {
      AppLog.failure('water', 'logging a glass', error, stack);
      _drop(op);
      return 'Could not log that glass. Nothing was saved.';
    }
  }

  /// Removes the most recent entry of [day]. Returns a sentence on failure.
  Future<String?> undoLatest(WaterDay day) async {
    final latest = day.latest;
    if (latest == null || latest.pending) return null;
    final id = latest.id;
    if (id == null) return 'This entry has no id, so it cannot be undone here.';
    final op = WaterOp(serial: ++_serial, removedId: id);
    state = [...state, op];
    try {
      final repository = await ref.read(journalRepositoryProvider.future);
      await repository.delete(id);
      _settle(op);
      return null;
    } on DioException catch (error, stack) {
      if (error.response?.statusCode == 404) {
        // Already gone elsewhere: the refresh shows the truth.
        _settle(op);
        return null;
      }
      AppLog.failure('water', 'undoing a glass', error, stack);
      _drop(op);
      return 'Could not undo that glass. It is still logged.';
    } on Object catch (error, stack) {
      AppLog.failure('water', 'undoing a glass', error, stack);
      _drop(op);
      return 'Could not undo that glass. It is still logged.';
    }
  }

  void _settle(WaterOp op) {
    state = [
      for (final o in state)
        if (o.serial == op.serial) o.confirmed(DateTime.now()) else o,
    ];
    ref.invalidate(journalFeedProvider);
  }

  void _drop(WaterOp op) => state = [
    for (final o in state)
      if (o.serial != op.serial) o,
  ];
}

/// The controller.
final waterControllerProvider =
    NotifierProvider<WaterController, List<WaterOp>>(WaterController.new);
