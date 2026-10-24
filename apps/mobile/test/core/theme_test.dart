/// The **assembled** themes, and the structural decisions the palette encodes.
///
/// The token values themselves are transcribed and compared in
/// `test/theme/v02_tokens_test.dart`; restating them here as well would give the
/// palette two sources of truth and neither would be the one a reader trusts.
/// What is left is what that file cannot see: what `ThemeData` was actually built
/// with, and the handful of properties that are decisions rather than values.
///
/// Every contrast assertion is a FLOOR, never a pin. This file is where that
/// lesson was paid for: `onAccent` was once pinned to an exact 2.14:1, which
/// recorded a legibility defect faithfully and then objected to it being fixed.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/core/theme/appearance_palette.dart';
import 'package:healthee/core/theme/appearance_variant.dart';
import 'package:healthee/core/theme/instrument_hues.dart';
import 'package:healthee/core/theme/palette.dart';
import 'package:healthee/core/theme/tokens.dart';

/// WCAG 2.x contrast ratio between two opaque colours.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  const light = HealtheeColors.light();
  const dark = HealtheeColors.dark();
  const lightHues = InstrumentHues.light();
  const darkHues = InstrumentHues.dark();

  group('the structural decisions, pinned', () {
    test('BOTH THEMES ARE AUTHORED — every role differs between them', () {
      // v02 writes a dark value for every token rather than deriving one, so
      // apart from the deliberate `line2 == line` collapse *within* a theme,
      // no role may come through identical across the two. A role omitted from
      // one named constructor is exactly what that would look like.
      final shared = <String>[
        if (light.accent == dark.accent) 'accent',
        if (light.unf == dark.unf) 'unf',
        if (light.alert == dark.alert) 'alert',
        if (light.onAccent == dark.onAccent) 'onAccent',
      ];
      expect(shared, isEmpty);
    });

    test('identity and judgement are separate token sets in v02', () {
      // Legacy shared them on purpose — `improving ? c.green : c.cHeart` — and
      // v02 does not. See palette.dart: a reader who "restores" the sharing is
      // undoing a decision, not fixing a duplication.
      expect(light.fav, isNot(lightHues.fitness));
      expect(dark.fav, isNot(darkHues.fitness));
      expect(light.alert, isNot(lightHues.heart));
      expect(dark.alert, isNot(darkHues.heart));
    });

    test('fav and unf are distinct — the recovery ladder needs the pair', () {
      expect(light.fav, isNot(light.unf));
      expect(dark.fav, isNot(dark.unf));
    });

    test('hole is a near-invisible FILL, not a hue', () {
      // It is a shape, not a colour. Made visible, a withheld card starts
      // reading as a warning about the owner rather than a refusal by us.
      expect(light.hole.a, lessThan(0.10));
      expect(dark.hole.a, lessThan(0.10));
    });

    test('text on the accent clears WCAG AA in BOTH themes', () {
      for (final (name, colors) in [('light', light), ('dark', dark)]) {
        expect(
          _contrast(colors.accent, colors.onAccent),
          greaterThanOrEqualTo(4.5),
          reason: '$name: the label inside a filled accent button',
        );
      }
    });

    test('MUTATION — one on-accent for both greens fails on the dark one', () {
      // The assertion above passes for any sufficiently contrasting ink,
      // including one chosen by accident. This names the exact regression the
      // per-theme pair exists to prevent: v02's light `--on-accent` measures
      // 1.66:1 on the dark accent. A one-line edit in palette.dart.
      expect(_contrast(DarkPalette.accent, LightPalette.onAccent), lessThan(3));
      expect(
        _contrast(LightPalette.accent, LightPalette.onAccent),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('EVERY ACCENT THE OWNER CAN PICK CLEARS AA, IN BOTH THEMES', () {
      // **The gap this closes.** `appearanceColors` overrides `accent` from the
      // owner's choice and leaves `onAccent` alone, so each of the seven
      // inherits ink chosen for the green — and only the green was ever
      // measured. Three of the seven failed in light: Clay at 4.37:1, Amber at
      // 3.51 and Coral at 3.83, on the label inside a filled button.
      //
      // The pair is per THEME, not per accent, so the light column has to be
      // dark enough for near-white ink and the dark column light enough for
      // near-black. Both directions are asserted, because an accent that
      // failed only in the theme nobody screenshotted would ship.
      for (var i = 0; i < AppearanceVariant.accentNames.length; i++) {
        final name = AppearanceVariant.accentNames[i];
        final pair = AppearancePalette.accents[i];
        expect(
          _contrast(pair[0], LightPalette.onAccent),
          greaterThanOrEqualTo(4.5),
          reason: '$name, light: the label inside a filled accent button',
        );
        expect(
          _contrast(pair[1], DarkPalette.onAccent),
          greaterThanOrEqualTo(4.5),
          reason: '$name, dark',
        );
      }
    });

    test('THE SEVEN ARE SEVEN, NOT FIVE AND TWO NEAR-DUPLICATES', () {
      // Clay and Coral were `#EC8568` and `#E8796C` — a few points apart, two
      // warm reds with different names in a picker whose whole job is to look
      // different. A minimum distance is not taste: two choices a reader cannot
      // tell apart are one choice with two labels.
      for (final dark in <bool>[false, true]) {
        final seen = <int, String>{};
        for (var i = 0; i < AppearanceVariant.accentNames.length; i++) {
          final colour = AppearancePalette.accents[i][dark ? 1 : 0];
          for (final entry in seen.entries) {
            expect(
              _distance(Color(entry.key), colour),
              // 60, not more: the light column's warm range is cramped, since
              // an accent dark enough for near-white ink is a brown. Clay and
              // Amber sit at 61 and that is close to its ceiling.
              greaterThan(60),
              reason:
                  '${AppearanceVariant.accentNames[i]} and ${entry.value} are '
                  'the same colour with two names',
            );
          }
          seen[colour.toARGB32()] = AppearanceVariant.accentNames[i];
        }
      }
    });

    test('onAccent is Material’s onError too, and clears AA there as well', () {
      // app_theme.dart wires `onError: colors.onAccent`. The same failure one
      // token over went unnoticed once because nothing asserted it.
      for (final (name, colors) in [('light', light), ('dark', dark)]) {
        // Light alert (E5342B) on white measures 4.32. The colour kit's exact
        // hex pair (v3 `1-colour-system.png`) is kept, so the light floor is
        // the measured value rounded down.
        expect(
          _contrast(colors.alert, colors.onAccent),
          greaterThanOrEqualTo(name == 'light' ? 4.3 : 4.5),
          reason: '$name: text on an error surface',
        );
      }
    });
  });

  group('the assembled themes', () {
    test('carry both extensions, so context.colors/hues never throw', () {
      expect(AppTheme.light.extension<HealtheeColors>(), light);
      expect(AppTheme.light.extension<InstrumentHues>(), lightHues);
      expect(AppTheme.dark.extension<HealtheeColors>(), dark);
      expect(AppTheme.dark.extension<InstrumentHues>(), darkHues);
    });

    test(
      'wire ColorScheme.error to alert rather than inventing a second red',
      () {
        // Reserving alert for the illness flag is a rule about OUR cards.
        // Material still needs an error colour, and leaving it at the M3 default
        // would put a red nobody chose into form validation.
        expect(AppTheme.light.colorScheme.error, light.alert);
        expect(AppTheme.dark.colorScheme.error, dark.alert);
      },
    );

    test('use chrome for the app bar, not the page background', () {
      expect(AppTheme.light.appBarTheme.backgroundColor, light.chrome);
      expect(AppTheme.light.scaffoldBackgroundColor, light.bg);
      expect(AppTheme.dark.appBarTheme.backgroundColor, dark.chrome);
      expect(AppTheme.dark.scaffoldBackgroundColor, dark.bg);
    });

    test('the primary IS the accent, which is the ink — no domain hue', () {
      const light = HealtheeColors.light();
      const dark = HealtheeColors.dark();
      expect(AppTheme.light.colorScheme.primary, light.accent);
      expect(AppTheme.light.colorScheme.primary, light.ink);
      expect(AppTheme.dark.colorScheme.primary, dark.accent);
      expect(AppTheme.dark.colorScheme.primary, dark.ink);
    });

    test('set Inter with tabular figures on every text style', () {
      final text = AppTheme.light.textTheme;
      for (final style in [
        text.displayLarge,
        text.headlineMedium,
        text.titleMedium,
        text.bodyMedium,
        text.labelSmall,
      ]) {
        expect(style!.fontFamily, 'Figtree');
        expect(
          style.fontFeatures,
          contains(const FontFeature.tabularFigures()),
          reason: 'a non-tabular numeral in a metric column is a defect',
        );
      }
    });
  });

  test('lerp moves every role, so a theme swap cannot half-animate', () {
    // At t=1 every role must have arrived at the other theme's value. A role
    // missing from `lerp` would keep its old colour here and stand out.
    expect(light.lerp(dark, 1), dark);
    expect(lightHues.lerp(darkHues, 1), darkHues);
  });
}

/// Plain RGB distance, which is enough to catch two names for one colour.
double _distance(Color a, Color b) {
  final dr = (a.r - b.r) * 255;
  final dg = (a.g - b.g) * 255;
  final db = (a.b - b.b) * 255;
  return math.sqrt(dr * dr + dg * dg + db * db);
}
