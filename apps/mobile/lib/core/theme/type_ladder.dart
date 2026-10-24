/// **The type ladder: the only sizes the app sets text at.**
///
/// Twelve steps on nine sizes. Every named style in the theme (`TypeScale`,
/// `KeyType`, `FormType`, `SleepType`, `MeterType`, `DateType`,
/// `HType` and the Material roles in `healtheeTextTheme`) is an alias of one of
/// these, so a size that is not on this list cannot be reached by naming a
/// style. Each step fixes size, line height, weight and tracking together,
/// and `type_ladder_test` pins the steps and every named role to them. It
/// does NOT police call sites: some still override a role's weight, tracking
/// or line height with `copyWith` (bold runs, spaced caps), and those are left
/// for the screen sweeps. The only call-site rule enforced today is that no
/// `fontSize` literal in `lib/` is below 11.
///
/// Every step is Figtree with tabular figures, and drives the variable font's
/// `wght` axis directly rather than relying on the weight slot alone.
///
/// ```text
///   step           size  line  weight  tracking
///   display         64    64    700    -1.25
///   metric          40    44    700    -0.6
///   title1          28    34    700    -0.3
///   title2          20    26    700    -0.1
///   headline        17    22    600     0
///   body            15    22    400     0
///   bodyStrong      15    22    600     0
///   callout         13    18    400     0
///   calloutStrong   13    18    600     0
///   label           12    16    700    +0.72   (text set in UPPERCASE)
///   caption         12    16    400     0
///   micro           11    14    400     0       (chart axes and end labels ONLY)
/// ```
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/typography.dart';

/// The ladder. Colourless: the tone supplies the colour at the point of use.
abstract final class TypeLadder {
  /// The hero figure: biological age, a night's duration.
  static final TextStyle display = _step(64, 64, FontWeight.w700, -1.25);

  /// A panel's or key number's own reading.
  static final TextStyle metric = _step(40, 44, FontWeight.w700, -0.6);

  /// A screen's title, and a secondary figure.
  static final TextStyle title1 = _step(28, 34, FontWeight.w700, -0.3);

  /// A section's or a sub-screen's title, and an inline figure.
  static final TextStyle title2 = _step(20, 26, FontWeight.w700, -0.1);

  /// A row's or a card's heading.
  static final TextStyle headline = _step(17, 22, FontWeight.w600, 0);

  /// Prose, and what is typed into a field.
  static final TextStyle body = _step(15, 22, FontWeight.w400, 0);

  /// [body] with weight: a card's own title.
  static final TextStyle bodyStrong = _step(15, 22, FontWeight.w600, 0);

  /// Dense prose: a row's sentence, a key number's line.
  static final TextStyle callout = _step(13, 18, FontWeight.w400, 0);

  /// [callout] with weight: a panel title, a button, a row's name.
  static final TextStyle calloutStrong = _step(13, 18, FontWeight.w600, 0);

  /// Uppercase marginalia. The caller uppercases the text; this does not.
  static final TextStyle label = _step(12, 16, FontWeight.w700, 0.72);

  /// The smallest prose: a note, a unit, a caption.
  static final TextStyle caption = _step(12, 16, FontWeight.w400, 0);

  /// Chart axes and a chart's end labels, and nothing else.
  static final TextStyle micro = _step(11, 14, FontWeight.w400, 0);

  /// Every size on the ladder, largest first.
  static const List<double> sizes = <double>[
    64,
    40,
    28,
    20,
    17,
    15,
    13,
    12,
    11,
  ];

  /// The step a requested [size] snaps to.
  ///
  /// Below 13 is [caption] ([micro] only when [chart] and below 12); 13 to 14
  /// is [callout], 14.5 to 16 [body], 17 and 18 [headline], 19 to 23 [title2],
  /// 24 to 33 [title1], 34 to 51 [metric], and 52 up [display]. A [weight] of
  /// 600 or more takes the strong step at callout and body, and only there:
  /// the ladder has no bold caption, so a small bold request stays [caption]
  /// (uppercase marginalia asks for [label] by name).
  static TextStyle nearest(
    double size, {
    required FontWeight weight,
    bool chart = false,
  }) {
    final strong = weight.value >= FontWeight.w600.value;
    if (size < 13) {
      return chart && size < 12 ? micro : caption;
    }
    if (size < 14.5) {
      return strong ? calloutStrong : callout;
    }
    if (size < 17) {
      return strong ? bodyStrong : body;
    }
    if (size < 19) {
      return headline;
    }
    if (size < 24) {
      return title2;
    }
    if (size < 34) {
      return title1;
    }
    return size < 52 ? metric : display;
  }

  static TextStyle _step(
    double size,
    double lineHeight,
    FontWeight weight,
    double tracking,
  ) => TextStyle(
    fontFamily: healtheeFontFamily,
    fontFamilyFallback: healtheeFontFallback,
    fontSize: size,
    fontWeight: weight,
    fontVariations: <FontVariation>[
      FontVariation('wght', weight.value.toDouble()),
    ],
    height: lineHeight / size,
    letterSpacing: tracking,
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
  );
}
