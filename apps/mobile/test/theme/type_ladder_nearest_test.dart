/// **`TypeLadder.nearest`: any requested size lands on a step.**
///
/// The `HType` builders take a free size (legacy's call sites passed 9, 11.5,
/// 14.5, 24...), and this is the function that snaps each one to the ladder.
/// Split from `type_ladder_test.dart` at the 400-line gate; that file pins the
/// steps and the named roles, this one pins the snapping rule.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/core/theme/type_ladder.dart';

void main() {
  group('TypeLadder.nearest', () {
    test('every request lands on a step', () {
      for (var size = 6.0; size <= 96; size += 0.5) {
        for (final chart in <bool>[false, true]) {
          final style = TypeLadder.nearest(
            size,
            weight: FontWeight.w400,
            chart: chart,
          );
          expect(TypeLadder.sizes, contains(style.fontSize), reason: '$size');
        }
      }
    });

    test('the rule, at its edges', () {
      double at(double size, {bool chart = false}) => TypeLadder.nearest(
        size,
        weight: FontWeight.w400,
        chart: chart,
      ).fontSize!;
      expect(at(9), 12);
      expect(at(9, chart: true), 11);
      expect(at(11.5, chart: true), 11);
      expect(at(12, chart: true), 12);
      expect(at(12.5), 12);
      expect(at(14), 13);
      expect(at(14.5), 15);
      expect(at(16), 15);
      expect(at(18), 17);
      expect(at(19), 20);
      expect(at(23), 20);
      expect(at(24), 28);
      expect(at(30), 28);
      expect(at(34), 40);
      expect(at(44), 40);
      expect(at(54), 64);
      expect(at(88), 64);
    });

    test('a strong request takes the strong step, never a chart’s', () {
      FontWeight weightAt(
        double size,
        FontWeight weight, {
        bool chart = false,
      }) => TypeLadder.nearest(size, weight: weight, chart: chart).fontWeight!;
      expect(weightAt(13, FontWeight.w700), FontWeight.w600);
      expect(weightAt(15, FontWeight.w600), FontWeight.w600);
      expect(weightAt(15, FontWeight.w500), FontWeight.w400);
      expect(weightAt(10, FontWeight.w700, chart: true), FontWeight.w400);
    });

    test(
      'a small bold request stays caption: the ladder has no bold caption',
      () {
        for (final size in <double>[9, 10, 11, 11.5, 12, 12.5]) {
          expect(
            TypeLadder.nearest(size, weight: FontWeight.w700),
            same(TypeLadder.caption),
            reason: '$size',
          );
        }
      },
    );
  });
}
