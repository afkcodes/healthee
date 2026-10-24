/// **The bundle is what the app asks for** — the gate that was missing.
///
/// Its sibling `typography_test.dart` measures the *face*: tabular figures,
/// glyph coverage, overflow at display size. Every one of those questions is
/// about a font that IS being used. This file asks a question one step earlier
/// and, it turns out, the one that was actually wrong: **is the app being served
/// the face it named?**
///
/// It was not. `HType.number` is legacy's `HType.num` and asks for **w700**;
/// `pubspec.yaml` vendored 400, 500 and 600. Flutter does not fail on a weight
/// it does not have — it substitutes the nearest — so all 74 instrument readouts
/// in the app rendered at 600. Nothing errored, nothing warned, and the screen
/// looked entirely correct while every number on it was the wrong drawing.
///
/// The same class of miss put `FontStyle.italic` on three call sites that
/// rendered upright, because Flutter does not synthesise a slant for a bundled
/// family either. Both are *incomplete font swap*, not design.
///
/// ## Both sides are derived, deliberately
///
/// The weights the app asks for are read by scanning `lib/`; what the bundle can
/// actually draw is read out of the font file. A hardcoded list on either side
/// would have to be kept current by the same person who forgot to add the 700 —
/// which is precisely how the gap opened, and why it stayed open through a port.
///
/// ## The bundle is now ONE variable file, and that changes what to assert
///
/// Figtree ships as a single variable `.ttf`, so "one file per weight" is no
/// longer the question — `fvar`'s `wght` axis range is. A weight outside that
/// range is the same silent substitution the 700 was, so the range is read out
/// of the font's own `fvar` table and compared against what `lib/` asks for.
///
/// A second family, `HealtheeSymbols`, is bundled as the glyph fallback. It is
/// deliberately NOT the theme's family and is excluded here by name.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/instrument_type.dart';
import 'package:healthee/core/theme/typography.dart';

/// The bundled fallback's file name. Not the theme's face; see the docstring.
const String kFallbackFace = 'InterFallback.ttf';

/// The `wght` axis range out of a variable font's own `fvar` table.
(int, int) _wghtAxis(String path) {
  final d = File(path).readAsBytesSync();
  final view = ByteData.sublistView(d);
  final tables = view.getUint16(4);
  int? fvar;
  for (var i = 0; i < tables; i++) {
    final rec = 12 + i * 16;
    final tag = String.fromCharCodes(d.sublist(rec, rec + 4));
    if (tag == 'fvar') fvar = view.getUint32(rec + 8);
  }
  expect(fvar, isNotNull, reason: '$path is not a variable font');
  final axesOffset = fvar! + view.getUint16(fvar + 4);
  final axisCount = view.getUint16(fvar + 8);
  for (var i = 0; i < axisCount; i++) {
    final a = axesOffset + i * 20;
    if (String.fromCharCodes(d.sublist(a, a + 4)) == 'wght') {
      // Fixed 16.16: the integer part is the whole-number weight.
      final min = view.getInt32(a + 4) >> 16;
      final max = view.getInt32(a + 12) >> 16;
      return (min, max);
    }
  }
  fail('$path has no wght axis');
}

