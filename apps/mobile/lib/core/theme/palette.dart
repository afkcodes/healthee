/// The colour system, both themes: one rule runs the whole app. **The domain hue
/// says what a number is; the state colour says how it is going.** Chrome stays
/// neutral. (`design colour kit v3`, `1-colour-system.png`.)
///
/// ## Seven domain hues, one per body system
///
/// | Domain    | Field in [InstrumentHues] | Tone                |
/// |-----------|---------------------------|---------------------|
/// | Heart     | `heart`                   | `heart`             |
/// | Sleep     | `sleep`                   | `sleep`             |
/// | Activity  | `movement`                | `movement` `activity` |
/// | Strain    | `strain`                  | `load`              |
/// | Breathing | `oxygen`                  | `oxygen`            |
/// | Body      | `fitness`                 | `fitness`           |
/// | Mind      | `stress`                  | `stress`            |
///
/// A domain hue is never good or bad. Recovery has no hue of its own: it is
/// judged by zone ([DarkPalette.fav] 67 to 100, [DarkPalette.unf] 34 to 66,
/// [DarkPalette.alert] 0 to 33).
///
/// ## Three state colours, reserved for judgement
///
/// `fav` is *better*, `alert` is *worse*, `unf` is *watch*. Inside the owner's
/// usual range is neutral ink, never green. Missing data is hatched grey with a
/// dash, [DarkPalette.ink3].
///
/// ## Light uses the darker hex of each pair
///
/// So a dot or a chip reads at 3:1 on white. Text in `ink` and `ink2` clears
/// 4.5:1 on every surface; `ink3` is for axes, disabled controls and the
/// no-data dash, which is why it is not held to the text floor.
///
/// This file, `appearance_palette.dart` and `sleep_stage_palette.dart` are the
/// only places a colour literal may live (`colour_literal_gate_test.dart`).
library;

import 'package:flutter/material.dart';

/// The seven domain hues, light. The `Soft` partner is the hue at 12% on white.
abstract final class LightFamilies {
  /// Body: biological age, weight, skin temperature, basal energy.
  static const Color fitness = Color(0xFF9F45D6);

  /// The fill behind [fitness] content.
  static const Color fitnessSoft = Color(0xFFF3E9FA);

  /// Sleep: duration, stages, regularity, debt.
  static const Color sleep = Color(0xFF5856D6);

  /// The fill behind [sleep] content.
  static const Color sleepSoft = Color(0xFFEBEBFA);

  /// Heart: HRV, resting HR, heart rate, VO₂max.
  static const Color heart = Color(0xFFE8304F);

  /// The fill behind [heart] content.
  static const Color heartSoft = Color(0xFFFCE6EA);

  /// Activity: steps, distance, calories, active minutes.
  static const Color movement = Color(0xFFE58600);

  /// The fill behind [movement] content.
  static const Color movementSoft = Color(0xFFFCF0E0);

  /// Breathing: blood oxygen, breathing rate.
  static const Color oxygen = Color(0xFF0098C9);

  /// The fill behind [oxygen] content.
  static const Color oxygenSoft = Color(0xFFE0F3F9);

  /// Mind: stress, journal, meditation.
  static const Color stress = Color(0xFF0FA37F);

  /// The fill behind [stress] content.
  static const Color stressSoft = Color(0xFFE2F4F0);

  /// Strain: cardio load, workouts.
  static const Color strain = Color(0xFF0071E3);

  /// The fill behind [strain] content.
  static const Color strainSoft = Color(0xFFE0EEFC);
}

/// The seven domain hues, dark. The `Soft` partner is the hue at 16% on the card.
abstract final class DarkFamilies {
  /// Body.
  static const Color fitness = Color(0xFFBF5AF2);

  /// The fill behind [fitness] content.
  static const Color fitnessSoft = Color(0xFF2B1C36);

  /// Sleep.
  static const Color sleep = Color(0xFF7D7AFF);

  /// The fill behind [sleep] content.
  static const Color sleepSoft = Color(0xFF212138);

  /// Heart.
  static const Color heart = Color(0xFFFF375F);

  /// The fill behind [heart] content.
  static const Color heartSoft = Color(0xFF35161E);

  /// Activity.
  static const Color movement = Color(0xFFFF9F0A);

  /// The fill behind [movement] content.
  static const Color movementSoft = Color(0xFF352711);

  /// Breathing.
  static const Color oxygen = Color(0xFF64D2FF);

  /// The fill behind [oxygen] content.
  static const Color oxygenSoft = Color(0xFF1D2F38);

  /// Mind.
  static const Color stress = Color(0xFF63E6BE);

  /// The fill behind [stress] content.
  static const Color stressSoft = Color(0xFF1C322E);

  /// Strain.
  static const Color strain = Color(0xFF0A84FF);

  /// The fill behind [strain] content.
  static const Color strainSoft = Color(0xFF0E2338);
}

/// Neutrals and state colours, light.
abstract final class LightPalette {
  /// The app canvas.
  static const Color canvas = Color(0xFFF2F2F7);

  /// The page.
  static const Color bg = Color(0xFFF2F2F7);

  /// A card.
  static const Color surface = Color(0xFFFFFFFF);

