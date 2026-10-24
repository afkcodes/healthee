/// **SectionHead, ColourKey, ContextBridge and IconTile, measured.**
///
/// The other half of the v02 primitive set; see `v02_primitives_test.dart` for
/// the method and `_v02_harness.dart` for the pump both halves share.
///
/// ## The numbers are LITERALS, and that is the whole point
///
/// These assertions used to read `Panel.padding` and `ContextBridge.ruleLeft` —
/// the very constants under test — so changing 18 to 14 changed the expectation
/// with it and the suite stayed green. Mutation testing caught two survivors on
/// exactly that shape. Every number below is now restated from the CSS by hand,
/// the same method `v02_tokens_test.dart` uses for the palette: a transcription
/// checked against a transcription.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/shared/v02/colour_key.dart';
import 'package:healthee/shared/v02/context_bridge.dart';
import 'package:healthee/shared/v02/icon_tile.dart';
import 'package:healthee/shared/v02/section_head.dart';
import 'package:solar_icons/solar_icons.dart';

import '_v02_harness.dart';

void main() {
  group('SectionHead — the headline step, 12 above whatever follows', () {
    testWidgets('the title is 17px at 600 and the block ends 12 below it', (
      tester,
    ) async {
      await pumpV02(tester, const SectionHead(title: 'Last night'));
      final style = tester.widget<Text>(find.text('Last night')).style!;
      expect(style.fontSize, 17);
      expect(style.fontWeight, FontWeight.w600);
      expect(style.letterSpacing, 0);
      final head = tester.getRect(find.byType(SectionHead));
      final title = tester.getRect(find.text('Last night'));
      expect(head.bottom - title.bottom, 12);
    });
  });

  group('ColourKey — 6px dots, 5 to the label, 12 between entries', () {
    testWidgets('the dot is a 6px circle in the family', (tester) async {
      await pumpV02(
        tester,
        const ColourKey(<ColourKeyEntry>[ColourKeyEntry('Deep')]),
        tone: Tone.sleep,
      );
      final dot = tester.getRect(
        find.descendant(
          of: find.byType(ColourKey),
          matching: find.byType(Container),
        ),
      );
      expect(dot.width, 6);
      expect(dot.height, 6);
      final decoration = decorationOf(
        tester,
        find.descendant(
          of: find.byType(ColourKey),
          matching: find.byType(Container),
        ),
      );
      expect(groundOf(decoration), kHues.sleep);
      // A dot is a circle and stays a `BoxDecoration` — `hSquircle` is for
      // corners, and a superellipse of a circle is not one.
      // A dot is a circle and stays a `BoxDecoration` — `hSquircle` is for
      // corners, and a superellipse of a circle is not one.
      expect((decoration as BoxDecoration).shape, BoxShape.circle);
      expect(tester.getRect(find.text('Deep')).left - dot.right, 5);
    });

    testWidgets('an explicit colour overrides the family — stage legends', (
      tester,
    ) async {
      await pumpV02(
        tester,
        ColourKey(<ColourKeyEntry>[
          ColourKeyEntry('Deep', colour: kHues.stageDeep),
        ]),
        tone: Tone.sleep,
      );
      final decoration = decorationOf(
        tester,
        find.descendant(
          of: find.byType(ColourKey),
          matching: find.byType(Container),
        ),
      );
      expect(groundOf(decoration), kHues.stageDeep);
      expect(groundOf(decoration), isNot(kHues.sleep));
    });
  });

  group('ContextBridge — the left rule at 8, its dot at 6/23', () {
    testWidgets('rule, dot and text sit where the CSS puts them', (
      tester,
    ) async {
      await pumpV02(
        tester,
        // `leadIn: 0` — this case measures the CSS geometry, and the default
        // lead-in is blank height above the sentence that the rule spans so it
        // reaches the card above. There is no card above it here.
        ContextBridge.text(
          'Your resting heart rate followed it down.',
          leadIn: 0,
        ),
        tone: Tone.heart,
      );
      final bridge = tester.getRect(find.byType(ContextBridge));
      final rule = tester.getRect(
        find.descendant(
          of: find.byType(ContextBridge),
          matching: find.byType(ColoredBox),
        ),
      );
      // `.first`: the Container that carries the bottom border builds a
      // DecoratedBox of its own, and the Stack's own child order puts the dot
      // ahead of it.
      final dot = tester.getRect(
        find
            .descendant(
              of: find.byType(ContextBridge),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final text = tester.getRect(
        find.text('Your resting heart rate followed it down.'),
      );

      // `margin: 0 8px`, then `::before { left: 8px; width: 1px }`.
      expect(rule.left - bridge.left, 8 + 8);
      expect(rule.width, 1);
      expect(rule.height, bridge.height);
      // `::after { left: 6px; top: 23px; width: 5px; height: 5px }`.
      expect(dot.left - bridge.left, 8 + 6);
      expect(dot.top - bridge.top, 23);
      expect(dot.width, 5);
      expect(dot.height, 5);
      // `padding: 14px 4px 14px 26px`.
      expect(text.left - bridge.left, 8 + 26);
      expect(text.top - bridge.top, 14);
      expect(
        tester
            .widget<Text>(
              find.text('Your resting heart rate followed it down.'),
            )
            .style!
            .fontSize,
        12,
      );
    });

    testWidgets('the dot takes the family, so the bridge names its subject', (
      tester,
    ) async {
      await pumpV02(
        tester,
        ContextBridge.text('Sleep debt grew.', leadIn: 0),
        tone: Tone.sleep,
      );
      final decoration =
          tester
                  .widget<DecoratedBox>(
                    find
                        .descendant(
                          of: find.byType(ContextBridge),
                          matching: find.byType(DecoratedBox),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      expect(groundOf(decoration), kHues.sleep);
      // A dot is a circle and stays a `BoxDecoration` — `hSquircle` is for
      // corners, and a superellipse of a circle is not one.
      expect(decoration.shape, BoxShape.circle);
    });
  });

  group('IconTile — a bare 24 px ink2 glyph, no tile (the brief)', () {
    testWidgets('the box is the glyph, in ink2, with nothing behind it', (
      tester,
    ) async {
      await pumpV02(
        tester,
        const IconTile(SolarIconsOutline.wind),
        tone: Tone.oxygen,
        width: null,
      );
      final rect = tester.getRect(find.byType(IconTile));
      expect(rect.width, 24);
      expect(rect.height, 24);
      expect(
        find.descendant(
          of: find.byType(IconTile),
          matching: find.byType(DecoratedBox),
        ),
        findsNothing,
        reason: 'an icon is never drawn inside a tile, circle or tint',
      );
      final icon = tester.widget<Icon>(find.byIcon(SolarIconsOutline.wind));
      expect(icon.color, kColors.ink2);
      expect(icon.size, 24);
    });

    testWidgets('the family never reaches it, with or without a scope', (
      tester,
    ) async {
      await pumpV02(
        tester,
        const IconTile.chrome(SolarIconsOutline.wind),
        width: null,
      );
      expect(
        tester.widget<Icon>(find.byIcon(SolarIconsOutline.wind)).color,
        kColors.ink2,
      );
    });
  });
}
