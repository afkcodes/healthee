/// Spacing, radii and rule widths — the non-colour half of the token set.
///
/// Split out of `tokens.dart` when the colour roles grew: that file's one reason
/// to change is the palette, and this one's is the geometry (Standards §1).
library;

/// Spacing scale. One rhythm, so gaps compose instead of accumulating.
///
/// Two generations live here until the Instrument pass lands: the t-shirt
/// sizes ([xs] to [xxl]) are what screens use today, and the role names
/// ([card], [gutter], [cardGap], [section]) are what the screen sweeps move
/// them onto. Where a role and a t-shirt size disagree, the role is the target.
abstract final class Insets {
  /// 4 — hairline gaps, chip padding.
  static const double xs = 4;

  /// 8 — between a label and its value.
  static const double sm = 8;

  /// 12 — inside a dense row.
  static const double md = 12;

  /// 16 — the general-purpose gap: today's page side padding
  /// (`InstrumentScreen`) and many cards' padding, until the Instrument pass
  /// moves those to [gutter] and [card].
  static const double lg = 16;

  /// 20 — a card's inner padding in the Instrument pass (the target for [lg]
  /// inside cards).
  static const double card = 20;

  /// 20 — the page's side margin in the Instrument pass (the target for [lg]
  /// at the page edge).
  static const double gutter = 20;

  /// 12 — between one card and the next in the Instrument pass.
  static const double cardGap = 12;

  /// 24 — a wide block gap, and a sheet's padding. Not the gap between cards:
  /// that is [cardGap].
  static const double xl = 24;

  /// 32 — between sections. The same value as [section], which is the name
  /// new code uses; this is the older alias.
  static const double xxl = 32;

  /// 32 — between one section and the next.
  static const double section = 32;
}

/// Corner radii — **legacy's ladder**, `theme.dart`'s `HRadius`, retuned.
///
/// Named by what wears them. Every radius is drawn as a **continuous-corner
/// squircle** (`shapes.dart`), never a circular arc.
abstract final class Radii {
  /// 20 — every module, card and banner.
  static const double card = 20;

  /// 24 — legacy's `xl`: sheets.
  static const double sheet = 24;

  /// 14 — legacy's `md`: badges and small tinted blocks.
  static const double badge = 14;

  /// 12 — buttons, and the value-shaped hole in a withheld card.
  static const double button = 12;

  /// Fully rounded — a chip is a pill. The same 999 as [pill]: a radius past
  /// half the height clamps to a semicircle, whatever the chip's size.
  static const double chip = 999;

  /// 6 — an inline hole, sitting on a single row.
  static const double inlineHole = 6;

  /// Fully rounded — pills, progress tracks, dots. Legacy's `pill`.
  static const double pill = 999;
}

/// The one border width the design uses for a rule or a card edge.
const double hairline = 1;

/// The stroke a data series is drawn with: a chart's line, a ring's arc.
const double kDataLine = 2;

/// The stroke of a needle or marker that points at a reading.
const double kNeedle = 3;

/// [logical] rounded to the nearest whole device pixel at [dpr].
///
/// A hairline or a stroke edge that falls between device pixels is antialiased
/// across two of them and reads soft and grey; snapping puts it on one.
double snapToPixel(double logical, double dpr) => (logical * dpr).round() / dpr;