void main() {
  test('the bundled family is the one the theme names', () {
    final vendored = Directory('assets/fonts')
        .listSync()
        .whereType<File>()
        .map((file) => file.uri.pathSegments.last)
        .where((name) => name.endsWith('.ttf'))
        .toList();

    expect(vendored, isNotEmpty);
    // The fallback is bundled on purpose and is not the theme's face.
    final faces = vendored.where((n) => n != kFallbackFace).toList();
    for (final face in faces) {
      expect(
        face,
        startsWith(healtheeFontFamily),
        reason:
            'two vendored text families is two things a TextStyle can name and '
            'one of them wrong — and the wrongness renders perfectly',
      );
    }
    expect(
      faces,
      hasLength(1),
      reason: 'Figtree is variable: one file, not one per weight',
    );
    expect(
      vendored,
      contains(kFallbackFace),
      reason:
          'the bundled fallback is load-bearing — Figtree has no U+2194, and a '
          'platform face does not beat the colour emoji font',
    );
  });

  test('EVERY WEIGHT THE APP ASKS FOR IS INSIDE THE VARIABLE AXIS', () {
    final asked = _weightsAskedFor();
    final (min, max) = _wghtAxis('assets/fonts/Figtree.ttf');
    expect(asked, isNotEmpty);
    final outside = asked.where((w) => w < min || w > max).toList();
    expect(
      outside,
      isEmpty,
      reason:
          'these weights are named in lib/ and lie outside the bundled fvar '
          'wght axis ($min-$max), so Flutter silently substitutes the nearest',
    );
    // Named, because it is the one that was wrong: legacy's numerals are bold.
    expect(asked, contains(700));
    expect(700, inInclusiveRange(min, max));
  });

  test('NOTHING ASKS FOR AN ITALIC — none is bundled to give', () {
    // Not a deferred vendoring job. Figtree publishes an italic; it is left
    // `wght` axis (200–800) and upstream publishes no italic companion —
    // measured off `Inter[wght].ttf`'s `fvar` table, not remembered. So the
    // app stopped asking, and this fails if it starts again.
    final asking = <String>[
      for (final file in _libSources())
        for (final line in file.readAsLinesSync())
          // Comments are excluded on purpose: `instrument_type.dart` explains
          // the removal at length and must be allowed to name what it removed.
          if (!line.trimLeft().startsWith('//') &&
              line.contains('FontStyle.italic'))
            '${file.path}: ${line.trim()}',
    ];
    expect(
      asking,
      isEmpty,
      reason:
          'an italic that renders upright is emphasis the reader never sees',
    );
    for (final style in _themeStyles()) {
      expect(style!.fontStyle ?? FontStyle.normal, FontStyle.normal);
    }
  });

  test('the whole text theme is one family, in the weights vendored', () {
    final vendored = _drawableWeights();
    for (final style in _themeStyles()) {
      expect(style!.fontFamily, healtheeFontFamily);
      expect(
        vendored,
        contains(style.fontWeight!.value),
        reason:
            'a weight the pubspec does not vendor is synthesised by the engine, '
            'which is a different drawing of the face nobody chose',
      );
      expect(style.fontFeatures, contains(const FontFeature.tabularFigures()));
    }
  });

  test('HType asks for exactly the four roles’ weights, and gets them', () {
    // The four roles ported from legacy's `HType`, at their ladder steps.
    // `number` is the one that was broken.
    final vendored = _drawableWeights();
    const ink = Color(0xFF000000);
    final roles = <String, TextStyle>{
      'serif': HType.serif(ink),
      'sans': HType.sans(ink),
      'number': HType.number(ink),
      'label': HType.label(ink),
    };
    for (final role in roles.entries) {
      expect(
        vendored,
        contains(role.value.fontWeight!.value),
        reason: 'HType.${role.key} asks for a weight the bundle does not have',
      );
    }
    expect(
      roles['number']!.fontWeight,
      FontWeight.w700,
      reason: 'legacy’s num',
    );
  });
}

/// The text-theme styles under test, in one place.
List<TextStyle?> _themeStyles() {
  final theme = healtheeTextTheme(
    ink: const Color(0xFF121217),
    ink2: const Color(0xFF56565F),
    ink3: const Color(0xFF6D6D7C),
  );
  return <TextStyle?>[
    theme.displayLarge,
    theme.displayMedium,
    theme.headlineMedium,
    theme.headlineSmall,
    theme.titleLarge,
    theme.titleMedium,
    theme.titleSmall,
    theme.bodyLarge,
    theme.bodyMedium,
    theme.bodySmall,
    theme.labelLarge,
    theme.labelMedium,
    theme.labelSmall,
  ];
}

/// Every `.dart` file under `lib/`, generated ones excluded.
List<File> _libSources() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'))
    .where((file) => !file.path.endsWith('.g.dart'))
    .where((file) => !file.path.endsWith('.drift.dart'))
    .toList();

/// Every numeric weight named anywhere in `lib/`, read out of the source.
Set<int> _weightsAskedFor() {
  final pattern = RegExp(r'FontWeight\.w(\d{3})');
  return <int>{
    for (final file in _libSources())
      for (final match in pattern.allMatches(file.readAsStringSync()))
        int.parse(match.group(1)!),
  };
}

/// Every weight `pubspec.yaml` declares under the one font family.
/// What the bundle can actually draw.
///
/// It used to read `weight:` lines out of `pubspec.yaml`, which was right while
/// four static instances were vendored. Figtree is variable and declares none,
/// so the answer now comes from the font's own `fvar` wght axis — every whole
/// hundred inside the range, which is what a `FontWeight` can name.
Set<int> _drawableWeights() {
  final (min, max) = _wghtAxis('assets/fonts/Figtree.ttf');
  final drawable = <int>{
    for (var w = 100; w <= 900; w += 100)
      if (w >= min && w <= max) w,
  };
  expect(drawable, isNotEmpty, reason: 'the bundled fvar wght axis is empty');
  return drawable;
}
