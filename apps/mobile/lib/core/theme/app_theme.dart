/// Assembles the two [ThemeData]s. Both are authored; neither is derived.
///
/// A dark theme generated from a light one by inverting lightness is how a
/// palette gets muddy greys and unreadable hairlines. `docs/APP_DESIGN_BRIEF.md`
/// §2 is explicit — "Both are authored above — do not derive one by inverting the
/// other" — so both are built here from their own token set.
///
/// Nothing outside this file constructs a [ThemeData], and nothing outside
/// `palette.dart` names a colour value.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/appearance_colors.dart';
import 'package:healthee/core/theme/appearance_variant.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/instrument_hues.dart';
import 'package:healthee/core/theme/shapes.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/typography.dart';

/// The app's light and dark themes.
abstract final class AppTheme {
  /// Light — the default.
  static ThemeData get light => _build(
    const HealtheeColors.light(),
    const InstrumentHues.light(),
    Brightness.light,
  );

  /// Dark.
  static ThemeData get dark => _build(
    const HealtheeColors.dark(),
    const InstrumentHues.dark(),
    Brightness.dark,
  );

  static ThemeData customized(
    Brightness brightness,
    AppearanceVariant variant,
  ) => _build(
    appearanceColors(brightness, variant),
    brightness == Brightness.dark
        ? const InstrumentHues.dark()
        : const InstrumentHues.light(),
    brightness,
  );

  static ThemeData _build(
    HealtheeColors colors,
    InstrumentHues hues,
    Brightness brightness,
  ) {
    final text = healtheeTextTheme(
      ink: colors.ink,
      ink2: colors.ink2,
      ink3: colors.ink3,
    );
    return ThemeData(
      brightness: brightness,
      useMaterial3: true,
      // Two extensions, deliberately not one: `colors` is structure and
      // judgement, `hues` is identity. See instrument_hues.dart — and note that
      // legacy makes two of the hues BE verdicts, by decision.
      extensions: <ThemeExtension<Object?>>[colors, hues],
      scaffoldBackgroundColor: colors.bg,
      canvasColor: colors.bg,
      // **No ink ripple, anywhere.** Material's splash expands a circle from
      // the touch point across the whole tappable box, which on this app's
      // cards means a pale disc sweeping over a chart. The app has its own
      // press feedback and has had since v02 — `HTap`'s scale to 0.975 with a
      // dip in opacity, legacy's own gesture — and the ripple was a second,
      // louder answer to the same question, drawn by whichever widgets
      // happened to be built on `InkWell`.
      //
      // Set here rather than at twenty call sites: this is one decision about
      // how the app answers a touch, and it should not be re-taken per widget.
      // The highlight is kept — a brief flat tint, so a control built on
      // `InkWell` still acknowledges a press without animating a disc.
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      dividerColor: colors.line,
      fontFamily: healtheeFontFamily,
      fontFamilyFallback: healtheeFontFallback,
      textTheme: text,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: colors.accent,
        onPrimary: colors.onAccent,
        // `secondary` is the stronger accent, not the soft wash. accentSoft is a
        // translucent FILL and would render Material's secondary-coloured text
        // as a ghost of the background.
        secondary: colors.accent2,
        onSecondary: colors.onAccent,
        // Material's own widgets (form validation, `TextField` errors) need a
        // red, and `alert` is the only one in the product. App-authored failure
        // states do NOT use it — see the note in tokens.dart. Reserving alert for
        // illness is a rule about OUR cards; it cannot stop Material having an
        // error colour, and leaving this at the M3 default would introduce a
        // second red nobody chose.
        error: colors.alert,
        onError: colors.onAccent,
        surface: colors.surface,
        onSurface: colors.ink,
        surfaceContainerLow: colors.surface2,
        outline: colors.line,
        outlineVariant: colors.line2,
      ),
      dividerTheme: DividerThemeData(
        color: colors.line2,
        thickness: hairline,
        space: hairline,
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        // Legacy's modules carry no shadow at all; the brief removed the hairline too: a card is a surface on the page.
        elevation: 0,
        margin: EdgeInsets.zero,
        // The continuous-corner squircle legacy draws every card with, not a
        // circular-arc rounded rectangle. See shapes.dart.
        shape: hSquircle(Radii.card),
      ),
      appBarTheme: AppBarTheme(
        // `chrome`, not `bg` — the app frame is its own surface in this design,
        // and in light mode it is white against a grey page.
        backgroundColor: colors.chrome,
        foregroundColor: colors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.headlineSmall,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: colors.chrome,
        selectedItemColor: colors.accent,
        unselectedItemColor: colors.ink3,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
      ),
      // The coach button. Material's default is a 16px circular arc, and it was
      // the one surface on Today still wearing somebody else's corner.
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colors.accent,
        foregroundColor: colors.onAccent,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: hSquircle(Radii.card),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.accent,
          foregroundColor: colors.onAccent,
          textStyle: text.labelLarge,
          shape: hSquircle(Radii.button),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.ink,
          textStyle: text.labelLarge,
          side: BorderSide(color: colors.line, width: hairline),
          shape: hSquircle(Radii.button),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          // `accent`, not `accentSoft` — the wash is 9% opaque and a text button
          // wearing it was invisible. (Latent bug from the previous palette,
          // where `accentSoft` happened to be a solid colour.)
          foregroundColor: colors.accent,
          textStyle: text.labelLarge,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.accent,
        linearTrackColor: colors.surface2,
      ),
    );
  }
}
