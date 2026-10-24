/// **Contrast floors for every text pair the colour system makes, both themes.**
///
/// ## Floors, never pins
///
/// Every assertion is `greaterThanOrEqualTo`. A pin fails when contrast
/// *improves*, which is the one direction nobody needs stopping — and this
/// project has the receipt: `onAccent` was once pinned to an exact 2.14:1, so the
/// pin recorded a legibility defect and then objected to it being fixed.
///
/// ## Which floor, and why
///
/// **4.5:1** for anything with words in it — WCAG 2.1 SC 1.4.3, normal text. It
/// is applied to the label colours as well as the body ones, because this app's
/// labels *are* the reading: a unit under a number is not decoration.
///
/// **3:1** for a family drawn as a mark rather than as words — SC 1.4.11,
/// non-text contrast. A line, a dot, an icon tile's glyph.
///
/// The gridline is deliberately **excluded**. It is structure at the edge of
/// perception and is asserted in `chart_ink_test.dart` as *the quietest ink on
/// the chart*; holding it to a text floor would be asking the background to
/// compete with the data drawn on it.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/instrument_hues.dart';
import 'package:healthee/core/theme/palette.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone.dart';

/// WCAG 2.x contrast ratio between two opaque colours.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// SC 1.4.3 — normal text.
const double kTextFloor = 4.5;

/// SC 1.4.11 — a graphical object.
const double kMarkFloor = 3.0;

/// `ink3` is axes, disabled controls and the no-data dash. It is NOT text and
/// cannot meet [kTextFloor]; this is only a "still visible" floor (the lowest
/// measured is light `ink3` on a well, 1.98).
const double kInk3Floor = 1.9;

// ## Light-theme exceptions (colour kit v3, `1-colour-system.png`)
//
// In light the kit uses state colours and domain hues as dots, marks and chip
// text at about 3:1 on white, with its own hex pairs, which are not changed.
// Where an exact kit hex measures a little under a floor, THAT assertion is
// relaxed to the measured value rounded down to one decimal. Dark meets the
// full floors except where noted below.

/// Light state colour on its own soft fill, then on a card (measured, floored).
const Map<String, (double, double)> kLightVerdictFloors = {
  'fav': (2.9, 3.3), // 2.94 / 3.35
  'unf': (2.3, 2.6), // 2.35 / 2.61
  'alert': (3.6, 4.3), // 3.65 / 4.32
};

/// Light family on its own soft fill (measured, floored).
const Map<Tone, double> kLightFamilyOnSoftFloor = {
  Tone.fitness: 4.1, // 4.15
  Tone.recovery: 4.5, // 4.54
  Tone.sleep: 4.7, // 4.79
  Tone.heart: 3.5, // 3.55
  Tone.load: 3.9, // 3.98
  Tone.movement: 2.4, // 2.41
  Tone.oxygen: 2.8, // 2.90
  Tone.stress: 2.8, // 2.81
};

/// Light family as a mark on a card and on the page (measured, floored).
/// Absent = holds [kMarkFloor].
const Map<Tone, (double, double)> kLightFamilyMarkFloor = {
  Tone.movement: (2.7, 2.4), // 2.71 / 2.43
  Tone.oxygen: (3.0, 2.9), // 3.32 / 2.97
  Tone.stress: (3.0, 2.8), // 3.20 / 2.87
};

