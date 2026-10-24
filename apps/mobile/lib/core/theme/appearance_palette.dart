/// The owner's own chrome — the accent they picked and the ground it sits on.
///
/// **The third and last file in this app allowed to contain a colour literal**,
/// alongside `palette.dart` and `sleep_stage_palette.dart`;
/// `test/core/colour_literal_gate_test.dart` reads `lib/` and fails on a fourth.
///
/// ## Why it is not in `palette.dart`
///
/// That file is the v02 token set: every value in it is the sRGB form of an
/// OKLCH token the prototype defines, and it is not free to change. These are
/// not tokens. They are seven accents and three grounds the owner chooses
/// between, authored for this app, answering to WCAG contrast and to being
/// **distinguishable from each other** rather than to `tokens.css`. Two sets of
/// colours with two different authorities and two different tests, so two files.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/appearance_variant.dart';
import 'package:healthee/core/theme/palette.dart';

/// The owner's seven selectable accents and three dark grounds, authored
/// independently for light/dark. Read by `appearance_colors.dart`.
///
/// **Index 0 is the theme's own accent and must stay that way**:
/// `appearanceColors` leaves the palette untouched at index 0, so a first entry
/// that disagreed with [LightPalette.accent] would mean "Forest" rendered one
/// green before the owner ever opened the picker and another after. It moved to
/// v02's fitness pair with the rest of the palette; the other six are the
/// owner's, unchanged.
abstract final class AppearancePalette {
  /// `[light, dark]` per accent, in [AppearanceVariant.accentNames] order.
  ///
  /// **Every pair clears WCAG AA against `onAccent`, and three of them did not.**
  /// `appearanceColors` overrides `accent` and leaves `onAccent` alone, so a
  /// chosen accent inherits ink picked for the green — and nothing measured the
  /// result. Clay was 4.37:1 in light, Amber 3.51 and Coral 3.83, which is the
  /// label inside a filled `Sync now` button. `theme_test.dart` measures all
  /// fourteen now.
  ///
  /// They are also more saturated than the muted set they replace, and each is
  /// the colour it is named after: Teal was a washed cyan, Berry a dusty rose,
  /// and Clay and Coral were within a few points of each other — two warm reds
  /// with different names. Clay is terracotta now and Coral is a pink-red.
  ///
  /// Clay and Amber are the tightest pair in the LIGHT column and that is a
  /// constraint rather than a choice: ink here is near-white, so a warm accent
  /// dark enough to carry it is a brown, and the range holds two distinguishable
  /// browns and not many more. 61 apart is close to the best available.
  ///
  /// **Index 0 stays the families' green on purpose.** `appearanceColors` only
  /// overrides for a non-zero choice, so Forest IS `--fitness` — the hue every
  /// recovery chart and VO₂max reading is drawn in. Making it "more vibrant"
  /// would repaint measurements, not chrome.
  static const accents = <List<Color>>[
    [LightPalette.ink, DarkPalette.ink],
    [Color(0xFFA62F0C), Color(0xFFFF8A50)],
    [Color(0xFF9A6A00), Color(0xFFFFC02E)],
    [Color(0xFF00786F), Color(0xFF1FD9C0)],
    [Color(0xFF4338CA), Color(0xFF8B93FF)],
    [Color(0xFFA3199C), Color(0xFFF260E8)],
    [Color(0xFFC81E4A), Color(0xFFFF5C80)],
  ];

  /// `BackgroundVariant.dark` — a neutral ground instead of v02's green-cast one.
  static const neutralBg = Color(0xFF121214);

  /// `BackgroundVariant.dark` surface.
  static const neutralSurface = Color(0xFF1B1B20);

  /// `BackgroundVariant.dark` sunken surface.
  static const neutralSunken = Color(0xFF0C0C0F);

  /// `BackgroundVariant.dark` hairline.
  static const neutralLine = Color(0xFF2A2A31);

  /// `BackgroundVariant.dark` stronger rule.
  static const neutralLine2 = Color(0xFF3A3A43);

  /// `BackgroundVariant.amoled` ground — true black, for an OLED panel.
  static const blackBg = Color(0xFF000000);

  /// `BackgroundVariant.amoled` surface.
  static const blackSurface = Color(0xFF0C0C0D);

  /// `BackgroundVariant.amoled` hairline.
  static const blackLine = Color(0xFF1B1B1E);

  /// `BackgroundVariant.amoled` stronger rule.
  static const blackLine2 = Color(0xFF2C2C30);
}