  /// A well: tiles inside a card, tracks, inputs.
  static const Color surface2 = Color(0xFFF2F2F7);

  /// Bars and sheets.
  static const Color chrome = surface;

  /// Text primary: numbers, titles, the primary button's fill.
  static const Color ink = Color(0xFF111113);

  /// Text secondary: labels, units, captions.
  static const Color ink2 = Color(0xFF6E6E73);

  /// Text tertiary: axes, disabled, the no-data dash.
  static const Color ink3 = Color(0xFFAEAEB2);

  /// A hairline between rows.
  static const Color line = Color(0xFFE5E5EA);

  /// A second hairline weight.
  static const Color line2 = line;

  /// A stronger rule.
  static const Color rule = Color(0xFFC7C7CC);

  /// A gridline, the quietest ink on a chart.
  static const Color grid = Color.fromRGBO(17, 17, 19, 0.06);

  /// A reference mark.
  static const Color reference = Color.fromRGBO(110, 110, 115, 0.55);

  /// The primary button and link ink: the text colour, no hue.
  static const Color accent = ink;

  /// The pressed accent.
  static const Color accent2 = Color(0xFF2C2C2E);

  /// The fill behind accent content.
  static const Color accentSoft = surface2;

  /// Text on an accent fill.
  static const Color onAccent = Color(0xFFFFFFFF);

  /// Better: better than your usual, a check passed, a goal met.
  static const Color fav = Color(0xFF24A148);

  /// The fill behind [fav].
  static const Color favSoft = Color(0xFFE5F4E9);

  /// Watch: moderate zone, outside the range with no good side, stale.
  static const Color unf = Color(0xFFC79A00);

  /// The fill behind [unf].
  static const Color unfSoft = Color(0xFFF8F3E0);

  /// Worse: worse than your usual, a check missed, a low zone, a failure.
  static const Color alert = Color(0xFFE5342B);

  /// The fill behind [alert].
  static const Color alertSoft = Color(0xFFFCE7E6);

  /// The hatch ground of a reading that is not there.
  static const Color hole = Color.fromRGBO(17, 17, 19, 0.045);

  /// The personal usual-range band behind a trend.
  static const Color band = Color.fromRGBO(0, 0, 0, 0.05);

  /// A sheet's scrim.
  static const Color overlay = Color(0x5911131F);

  /// A drop shadow.
  static const Color shadow = Color(0x121E1F34);

  /// A map's land.
  static const Color mapLand = Color(0xFFE7F2E7);
}

/// Neutrals and state colours, dark.
abstract final class DarkPalette {
  /// The app canvas, AMOLED black.
  static const Color canvas = Color(0xFF000000);

  /// The page.
  static const Color bg = Color(0xFF000000);

  /// A card.
  static const Color surface = Color(0xFF0F1012);

  /// A well.
  static const Color surface2 = Color(0xFF1C1D21);

  /// Bars and sheets.
  static const Color chrome = surface;

  /// Text primary.
  static const Color ink = Color(0xFFF5F5F7);

  /// Text secondary.
  static const Color ink2 = Color(0xFF8E8E93);

  /// Text tertiary: axes, disabled, the no-data dash.
  static const Color ink3 = Color(0xFF55555B);

  /// A hairline between rows.
  static const Color line = Color(0xFF232427);

  /// A second hairline weight.
  static const Color line2 = line;

  /// A stronger rule.
  static const Color rule = Color(0xFF3A3A3F);

  /// A gridline.
  static const Color grid = Color.fromRGBO(255, 255, 255, 0.06);

  /// A reference mark.
  static const Color reference = Color.fromRGBO(142, 142, 147, 0.55);

  /// The primary button and link ink: the text colour, no hue.
  static const Color accent = ink;

  /// The pressed accent.
  static const Color accent2 = Color(0xFFD1D1D6);

  /// The fill behind accent content.
  static const Color accentSoft = surface2;

  /// Text on an accent fill.
  static const Color onAccent = Color(0xFF111113);

  /// Better.
  static const Color fav = Color(0xFF30D158);

  /// The fill behind [fav].
  static const Color favSoft = Color(0xFF142F1D);

  /// Watch.
  static const Color unf = Color(0xFFFFD60A);

  /// The fill behind [unf].
  static const Color unfSoft = Color(0xFF353011);

  /// Worse.
  static const Color alert = Color(0xFFFF453A);

  /// The fill behind [alert].
  static const Color alertSoft = Color(0xFF351818);

  /// The hatch ground of a reading that is not there.
  static const Color hole = Color.fromRGBO(255, 255, 255, 0.05);

  /// The personal usual-range band behind a trend.
  static const Color band = Color.fromRGBO(255, 255, 255, 0.07);

  /// A sheet's scrim.
  static const Color overlay = Color(0xA6020208);

  /// A drop shadow.
  static const Color shadow = Color(0x33000001);

  /// A map's land.
  static const Color mapLand = Color(0xFF1B211B);
}

/// Colours that are not part of a theme: masks a painter tints.
abstract final class MaskColors {
  /// Opaque white, for a sprite that `BlendMode.modulate` then tints. It is
  /// never seen as white; the tint supplies every visible colour.
  static const Color white = Color(0xFFFFFFFF);
}
