/// **The tone cascade** — v02's central mechanism, asserted as behaviour.
///
/// `richer.css` lines 37-50 set one custom property from a `data-tone` attribute
/// and let six rules read it. The Flutter equivalent is `ToneScope` plus
/// `context.family`, and what has to be true is that a **descendant** resolves
/// the **declaring ancestor's** colour without anyone passing it down. So the
/// tests below pump real widget trees and read what a child sees, rather than
/// calling the resolver directly — a resolver that is correct and a cascade that
/// does not reach are indistinguishable from the outside.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/core/theme/instrument_hues.dart';
import 'package:healthee/core/theme/metric_hue.dart';
import 'package:healthee/core/theme/stage_colors.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/core/theme/tone_scope.dart';

/// Pumps [child] under a real theme and hands back what it resolved.
Future<(Tone, Color, Color)> _resolve(
  WidgetTester tester,
  Widget Function(Widget probe) wrap, {
  required ThemeData theme,
}) async {
  late Tone tone;
  late Color family;
  late Color familySoft;
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: wrap(
        Builder(
          builder: (context) {
            tone = context.tone;
            family = context.family;
            familySoft = context.familySoft;
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  // MaterialApp animates a theme change through `AnimatedTheme`, so the frame
  // straight after `pumpWidget` still carries the PREVIOUS theme's extensions
  // lerped part of the way. Settling is what makes the second pump in a test
  // report the theme it was actually given.
  await tester.pumpAndSettle();
  return (tone, family, familySoft);
}

void main() {
  const lightHues = InstrumentHues.light();
  const darkHues = InstrumentHues.dark();

  group('the resolver — every tone, both themes', () {
    test('each of the nine tones resolves a family and a fill', () {
      for (final (name, hues) in [('light', lightHues), ('dark', darkHues)]) {
        for (final tone in Tone.values) {
          expect(tone.family(hues), isNotNull, reason: '$name ${tone.name}');
          expect(
            tone.familySoft(hues),
            isNotNull,
            reason: '$name ${tone.name}',
          );
          expect(
            tone.family(hues),
            isNot(tone.familySoft(hues)),
            reason: '$name ${tone.name}: a fill that IS the ink draws nothing',
          );
        }
      }
    });

    test('THE ONE ALIAS RESOLVES TO ITS FAMILY, and nothing else does', () {
      // Activity is the only tone with a second name. Strain was split from
      // heart and recovery lost its fitness hue (it is neutral ink2), so any
      // OTHER pair sharing a colour would mean two categories the owner cannot
      // tell apart.
      const aliases = <Tone, Tone>{Tone.activity: Tone.movement};
      for (final hues in [lightHues, darkHues]) {
        for (final entry in aliases.entries) {
          expect(entry.key.family(hues), entry.value.family(hues));
          expect(entry.key.familySoft(hues), entry.value.familySoft(hues));
          expect(entry.key.canonical, entry.value);
        }
        for (final a in kToneFamilies) {
          for (final b in kToneFamilies) {
            if (a != b) {
              expect(a.family(hues), isNot(b.family(hues)), reason: '$a vs $b');
            }
          }
        }
      }
    });

    test('the four sleep stages are their own mapping, not a family', () {
      // Stages do not follow a card's tone: a hypnogram inside a sleep-toned
      // panel still paints four stage colours, and `sleepStage` is where they
      // come from. An unreadable code resolves to the grey, never to a stage.
      for (final hues in [lightHues, darkHues]) {
        final drawn = <Color>{
          for (final stage in kSleepStages) sleepStageColor(hues, stage),
        };
        expect(drawn.length, kSleepStages.length);
        expect(sleepStageColor(hues, 'core'), hues.stageLight);
        expect(sleepStageColor(hues, 'a_code_nobody_decoded'), hues.unstaged);
        expect(drawn, isNot(contains(hues.unstaged)));
        for (final tone in kToneFamilies) {
          // The colour kit deliberately gives dark Core the Strain hex
          // (0A84FF) and dark REM the Breathing hex (64D2FF); every other
          // stage/family pair is distinct.
          if (hues == darkHues && (tone == Tone.load || tone == Tone.oxygen)) {
            continue;
          }
          expect(drawn, isNot(contains(tone.family(hues))), reason: '$tone');
        }
      }
    });

    test(
      'the kit’s stage/family coincidences are exactly the two dark ones',
      () {
        expect(darkHues.stageLight, darkHues.strain);
        expect(darkHues.stageRem, darkHues.oxygen);
        expect(lightHues.stageLight, isNot(lightHues.strain));
        expect(lightHues.stageRem, isNot(lightHues.oxygen));
      },
    );
  });

  group('the cascade — a declaring ancestor, a resolving descendant', () {
    testWidgets('with no scope the family is fitness — richer.css :root', (
      tester,
    ) async {
      final (tone, family, soft) = await _resolve(
        tester,
        (probe) => probe,
        theme: AppTheme.dark,
      );
      expect(tone, Tone.fitness);
      expect(family, darkHues.fitness);
      expect(soft, darkHues.fitnessSoft);
    });

    testWidgets('a scope changes what its descendant resolves', (tester) async {
      for (final tone in kToneFamilies) {
        final (seen, family, soft) = await _resolve(
          tester,
          (probe) => ToneScope(tone: tone, child: probe),
          theme: AppTheme.light,
        );
        expect(seen, tone);
        expect(family, tone.family(lightHues), reason: tone.name);
        expect(soft, tone.familySoft(lightHues), reason: tone.name);
      }
    });

    testWidgets('the NEAREST scope wins — a panel inside a section', (
      tester,
    ) async {
      final (tone, family, _) = await _resolve(
        tester,
        (probe) => ToneScope(
          tone: Tone.sleep,
          child: ToneScope(tone: Tone.oxygen, child: probe),
        ),
        theme: AppTheme.dark,
      );
      expect(tone, Tone.oxygen);
      expect(family, darkHues.oxygen);
    });

    testWidgets('the same scope resolves differently under a different theme', (
      tester,
    ) async {
      final (_, lightFamily, _) = await _resolve(
        tester,
        (probe) => ToneScope(tone: Tone.heart, child: probe),
        theme: AppTheme.light,
      );
      final (_, darkFamily, _) = await _resolve(
        tester,
        (probe) => ToneScope(tone: Tone.heart, child: probe),
        theme: AppTheme.dark,
      );
      expect(lightFamily, lightHues.heart);
      expect(darkFamily, darkHues.heart);
      expect(lightFamily, isNot(darkFamily));
    });
  });

  group('the metric table feeds the cascade', () {
    test('a metric names a TONE, and the resolved colour follows', () {
      expect(toneFor('sleep_debt_min'), Tone.sleep);
      expect(toneFor('rhr_daily'), Tone.heart);
      expect(toneFor('cardio_load'), Tone.load);
      expect(toneFor('steps_total'), Tone.movement);
      expect(toneFor('active_calories'), Tone.movement);
      expect(toneFor('respiratory_rate'), Tone.oxygen);
      expect(toneFor('spo2_overnight'), Tone.oxygen);
      expect(toneFor('stress'), Tone.stress);
      expect(toneFor('skin_temp_c'), Tone.fitness);
      expect(toneFor('hrv'), Tone.heart);
      expect(toneFor('readiness'), Tone.recovery);
      expect(toneFor('vo2max_estimate'), Tone.heart);
      expect(toneFor('a_metric_nobody_listed'), Tone.fitness);
    });

    test('hueFor is exactly the tone, resolved — not a second table', () {
      const metrics = <String>[
        'sleep_debt_min',
        'rhr_daily',
        'cardio_load',
        'steps_total',
        'active_calories',
        'respiratory_rate',
        'spo2',
        'stress',
        'skin_temp_c',
        'hrv',
        'vo2max_estimate',
        'nothing_at_all',
      ];
      for (final hues in [lightHues, darkHues]) {
        for (final metric in metrics) {
          expect(hueFor(hues, metric), toneFor(metric).family(hues));
        }
      }
    });

    test('the two ids for one metric agree — one metric, one tone', () {
      expect(toneFor('rhr_daily'), toneFor('resting_hr'));
      expect(toneFor('steps_total'), toneFor('steps'));
      expect(toneFor('spo2_overnight'), toneFor('spo2'));
      // v02 dissolved legacy's own second conflict: respiratory rate and SpO₂
      // were `cResp` on Today and `cSpo2` on Sleep, and are now one family.
      expect(toneFor('respiratory_rate'), toneFor('spo2'));
    });
  });

  group('MUTATION — the assertions above can actually fail', () {
    test('a tone table that collapsed two families is caught', () {
      // The mutation `Tone.oxygen => hues.sleep` in tone.dart would keep every
      // "resolves a colour" assertion green. This proves the distinctness sweep
      // in "THE ONE ALIAS…" is what catches it, by running that sweep over
      // a set with two families already collapsed.
      final collapsed = lightHues.copyWith(oxygen: lightHues.sleep);
      var clashes = 0;
      for (final a in kToneFamilies) {
        for (final b in kToneFamilies) {
          if (a != b && a.family(collapsed) == b.family(collapsed)) {
            clashes++;
          }
        }
      }
      expect(clashes, greaterThan(0));
    });

    test('a cascade that ignored its scope is caught', () {
      // If `ToneScope.of` returned the default instead of reading the tree,
      // every toned resolution would come back fitness. The scope test asserts
      // a specific per-tone colour, so it fails for all but one family — proved
      // here by showing those five differ from the default.
      final defaulted = Tone.fitness.family(darkHues);
      final differ = kToneFamilies
          .where((tone) => tone.family(darkHues) != defaulted)
          .length;
      expect(differ, kToneFamilies.length - 1);
    });

    test('a stage mapping that fell back to a family is caught', () {
      // Legacy defaulted an unrecognised code to `cSpo2` — it drew an undecoded
      // byte AS light sleep. The stage test asserts the grey; this proves the
      // grey is not any family, so the old fallback could not pass it.
      for (final hues in [lightHues, darkHues]) {
        for (final tone in kToneFamilies) {
          expect(hues.unstaged, isNot(tone.family(hues)));
        }
      }
    });
  });
}
