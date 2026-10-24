/// The owner's choices for the plan, kept on the phone.
///
/// Stored in the same on-device key-value table the reminder preferences use
/// (`BackgroundStore`), so it needs no new storage and is covered by the same
/// tests. Everything has a default, so a first run needs no setup.
library;

import 'dart:convert';

import 'package:healthee/data/basics/breathing/breathing_pattern.dart';
import 'package:healthee/data/basics/breathing/breathing_plan.dart';
import 'package:meta/meta.dart';

/// The owner's settings for the breathing plan.
@immutable
class BreathingSettings {
  /// Defaults: all four on, free from 22:15, morning fallback 08:00.
  const BreathingSettings({
    this.off = const {},
    this.nightFreeFromMinute = 1335,
    this.morningDefaultMinute = 480,
    this.custom,
    this.patternOverrides = const {},
    this.acceptedAt,
  });

  /// Reads settings saved by [encode]; null is the defaults.
  ///
  /// Throws [FormatException] for a value that is not valid, rather than
  /// quietly using defaults over the owner's choices.
  factory BreathingSettings.decode(String? raw) {
    if (raw == null) return const BreathingSettings();
    final data = jsonDecode(raw);
    if (data is! Map<String, Object?>) {
      throw const FormatException('Invalid breathing settings');
    }
    final off = <BreathingItemKind>{};
    for (final name in (data['off'] as List<Object?>? ?? const [])) {
      off.add(_kind(name));
    }
    final overrides = <BreathingItemKind, String>{};
    final rawOverrides = data['patterns'] as Map<String, Object?>? ?? const {};
    for (final entry in rawOverrides.entries) {
      overrides[_kind(entry.key)] = entry.value! as String;
    }
    final rawCustom = data['custom'] as List<Object?>?;
    BreathPattern? custom;
    if (rawCustom != null) {
      if (rawCustom.length != 4) {
        throw const FormatException('Invalid custom pattern');
      }
      final counts = [for (final c in rawCustom) c! as int];
      custom = BreathPattern.custom(
        inSeconds: counts[0],
        hold1Seconds: counts[1],
        outSeconds: counts[2],
        hold2Seconds: counts[3],
      );
    }
    final accepted = data['accepted_at_ms'] as int?;
    return BreathingSettings(
      off: off,
      nightFreeFromMinute: _minute(data['night_free_from']),
      morningDefaultMinute: _minute(data['morning_default']),
      custom: custom,
      patternOverrides: overrides,
      acceptedAt: accepted == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(accepted),
    );
  }

  static BreathingItemKind _kind(Object? name) {
    for (final kind in BreathingItemKind.values) {
      if (kind.name == name) return kind;
    }
    throw FormatException('Unknown breathing item: $name');
  }

  static int _minute(Object? value) {
    if (value is! int || value < 0 || value >= 1440) {
      throw const FormatException('Invalid breathing time');
    }
    return value;
  }

  /// Items the owner switched off. Everything else is on.
  final Set<BreathingItemKind> off;

  /// The time the owner is free from in the evening, local clock minutes.
  final int nightFreeFromMinute;

  /// The morning time used when there are too few nights to time it.
  final int morningDefaultMinute;

  /// The owner's own counts, or null until they set them.
  final BreathPattern? custom;

  /// Pattern id chosen per item, replacing that item's default.
  final Map<BreathingItemKind, String> patternOverrides;

  /// When the owner accepted the plan, or null before they did.
  final DateTime? acceptedAt;

  /// Whether [kind] is switched on.
  bool isEnabled(BreathingItemKind kind) => !off.contains(kind);

  /// The pattern for [kind]: the owner's choice, else its default.
  ///
  /// Choosing custom before setting counts falls back to the default rather
  /// than inventing counts.
  BreathPattern patternFor(BreathingItemKind kind) {
    final id = patternOverrides[kind];
    if (id == null) return kind.defaultPattern;
    if (id == BreathPattern.customId) return custom ?? kind.defaultPattern;
    return presetById(id) ?? kind.defaultPattern;
  }

  /// A copy with the given changes. Pass [clearCustom] to remove the counts.
  BreathingSettings copyWith({
    Set<BreathingItemKind>? off,
    int? nightFreeFromMinute,
    int? morningDefaultMinute,
    BreathPattern? custom,
    Map<BreathingItemKind, String>? patternOverrides,
    DateTime? acceptedAt,
  }) => BreathingSettings(
    off: off ?? this.off,
    nightFreeFromMinute: nightFreeFromMinute ?? this.nightFreeFromMinute,
    morningDefaultMinute: morningDefaultMinute ?? this.morningDefaultMinute,
    custom: custom ?? this.custom,
    patternOverrides: patternOverrides ?? this.patternOverrides,
    acceptedAt: acceptedAt ?? this.acceptedAt,
  );

  /// The JSON stored on the phone.
  String encode() => jsonEncode({
    'off': [for (final kind in off) kind.name],
    'night_free_from': nightFreeFromMinute,
    'morning_default': morningDefaultMinute,
    if (custom != null)
      'custom': [
        custom!.inSeconds,
        custom!.hold1Seconds,
        custom!.outSeconds,
        custom!.hold2Seconds,
      ],
    'patterns': {
      for (final entry in patternOverrides.entries) entry.key.name: entry.value,
    },
    if (acceptedAt != null)
      'accepted_at_ms': acceptedAt!.millisecondsSinceEpoch,
  });
}
