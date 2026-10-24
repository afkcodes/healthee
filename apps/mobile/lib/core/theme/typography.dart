/// The type system: Figtree, and tabular figures wherever a number lives.
///
/// ## Tabular figures are on by default, and that is a correctness decision
///
/// This app's screens are columns of numbers that change every day. With
/// proportional figures a 1 is narrower than an 8, so a resting heart rate moving
/// 55 → 58 shifts every glyph beside it and a 30-night strip visibly ripples as
/// you scroll. `FontFeature.tabularFigures()` fixes every digit to one advance
/// width, so columns line up and a changing value does not move its neighbours.
///
/// `docs/APP_DESIGN_BRIEF.md` §7 makes it a hard constraint — *"Tabular figures
/// everywhere. Non-tabular numerals in a metric column is a defect."* It is
/// applied to the whole [TextTheme] rather than to a numeric style, because the
/// alternative is remembering, and a number set in the wrong style is exactly the
/// kind of miss nobody files a bug for. Prose loses nothing.
///
/// ## The scale is the ladder
///
/// Every role below is an alias of a step on `type_ladder.dart`: twelve steps on
/// nine sizes, each with its own line height, weight and tracking. The Material
/// roles keep their names so the un-migrated screens read the same; what they
/// resolve to is a ladder step, so no role can set a size the ladder lacks.
///
/// ## The face is Figtree, after Inter, Manrope and Instrument Sans
///
/// Owner decision 2026-08-05: *Instrument Sans reads "newspaper" at display
/// sizes.* It does — its high-contrast, tight-apertured caps carry an editorial
/// texture, which is the one direction `docs/APP_DESIGN_BRIEF.md` §2 rules out by
/// name ("modern instrument. **Not editorial**"). Every replacement since is the
/// opposite build: open apertures, near-uniform stroke, a wide and untroubled
/// `0`. Figtree is the current one; [healtheeFontFamily] records why.
///
/// **The old family is deleted, not left beside the new one.** Two vendored
/// families is two things a `TextStyle` can name and one of them wrong, and the
/// wrongness is invisible — a stray `fontFamily: 'Instrument Sans'` would render
/// perfectly and simply not be the app's face.
///
/// Two measurements came with each swap, because a face is not a drop-in:
///
///   * **Tabular figures survive.** Figtree ships `tnum`, which is what
///     [FontFeature.tabularFigures] selects. That mattered more than the face —
///     brief §7 makes it a hard constraint, and a face without it would have been
///     rejected whatever it looked like.
///   * **Glyph coverage was checked, not assumed.** Instrument Sans had no
///     U+2082 (the subscript in `SpO₂`) and drew a tofu box on the live screen.
///     Figtree has `₂` but not `↔`, `⌄`, `ρ`, `σ` or `ⓘ`, which is why
///     [healtheeFontFallback] leads with a bundled fallback; the widths were
///     re-checked against overflow (`test/core/typography_test.dart`).
///
/// ## The font is vendored, not fetched
///
/// `assets/fonts/` holds Figtree as one variable font (SIL OFL, no Reserved Font
/// Name; see the OFL text beside it) and the Inter-based symbol fallback.
/// Bundling buys a binary with no network dependency at paint time, against a
/// cold-start budget of 2 s to first meaningful paint (Standards §1).
///
/// [healtheeFontFallback] still names the platform faces, so a failed asset
/// degrades to the system font rather than to Flutter's fallback box glyphs.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/type_ladder.dart';

