/// The sleep-stage set, measured. Every pair, both themes — **recorded, not
/// gated**.
///
/// ## What changed, and why the numbers stayed
///
/// This file used to be a gate. It measured a derived luminance ramp that had
/// been substituted for the prototype's four stage colours on accessibility
/// grounds, and it failed the build on any move back toward them.
///
/// The owner answered by restating the standing instruction — **the prototype in
/// `design/mobile-preview/` is the specification and we match it exactly** — so
/// `richer.css`'s four hues are what ships. The argument is over.
///
/// The **measurements are not deleted**, because deleting them would leave the
/// repo unable to say what the set costs. Every number the gate used to assert
/// is still computed here, by the same code, and printed on every run. What is
/// gone is the assertion: no test in this file fails because a stage pair is
/// close, nothing warns at runtime, and no build gate exists anywhere.
///
/// ## What IS still asserted, and why each one is a fact rather than a taste
///
///   * **The shipped values are v02's, by hex, in both themes.** A stage that
///     drifts one digit from `richer.css` is a port defect; that is the property
///     this file now guards.
///   * **Four distinct colours.** Two stages sharing a value is a hypnogram that
///     cannot be read at all, in any palette.
///   * **The unrecognised grey has no chroma and every stage does.** With the
///     v02 set the separation between a named stage and an undecoded byte rests
///     on chroma and on the legend's word, so those are the two things worth
///     holding — and both are true of the shipped set.
///   * **The superseded ramp still measures what its docstring claims.** It is
///     kept in `sleep_stage_palette.dart` as the recorded alternative, so its
///     numbers are checked rather than left to rot into fiction.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/instrument_hues.dart';
import 'package:healthee/core/theme/sleep_stage_palette.dart';
import 'package:healthee/core/theme/stage_colors.dart';
import 'package:healthee/core/theme/tokens.dart';

/// WCAG 2.x contrast ratio between two opaque colours.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// OKLab chroma — how much colour there is, independent of how light it is.
double _chroma(Color c) {
  double lin(double v) =>
      v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  final r = lin(c.r);
  final g = lin(c.g);
  final b = lin(c.b);
  double cbrt(double v) =>
      math.pow(v.abs(), 1 / 3).toDouble() * (v < 0 ? -1 : 1);
  final l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
  final m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
  final s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
  final aa = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s;
  final bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s;
  return math.sqrt(aa * aa + bb * bb);
}

/// The four, by name, so a recording says which pair.
Map<String, Color> _stages(InstrumentHues hues) => <String, Color>{
  for (final stage in kSleepStages) stage: hues.sleepStage(stage),
};

/// The lowest contrast among every pair in [set]. The measurement this file is
/// built on, so the recordings and the superseded ramp's check share one
/// implementation.
double _worstPair(List<Color> set) {
  var lowest = double.infinity;
  for (var i = 0; i < set.length; i++) {
    for (var j = i + 1; j < set.length; j++) {
      lowest = math.min(lowest, _contrast(set[i], set[j]));
    }
  }
  return lowest;
}

/// Whether [set] is strictly darkening in `kSleepStages` order — the depth
/// ordering the superseded ramp was built around.
bool _isDescending(List<Color> set) {
  for (var i = 1; i < set.length; i++) {
    if (set[i].computeLuminance() >= set[i - 1].computeLuminance()) {
      return false;
    }
  }
  return true;
}

/// `#RRGGBB`, so a recording is readable beside `richer.css`.
String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0')}';

/// Prints one line of the record. Deliberately unconditional: a measurement
/// nobody sees unless something fails is a measurement that was really an
/// assertion.
void _record(String line) => debugPrint('  $line');

