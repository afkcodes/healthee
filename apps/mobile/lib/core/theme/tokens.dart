/// Semantic colour roles, reachable from any widget as `context.colors`.
///
/// Feature code names a ROLE (`colors.ink3`, `colors.unf`) and never a value.
/// That is what makes both themes real: a widget written against roles is correct
/// in dark mode by construction; one written against hex is a bug nobody sees
/// until they toggle.
///
/// A `ThemeExtension` rather than top-level constants precisely so it varies with
/// the theme — and rather than Flutter's `ColorScheme`, which has no room for
/// "the fill of a number-shaped absence" and would only let us hide it in
/// `tertiaryContainer` under a name that lies.
///
/// ## Three naming decisions, because each replaced something
///
/// **[hole] is a FILL, not a hue.** A withheld value is drawn as a dashed [line]
/// border around a value-shaped box filled with [hole], at the size and position
/// the number would have had. Colour is rationed to judgement, so tinting a
/// refusal would make "we are declining to tell you" look like a verdict about
/// the owner's body. It is the opposite of one.
///
/// **[unf] is not a `warn`.** `unf` says *this reading is below your normal* — a
/// claim about the owner. A withhold says *we are not going to tell you* — a
/// claim about us. Colouring a refusal `unf` asserts the thing it declines.
///
/// **[alert] is the illness flag alone.** A failed network call is not a fact
/// about the owner's health, so it gets no health colour. `ColorScheme.error` is
/// still wired to [alert] because Material's own widgets need a red;
/// app-authored failure states do not use it.
///
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/palette.dart';

/// Semantic colour roles for the whole app.
@immutable
class HealtheeColors extends ThemeExtension<HealtheeColors> {
  /// Builds a token set. Prefer [HealtheeColors.light] / [HealtheeColors.dark].
  const HealtheeColors({
    required this.canvas,
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.chrome,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.line,
    required this.line2,
    required this.rule,
    required this.grid,
    required this.reference,
    required this.accent,
    required this.accent2,
    required this.accentSoft,
    required this.onAccent,
    required this.fav,
    required this.favSoft,
    required this.unf,
    required this.unfSoft,
    required this.alert,
    required this.alertSoft,
    required this.hole,
    required this.band,
    required this.overlay,
    required this.shadow,
    required this.mapLand,
  });

  /// The approved design, light — the default theme.
  const HealtheeColors.light()
    : canvas = LightPalette.canvas,
      bg = LightPalette.bg,
      surface = LightPalette.surface,
      surface2 = LightPalette.surface2,
      chrome = LightPalette.chrome,
      ink = LightPalette.ink,
      ink2 = LightPalette.ink2,
      ink3 = LightPalette.ink3,
      line = LightPalette.line,
      line2 = LightPalette.line2,
      rule = LightPalette.rule,
      grid = LightPalette.grid,
      reference = LightPalette.reference,
      accent = LightPalette.accent,
      accent2 = LightPalette.accent2,
      accentSoft = LightPalette.accentSoft,
      onAccent = LightPalette.onAccent,
      fav = LightPalette.fav,
      favSoft = LightPalette.favSoft,
      unf = LightPalette.unf,
      unfSoft = LightPalette.unfSoft,
      alert = LightPalette.alert,
      alertSoft = LightPalette.alertSoft,
      hole = LightPalette.hole,
      band = LightPalette.band,
      overlay = LightPalette.overlay,
      shadow = LightPalette.shadow,
      mapLand = LightPalette.mapLand;

  /// The approved design, dark — authored, not derived from light.
  const HealtheeColors.dark()
    : canvas = DarkPalette.canvas,
      bg = DarkPalette.bg,
      surface = DarkPalette.surface,
      surface2 = DarkPalette.surface2,
      chrome = DarkPalette.chrome,
      ink = DarkPalette.ink,
      ink2 = DarkPalette.ink2,
      ink3 = DarkPalette.ink3,
      line = DarkPalette.line,
      line2 = DarkPalette.line2,
      rule = DarkPalette.rule,
      grid = DarkPalette.grid,
      reference = DarkPalette.reference,
      accent = DarkPalette.accent,
      accent2 = DarkPalette.accent2,
      accentSoft = DarkPalette.accentSoft,
      onAccent = DarkPalette.onAccent,
      fav = DarkPalette.fav,
      favSoft = DarkPalette.favSoft,
      unf = DarkPalette.unf,
      unfSoft = DarkPalette.unfSoft,
      alert = DarkPalette.alert,
      alertSoft = DarkPalette.alertSoft,
      hole = DarkPalette.hole,
      band = DarkPalette.band,
      overlay = DarkPalette.overlay,
      shadow = DarkPalette.shadow,
      mapLand = DarkPalette.mapLand;

