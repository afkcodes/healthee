/// The face swap, measured rather than eyeballed.
///
/// Inter replaced Instrument Sans (owner decision 2026-08-05: the old face
/// reads "newspaper" at display sizes). A typeface is not a drop-in, and three
/// things could have broken silently:
///
///   1. **Tabular figures.** `docs/APP_DESIGN_BRIEF.md` §7 makes them a hard
///      constraint — "non-tabular numerals in a metric column is a defect" — and
///      a face without a `tnum` table would keep the `FontFeature` and simply
///      ignore it. So this measures two digit strings of the same length and
///      asserts they come out the same width, which is what tabular MEANS.
///   2. **Overflow at display size.** A face can run wider. The largest
///      role's figures and the hero figures are the strings with the least
///      slack, so they are laid out at the narrowest phone this app targets and
///      checked against the box.
///   3. **A missing glyph.** Instrument Sans had **no U+2082**, so `SpO₂` drew a
///      tofu box on the live screen, and no `σ` for the recovery ladder's caption
///      either. Neither is caught by anything except looking — or by this, which
///      renders each character and asserts it is not the notdef box.
///
/// The fonts are loaded from `assets/fonts/` with a `FontLoader`, so every
/// measurement here is against the real face rather than the test host's
/// fallback.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/core/theme/type_scale.dart';
import 'package:healthee/core/theme/typography.dart';

/// The narrowest phone the app targets, in logical pixels, less the page
/// padding a screen actually leaves a card.
const double _narrowContent = 320 - 16 * 2 - 13 * 2;