void main() {
  const themes = <String, (InstrumentHues, HealtheeColors)>{
    'light': (InstrumentHues.light(), HealtheeColors.light()),
    'dark': (InstrumentHues.dark(), HealtheeColors.dark()),
  };

  // The prototype's own values, written out rather than imported, so a mutation
  // to `V02StagePrototype` is caught instead of compared against itself.
  const shipped = <String, Map<String, Color>>{
    'light': <String, Color>{
      'deep': Color(0xFF3634A3),
      'light': Color(0xFF007AFF),
      'rem': Color(0xFF32ADE6),
      'awake': Color(0xFFE5603F),
    },
    'dark': <String, Color>{
      'deep': Color(0xFF5E5CE6),
      'light': Color(0xFF0A84FF),
      'rem': Color(0xFF64D2FF),
      'awake': Color(0xFFFF7A59),
    },
  };

  for (final entry in themes.entries) {
    final (hues, colors) = entry.value;
    final stages = _stages(hues);
    final names = stages.keys.toList();

    group('${entry.key} — the shipped stage set', () {
      test('IS THE KIT’S, BY HEX — colour kit v3, digit for digit', () {
        // The one gate this file still holds, and the reason the values are
        // written out above rather than read from `V02StagePrototype`: a
        // constant compared against itself agrees with every typo.
        final expected = shipped[entry.key]!;
        for (final stage in expected.entries) {
          expect(
            stages[stage.key],
            stage.value,
            reason:
                '${stage.key} is ${_hex(stages[stage.key]!)}, '
                'the colour kit says ${_hex(stage.value)}',
          );
        }
      });

      test('RECORDED — every pair, against the number the ramp reached', () {
        // Six pairs, not three: the stacked bar puts deep beside light, the
        // hypnogram can put any lane above any other, and the legend sets all
        // four side by side.
        _record('${entry.key}: band against band');
        for (var i = 0; i < names.length; i++) {
          for (var j = i + 1; j < names.length; j++) {
            final ratio = _contrast(stages[names[i]]!, stages[names[j]]!);
            _record(
              '  ${names[i].padRight(6)} vs ${names[j].padRight(6)} '
              '${ratio.toStringAsFixed(2)}'
              '${ratio < kStagePairFloor ? '   under $kStagePairFloor' : ''}',
            );
          }
        }
        _record(
          '  worst pair ${_worstPair(stages.values.toList()).toStringAsFixed(2)} '
          '(the superseded ramp reached $kStagePairFloor)',
        );
        // Two stages painted the same colour is not a palette question — it is
        // a chart with a lane missing — so distinctness stays a gate.
        expect(stages.values.toSet().length, kSleepStages.length);
      });

      test('RECORDED — every stage on its card and on its page', () {
        _record(
          '${entry.key}: stage on surface ${_hex(colors.surface)} '
          'and page ${_hex(colors.bg)}',
        );
        for (final stage in stages.entries) {
          final card = _contrast(stage.value, colors.surface);
          final page = _contrast(stage.value, colors.bg);
          _record(
            '  ${stage.key.padRight(6)} ${_hex(stage.value)}  '
            'card ${card.toStringAsFixed(2)}  page ${page.toStringAsFixed(2)}'
            '${card < kStageSurfaceFloor ? '   under $kStageSurfaceFloor' : ''}',
          );
        }
      });

      test('RECORDED — the depth ordering, which this set does not have', () {
        // The superseded ramp darkened monotonically in lane order, so lane
        // position and lightness said the same thing and a greyscale reader got
        // the hypnogram for free. v02 separates the four by HUE instead. Both
        // facts are asserted, in the direction each is true.
        final ladder = <double>[
          for (final stage in kSleepStages) stages[stage]!.computeLuminance(),
        ];
        _record(
          '${entry.key}: luminance in lane order  '
          '${ladder.map((y) => y.toStringAsFixed(4)).join('  ')}',
        );
        expect(
          _isDescending(stages.values.toList()),
          isFalse,
          reason:
              'v02 orders by hue, not by depth — if this passes, the '
              'shipped set is no longer v02’s',
        );
        expect(
          _isDescending(
            entry.key == 'light'
                ? const <Color>[
                    LightStagePalette.deep,
                    LightStagePalette.light,
                    LightStagePalette.rem,
                    LightStagePalette.awake,
                  ]
                : const <Color>[
                    DarkStagePalette.deep,
                    DarkStagePalette.light,
                    DarkStagePalette.rem,
                    DarkStagePalette.awake,
                  ],
          ),
          isTrue,
          reason: 'the superseded ramp no longer measures what it claims',
        );
      });

      test('THE UNSTAGED GREY HAS NO CHROMA, and every stage has some', () {
        // With the v02 set this is the separation that carries the fifth value:
        // chroma, plus `legendStages` adding an "Unrecognised" key exactly when
        // a grey band was drawn. Luminance never did this job and is recorded
        // below rather than asserted.
        final grey = hues.unstaged;
        expect(grey.r, closeTo(grey.g, 0.001));
        expect(grey.g, closeTo(grey.b, 0.001));
        expect(_chroma(grey), lessThan(0.005));
        _record(
          '${entry.key}: grey ${_hex(grey)}  '
          'card ${_contrast(grey, colors.surface).toStringAsFixed(2)}  '
          'page ${_contrast(grey, colors.bg).toStringAsFixed(2)}',
        );
        for (final stage in stages.entries) {
          _record(
            '  grey vs ${stage.key.padRight(6)} '
            '${_contrast(grey, stage.value).toStringAsFixed(2)}  '
            'chroma ${_chroma(stage.value).toStringAsFixed(4)}',
          );
          expect(
            _chroma(stage.value),
            greaterThan(0.05),
            reason: '${stage.key} would be mistaken for “unrecognised”',
          );
          expect(stage.value, isNot(grey), reason: stage.key);
        }
      });
    });
  }

  test('THE SUPERSEDED RAMP STILL MEASURES WHAT ITS DOCSTRING CLAIMS', () {
    // `sleep_stage_palette.dart` keeps the derived ramp as the recorded
    // alternative. A record nobody checks decays into a story, so the two
    // numbers it quotes are checked here — against the ramp's own constants,
    // never against what ships.
    const light = <Color>[
      LightStagePalette.deep,
      LightStagePalette.light,
      LightStagePalette.rem,
      LightStagePalette.awake,
    ];
    const dark = <Color>[
      DarkStagePalette.deep,
      DarkStagePalette.light,
      DarkStagePalette.rem,
      DarkStagePalette.awake,
    ];
    _record(
      'superseded ramp: worst pair '
      'light ${_worstPair(light).toStringAsFixed(2)}  '
      'dark ${_worstPair(dark).toStringAsFixed(2)}',
    );
    expect(_worstPair(light), greaterThanOrEqualTo(kStagePairFloor));
    expect(_worstPair(dark), greaterThanOrEqualTo(kStagePairFloor));
    for (final stage in light) {
      expect(
        _contrast(stage, const HealtheeColors.light().surface),
        greaterThanOrEqualTo(kStageSurfaceFloor),
      );
    }
    for (final stage in dark) {
      expect(
        _contrast(stage, const HealtheeColors.dark().surface),
        greaterThanOrEqualTo(kStageSurfaceFloor),
      );
    }
  });

  test('THE CEILING IS PROVED, so 1.5 reads as a limit and not a surrender', () {
    // Four colours each 3:1 clear of the next need 27:1 end to end; sRGB offers
    // 21:1 at the absolute most (#000000 on #FFFFFF). It is why the ramp's own
    // floor was never 3:1, and it is still worth stating beside the recording.
    const black = Color(0xFF000000);
    const white = Color(0xFFFFFFFF);
    expect(_contrast(black, white), lessThan(3.0 * 3.0 * 3.0));
    expect(kStagePairFloor, lessThan(3.0));
  });
}