  /// The ground the app shell sits on, behind [bg]. `--canvas`, new in v02.
  final Color canvas;

  /// Page background, behind every surface.
  final Color bg;

  /// Cards and sheets.
  final Color surface;

  /// A recessed or secondary surface inside a card.
  final Color surface2;

  /// App frame — top bar and tab bar. Distinct from [surface] by role.
  final Color chrome;

  /// Primary text and hero figures.
  final Color ink;

  /// Secondary text — the sentence under a number, and a withheld reason.
  final Color ink2;

  /// Tertiary text — labels, units, captions, and a signal sitting at baseline.
  final Color ink3;

  /// Hairline dividers and card borders. Also the dashed edge of a [hole].
  final Color line;

  /// The lighter hairline — rows inside a list, the rule under the app bar.
  ///
  /// **v02 has one hairline**, so this holds the same value as [line]; see
  /// `palette.dart`. The role is kept because the screens that name it have not
  /// been redesigned yet, and because a design may split the pair again.
  final Color line2;

  /// The louder mark — a sheet handle, a separator, a secondary button's edge.
  /// `--rule`, new in v02.
  final Color rule;

  /// A rule drawn INSIDE a plot: gridlines and axis rules.
  ///
  /// Structure at the edge of perception, and **never** derived at a call site.
  /// Every gridline in the app resolves here, because the three painters that
  /// each derived their own from [line] all derived it wrong — see
  /// [DarkPalette.grid] for the arithmetic and the owner report.
  final Color grid;

  /// The horizontal line a series is READ AGAINST — a baseline, a convention.
  ///
  /// Quieter than a caption and louder than [grid]. See
  /// [LightPalette.reference]; `charts/chart_reference.dart` is the only user.
  final Color reference;

  /// The one accent. Actions, links, the owner's own data line.
  final Color accent;

  /// The accent under pressure — pressed, hovered, the stronger of the pair.
  final Color accent2;

  /// A wash of the accent, as a fill behind accent content.
  final Color accentSoft;

  /// Text and icons sitting ON [accent]. Per-theme — see [DarkPalette.onAccent].
  final Color onAccent;

  /// **Judgement.** This reading sits better than the owner's own normal.
  final Color fav;

  /// [fav] as a fill — the favourable side of a band or ladder row.
  final Color favSoft;

  /// **Judgement.** This reading sits worse than the owner's own normal.
  ///
  /// Not the colour of an error, and not the colour of a refusal. Required by the
  /// recovery signal ladder (brief §5.1), which cannot be drawn without the pair.
  final Color unf;

  /// [unf] as a fill — the unfavourable side of a band or ladder row.
  final Color unfSoft;

  /// **The illness flag, and nothing else.** The only red in the product.
  final Color alert;

  /// [alert] as a fill — the illness banner's background.
  final Color alertSoft;

  /// The number-shaped absence: the fill of a withheld value's slot.
  ///
  /// Drawn as a box the size the number would have been, with a **dashed [line]
  /// border** and this as its fill. Deliberately almost invisible — 4.5% ink in
  /// light, 5% white in dark — because the point is the shape, not the colour.
  final Color hole;

  /// The personal usual-range band drawn behind a trend (`white 7%` dark,
  /// `black 5%` light). The 30-day middle of the owner's own readings.
  final Color band;

  /// The scrim behind a modal sheet. `--overlay`; already translucent.
  final Color overlay;

  /// The one shadow v02 casts, under a pressed segment. `--shadow-color`.
  final Color shadow;

  /// The ground a recorded track is drawn on. `--map-land`. A role of its own
  /// because it belongs to one drawing rather than to a category.
  /// `features/gps/route_map.dart` draws **no basemap**.
  final Color mapLand;

