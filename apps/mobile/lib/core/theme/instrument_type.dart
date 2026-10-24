/// Legacy's type roles, wearing Figtree and snapped to the ladder.
///
/// **Ported from** `healthee-legacy/app/lib/ui/theme.dart`'s `HType`. The role
/// names are legacy's, so a ported screen reads the same as the legacy screen it
/// came from; the metrics are not any more. Every role resolves to a step on
/// `type_ladder.dart`: [serif], [sans] and [number] take legacy's size and
/// weight as a request and [TypeLadder.nearest] snaps it, and [label] is the
/// ladder's own uppercase step. A call site therefore cannot set a size, line
/// height or tracking the ladder does not have.
///
/// ```text
///   legacy                          here
///   ────────────────────────────    ──────────────────
///   Newsreader   (serif display)    Figtree
///   Hanken Grotesk (UI sans)        Figtree
///   Space Mono   (numerals, labels) Figtree (tabular figures)
/// ```
///
/// Three faces became one, and one of the three was a **monospace**. That is not
/// a loss for the thing a mono face was doing here: every ladder step turns
/// `FontFeature.tabularFigures()` on, so a column of numbers still holds its
/// glyph advances.
///
/// ## [serif] is not serif
///
/// It keeps legacy's name and legacy's default request (23 px, weight 400),
/// which the ladder resolves to [TypeLadder.title2]. It renders in Figtree.
///
/// ## The italic is GONE, and that is a finding rather than a deferral
///
/// [serif] used to take an `italic` flag, legacy's greeting passed it, and two
/// cards set `FontStyle.italic` on a source line. **All three rendered upright.**
/// Flutter does not synthesise a slant for a bundled family, so what looked like
/// three deliberate emphases were three parameters doing nothing — the exact
/// shape of a dead control, and invisible because the text still rendered
/// perfectly. No italic is bundled, because nothing in the app sets one;
/// `test/core/typography_test.dart` fails if the app starts asking for one.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/type_ladder.dart';

/// Legacy's type roles. One source of truth, exactly as `HType` was.
abstract final class HType {
  /// Display text — a sheet's title, a verdict word. Legacy's `HType.serif`
  /// (23 px, weight 400) is the default request; see the library docstring.
  static TextStyle serif(
    Color color, {
    double size = 23,
    FontWeight weight = FontWeight.w400,
  }) => TypeLadder.nearest(size, weight: weight).copyWith(color: color);

  /// UI prose. Legacy's `HType.sans` (14 px, weight 500) is the default request.
  static TextStyle sans(
    Color color, {
    double size = 14,
    FontWeight weight = FontWeight.w500,
  }) => TypeLadder.nearest(size, weight: weight).copyWith(color: color);

  /// The instrument readout. Legacy's `HType.num` (27 px, weight 700) is the
  /// default request, which the ladder resolves to [TypeLadder.title1].
  static TextStyle number(
    Color color, {
    double size = 27,
    FontWeight weight = FontWeight.w700,
  }) => TypeLadder.nearest(size, weight: weight).copyWith(color: color);

  /// The uppercase label under everything: [TypeLadder.label]. The caller
  /// uppercases the text; legacy's 9 px and per-call tracking are gone with it.
  static TextStyle label(Color color) =>
      TypeLadder.label.copyWith(color: color);
}
