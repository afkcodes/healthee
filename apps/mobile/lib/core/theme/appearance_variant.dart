import 'dart:async';
import 'dart:convert';

import 'package:healthee/core/logging.dart';
import 'package:healthee/core/theme/appearance_preferences.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'appearance_variant.g.dart';

enum BackgroundVariant { espresso, dark, amoled }

class AppearanceVariant {
  factory AppearanceVariant.decode(String? raw) {
    if (raw == null) return const AppearanceVariant();
    final data = jsonDecode(raw) as Map<String, Object?>;
    final accent = data['accent']! as int;
    if (accent < 0 || accent >= accentNames.length) {
      throw const FormatException('Invalid accent');
    }
    return AppearanceVariant(
      accent: accent,
      background: BackgroundVariant.values.byName(
        data['background']! as String,
      ),
    );
  }
  const AppearanceVariant({
    this.accent = 0,
    this.background = BackgroundVariant.espresso,
  });
  final int accent;
  final BackgroundVariant background;
  static const accentNames = [
    'Ink',
    'Clay',
    'Amber',
    'Teal',
    'Indigo',
    'Berry',
    'Coral',
  ];
  String encode() =>
      jsonEncode({'accent': accent, 'background': background.name});
}

@Riverpod(keepAlive: true)
class AppearanceController extends _$AppearanceController {
  int _revision = 0;
  Future<void> _pending = Future<void>.value();
  @override
  AppearanceVariant build() {
    final storage = ref.watch(appearancePreferencesProvider);
    unawaited(_restore(storage, _revision));
    return const AppearanceVariant();
  }

  Future<void> _restore(AppearancePreferences storage, int revision) async {
    try {
      final saved = AppearanceVariant.decode(
        await storage.read('appearance_variant'),
      );
      if (ref.mounted && revision == _revision) state = saved;
    } on Exception catch (error, stack) {
      _failed(error, stack);
    }
  }

  void set(AppearanceVariant value) {
    ++_revision;
    state = value;
    final storage = ref.read(appearancePreferencesProvider);
    _pending = _pending
        .then((_) => storage.write('appearance_variant', value.encode()))
        .then<void>((_) {
          if (ref.mounted) {
            ref.read(appearanceErrorProvider.notifier).report(null);
          }
        })
        .onError<Exception>(_failed);
  }

  void _failed(Exception error, StackTrace stack) {
    AppLog.failure('appearance', 'persisting appearance', error, stack);
    if (ref.mounted) {
      ref
          .read(appearanceErrorProvider.notifier)
          .report('Appearance could not be saved. Choose it again to retry.');
    }
  }
}
