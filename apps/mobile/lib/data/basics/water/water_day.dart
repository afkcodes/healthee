/// Today's water, worked out from the journal feed and any taps in flight.
///
/// One definition: the total is the sum of today's water entries in ml, and a
/// glass is [kGlassMl] of it, rounded down. A time is shown under a glass only
/// when each entry is exactly one glass; otherwise no time is invented.
library;

import 'package:healthee/data/api/server_snapshot.dart';
import 'package:healthee/data/basics/water/water_format.dart';
import 'package:healthee/data/basics/water/water_settings.dart';
import 'package:healthee/data/journal/journal_feed.dart';
import 'package:meta/meta.dart';

/// One logged drink.
@immutable
class WaterEntry {
  /// An entry; [id] is null for one not yet confirmed or from an old server.
  const WaterEntry({
    required this.at,
    required this.ml,
    this.id,
    this.pending = false,
  });

  /// When it was logged.
  final DateTime at;

  /// How much, in ml.
  final int ml;

  /// The server's id.
  final String? id;

  /// Added on this phone and not yet seen in the server's feed.
  final bool pending;
}

/// A tap that has changed the picture before the server's feed shows it.
@immutable
class WaterOp {
  /// An add ([added]) or a removal ([removedId]).
  const WaterOp({
    required this.serial,
    this.added,
    this.removedId,
    this.confirmedAt,
  });

  /// Orders and identifies the op.
  final int serial;

  /// The entry added on this phone.
  final WaterEntry? added;

  /// The server entry hidden because the owner undid it.
  final String? removedId;

  /// When the server accepted it; null while in flight.
  final DateTime? confirmedAt;

  /// The same op, accepted at [at].
  WaterOp confirmed(DateTime at) => WaterOp(
    serial: serial,
    added: added,
    removedId: removedId,
    confirmedAt: at,
  );

  /// Whether a feed read after the server accepted it already shows it.
  bool absorbedBy(ServerSnapshot<JournalFeed> snapshot) =>
      confirmedAt != null &&
      !snapshot.stale &&
      snapshot.fetchedAt.isAfter(confirmedAt!);
}

/// Today's total and glasses.
@immutable
class WaterDay {
  /// A day of [entries], oldest first.
  const WaterDay(this.entries);

  /// Today's entries from [snapshot], with [ops] laid over them.
  factory WaterDay.from(
    ServerSnapshot<JournalFeed> snapshot,
    List<WaterOp> ops,
    DateTime now,
  ) {
    final live = [
      for (final op in ops)
        if (!op.absorbedBy(snapshot)) op,
    ];
    final hidden = {
      for (final op in live)
        if (op.removedId != null) op.removedId,
    };
    final out = <WaterEntry>[
      for (final entry in snapshot.data.entries)
        if (entry.type == 'water' &&
            entry.amount != null &&
            entry.amount! > 0 &&
            !hidden.contains(entry.id) &&
            _sameDay(entry.at.toLocal(), now))
          WaterEntry(at: entry.at, ml: entry.amount!.round(), id: entry.id),
      for (final op in live)
        if (op.added != null && _sameDay(op.added!.at.toLocal(), now))
          op.added!,
    ]..sort((a, b) => a.at.compareTo(b.at));
    return WaterDay(out);
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Today's entries, oldest first.
  final List<WaterEntry> entries;

  /// The sum in ml.
  int get totalMl => entries.fold(0, (sum, e) => sum + e.ml);

  /// Whole glasses drunk.
  int get filled => totalMl ~/ kGlassMl;

  /// The most recent entry, or null.
  WaterEntry? get latest => entries.isEmpty ? null : entries.last;

  /// Whether every entry is exactly one glass, so a time per glass is true.
  bool get oneToOne =>
      entries.length == filled && entries.every((e) => e.ml == kGlassMl);

  /// The time under filled glass [index] (from 0), or null when none is true.
  String? timeLabel(int index) =>
      oneToOne && index < entries.length ? glassTime(entries[index].at) : null;
}
