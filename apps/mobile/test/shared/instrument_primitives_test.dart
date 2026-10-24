/// The widgets ported from `ui.dart` that v02 still draws — measured, not
/// merely rendered.
///
/// It would be easy to test only that these render. What is actually
/// load-bearing is their **geometry**: a module that pads at 13 instead of 14,
/// an eyebrow at the wrong tracking. Both are invisible in a diff and visible
/// on a phone.
///
/// ## What left, and why
///
/// Three groups lived here — `HDeltaBadge`, `HProgressBar` and `SectionHeading`
/// — including the polarity mutation that proved `good: true` flips a verdict
/// colour. All three widgets became unreachable from `main.dart` in the v02
/// redesign and are deleted, so their assertions are gone with them rather than
/// kept green against code nothing draws.
///
/// The pure values these lean on — the corner, the curve, the type roles — are
/// in `instrument_tokens_test.dart`; the skeletons are in `skeletons_test.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/core/theme/instrument_hues.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/shared/instrument/h_icon_badge.dart';
import 'package:healthee/shared/instrument/h_tap.dart';
import 'package:healthee/shared/instrument_module.dart';
import 'package:solar_icons/solar_icons.dart';

import '_v02_harness.dart';

const HealtheeColors _light = HealtheeColors.light();
const InstrumentHues _hues = InstrumentHues.light();

Widget _host(Widget child, {ThemeData? theme}) => MaterialApp(
  theme: theme ?? AppTheme.light,
  home: Scaffold(
    body: Center(child: SizedBox(width: 320, child: child)),
  ),
);

/// A host with NO width constraint, for widgets that size themselves.
Widget _tightHost(Widget child) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(body: Center(child: child)),
);

TextStyle _styleOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text).first).style!;

void main() {
  group('HTap', () {
    testWidgets('a null onTap is a PASS-THROUGH, with no detector at all', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const HTap(child: Text('quiet'))));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(HTap),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
      );
    });

    testWidgets('SCALES TO 97.5% UNDER THE FINGER, and back', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(HTap(onTap: () => taps++, child: const Text('press'))),
      );
      await tester.pumpAndSettle();

      double scale() =>
          tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;
      expect(scale(), 1);

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('press')),
      );
      await tester.pump();
      expect(scale(), 0.975, reason: 'legacy’s `.tap:active { scale(0.975) }`');

      await gesture.up();
      await tester.pumpAndSettle();
      expect(scale(), 1);
      expect(taps, 1);
    });
  });

  group('HIconBadge and HAvatar', () {
    testWidgets('the badge is legacy’s 40 px at 18% of its own colour', (
      tester,
    ) async {
      await tester.pumpWidget(
        _tightHost(HIconBadge(SolarIconsOutline.moonSleep, color: _hues.sleep)),
      );
      await tester.pumpAndSettle();

      expect(tester.getSize(find.byType(HIconBadge)), const Size(40, 40));
      final box = tester.widget<Container>(find.byType(Container));
      expect(groundOf(box.decoration!)!.a, closeTo(0.18, 0.005));
      expect(tester.widget<Icon>(find.byType(Icon)).size, 20);
    });

    testWidgets('the avatar is 38 px of accent with the letter on the ladder', (
      tester,
    ) async {
      await tester.pumpWidget(_tightHost(const HAvatar('A')));
      await tester.pumpAndSettle();

      expect(tester.getSize(find.byType(HAvatar)), const Size(38, 38));
      // 42% of 38 is a 15.96 px bold request, which snaps to bodyStrong.
      expect(_styleOf(tester, 'A').fontSize, 15);
      expect(_styleOf(tester, 'A').fontWeight, FontWeight.w600);
      expect(_styleOf(tester, 'A').color, _light.onAccent);
    });
  });

  group('InstrumentModule', () {
    testWidgets('LEGACY’S 14 PX PADDING, AND NO IDENTITY DOT', (tester) async {
      await tester.pumpWidget(
        _host(
          InstrumentModule(
            label: 'Sleep',
            tag: _hues.sleep,
            children: const <Widget>[ModuleValue(value: '7:50', unit: 'hrs')],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final padding = tester.widget<Padding>(
        find
            .descendant(
              of: find.byType(InstrumentModule),
              matching: find.byType(Padding),
            )
            .first,
      );
      expect(padding.padding, const EdgeInsets.all(14));

      // THE DOT IS GONE — owner-directed, 2026-08-06: *"can we remove that
      // colored dots from cards"*. Legacy draws a 6 px circle in the metric's
      // hue at the top right of every module and this port drew it too. The hue
      // is still DECLARED (`tag`, asserted in `moved_card_tags_test.dart`) and
      // still tints the module's chart; nothing paints it as a mark.
      final circles = tester
          .widgetList<Container>(find.byType(Container))
          .where(
            (container) =>
                (container.decoration as BoxDecoration?)?.shape ==
                BoxShape.circle,
          );
      expect(circles, isEmpty, reason: 'the identity dot is not drawn');
      expect(
        tester.widget<InstrumentModule>(find.byType(InstrumentModule)).tag,
        _hues.sleep,
        reason: 'the hue is still the module’s declared identity',
      );
    });

    testWidgets(
      'the eyebrow is uppercase on screen and NOT to a screen reader',
      (tester) async {
        await tester.pumpWidget(_host(const ModuleLabel('Resting HR')));
        await tester.pumpAndSettle();

        expect(find.text('RESTING HR'), findsOneWidget);
        expect(_styleOf(tester, 'RESTING HR').fontSize, 12);
        expect(_styleOf(tester, 'RESTING HR').fontWeight, FontWeight.w700);
        final handle = tester.ensureSemantics();
        expect(find.bySemanticsLabel('Resting HR'), findsOneWidget);
        handle.dispose();
      },
    );

    testWidgets('the value is title1 with its unit a caption on the baseline', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const ModuleValue(value: '7:50', unit: 'hrs')),
      );
      await tester.pumpAndSettle();
      expect(_styleOf(tester, '7:50').fontSize, 28);
      expect(_styleOf(tester, 'hrs').fontSize, 12);
      expect(_styleOf(tester, 'hrs').fontWeight, FontWeight.w400);
      expect(_styleOf(tester, 'hrs').color, _light.ink2);
    });

    testWidgets('a module that opens PRESSES, it does not ripple', (
      tester,
    ) async {
      var opened = 0;
      await tester.pumpWidget(
        _host(
          InstrumentModule(
            label: 'Sleep',
            tag: _hues.sleep,
            onOpen: () => opened++,
            children: const <Widget>[Text('7:50')],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byType(InkWell),
        findsNothing,
        reason: 'legacy scales, not ripples',
      );
      expect(find.byType(HTap), findsOneWidget);
      await tester.tap(find.byType(InstrumentModule));
      await tester.pumpAndSettle();
      expect(opened, 1);
    });

    testWidgets('the foot is the label step, 8 px above', (tester) async {
      await tester.pumpWidget(_host(const ModuleFoot('goal 10,000 · 84%')));
      await tester.pumpAndSettle();
      final style = _styleOf(tester, 'GOAL 10,000 · 84%');
      expect(style.fontSize, 12);
      expect(style.letterSpacing, 0.72);
      expect(
        tester.widget<Padding>(find.byType(Padding).first).padding,
        const EdgeInsets.only(top: 8),
      );
    });
  });
}