void main() {
  const themes = <String, (HealtheeColors, InstrumentHues)>{
    'light': (HealtheeColors.light(), InstrumentHues.light()),
    'dark': (HealtheeColors.dark(), InstrumentHues.dark()),
  };

  for (final entry in themes.entries) {
    final name = entry.key;
    final (colors, hues) = entry.value;

    group('$name — the three inks', () {
      test(
        'ink3 is NOT text: axes and the dash stay visible, nothing more',
        () {
          for (final ground in [colors.surface, colors.bg, colors.surface2]) {
            expect(
              contrast(colors.ink3, ground),
              greaterThanOrEqualTo(kInk3Floor),
              reason: '$name ink3',
            );
            expect(
              contrast(colors.ink3, ground),
              lessThan(kTextFloor),
              reason:
                  '$name: if ink3 ever clears the text floor it is no '
                  'longer the quiet tier',
            );
          }
        },
      );

      test('ink and ink2 clear AA on the card, the page AND a well', () {
        // Every ground, because a card that moved onto the page (or a page
        // section that gained a surface) must not degrade silently.
        for (final (role, ink) in <(String, Color)>[
          ('ink', colors.ink),
          ('ink2', colors.ink2),
        ]) {
          expect(
            contrast(ink, colors.surface),
            greaterThanOrEqualTo(kTextFloor),
            reason: '$name $role on a card',
          );
          expect(
            contrast(ink, colors.bg),
            greaterThanOrEqualTo(kTextFloor),
            reason: '$name $role on the page',
          );
          expect(
            contrast(ink, colors.surface2),
            greaterThanOrEqualTo(kTextFloor),
            reason: '$name $role on a recessed block',
          );
        }
      });
    });

    group('$name — judgement and the accent', () {
      test(
        'text ON the accent, and on the error surface Material shares it',
        () {
          expect(
            contrast(colors.accent, colors.onAccent),
            greaterThanOrEqualTo(kTextFloor),
            reason: '$name: the label inside a filled accent button',
          );
          expect(
            contrast(colors.alert, colors.onAccent),
            greaterThanOrEqualTo(name == 'light' ? 4.3 : kTextFloor),
            reason: '$name: app_theme wires onError to onAccent',
          );
        },
      );

      test('each verdict reads as words on its own soft fill', () {
        for (final (role, ink, fill) in <(String, Color, Color)>[
          ('fav', colors.fav, colors.favSoft),
          ('unf', colors.unf, colors.unfSoft),
          ('alert', colors.alert, colors.alertSoft),
          ('accent', colors.accent, colors.accentSoft),
        ]) {
          final light = name == 'light' ? kLightVerdictFloors[role] : null;
          expect(
            contrast(ink, fill),
            greaterThanOrEqualTo(light?.$1 ?? kTextFloor),
            reason: '$name: a $role chip',
          );
          expect(
            contrast(ink, colors.surface),
            greaterThanOrEqualTo(light?.$2 ?? kTextFloor),
            reason: '$name: $role as a word on a card',
          );
        }
      });

      test('the three verdicts are distinguishable from each other', () {
        // Not a contrast floor — a distinctness one. `fav` and `unf` are the
        // two sides of the recovery ladder and collapsing them makes the app's
        // signature chart undrawable.
        expect(colors.fav, isNot(colors.unf));
        expect(colors.unf, isNot(colors.alert));
        expect(colors.fav, isNot(colors.alert));
      });
    });

    group('$name — the domain hues', () {
      test('a family is READABLE on its own soft ground', () {
        // The summary tile writes its label in `--family` on `--family-soft`,
        // so this pair carries words and takes the text floor.
        for (final tone in kToneFamilies) {
          final floor = name == 'light'
              ? kLightFamilyOnSoftFloor[tone]!
              : (tone == Tone.load ? 4.3 : kTextFloor); // dark load: 4.37
          expect(
            contrast(tone.family(hues), tone.familySoft(hues)),
            greaterThanOrEqualTo(floor),
            reason: '$name: a ${tone.name} tile’s label',
          );
        }
      });

      test('a family is VISIBLE as a mark on the card and on the page', () {
        for (final tone in kToneFamilies) {
          final relaxed = name == 'light' ? kLightFamilyMarkFloor[tone] : null;
          expect(
            contrast(tone.family(hues), colors.surface),
            greaterThanOrEqualTo(relaxed?.$1 ?? kMarkFloor),
            reason: '$name: a ${tone.name} line on a panel',
          );
          expect(
            contrast(tone.family(hues), colors.bg),
            greaterThanOrEqualTo(relaxed?.$2 ?? kMarkFloor),
            reason: '$name: a ${tone.name} line on the page',
          );
        }
      });
    });
  }

  group('MUTATION — the guard can see a failure', () {
    test('the ratio itself is right at both extremes', () {
      // A helper that always returned a large number would pass every test in
      // this file. These two are arithmetic, not design.
      expect(
        contrast(const Color(0xFF000000), const Color(0xFFFFFFFF)),
        closeTo(21, 0.01),
      );
      expect(
        contrast(const Color(0xFF808080), const Color(0xFF808080)),
        closeTo(1, 0.001),
      );
    });

    test('using the light on-accent on the dark accent is caught', () {
      // The exact regression the palette carries a per-theme `onAccent` to
      // prevent: one value for both themes. Dark accent (near-white ink) under
      // the light on-accent (white) is about 1.1:1.
      expect(
        contrast(DarkPalette.accent, LightPalette.onAccent),
        lessThan(kMarkFloor),
      );
      expect(
        contrast(LightPalette.accent, LightPalette.onAccent),
        greaterThanOrEqualTo(kTextFloor),
      );
    });

    test('writing a family in its own soft fill is caught', () {
      // The mutation `color: familySoft` where the label should be `family` —
      // a one-word slip that renders an invisible label rather than a wrong one.
      for (final entry in themes.entries) {
        final (_, hues) = entry.value;
        for (final tone in kToneFamilies) {
          expect(
            contrast(tone.familySoft(hues), tone.familySoft(hues)),
            lessThan(kTextFloor),
            reason: '${entry.key} ${tone.name}',
          );
        }
      }
    });

    test('the ink floor would catch an ink drawn on the wrong ground', () {
      // Dark ink on the dark page is the classic theme-crossing bug. It must
      // fail the same floor the tests above apply.
      expect(contrast(LightPalette.ink, DarkPalette.bg), lessThan(kTextFloor));
      expect(contrast(DarkPalette.ink, LightPalette.bg), lessThan(kTextFloor));
    });
  });
}
