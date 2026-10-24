/// The owner's glass count, kept on the phone.
///
/// Stored in the same on-device key-value table as the breathing settings
/// (`BackgroundStore`). The app never prescribes an amount (the 8 x 8 rule is
/// graded a myth in `hydration_8x8_rule`), so 8 is only a starting count and
/// [isSet] says whether the owner has chosen one.
library;

import 'dart:convert';

import 'package:meta/meta.dart';

/// One glass, in millilitres.
const int kGlassMl = 250;

/// The count shown until the owner picks one. Not a recommendation.
const int kDefaultGlasses = 8;

/// The smallest and largest count the owner can pick.
const int kMinGlasses = 1;
const int kMaxGlasses = 20;

/// The owner's glass count, or none yet.
@immutable
class WaterSettings {
  /// [glasses] null means the owner has not chosen.
  const WaterSettings({this.glasses});

  /// Reads settings saved by [encode]; null is the defaults.
  ///
  /// Throws [FormatException] for a value that is not valid, rather than
  /// quietly using the default over the owner's choice.
  factory WaterSettings.decode(String? raw) {
    if (raw == null) return const WaterSettings();
    final data = jsonDecode(raw);
    if (data is! Map<String, Object?>) {
      throw const FormatException('Invalid water settings');
    }
    final glasses = data['glasses'];
    if (glasses == null) return const WaterSettings();
    if (glasses is! int || glasses < kMinGlasses || glasses > kMaxGlasses) {
      throw const FormatException('Invalid water glass count');
    }
    return WaterSettings(glasses: glasses);
  }

  /// What the owner chose, or null.
  final int? glasses;

  /// Whether the owner has chosen a count.
  bool get isSet => glasses != null;

  /// The count to draw: the owner's, else [kDefaultGlasses].
  int get target => glasses ?? kDefaultGlasses;

  /// The JSON stored on the phone.
  String encode() => jsonEncode({if (glasses != null) 'glasses': glasses});

  @override
  bool operator ==(Object other) =>
      other is WaterSettings && other.glasses == glasses;

  @override
  int get hashCode => glasses.hashCode;
}
