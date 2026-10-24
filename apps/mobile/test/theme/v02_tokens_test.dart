/// **Every colour-kit token, transcribed independently and compared.**
///
/// The values below were read from the colour kit (v3 `1-colour-system.png`) a
/// second time, by hand, and written out here. That is the whole method: a
/// transcription checked against a transcription. `flutter analyze` cannot see a
/// transposed digit, and a palette that is merely *self-consistent* is a palette
/// that can be wrong everywhere at once.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/core/theme/appearance_palette.dart';
import 'package:healthee/core/theme/appearance_variant.dart';
import 'package:healthee/core/theme/instrument_hues.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone.dart';

void main() {
  const light = HealtheeColors.light();
  const dark = HealtheeColors.dark();
  const lightHues = InstrumentHues.light();
  const darkHues = InstrumentHues.dark();

  group('scaffolding — light', () {
    test('the neutrals are the colour kit’s (v3 1-colour-system.png)', () {
      expect(light.canvas, const Color(0xFFF2F2F7), reason: 'canvas');
      expect(light.bg, const Color(0xFFF2F2F7), reason: 'page');
      expect(light.surface, const Color(0xFFFFFFFF), reason: 'card');
      expect(light.surface2, const Color(0xFFF2F2F7), reason: 'well');
      expect(light.ink, const Color(0xFF111113), reason: 'ink');
      expect(light.ink2, const Color(0xFF6E6E73), reason: 'ink2');
      expect(light.ink3, const Color(0xFFAEAEB2), reason: 'ink3');
      expect(light.line, const Color(0xFFE5E5EA), reason: 'line');
      expect(light.rule, const Color(0xFFC7C7CC), reason: 'rule');
    });

    test('accent and verdicts', () {
      expect(light.accent, light.ink, reason: 'the accent is ink, no hue');
      expect(light.accent2, const Color(0xFF2C2C2E));
      expect(light.accentSoft, light.surface2);
      expect(light.onAccent, const Color(0xFFFFFFFF));
      expect(light.fav, const Color(0xFF24A148), reason: 'better');
      expect(light.favSoft, const Color(0xFFE5F4E9));
      expect(light.unf, const Color(0xFFC79A00), reason: 'watch');
      expect(light.unfSoft, const Color(0xFFF8F3E0));
      expect(light.alert, const Color(0xFFE5342B), reason: 'worse');
      expect(light.alertSoft, const Color(0xFFFCE7E6));
    });
  });

  group('scaffolding — dark, the default appearance for this direction', () {
    test('the neutrals', () {
      expect(dark.canvas, const Color(0xFF000000));
      expect(dark.bg, const Color(0xFF000000));
      expect(dark.surface, const Color(0xFF0F1012));
      expect(dark.surface2, const Color(0xFF1C1D21));
      expect(dark.ink, const Color(0xFFF5F5F7));
      expect(dark.ink2, const Color(0xFF8E8E93));
      expect(dark.ink3, const Color(0xFF55555B));
      expect(dark.line, const Color(0xFF232427));
      expect(dark.rule, const Color(0xFF3A3A3F));
    });

    test('accent and verdicts', () {
      expect(dark.accent, dark.ink, reason: 'the accent is ink, no hue');
      expect(dark.accent2, const Color(0xFFD1D1D6));
      expect(dark.accentSoft, dark.surface2);
      expect(dark.onAccent, const Color(0xFF111113));
      expect(dark.fav, const Color(0xFF30D158));
      expect(dark.favSoft, const Color(0xFF142F1D));
      expect(dark.unf, const Color(0xFFFFD60A));
      expect(dark.unfSoft, const Color(0xFF353011));
      expect(dark.alert, const Color(0xFFFF453A));
      expect(dark.alertSoft, const Color(0xFF351818));
    });
  });

  group('the seven domain hues', () {
    test('light', () {
      expect(lightHues.fitness, const Color(0xFF9F45D6));
      expect(lightHues.fitnessSoft, const Color(0xFFF3E9FA));
      expect(lightHues.sleep, const Color(0xFF5856D6));
      expect(lightHues.sleepSoft, const Color(0xFFEBEBFA));
      expect(lightHues.heart, const Color(0xFFE8304F));
      expect(lightHues.heartSoft, const Color(0xFFFCE6EA));
      expect(lightHues.movement, const Color(0xFFE58600));
      expect(lightHues.movementSoft, const Color(0xFFFCF0E0));
      expect(lightHues.oxygen, const Color(0xFF0098C9));
      expect(lightHues.oxygenSoft, const Color(0xFFE0F3F9));
      expect(lightHues.stress, const Color(0xFF0FA37F));
      expect(lightHues.stressSoft, const Color(0xFFE2F4F0));
      expect(lightHues.strain, const Color(0xFF0071E3));
      expect(lightHues.strainSoft, const Color(0xFFE0EEFC));
    });

    test('dark', () {
      expect(darkHues.fitness, const Color(0xFFBF5AF2));
      expect(darkHues.fitnessSoft, const Color(0xFF2B1C36));
      expect(darkHues.sleep, const Color(0xFF7D7AFF));
      expect(darkHues.sleepSoft, const Color(0xFF212138));
      expect(darkHues.heart, const Color(0xFFFF375F));
      expect(darkHues.heartSoft, const Color(0xFF35161E));
      expect(darkHues.movement, const Color(0xFFFF9F0A));
      expect(darkHues.movementSoft, const Color(0xFF352711));
      expect(darkHues.oxygen, const Color(0xFF64D2FF));
      expect(darkHues.oxygenSoft, const Color(0xFF1D2F38));
      expect(darkHues.stress, const Color(0xFF63E6BE));
      expect(darkHues.stressSoft, const Color(0xFF1C322E));
      expect(darkHues.strain, const Color(0xFF0A84FF));
      expect(darkHues.strainSoft, const Color(0xFF0E2338));
    });

    test('recovery has no hue: it is ink2 on the well, in both themes', () {
      expect(lightHues.recovery, light.ink2);
      expect(lightHues.recoverySoft, light.surface2);
      expect(darkHues.recovery, dark.ink2);
      expect(darkHues.recoverySoft, dark.surface2);
    });

    test('DISTINCT FAMILIES, and distinct fills, in both themes', () {
      for (final (name, hues) in [('light', lightHues), ('dark', darkHues)]) {
        final families = <Color>{
          for (final tone in kToneFamilies) tone.family(hues),
        };
        final softs = <Color>{
          for (final tone in kToneFamilies) tone.familySoft(hues),
        };
        expect(families.length, kToneFamilies.length, reason: name);
        expect(softs.length, kToneFamilies.length, reason: name);
      }
    });
  });

  group('the collisions legacy made on purpose are GONE', () {
    // Legacy's `improving ? c.green : c.cHeart` put a metric hue on both sides
    // of a verdict: green was HRV *and* "improving", red-orange was heart *and*
    // "degrading". v02 gives judgement its own three pairs, so identity and
    // judgement can no longer be confused — and a reader who "restores" the
    // sharing would be undoing a decision rather than fixing a duplication.
    test('fav is the better state, not the fitness family', () {
      expect(light.fav, isNot(lightHues.fitness));
      expect(dark.fav, isNot(darkHues.fitness));
    });

    test('alert is the worse state, not the heart family', () {
      expect(light.alert, isNot(lightHues.heart));
      expect(dark.alert, isNot(darkHues.heart));
    });

    test('the accent is INK, not any domain hue', () {
      // The kit's rule: the domain hue says what a number is, chrome stays
      // neutral. A hued accent would put a ninth meaning on the screen.
      for (final (colors, hues) in [(light, lightHues), (dark, darkHues)]) {
        expect(colors.accent, colors.ink);
        for (final tone in kToneFamilies) {
          expect(colors.accent, isNot(tone.family(hues)), reason: '$tone');
        }
      }
    });
  });

  group('the derived roles keep their relation to what they came from', () {
    test('v02 has ONE hairline, so line2 is line — by transcription', () {
      // Recorded rather than asserted-away: if a later design splits the pair
      // again this test is where the intent is written down.
      expect(light.line2, light.line);
      expect(dark.line2, dark.line);
    });

    test('grid is ink, quieter; reference is ink2, quieter', () {
      for (final (name, colors) in [('light', light), ('dark', dark)]) {
        // Dark grid is pure white at 6%, 10/255 off the F5F5F7 ink.
        expect(colors.grid.r, closeTo(colors.ink.r, 11 / 255), reason: name);
        expect(colors.grid.g, closeTo(colors.ink.g, 11 / 255), reason: name);
        expect(colors.grid.b, closeTo(colors.ink.b, 11 / 255), reason: name);
        expect(colors.grid.a, lessThan(0.10), reason: name);
        expect(colors.reference.r, closeTo(colors.ink2.r, 1 / 255));
        expect(colors.reference.g, closeTo(colors.ink2.g, 1 / 255));
        expect(colors.reference.b, closeTo(colors.ink2.b, 1 / 255));
        expect(colors.reference.a, lessThan(1));
      }
    });

    test('band is the usual range: a faint translucent wash', () {
      expect(light.band.a, lessThan(0.10));
      expect(dark.band.a, lessThan(0.10));
      expect(light.band.a, greaterThan(0));
      expect(dark.band.a, greaterThan(0));
    });

    test('hole is a near-invisible FILL, not a hue', () {
      expect(light.hole.a, lessThan(0.10));
      expect(dark.hole.a, lessThan(0.10));
    });

    test('overlay and shadow are translucent — they sit ON something', () {
      for (final colors in [light, dark]) {
        expect(colors.overlay.a, lessThan(1));
        expect(colors.shadow.a, lessThan(1));
      }
    });
  });

  group('EVERY role resolves, in both themes', () {
    test('lerp reaches every role, so none was forgotten in a constructor', () {
      // The catch-all. A role added to the class but omitted from `lerp` keeps
      // its starting value at t=1, so the two sides cannot compare equal — and
      // a role omitted from a named constructor would not compile.
      expect(light.lerp(dark, 1), dark);
      expect(light.lerp(dark, 0), light);
      expect(lightHues.lerp(darkHues, 1), darkHues);
      expect(darkHues.lerp(lightHues, 1), lightHues);
    });

    test('the assembled themes carry both extensions', () {
      expect(AppTheme.light.extension<HealtheeColors>(), light);
      expect(AppTheme.light.extension<InstrumentHues>(), lightHues);
      expect(AppTheme.dark.extension<HealtheeColors>(), dark);
      expect(AppTheme.dark.extension<InstrumentHues>(), darkHues);
    });
  });

  test('the owner’s first accent IS the theme accent, in both themes', () {
    // `appearanceColors` leaves the palette alone at index 0, so a first entry
    // disagreeing with the theme would render one green before the owner opened
    // the picker and another after. The other six are the owner's own.
    expect(
      AppearancePalette.accents.length,
      AppearanceVariant.accentNames.length,
    );
    expect(AppearancePalette.accents.first.first, light.accent);
    expect(AppearancePalette.accents.first.last, dark.accent);
  });
}
