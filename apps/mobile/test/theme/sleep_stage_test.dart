/// `sleepStage()` — the one mapping every sleep chart draws from.
///
/// Legacy states the rule in a comment and then relies on it in four places
/// (the hypnogram, the seven-night bars, the legend, the stage bar). A second
/// mapping anywhere would mean one night drawn in two colour schemes, which is
/// the kind of wrongness nobody files a bug for because each screen looks fine
/// on its own.
///
/// **Every assertion here is mutation-tested**: for each stage, the test proves
/// the mapping answers that hue AND that it answers none of the other three. An
/// assertion that only checks the expected value passes for a mapping that
/// returns the same colour for everything.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/instrument_hues.dart';
import 'package:healthee/core/theme/stage_colors.dart';
import 'package:healthee/features/sleep/sleep_format.dart';

void main() {
  const themes = <String, InstrumentHues>{
    'light': InstrumentHues.light(),
    'dark': InstrumentHues.dark(),
  };

  for (final theme in themes.entries) {
    final hues = theme.value;

    group('${theme.key} — the canonical four', () {
      /// The stage colours, which since the contrast repair are their OWN four
      /// values rather than four borrowed metric hues. See
      /// `lib/core/theme/sleep_stage_palette.dart`.
      final canonical = <String, Color>{
        'deep': hues.stageDeep,
        'light': hues.stageLight,
        'core': hues.stageLight,
        'rem': hues.stageRem,
        'awake': hues.stageAwake,
      };

      /// What legacy drew each stage in, and what the port drew it in until the
      /// repair (`theme.dart:31` — deep=cSteps · core/light=cSpo2 · rem=cSleep ·
      /// awake=cHeart). Those four metric hues still exist and still have those
      /// values; they are simply no longer what a stage is painted with.
      final borrowed = <String, Color>{
        'deep': hues.movement,
        'light': hues.oxygen,
        'core': hues.oxygen,
        'rem': hues.sleep,
        'awake': hues.heart,
      };

      test('each stage answers its own stage colour', () {
        for (final entry in canonical.entries) {
          expect(
            hues.sleepStage(entry.key),
            entry.value,
            reason: '${entry.key} is not its stage colour',
          );
        }
      });

      test('THE STAGE COLOUR IS SPLIT FROM THE METRIC COLOUR', () {
        // The load-bearing half of the repair. Deep sleep and the steps metric
        // used to be one value; awake and `alert` used to be one value. Moving
        // the stage without splitting it would have dragged the steps tile, the
        // SpO₂ vitals row, the sleep gauge and the illness flag along with it.
        for (final entry in borrowed.entries) {
          expect(
            hues.sleepStage(entry.key),
            isNot(entry.value),
            reason: '${entry.key} is back on its old metric hue',
          );
        }
      });

      test('THE FAMILIES ARE THE KIT’s — only the stages are derived', () {
        // Restating the four family values here, independently of palette.dart,
        // is what makes the assertion above safe: it could otherwise be
        // satisfied by moving the FAMILY instead of the stage.
        //
        // These are v02's, not legacy's. The four the stages used to borrow
        // (`cSteps` · `cSpo2` · `cSleep` · `cHeart`) were replaced wholesale
        // when the prototype became the specification; what survives is the
        // structure — a family a card is *about*, and a stage ramp that is its
        // own derived four.
        final expected = theme.key == 'dark'
            ? const <Color>[
                Color(0xFFFF9F0A),
                Color(0xFF64D2FF),
                Color(0xFF7D7AFF),
                Color(0xFFFF375F),
              ]
            : const <Color>[
                Color(0xFFE58600),
                Color(0xFF0098C9),
                Color(0xFF5856D6),
                Color(0xFFE8304F),
              ];
        expect(<Color>[
          hues.movement,
          hues.oxygen,
          hues.sleep,
          hues.heart,
        ], expected);
      });

      test('MUTATION — no stage answers another stage’s colour', () {
        // The check that makes the first one mean something. Deep must be amber
        // and must NOT be the blue, the purple or the red; and so on round.
        final distinct = <String, Color>{
          'deep': hues.stageDeep,
          'light': hues.stageLight,
          'rem': hues.stageRem,
          'awake': hues.stageAwake,
        };
        for (final mine in distinct.entries) {
          for (final other in distinct.entries) {
            if (other.key == mine.key) {
              continue;
            }
            expect(
              hues.sleepStage(mine.key),
              isNot(other.value),
              reason: '${mine.key} draws in ${other.key}’s colour',
            );
          }
        }
      });

      test('THE FOUR ARE FOUR — a hypnogram of one hue is unreadable', () {
        final drawn = <Color>{
          for (final stage in const <String>['deep', 'light', 'rem', 'awake'])
            hues.sleepStage(stage),
        };
        expect(drawn.length, 4);
      });

      test('core and light are ONE stage under two vocabularies', () {
        // The server says `core`, the strap says `light`. Giving them different
        // colours would draw a distinction that does not exist.
        expect(hues.sleepStage('core'), hues.sleepStage('light'));
        expect(sleepStageLabel('core'), sleepStageLabel('light'));
      });

      test('AN UNRECOGNISED CODE IS NOT DRAWN AS A STAGE', () {
        // Legacy defaults an unknown code to cSpo2 (theme.dart:36 and
        // instrument_charts.dart:403), i.e. it draws a byte nobody has decoded
        // as LIGHT SLEEP — a named stage asserted about a measurement we could
        // not read. That is the failure this app exists to prevent, so it is the
        // one row of the mapping that is not ported.
        for (final code in const <String>[
          '0x7f',
          '',
          'nap',
          'LIGHT',
          'unknown',
        ]) {
          expect(hues.sleepStage(code), hues.unstaged, reason: code);
        }
      });

      test('MUTATION — no unrecognised code resolves to ANY of the four', () {
        // The assertion above passes for a mapping that answers `unstaged` for
        // everything, and it would also pass if `unstaged` were quietly set to
        // `stageLight`. This is the one that fails if the fallback goes back to
        // being a stage.
        final four = <Color>[
          hues.stageDeep,
          hues.stageLight,
          hues.stageRem,
          hues.stageAwake,
        ];
        for (final code in const <String>[
          '0x7f',
          '',
          'nap',
          'LIGHT',
          'unknown',
        ]) {
          expect(four, isNot(contains(hues.sleepStage(code))), reason: code);
        }
        expect(four, isNot(contains(hues.unstaged)));
      });

      test(
        'the unrecognised grey has NO CHROMA — it is not a fifth stage hue',
        () {
          // Legacy's four are all chromatic. "Unrecognised" must read as the
          // absence of a stage identity, not as one more of them.
          final grey = hues.unstaged;
          expect(grey.r, closeTo(grey.g, 0.001));
          expect(grey.g, closeTo(grey.b, 0.001));
          // And every real stage hue IS chromatic, so the distinction holds.
          for (final stage in const <String>['deep', 'light', 'rem', 'awake']) {
            final colour = hues.sleepStage(stage);
            expect(
              (colour.r - colour.g).abs() + (colour.g - colour.b).abs(),
              greaterThan(0.02),
              reason: '$stage would be indistinguishable from “unrecognised”',
            );
          }
        },
      );

      test(
        'the LABEL agrees with the colour — grey band, “Unrecognised” key',
        () {
          // The two halves live in different files; a fix applied to one of them
          // leaves a grey band the legend calls Light, or a key called
          // Unrecognised beside a blue band.
          for (final code in const <String>['0x7f', '', 'nap']) {
            expect(sleepStageLabel(code), 'Unrecognised', reason: code);
            expect(InstrumentHues.isRecognised(code), isFalse, reason: code);
          }
          for (final code in const <String>[
            'deep',
            'light',
            'core',
            'rem',
            'awake',
          ]) {
            expect(sleepStageLabel(code), isNot('Unrecognised'), reason: code);
            expect(InstrumentHues.isRecognised(code), isTrue, reason: code);
          }
        },
      );

      test('the legend key appears ONLY when the chart drew one', () {
        // The governing rule: an empty field renders nothing. A legend that
        // always carried the fifth key would name a stage no bar painted.
        expect(legendStages(const <String>['deep', 'light']), kSleepStages);
        expect(legendStages(const <String>[]), kSleepStages);
        expect(legendStages(const <String>['deep', '0x7f']), <String>[
          ...kSleepStages,
          kUnrecognisedStage,
        ]);
        // And the key it adds resolves to the same grey the band was drawn in.
        expect(hues.sleepStage(kUnrecognisedStage), hues.unstaged);
      });

      test('the alias resolves to the same mapping', () {
        for (final stage in const <String>[
          'deep',
          'light',
          'core',
          'rem',
          'awake',
        ]) {
          expect(sleepStageColor(hues, stage), hues.sleepStage(stage));
        }
      });
    });
  }

  test('the stacking order is legacy’s, deepest first', () {
    // instrument_charts.dart:335 stacks deep, core, rem, awake from the floor
    // up. A reordered list silently redraws every seven-night chart.
    expect(kSleepStages, const <String>['deep', 'light', 'rem', 'awake']);
  });

  test(
    'MUTATION — the label table does not answer one word for everything',
    () {
      final labels = <String>{
        for (final stage in kSleepStages) sleepStageLabel(stage),
      };
      expect(labels.length, kSleepStages.length);
      expect(sleepStageLabel('0x7f'), 'Unrecognised');
    },
  );

  test(
    'ONE STAGE, ONE WORD — every vocabulary the app meets answers “Light”',
    () {
      // The defect: legacy said `Core` in the breakdown and the hypnogram lanes,
      // `light` in the naps legend and `CORE` on the seven-night chip — three
      // words, two of them on one screen. Every surface asks this function now.
      for (final spelling in const <String>['light', 'core']) {
        expect(sleepStageLabel(spelling), 'Light', reason: spelling);
      }
      expect(sleepStageLabel('light'), isNot('Core'));
    },
  );

  test('normaliseStage does not turn an unknown code into light sleep', () {
    // Legacy's `_normStage` ended `return 'core'`, so it laundered every
    // unreadable code into a named stage BEFORE the colour mapping ever saw it.
    // Fixing only the colour would have left this path intact.
    expect(normaliseStage('deep sleep'), 'deep');
    expect(normaliseStage('REM'), 'rem');
    expect(normaliseStage('awake'), 'awake');
    expect(normaliseStage('light'), 'core');
    expect(normaliseStage('core'), 'core');
    for (final code in <String?>['0x7f', '', null, 'nap', 'stage9']) {
      expect(normaliseStage(code), kUnrecognisedStage, reason: '$code');
    }
  });

  test('the two themes agree on WHICH FIELD each stage takes', () {
    // The hexes differ by theme, and must; the mapping may not. This compares
    // the field a stage resolves to, not its value.
    const light = InstrumentHues.light();
    const dark = InstrumentHues.dark();
    String fieldOf(InstrumentHues hues, String stage) {
      final colour = hues.sleepStage(stage);
      if (colour == hues.stageDeep) {
        return 'stageDeep';
      }
      if (colour == hues.stageLight) {
        return 'stageLight';
      }
      if (colour == hues.stageRem) {
        return 'stageRem';
      }
      if (colour == hues.stageAwake) {
        return 'stageAwake';
      }
      return 'unknown';
    }

    for (final stage in const <String>[
      'deep',
      'light',
      'core',
      'rem',
      'awake',
    ]) {
      expect(fieldOf(dark, stage), fieldOf(light, stage), reason: stage);
      expect(fieldOf(light, stage), isNot('unknown'), reason: stage);
    }
  });
}
