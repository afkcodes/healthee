/// The owner's breathing settings as a provider, saved on every change.
library;

import 'package:healthee/data/background/background_store.dart';
import 'package:healthee/data/basics/breathing/breathing_pattern.dart';
import 'package:healthee/data/basics/breathing/breathing_plan.dart';
import 'package:healthee/data/basics/breathing/breathing_settings.dart';
import 'package:healthee/data/store/store_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'breathing_settings_provider.g.dart';

/// The key in the on-device key-value table.
const String kBreathingSettingsKey = 'breathing_settings';

/// Reads and writes [BreathingSettings].
@Riverpod(keepAlive: true)
class BreathingSettingsController extends _$BreathingSettingsController {
  BackgroundStore get _store => BackgroundStore(ref.read(localStoreProvider));

  @override
  Future<BreathingSettings> build() async =>
      BreathingSettings.decode(await _store.read(kBreathingSettingsKey));

  Future<void> _save(BreathingSettings value) async {
    await _store.write(kBreathingSettingsKey, value.encode());
    state = AsyncData(value);
  }

  Future<BreathingSettings> _current() => future;

  /// Switches one item on or off.
  Future<void> setEnabled(BreathingItemKind kind, {required bool on}) async {
    final now = await _current();
    final off = {...now.off};
    on ? off.remove(kind) : off.add(kind);
    await _save(now.copyWith(off: off));
  }

  /// Turns every item on and records when the owner accepted the plan.
  Future<void> acceptAll() async =>
      _save((await _current()).copyWith(off: {}, acceptedAt: DateTime.now()));

  /// Sets the evening free-from time, local clock minutes.
  Future<void> setNightFreeFrom(int minute) async {
    _checkMinute(minute);
    await _save((await _current()).copyWith(nightFreeFromMinute: minute));
  }

  /// Sets the morning time used when there are too few nights.
  Future<void> setMorningDefault(int minute) async {
    _checkMinute(minute);
    await _save((await _current()).copyWith(morningDefaultMinute: minute));
  }

  /// Saves the owner's own counts. Throws [FormatException] if invalid.
  Future<void> setCustom({
    required int inSeconds,
    required int hold1Seconds,
    required int outSeconds,
    required int hold2Seconds,
  }) async => _save(
    (await _current()).copyWith(
      custom: BreathPattern.custom(
        inSeconds: inSeconds,
        hold1Seconds: hold1Seconds,
        outSeconds: outSeconds,
        hold2Seconds: hold2Seconds,
      ),
    ),
  );

  /// Chooses the pattern [patternId] for [kind]; null restores its default.
  Future<void> setPattern(BreathingItemKind kind, String? patternId) async {
    final now = await _current();
    if (patternId != null &&
        presetById(patternId) == null &&
        !(patternId == BreathPattern.customId && now.custom != null)) {
      throw FormatException('Unknown pattern: $patternId');
    }
    final overrides = {...now.patternOverrides};
    patternId == null ? overrides.remove(kind) : overrides[kind] = patternId;
    await _save(now.copyWith(patternOverrides: overrides));
  }

  static void _checkMinute(int minute) {
    if (minute < 0 || minute >= 1440) {
      throw const FormatException('Choose a time within one day.');
    }
  }
}