/// The bundled family name, as declared in pubspec.yaml.
///
/// **Figtree, chosen by the owner on 2026-09-07** after Inter ("not good") and
/// Plus Jakarta Sans ("numbers too elongated"). The brief was "circular clean",
/// and Figtree is the only geometric face of that shape that survives what this
/// app actually draws: it keeps `₂` (SpO₂, VO₂max) and tabular figures, where
/// DM Sans, Outfit, Poppins and Jost each lose one or both.
///
/// The elongation complaint was real and measurable: Plus Jakarta's digits are
/// **0.769 em tall**, the tallest of twenty-one faces measured, against a
/// typical 0.72. Figtree's are 0.724 with a rounder 0.74 width-to-height ratio.
///
/// It is a VARIABLE font shipped as one file; `type_ladder.dart` drives the
/// `wght` axis directly rather than relying on four static instances.
const String healtheeFontFamily = 'Figtree';

/// Faces to fall back on, in order, when Figtree has no glyph for a character.
///
/// ## The first entry is BUNDLED, and that is the whole point
///
/// Figtree has no `↔` (U+2194) — nor `⌄`, `ρ`, `σ` or `ⓘ`. The app draws all of
/// them.
///
/// An earlier revision named platform symbol faces here (`Noto Sans Symbols`
/// and friends) and asserted that `fontFamilyFallback` is consulted before the
/// platform chain, so the colour emoji font could never be reached. **That was
/// never tested, because the face at the time was Inter, which HAS U+2194 — the
/// fallback never ran.** The moment Figtree shipped, `Overnight HRV ↔ recovery`
/// drew a blue emoji box again, on the device, exactly as before.
///
/// So [HealtheeSymbols] is a **bundled** family (Inter, in `assets/fonts/`),
/// named first. A bundled family is resolved by the engine's own font manager
/// rather than the platform's, and it does beat `NotoColorEmoji` — verified on
/// the device, which is the only way this has ever been established.
///
/// The platform faces stay behind it as a second line, and cost nothing.
///
/// `test/core/typography_test.dart` walks `lib/` and fails if a character the
/// app writes is covered by neither the bundled face nor the bundled fallback.
const List<String> healtheeFontFallback = <String>[
  // Bundled. Complete. Load-bearing — see above.
  'HealtheeSymbols',
  // Platform text faces, for the case where the bundled asset fails entirely.
  'SF Pro Text', // iOS
  'Roboto', // Android
  'Segoe UI',
  'Helvetica Neue',
  'Arial',
  // Platform symbol faces. Kept, but NOT relied on.
  'Noto Sans Symbols', // Android
  'Segoe UI Symbol', // Windows
  'Apple Symbols', // iOS / macOS
];

/// The app's text theme, coloured for the three ink roles.
///
/// Styles are named for ROLE, not size, and every role is a ladder step.
/// [ink3] carries the smallest labels — the marginalia that must not compete
/// with the number it annotates.
TextTheme healtheeTextTheme({
  required Color ink,
  required Color ink2,
  required Color ink3,
}) => TextTheme(
  // Hero figures — the recovery score, the VO₂max estimate.
  displayLarge: TypeLadder.metric.copyWith(color: ink),
  displayMedium: TypeLadder.title1.copyWith(color: ink),
  // Screen and section headings.
  headlineMedium: TypeLadder.headline.copyWith(color: ink),
  headlineSmall: TypeLadder.headline.copyWith(color: ink),
  // A sheet's or a list's own title. Set here so it is not Material's 22/400.
  titleLarge: TypeLadder.title2.copyWith(color: ink),
  // A card's own title.
  titleMedium: TypeLadder.bodyStrong.copyWith(color: ink),
  titleSmall: TypeLadder.calloutStrong.copyWith(color: ink),
  // Prose. `bodyMedium` is the app's default paragraph.
  bodyLarge: TypeLadder.body.copyWith(color: ink),
  bodyMedium: TypeLadder.callout.copyWith(color: ink2),
  bodySmall: TypeLadder.caption.copyWith(color: ink2),
  // Units, captions, chips — the instrument's marginalia.
  labelLarge: TypeLadder.calloutStrong.copyWith(color: ink),
  labelMedium: TypeLadder.caption.copyWith(color: ink2),
  labelSmall: TypeLadder.caption.copyWith(color: ink3),
);