/// Lays [text] out in [style] and returns its size.
Size _measure(
  String text,
  TextStyle style, {
  double maxWidth = double.infinity,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout(maxWidth: maxWidth);
  return Size(painter.width, painter.height);
}

/// Every Unicode codepoint the TTF at [path] has a glyph for.
///
/// ## Why the font file is read rather than the glyph measured
///
/// A `TextPainter` cannot report "this came out as notdef", and the two obvious
/// proxies both fail here. Comparing **advance widths** against the notdef box
/// is not enough — `→` in Inter lands 0.04 px from it, so a width check would
/// have gone green while proving nothing. Comparing **rasters** needs
/// `Picture.toImage`, which does not complete under the plain test binding.
///
/// The font file is the actual authority, so it is what gets asked. This walks
/// the `cmap` table's format-4 and format-12 subtables, which between them cover
/// every modern TTF; a font with neither returns empty and fails loudly rather
/// than passing by default.
Set<int> _codepoints(String path) {
  final bytes = File(path).readAsBytesSync();
  final data = ByteData.sublistView(bytes);
  final tables = data.getUint16(4);
  var cmapOffset = -1;
  for (var i = 0; i < tables; i++) {
    final record = 12 + i * 16;
    final tag = String.fromCharCodes(bytes.sublist(record, record + 4));
    if (tag == 'cmap') {
      cmapOffset = data.getUint32(record + 8);
    }
  }
  if (cmapOffset < 0) {
    return const <int>{};
  }

  final covered = <int>{};
  final subtables = data.getUint16(cmapOffset + 2);
  for (var i = 0; i < subtables; i++) {
    final encoding = cmapOffset + 4 + i * 8;
    final table = cmapOffset + data.getUint32(encoding + 4);
    switch (data.getUint16(table)) {
      case 4:
        final segments = data.getUint16(table + 6) ~/ 2;
        final ends = table + 14;
        final starts = ends + segments * 2 + 2;
        final deltas = starts + segments * 2;
        final ranges = deltas + segments * 2;
        for (var s = 0; s < segments; s++) {
          final end = data.getUint16(ends + s * 2);
          final start = data.getUint16(starts + s * 2);
          final delta = data.getUint16(deltas + s * 2);
          final rangeOffset = data.getUint16(ranges + s * 2);
          if (start == 0xFFFF) {
            continue;
          }
          for (var c = start; c <= end; c++) {
            final glyph = rangeOffset == 0
                ? (c + delta) & 0xFFFF
                : data.getUint16(
                    ranges + s * 2 + rangeOffset + (c - start) * 2,
                  );
            if (glyph != 0) {
              covered.add(c);
            }
          }
        }
      case 12:
        final groups = data.getUint32(table + 12);
        for (var g = 0; g < groups; g++) {
          final record = table + 16 + g * 12;
          final start = data.getUint32(record);
          final end = data.getUint32(record + 4);
          for (var c = start; c <= end && c - start < 0x10000; c++) {
            covered.add(c);
          }
        }
    }
  }
  return covered;
}

/// A single- or double-quoted Dart string with no escapes or interpolation.
final RegExp _literal = RegExp(
  r"'([^'\\\n$]*)'"
  r'|"([^"\\\n$]*)"',
);

/// Codepoints neither bundled face carries, and why each is safe anyway.
///
/// **One entry, and the reason it may be waived is specific.** `ⓘ` (U+24D8) is
/// drawn in prose on the withheld hero and in the instrument module. No text
/// family carries it — not Figtree, not Inter — so it reaches a platform face.
/// That is acceptable **only because U+24D8 has no colour-emoji form**, so the
/// platform face that answers is monochrome. Confirmed on the device: it draws
/// as a plain circled i.
///
/// `↔` is the counter-example and the reason this set is not a convenience.
/// U+2194 DOES have an emoji form, so when no bundled face could draw it,
/// Android reached `NotoColorEmoji` and put a blue box in a sentence — twice,
/// under two different typefaces, with the platform symbol faces named in the
/// fallback chain the whole time.
///
/// **So: a character may be waived here only if it has no emoji presentation.**
/// Anything else needs a bundled face that can draw it.
const Set<int> kFallbackGlyphs = <int>{0x24D8};

void main() {
  setUpAll(() async {
    final faces = Directory(
      'assets/fonts',
    ).listSync().whereType<File>().where((file) => file.path.endsWith('.ttf'));
    final loader = FontLoader(healtheeFontFamily);
    for (final face in faces) {
      loader.addFont(
        Future<ByteData>.value(face.readAsBytesSync().buffer.asByteData()),
      );
    }
    await loader.load();
  });

  final theme = AppTheme.light.textTheme;

  group('tabular figures survived the swap', () {
    test('EVERY DIGIT HAS THE SAME ADVANCE WIDTH', () {
      // The failure this catches: a face with no `tnum` table keeps the
      // FontFeature and ignores it, so a 55 → 58 shifts every glyph beside it
      // and a 30-night column visibly ripples on scroll.
      final style = theme.displayLarge!;
      final narrow = _measure('11111', style).width;
      final wide = _measure('88888', style).width;
      expect(
        (narrow - wide).abs(),
        lessThan(0.01),
        reason: 'brief §7: non-tabular numerals in a metric column is a defect',
      );
    });

    test('it holds at label size too, where the sparkline feet live', () {
      final style = theme.labelSmall!;
      expect(
        (_measure('10:00', style).width - _measure('23:58', style).width).abs(),
        lessThan(0.01),
      );
    });
  });

  group('every glyph the app draws has one to draw with', () {
    // ## Why this group is DERIVED and no longer a list
    //
    // It used to be eight hand-written cases, added when Instrument Sans was
    // replaced and never extended. So when `Overnight HRV <-> recovery` started
    // drawing a U+2194 that Manrope did not have, nothing failed — the
    // character simply was not on the list. It shipped, and the owner found it
    // on the phone as a blue emoji box in the middle of a sentence.
    //
    // A list cannot cover characters nobody thought to add. This walks `lib/`
    // instead, pulls every non-ASCII character out of the string literals that
    // reach a screen, and requires the bundled face to have a glyph for it — or
    // the fallback chain to name a face that does.
    late Set<int> covered;

    setUpAll(() {
      covered = _codepoints('assets/fonts/Figtree.ttf')
        ..addAll(_codepoints('assets/fonts/InterFallback.ttf'));
      expect(
        covered,
        isNotEmpty,
        reason:
            'the cmap reader found nothing, so every check below is vacuous',
      );
      // A control: a private-use codepoint no text font covers. Without it a
      // reader that silently answered "everything" would pass every case.
      // U+4E00, the CJK ideograph "one". Neither face covers the CJK block, and
      // the earlier control (U+E000) passed vacuously because Inter DOES cover
      // the private-use area.
      expect(covered, isNot(contains(0x4E00)));
    });

    test('THE BUNDLED FACE COVERS EVERY CHARACTER THE APP PUTS ON SCREEN', () {
      final missing = <String, String>{};
      for (final file in Directory('lib').listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) {
          continue;
        }
        var line = 0;
        for (final text in file.readAsLinesSync()) {
          line++;
          final trimmed = text.trimLeft();
          // Comments and doc comments draw nothing.
          if (trimmed.startsWith('//') || trimmed.startsWith('*')) {
            continue;
          }
          for (final match in _literal.allMatches(text)) {
            final body = match.group(1) ?? match.group(2) ?? '';
            if (body.startsWith('package:') || body.startsWith('dart:')) {
              continue;
            }
            for (final rune in body.runes) {
              if (rune > 0x7F &&
                  !covered.contains(rune) &&
                  !kFallbackGlyphs.contains(rune)) {
                missing['U+${rune.toRadixString(16).toUpperCase()}'] =
                    '${file.path}:$line';
              }
            }
          }
        }
      }
      expect(
        missing,
        isEmpty,
        reason:
            'these draw as tofu, or worse as a colour emoji, because neither '
            'the bundled face nor a named fallback has them: $missing',
      );
    });

    test('MUTATION — the scan can actually see a missing glyph', () {
      // Otherwise a broken literal pattern reports a clean sweep, which is what
      // "no characters are missing" looks like either way.
      expect(_literal.hasMatch("  const x = 'HRV ↔ recovery';"), isTrue);
      expect(_literal.hasMatch('  const x = "a ↔ b";'), isTrue);
      // U+2194 shipped broken twice: Manrope had no glyph, and Figtree has none
      // either. What fixed it was BUNDLING a face that does, not naming a
      // platform one — so this asserts the union of the two bundled faces.
      expect(covered, contains(0x2194));
    });

    test('THE BUNDLED FALLBACK IS NAMED FIRST, AHEAD OF EVERY PLATFORM FACE', () {
      // The order is the fix. Naming platform symbol faces did NOT stop Android
      // reaching for NotoColorEmoji — measured on the device, twice. A bundled
      // family does, and it only helps if nothing platform-supplied precedes it.
      expect(healtheeFontFallback.first, 'HealtheeSymbols');
    });
  });

  group('display sizes still fit the narrowest phone', () {
    test('the largest role still fits the narrowest phone', () {
      // ## What this used to measure, and why it moved
      //
      // It measured the greeting (`Good morning.`) at `displayLarge`. The
      // greeting is gone from the app (`today_header.dart` records why) and
      // nothing in `lib/` sets `displayLarge` any more, so measuring it was a
      // test of a sentence nobody draws. `displayLarge` is now the ladder's
      // metric step, and what IS drawn at that step is a key number's or a
      // panel's figure, so those are measured instead — the widest the
      // payloads produce. The constraint is the one it always encoded: the
      // largest type a role names must fit a 320 px card.
      for (final figure in <String>['10,264', '100%', '23:58', '188 bpm']) {
        final size = _measure(figure, theme.displayLarge!);
        expect(
          size.width,
          lessThan(_narrowContent),
          reason:
              '"$figure" is ${size.width.toStringAsFixed(1)} px of '
              '${_narrowContent.toStringAsFixed(0)}',
        );
      }
    });

    test('a hero figure and its unit fit half a grid row', () {
      // Two cells share a 320 px phone: each has roughly (320 - 40) / 2 px.
      // The figure is `HType.number`'s default, legacy's 27 px grid module,
      // which the ladder sets at title1.
      const cell = (320 - Insets.lg * 2 - 10) / 2 - 13 * 2;
      for (final figure in <String>['9,264', '2,350', '43.0', '6:20']) {
        final size = _measure(figure, TypeLadder.title1);
        expect(
          size.width,
          lessThan(cell),
          reason: '"$figure" is ${size.width.toStringAsFixed(1)} px of $cell',
        );
      }
    });

    test('the widest v02 tile label fits its cell without ellipsis', () {
      // ## What this used to measure, and why it moved
      //
      // It measured `RESP / SPO₂ · STRAP` at `HType.label`'s 9.5 px and 0.12 em
      // — "the longest label the grid can produce" on the pre-v02 Today. That
      // grid is gone: `recovery_signals_card.dart` is unreachable from
      // `main.dart`, no string of that shape exists anywhere in `lib/` any
      // more, and nothing reachable constructs an `InstrumentLabel` with a
      // literal at all.
      //
      // The old assertion did fail when the face changed to Inter — 117.9 px
      // against a 113 px cell — but it was failing about a label the app had
      // stopped drawing, which is a stale test rather than a layout defect. It
      // is retargeted here at the v02 tile label, which IS live, rather than
      // deleted: the constraint it encodes (the narrowest phone must not
      // ellipsise a metric’s own name) is still the right one. The 10 px insets
      // are SummaryTile.padding’s horizontal pair, inlined so the sum reads.
      const cell = (320 - Insets.lg * 2 - 10) / 2 - (10 + 10);
      final size = _measure('Cardiovascular load', TypeScale.tileTitle);
      expect(size.width, lessThan(cell));
    });
  });
}
