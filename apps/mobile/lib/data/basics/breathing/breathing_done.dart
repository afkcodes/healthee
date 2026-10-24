/// Which plan items the owner did today, kept on the phone.
///
/// This is what the owner did in the app: a session from that item that
/// finished, or that ended with at least one whole minute. It is not a verdict
/// from the strap, and nothing here reads one. Only today is kept, so the row
/// never grows and yesterday cannot count toward today.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthee/data/background/background_store.dart';
import 'package:healthee/data/basics/breathing/breathing_plan.dart';
import 'package:healthee/data/store/store_provider.dart';
import 'package:meta/meta.dart';

/// The key in the on-device key-value table.
const String kBreathingDoneKey = 'breathing_done';

/// `YYYY-MM-DD` for [day], local.
String breathingDayKey(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// The items done on one day.
@immutable
class BreathingDone {
  /// Items [kinds] done on [day].
  const BreathingDone({required this.day, this.kinds = const {}});

  /// Reads what [encode] wrote. Null is nothing done. A value that is not
  /// valid throws [FormatException] rather than reading as nothing done.
  factory BreathingDone.decode(String? raw) {
    if (raw == null) return const BreathingDone(day: '');
    final data = jsonDecode(raw);
    if (data is! Map<String, Object?> || data['day'] is! String) {
      throw const FormatException('Invalid breathing done record');
    }
    final kinds = <BreathingItemKind>{};
    for (final name in (data['items'] as List<Object?>? ?? const [])) {
      kinds.add(
        BreathingItemKind.values.firstWhere(
          (kind) => kind.name == name,
          orElse: () => throw FormatException('Unknown breathing item: $name'),
        ),
      );
    }
    return BreathingDone(day: data['day']! as String, kinds: kinds);
  }

  /// The local day, `YYYY-MM-DD`; empty when nothing was ever saved.
  final String day;

  /// The items done on [day].
  final Set<BreathingItemKind> kinds;

  /// The items done on [today]: none when this record is from another day.
  Set<BreathingItemKind> forDay(String today) => day == today ? kinds : {};

  /// The JSON stored on the phone.
  String encode() => jsonEncode({
    'day': day,
    'items': [for (final kind in kinds) kind.name],
  });
}

/// The clock the done record reads; a test pins it.
final Provider<DateTime Function()> breathingClockProvider =
    Provider<DateTime Function()>((ref) => DateTime.now);

/// The items done today.
final AsyncNotifierProvider<BreathingDoneController, Set<BreathingItemKind>>
breathingDoneProvider =
    AsyncNotifierProvider<BreathingDoneController, Set<BreathingItemKind>>(
      BreathingDoneController.new,
    );

/// Reads and writes today's done items.
class BreathingDoneController extends AsyncNotifier<Set<BreathingItemKind>> {
  BackgroundStore get _store => BackgroundStore(ref.read(localStoreProvider));

  String get _today => breathingDayKey(ref.read(breathingClockProvider)());

  @override
  Future<Set<BreathingItemKind>> build() async =>
      BreathingDone.decode(await _store.read(kBreathingDoneKey)).forDay(_today);

  /// Records that [kind] was done today.
  Future<void> mark(BreathingItemKind kind) async {
    final done = {...await future, kind};
    await _store.write(
      kBreathingDoneKey,
      BreathingDone(day: _today, kinds: done).encode(),
    );
    state = AsyncData(done);
  }
}
