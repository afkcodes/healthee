/// The owner's water settings as a provider, saved on every change.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthee/data/background/background_store.dart';
import 'package:healthee/data/basics/water/water_settings.dart';
import 'package:healthee/data/store/store_provider.dart';

/// The key in the on-device key-value table.
const String kWaterSettingsKey = 'water_settings';

/// Reads and writes [WaterSettings].
class WaterSettingsController extends AsyncNotifier<WaterSettings> {
  BackgroundStore get _store => BackgroundStore(ref.read(localStoreProvider));

  @override
  Future<WaterSettings> build() async =>
      WaterSettings.decode(await _store.read(kWaterSettingsKey));

  /// Saves the owner's glass count. Throws [FormatException] outside 1 to 20.
  Future<void> setGlasses(int glasses) async {
    if (glasses < kMinGlasses || glasses > kMaxGlasses) {
      throw const FormatException('Choose between 1 and 20 glasses.');
    }
    final value = WaterSettings(glasses: glasses);
    await _store.write(kWaterSettingsKey, value.encode());
    state = AsyncData(value);
  }
}

/// The settings, kept for the session.
final waterSettingsProvider =
    AsyncNotifierProvider<WaterSettingsController, WaterSettings>(
      WaterSettingsController.new,
    );
