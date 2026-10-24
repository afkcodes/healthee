/// Whether the "What moves it" lever list is open, remembered across launches.
///
/// Persisted because the owner asked for it. That is the opposite of
/// `lib/features/sleep/v02/tail_panels.dart`, whose analysis fold deliberately
/// does not persist (a remembered fold would hide new analysis the next
/// morning). The shape is `ThemeController`'s: a string-only store, a revision
/// so a tap made before the restore finished wins, and a failed write logged
/// and reported rather than swallowed.
library;

import 'dart:async';

import 'package:healthee/core/logging.dart';
import 'package:healthee/core/theme/appearance_preferences.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'what_moves_it_preference.g.dart';

/// The storage key.
const String kWhatMovesItKey = 'what_moves_it_open';

/// Open or shut. Closed until the stored choice has been read.
@Riverpod(keepAlive: true)
class WhatMovesItOpen extends _$WhatMovesItOpen {
  int _revision = 0;
  Future<void> _pending = Future<void>.value();

  @override
  bool build() {
    final storage = ref.watch(appearancePreferencesProvider);
    final revision = _revision;
    unawaited(_restore(storage, revision));
    return false;
  }

  Future<void> _restore(AppearancePreferences storage, int revision) async {
    try {
      final saved = await storage.read(kWhatMovesItKey);
      if (ref.mounted && revision == _revision) {
        state = saved == 'true';
      }
    } on Exception catch (error, stack) {
      _failed(error, stack);
    }
  }

  /// Opens or shuts the list, and remembers it.
  void set({required bool open}) {
    ++_revision;
    state = open;
    final storage = ref.read(appearancePreferencesProvider);
    _pending = _pending
        .then((_) => storage.write(kWhatMovesItKey, open.toString()))
        .then<void>((_) {
          if (ref.mounted) {
            ref.read(appearanceErrorProvider.notifier).report(null);
          }
        })
        .onError<Exception>(_failed);
  }

  void _failed(Exception error, StackTrace stack) {
    AppLog.failure('appearance', 'persisting what moves it', error, stack);
    if (ref.mounted) {
      ref
          .read(appearanceErrorProvider.notifier)
          .report('That choice could not be saved. Tap again to retry.');
    }
  }
}
