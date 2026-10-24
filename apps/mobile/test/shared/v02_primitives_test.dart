/// **Panel, PanelHead and SummaryTile, measured.** Every assertion is a
/// rectangle, a radius or a painted colour — never "the widget is there".
///
/// This project has the receipt for why: two charts shipped at zero height
/// because their tests only asserted presence, and a panel whose padding is 8
/// instead of 18 is present in exactly the same way. The prototype's numbers are
/// the specification, so the numbers are what is checked.
///
/// The rest of the set is measured the same way in `v02_layout_test.dart`; both
/// halves pump through `_v02_harness.dart`, so neither can drift into measuring
/// a different thing. Geometry is read from the laid-out render tree
/// (`tester.getRect`) and decoration from the `Container`s that carry it.
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
import 'package:healthee/shared/v02/panel.dart';
import 'package:healthee/shared/v02/panel_head.dart';
import 'package:healthee/shared/v02/summary_tile.dart';

import '_v02_harness.dart';

void main() {
  group('Panel — 20px padding, 20px radius, no border (the brief)', () {
    testWidgets('the content box is inset by the padding alone', (
      tester,
    ) async {
      // The owner's brief replaced the prototype's 18px padding and 1px border
      // with 20px and no border, so content starts 20 from the outer edge.
      const bodyKey = Key('body');
      await pumpV02(
        tester,
        const Panel(child: SizedBox(key: bodyKey, height: 40)),
      );
      final panel = tester.getRect(find.byType(Panel));
      final body = tester.getRect(find.byKey(bodyKey));
      expect(panel.width, kContentWidth);
      expect(body.left - panel.left, 20);
      expect(panel.right - body.right, 20);
      expect(body.top - panel.top, 20);
      expect(panel.bottom - body.bottom, 20);
      expect(panel.height, 40 + 2 * 20);
    });

    testWidgets('the surface and the 20px corner are painted, with NO border', (
      tester,
    ) async {
      await pumpV02(tester, const Panel(child: SizedBox(height: 10)));
      final decoration = decorationOf(
        tester,
        find.descendant(
          of: find.byType(Panel),
          matching: find.byType(Container),
        ),
      );
      expect(groundOf(decoration), kColors.surface);
      expect(radiusOf(decoration), 20);
      expect(edgeOf(decoration), isNull);
    });

    testWidgets('a head sits exactly 12 above the body', (tester) async {
      const headKey = Key('head');
      const bodyKey = Key('body');
      await pumpV02(
        tester,
        const Panel(
          head: SizedBox(key: headKey, height: 20),
          child: SizedBox(key: bodyKey, height: 30),
        ),
      );
      expect(
        tester.getRect(find.byKey(bodyKey)).top -
            tester.getRect(find.byKey(headKey)).bottom,
        12,
      );
    });

    testWidgets(
      'a declared tone does not tint the head: ink2 icon, accent action',
      (tester) async {
        await pumpV02(
          tester,
          const Panel(
            tone: Tone.sleep,
            head: PanelHead(
              title: 'Sleep',
              icon: Icons.bedtime,
              actionLabel: 'Details',
            ),
            child: SizedBox(height: 10),
          ),
        );
        expect(
          tester.widget<Icon>(find.byIcon(Icons.bedtime)).color,
          kColors.ink2,
        );
        final action = tester.widget<Text>(find.text('Details'));
        final button = tester.widget<TextButton>(find.byType(TextButton));
        expect(
          button.style!.foregroundColor!.resolve(<WidgetState>{}),
          kColors.accent,
        );
        expect(action.data, 'Details');
      },
    );
  });

  group('PanelHead — 16px icon, 8px gaps, the calloutStrong title', () {
    testWidgets('the icon is 16 and the title starts 8 after it', (
      tester,
    ) async {
      await pumpV02(
        tester,
        const PanelHead(title: 'Resting heart rate', icon: Icons.favorite),
      );
      final icon = tester.getRect(find.byIcon(Icons.favorite));
      final title = tester.getRect(find.text('Resting heart rate'));
      expect(icon.width, 16);
      expect(icon.height, 16);
      expect(title.left - icon.right, 8);
    });

    testWidgets('the title is 13px at weight 600', (tester) async {
      await pumpV02(tester, const PanelHead(title: 'Resting heart rate'));
      final style = tester.widget<Text>(find.text('Resting heart rate')).style!;
      expect(style.fontSize, 13);
      expect(style.fontWeight, FontWeight.w600);
      expect(style.color, kColors.ink);
    });

    testWidgets('the action is a 12px caption and no shorter than 28', (
      tester,
    ) async {
      await pumpV02(
        tester,
        const PanelHead(title: 'Steps', actionLabel: 'History'),
      );
      final button = tester.widget<TextButton>(find.byType(TextButton));
      final label = button.style!.textStyle!.resolve(<WidgetState>{})!;
      expect(label.fontSize, 12);
      expect(label.fontWeight, FontWeight.w400);
      expect(
        tester.getRect(find.byType(TextButton)).height,
        greaterThanOrEqualTo(28),
      );
    });
  });

  group('SummaryTile — 18px radius, family-soft ground, micro-track', () {
    testWidgets('padding is 14 top, 10 sides, 10 bottom', (tester) async {
      await pumpV02(
        tester,
        const SummaryTile(title: 'Steps', value: '8,214', tone: Tone.movement),
      );
      final tile = tester.getRect(find.byType(SummaryTile));
      final title = tester.getRect(find.text('Steps'));
      final value = tester.getRect(find.text('8,214'));
      expect(title.left - tile.left, 10);
      expect(title.top - tile.top, 14);
      expect(tile.bottom - value.bottom, 10);
    });

    testWidgets('the ground is family-soft and the label is family', (
      tester,
    ) async {
      await pumpV02(
        tester,
        const SummaryTile(title: 'Steps', value: '8,214', tone: Tone.movement),
      );
      final decoration = decorationOf(
        tester,
        find.descendant(
          of: find.byType(SummaryTile),
          matching: find.byType(Container),
        ),
      );
      expect(groundOf(decoration), kHues.movementSoft);
      expect(radiusOf(decoration), 18);
      expect(
        tester.widget<Text>(find.text('Steps')).style!.color,
        kHues.movement,
      );
    });

    testWidgets('the value is 28px and the meta 12px, 10 and 24 apart', (
      tester,
    ) async {
      await pumpV02(
        tester,
        const SummaryTile(
          title: 'Steps',
          value: '8,214',
          meta: 'goal 10,000',
          tone: Tone.movement,
        ),
      );
      final title = tester.getRect(find.text('Steps'));
      final value = tester.getRect(find.text('8,214'));
      final meta = tester.getRect(find.text('goal 10,000'));
      expect(value.top - title.bottom, 10);
      // 24, not 4: a tile with no fraction now KEEPS the meter's slot, so its
      // meta sits on the same baseline as a tile that has one. Three tiles of
      // different internal rhythm in one row read as three kinds of thing.
      expect(meta.top - value.bottom, closeTo(24, 0.5));
      expect(tester.widget<Text>(find.text('8,214')).style!.fontSize, 28);
      expect(tester.widget<Text>(find.text('goal 10,000')).style!.fontSize, 12);
    });

    testWidgets('the micro-track is 5 high, 14 down, gapped 3, first 4 solid', (
      tester,
    ) async {
      await pumpV02(
        tester,
        const SummaryTile(
          title: 'Steps',
          value: '8,214',
          meta: 'goal 10,000',
          tone: Tone.movement,
          segments: 7,
        ),
      );
      final meta = tester.getRect(find.text('goal 10,000'));
      final track = tester.getRect(find.byType(MicroTrack));
      expect(track.top - meta.bottom, 14);
      expect(track.height, 5);

      final segments = find.descendant(
        of: find.byType(MicroTrack),
        matching: find.byType(DecoratedBox),
      );
      expect(segments, findsNWidgets(7));
      final rects = <Rect>[
        for (var i = 0; i < 7; i++) tester.getRect(segments.at(i)),
      ];
      for (var i = 1; i < rects.length; i++) {
        expect(
          rects[i].left - rects[i - 1].right,
          closeTo(3, 0.01),
          reason: 'gap $i',
        );
        expect(rects[i].width, closeTo(rects[0].width, 0.01));
      }
      for (var i = 0; i < 7; i++) {
        final fill =
            (tester.widget<DecoratedBox>(segments.at(i)).decoration
                    as BoxDecoration)
                .color!;
        expect(
          fill.a,
          i < 4 ? 1.0 : closeTo(0.45, 0.001),
          reason: 'segment $i',
        );
      }
    });
  });
}