  // Grouped by role, as the fields are; the formatter would put one a line.
  // dart format off
  @override
  HealtheeColors copyWith({
    Color? canvas, Color? bg, Color? surface, Color? surface2, Color? chrome,
    Color? ink, Color? ink2, Color? ink3,
    Color? line, Color? line2, Color? rule, Color? grid, Color? reference,
    Color? accent, Color? accent2, Color? accentSoft, Color? onAccent,
    Color? fav, Color? favSoft, Color? unf, Color? unfSoft,
    Color? alert, Color? alertSoft, Color? hole, Color? band, Color? overlay,
    Color? shadow,
    Color? mapLand,
  }) {
    // dart format on
    return HealtheeColors(
      canvas: canvas ?? this.canvas,
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surface2: surface2 ?? this.surface2,
      chrome: chrome ?? this.chrome,
      ink: ink ?? this.ink,
      ink2: ink2 ?? this.ink2,
      ink3: ink3 ?? this.ink3,
      line: line ?? this.line,
      line2: line2 ?? this.line2,
      rule: rule ?? this.rule,
      grid: grid ?? this.grid,
      reference: reference ?? this.reference,
      accent: accent ?? this.accent,
      accent2: accent2 ?? this.accent2,
      accentSoft: accentSoft ?? this.accentSoft,
      onAccent: onAccent ?? this.onAccent,
      fav: fav ?? this.fav,
      favSoft: favSoft ?? this.favSoft,
      unf: unf ?? this.unf,
      unfSoft: unfSoft ?? this.unfSoft,
      alert: alert ?? this.alert,
      alertSoft: alertSoft ?? this.alertSoft,
      hole: hole ?? this.hole,
      band: band ?? this.band,
      overlay: overlay ?? this.overlay,
      shadow: shadow ?? this.shadow,
      mapLand: mapLand ?? this.mapLand,
    );
  }

  @override
  HealtheeColors lerp(ThemeExtension<HealtheeColors>? other, double t) {
    if (other is! HealtheeColors) {
      return this;
    }
    return HealtheeColors(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      chrome: Color.lerp(chrome, other.chrome, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      ink2: Color.lerp(ink2, other.ink2, t)!,
      ink3: Color.lerp(ink3, other.ink3, t)!,
      line: Color.lerp(line, other.line, t)!,
      line2: Color.lerp(line2, other.line2, t)!,
      rule: Color.lerp(rule, other.rule, t)!,
      grid: Color.lerp(grid, other.grid, t)!,
      reference: Color.lerp(reference, other.reference, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accent2: Color.lerp(accent2, other.accent2, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      fav: Color.lerp(fav, other.fav, t)!,
      favSoft: Color.lerp(favSoft, other.favSoft, t)!,
      unf: Color.lerp(unf, other.unf, t)!,
      unfSoft: Color.lerp(unfSoft, other.unfSoft, t)!,
      alert: Color.lerp(alert, other.alert, t)!,
      alertSoft: Color.lerp(alertSoft, other.alertSoft, t)!,
      hole: Color.lerp(hole, other.hole, t)!,
      band: Color.lerp(band, other.band, t)!,
      overlay: Color.lerp(overlay, other.overlay, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      mapLand: Color.lerp(mapLand, other.mapLand, t)!,
    );
  }

  /// Every role, in declaration order. **Add new roles here too** — this backs
  /// equality, and Flutter compares theme extensions to decide whether a theme
  /// change needs a rebuild.
  // dart format off
  List<Color> get _roles => [
    canvas, bg, surface, surface2, chrome,
    ink, ink2, ink3,
    line, line2, rule, grid, reference,
    accent, accent2, accentSoft, onAccent,
    fav, favSoft, unf, unfSoft,
    alert, alertSoft, hole, band, overlay, shadow,
    mapLand,
  ];
  // dart format on

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! HealtheeColors) {
      return false;
    }
    final mine = _roles;
    final theirs = other._roles;
    for (var i = 0; i < mine.length; i++) {
      if (mine[i] != theirs[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_roles);
}

/// Reaches the token set from a widget: `context.colors.ink3`.
extension HealtheeColorsOf on BuildContext {
  /// The active theme's semantic colours.
  ///
  /// Throws if the theme was built without the extension, which is the right
  /// behaviour — a silent fallback palette would let a screen render in colours
  /// nobody chose, and look almost right.
  HealtheeColors get colors => Theme.of(this).extension<HealtheeColors>()!;
}
