/// The non-widget half of the ported foundation: the corner, the motion scale
/// and the type roles.
///
/// Split from `instrument_primitives_test.dart` at the 400-line gate. These are
/// pure values, and pure values are exactly where a transcription goes wrong
/// without anything looking broken — a smoothness of 0.5, a curve of
/// `Curves.easeOut`, a label tracked in ems where the ladder tracks it in
/// pixels. None of those would fail to compile and none would fail a render.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/instrument_type.dart';
import 'package:healthee/core/theme/motion.dart';
import 'package:healthee/core/theme/shapes.dart';
import 'package:healthee/core/theme/tokens.dart';

const HealtheeColors _light = HealtheeColors.light();

void main() {
  group('hSquircle', () {
    test('is legacy’s continuous corner, at legacy’s smoothness', () {
      expect(kSquircleSmoothness, 0.6);
      final shape = hSquircle(Radii.card);
      expect(shape, isA<ShapeBorder>());
    });

    test('THE CARD SHAPE IS THE SQUIRCLE, not a rounded rectangle', () {
      // One definition of the corner in the app. A `RoundedRectangleBorder`
      // reappearing here would change every card on every screen.
      expect(hSquircle(Radii.card).runtimeType, isNot(RoundedRectangleBorder));
    });
  });

  group('HMotion', () {
    test('carries legacy’s four durations and its signature ease', () {
      expect(HMotion.fast, const Duration(milliseconds: 200));
      expect(HMotion.base, const Duration(milliseconds: 450));
      expect(HMotion.slow, const Duration(milliseconds: 950));
      expect(HMotion.stagger, const Duration(milliseconds: 40));
      expect(HMotion.curve, const Cubic(0.2, 0.7, 0.3, 1));
    });
  });

  group('the geometry tokens', () {
    test('the card, button and chip radii are the Instrument pass’s', () {
      expect(Radii.card, 20);
      expect(Radii.button, 12);
      expect(Radii.sheet, 24);
      // A chip is a pill: past half its height the radius clamps.
      expect(Radii.chip, 999);
    });

    test('the spacing rhythm', () {
      expect(Insets.lg, 16);
      expect(Insets.card, 20);
      expect(Insets.gutter, 20);
      expect(Insets.cardGap, 12);
      expect(Insets.section, 32);
    });

    test('the strokes: a hairline, a data line and a needle', () {
      expect(hairline, 1);
      expect(kDataLine, 2);
      expect(kNeedle, 3);
    });

    test('snapToPixel lands on a whole device pixel', () {
      expect(snapToPixel(1, 3), 1);
      expect(snapToPixel(0.5, 3), closeTo(2 / 3, 1e-9));
      expect(snapToPixel(10.2, 2), 10);
      expect(snapToPixel(10.3, 2), 10.5);
      for (final dpr in <double>[1, 1.5, 2, 2.625, 3]) {
        final device = snapToPixel(7.37, dpr) * dpr;
        expect(device, closeTo(device.roundToDouble(), 1e-9));
      }
    });
  });

  group('HType', () {
    test('every role is Figtree, and every role is tabular', () {
      for (final style in <TextStyle>[
        HType.serif(_light.ink),
        HType.sans(_light.ink),
        HType.number(_light.ink),
        HType.label(_light.ink3),
      ]) {
        expect(style.fontFamily, 'Figtree');
        expect(
          style.fontFeatures,
          contains(const FontFeature.tabularFigures()),
        );
      }
    });

    test('legacy’s default requests land on their ladder steps', () {
      // serif 23/400 → title2; sans 14/500 → callout; num 27/700 → title1.
      expect(HType.serif(_light.ink).fontSize, 20);
      expect(HType.serif(_light.ink).height! * 20, closeTo(26, 1e-9));
      expect(HType.serif(_light.ink).letterSpacing, -0.1);
      expect(HType.sans(_light.ink).fontSize, 13);
      expect(HType.sans(_light.ink).fontWeight, FontWeight.w400);
      expect(HType.number(_light.ink).fontSize, 28);
      expect(HType.number(_light.ink).fontWeight, FontWeight.w700);
      expect(HType.number(_light.ink).letterSpacing, -0.3);
      // The uppercase label: 12 px at 700, +0.72 px of tracking.
      expect(HType.label(_light.ink3).fontSize, 12);
      expect(HType.label(_light.ink3).fontWeight, FontWeight.w700);
      expect(HType.label(_light.ink3).letterSpacing, 0.72);
    });

    test('an off-ladder request is snapped, never honoured', () {
      expect(HType.sans(_light.ink, size: 14.5).fontSize, 15);
      expect(HType.sans(_light.ink, size: 11.5).fontSize, 12);
      expect(
        HType.sans(_light.ink, size: 13, weight: FontWeight.w700).fontWeight,
        FontWeight.w600,
      );
      expect(HType.serif(_light.ink, size: 24).fontSize, 28);
      // ModuleValue's unit: a 10 px weight-400 request is a caption...
      expect(
        HType.number(_light.ink, size: 10, weight: FontWeight.w400).fontSize,
        12,
      );
      // ...and so is a bold one: the ladder has no bold caption, and `label`
      // is asked for by name, for uppercase.
      expect(HType.number(_light.ink, size: 10).fontSize, 12);
      expect(HType.number(_light.ink, size: 10).fontWeight, FontWeight.w400);
    });
  });
}
