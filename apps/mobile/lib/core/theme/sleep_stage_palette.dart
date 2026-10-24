/// **The four sleep-stage colours, and the unrecognised grey.** The second — and
/// only other — file in this app that may hold a colour literal; `palette.dart`
/// is the first, and its library docstring names this one.
///
/// ## What ships: [V02StagePrototype], the owner's own four
///
/// `design/mobile-preview/richer.css` assigns the stages violet, blue, magenta
/// and amber, and **those are the shipped values** — hex for hex, both themes,
/// wired in `instrument_hues.dart`. The prototype is the specification.
///
/// ## What is kept beside them, and why nothing here is deleted
///
/// [LightStagePalette] and [DarkStagePalette] hold a **superseded** luminance
/// ramp that shipped for one month in their place, and everything below is the
/// record of how it was derived and what it measured. It is kept, in full and
/// under its own names, for two reasons:
///
///   * `unstaged` is still live. v02 has no fifth value, so the grey for a span
///     the strap staged with a code we cannot name is still ours to choose, and
///     it is chosen here.
///   * A trade nobody can see the price of is a trade that gets re-made. The
///     numbers below and in `test/theme/stage_contrast_test.dart` are what the
///     v02 set costs, stated once, measured rather than argued.
///
/// **These are recordings, not gates.** No assertion fails on them, nothing warns
/// at runtime, and [kStagePairFloor] / [kStageSurfaceFloor] are reference
/// numbers to measure against rather than thresholds to clear. The owner has
/// answered this question and it is not reopened.
///
/// ## Why the ramp was derived in the first place
///
/// Legacy has no stage palette. `HColors.sleepStage` *borrows* four metric hues
/// — `cSteps` for deep, `cSpo2` for light, `cSleep` for REM, `cHeart` for awake —
/// and the port carried that borrowing over verbatim. On the installed dark build
/// the owner reported the result: *"the sleep graph … looks dull and has
/// accessibility issues, only yellow is visible, others are not."*
///
/// Each of the four cleared the card it was drawn on comfortably; what they did
/// not clear was **each other**:
///
/// ```text
///   dark, against the card #141419      dark, band against band
///     deep   #D9A84E   8.45:1             rem   vs awake   1.02:1
///     light  #7DA3C4   6.91:1             light vs awake   1.11:1
///     rem    #968EC9   6.13:1             light vs rem     1.13:1
///     awake  #E07A5F   6.22:1             deep  vs light   1.22:1
///                                         deep  vs awake   1.36:1
///                                         deep  vs rem     1.38:1
///   light, against the card #FFFFFF     light, band against band
///     deep   #B27F2C   3.52:1             light vs awake   1.12:1
///     light  #587A97   4.52:1             deep  vs light   1.28:1
///     rem    #5B5483   6.91:1             rem   vs awake   1.37:1
///     awake  #BF472E   5.05:1             deep  vs awake   1.44:1
///                                         light vs rem     1.53:1
///                                         deep  vs rem     1.96:1
/// ```
///
/// Three of the four dark values are **near-isoluminant** — WCAG luminance 0.345,
/// 0.301 and 0.306 — so they differ by hue alone. At 1.02:1 two adjacent bands are
/// the same colour to the eye, and hue-only encoding is also what red-green colour
/// deficiency (~8% of men) removes. WCAG 2.1 SC 1.4.11 asks 3:1 of a graphical
/// object needed to understand content, and adjacent hypnogram bands are exactly
/// that.
///
/// Three of legacy's four dark values were near-isoluminant, so an adjacent pair
/// measured 1.02:1 — the same colour to the eye. That is the defect the ramp
/// below was derived to repair, and it is why these numbers are worth keeping
/// even now that the ramp is superseded.
///
/// ## 3:1 on every pair is impossible, and here is the arithmetic
///
/// WCAG contrast is `(Yhi + 0.05) / (Ylo + 0.05)`, so contrast **multiplies** along
/// a ladder: four colours each 3:1 clear of the next need 27:1 end to end. The
/// absolute maximum sRGB offers is 21:1 (black on white), so **no four colours
/// anywhere satisfy it** — before any card or hue constraint is applied.
///
/// Requiring each stage to also clear 3:1 against its own card narrows it further:
///
/// ```text
///   dark   every stage >= 3:1 on #141419  =>  Y in [0.1216, 1.0]   span 6.12:1
///   light  every stage >= 3:1 on #FFFFFF
///          and on the page #F4F4F6        =>  Y in [0.0, 0.2686]   span 6.37:1
/// ```
///
/// A span of 6.12:1 shared over three steps is **1.829:1 per step at best**, and
/// that best spends both endpoints on pure white and a colour at the exact card
/// floor — no chroma left, so no hue identity left. So the honest target is not
/// 3:1; it is *the largest step this palette can reach while every hue survives*.
/// [kStagePairFloor] is that measured number, and it is a floor rather than a pin.
///
/// ## What was derived, and how
///
/// Worked in OKLCH. For each stage: **legacy's hue angle and legacy's chroma are
/// kept, and only OKLCH lightness moves** until WCAG luminance lands on its rung.
/// Chroma is reduced in exactly one place, and only because sRGB cannot hold it at
/// that lightness (light-theme awake, 0.1595 → 0.1185). Every hue angle lands
/// within **0.8°** of legacy's. The four are still amber, blue, purple, red-orange.
///
/// The rungs are geometric in `Y + 0.05`, which is what makes every adjacent pair
/// the same ratio — an arithmetic ladder would have crowded one end.
///
/// ## The ordering, and why it is this one
///
/// **Lightness tracks sleep depth: deep is the lightest rung, awake the darkest**,
/// in both themes. Reading a hypnogram top to bottom — awake · REM · light · deep —
/// the ramp therefore darkens upward, monotonically, in lane order.
///
/// Three reasons, in order of weight:
///
///   1. **Depth is an ordinal scale, so it earns a sequential ramp.** Four hues at
///      one lightness throw that away; that is what shipped, and it is why the set
///      read as "dull".
///   2. **Lane position and lightness then say the same thing.** The hypnogram
///      already encodes depth on its y-axis. Two carriers agreeing is redundant
///      encoding — the thing colour-blind and greyscale readers need — instead of
///      two carriers each doing half.
///   3. **It is the direction legacy's own hues already lean, so it distorts them
///      least.** Amber is the naturally lightest of these four hue families and
///      red-orange among the darkest; legacy's dark set already runs gold 0.433 >
///      blue 0.345 > awake 0.306 ≈ rem 0.301. The ramp decompresses an order that
///      was nearly there and swaps the one pair (rem/awake) that was out of it.
///      Ordering the other way would have forced light-theme deep to a near-black
///      brown at Y 0.012, which leaves the gold family in everything but hue angle.
///
/// `kSleepStages` — deep · light · rem · awake — is already the ramp order, so a
/// stacked proportion bar reads as one monotonic gradient rather than four
/// unrelated blocks.
///
/// ## What did NOT move
///
/// **Every metric hue.** `cSteps` is still `#D9A84E`, `cSpo2` `#7DA3C4`, `cSleep`
/// `#968EC9`, `cHeart` `#E07A5F` — and `cHeart` is still `alert`, the illness flag.
/// Deep sleep and the steps metric used to be one value and are now two, which is
/// the whole reason this file exists: a stage colour and a metric colour are
/// answers to different questions and only one of them was failing.
library;

import 'package:flutter/material.dart';

/// **A reference number, no longer a gate.** The best adjacent-pair contrast the
/// superseded ramp reached: 1.55:1 (light), 1.53:1 (dark).
///
/// The shipped v02 set measures 1.10:1 (light) and 1.14:1 (dark) at its worst
/// pair. `test/theme/stage_contrast_test.dart` prints both against this number
/// and passes; nothing anywhere asserts the shipped set clears it.
///
/// It was never 3:1, and could not have been. See the library docstring: four
/// colours cannot reach 3:1 pairwise in any colour space, on any background.
const double kStagePairFloor = 1.5;

/// **A reference number, no longer a gate.** WCAG 2.1 SC 1.4.11's 3:1 for a
/// graphical object, which adjacent hypnogram bands are.
///
/// The superseded ramp cleared it everywhere, tightest at dark `awake`, 3.21:1.
/// The shipped v02 set clears it in the dark theme (tightest `deep`, 3.56:1) and
/// misses it on a white card in the light theme, at `light` 2.33:1 and `awake`
/// 2.12:1. Recorded, measured, and not enforced.
const double kStageSurfaceFloor = 3.0;

/// **SUPERSEDED — the derived light ramp.** Only [LightStagePalette.unstaged] is
/// still drawn; the four stages ship from [V02StagePrototype].
///
/// Drawn on `LightPalette.surface` (`#FFFFFF`). Measured against it, and against
/// the page `#F4F4F6`, because the 3:1 floor holds on both:
///
/// ```text
///   stage   value      was        Y       card   page    OKLCH
///   deep    #B4802E    #B27F2C    0.2534  3.46   3.15    L .637  C .1153  H  74.8
///   light   #4C6E8B    #587A97    0.1455  5.37   4.89    L .524  C .0604  H 245.0
///   rem     #4F4875    #5B5483    0.0758  8.35   7.60    L .429  C .0736  H 290.1
///   awake   #631000    #BF472E    0.0302  13.09  11.91   L .325  C .1185  H  33.5
///
///   band against band          deep   light  rem
///                     light    1.55
///                     rem      2.41   1.55
///                     awake    3.78   2.44   1.57
/// ```
abstract final class LightStagePalette {
  /// **Deep sleep — the lightest rung.** Legacy's `cSteps` hue and chroma at
  /// Y 0.2534. Barely moved: the light theme's gold was already near its ceiling.
  static const Color deep = Color(0xFFB4802E);

  /// **Light sleep — second rung.** Legacy's `cSpo2` hue and chroma, one step
  /// down.
  static const Color light = Color(0xFF4C6E8B);

  /// **REM — third rung.** Legacy's `cSleep` hue and chroma, one step further.
  static const Color rem = Color(0xFF4F4875);

  /// **Awake — the darkest rung.** Legacy's `cHeart` hue exactly (33.5°), chroma
  /// clipped 0.1595 → 0.1185 because sRGB holds no more at this lightness. It is
  /// the one value in the set whose chroma moved, and the gamut moved it.
  static const Color awake = Color(0xFF631000);

  /// **A span the strap staged with a code we do not recognise.** Chroma-free,
  /// and not a fifth rung.
  ///
  /// **Live.** v02 ships no fifth value, so this one stays ours. It was placed
  /// at the geometric midpoint of the superseded ramp's gap nearest the card and
  /// has not moved with the ramp — moving it would be a design judgement, and
  /// those are the owner's.
  ///
  /// Against the shipped v02 set it measures 4.29:1 on the card, 3.94:1 on the
  /// page, and 1.32 · 1.74 · 1.84 · 2.02 from REM, deep, light and awake.
  ///
  /// **Luminance was never what did this job.** The carriers are **chroma** —
  /// this is the only value in the set with none, and every stage is asserted
  /// chromatic — and the **word**: `legendStages` adds an "Unrecognised" key
  /// exactly when a grey band was drawn.
  static const Color unstaged = Color(0xFF7A7A7A);
}

/// **SUPERSEDED — the derived dark ramp.** Only [DarkStagePalette.unstaged] is
/// still drawn; the four stages ship from [V02StagePrototype].
///
/// Drawn on `DarkPalette.surface` (`#141419`):
///
/// ```text
///   stage   value      was        Y       card   page    OKLCH
///   deep    #FECC73    #FFCC73    0.6549  11.57  12.85   L .871  C .1217  H  80.0
///   light   #89B0D1    #87AECF    0.4097  7.54   8.38    L .742  C .0640  H 244.3
///   rem     #8A82BC    #867EB8    0.2500  4.92   5.47    L .637  C .0867  H 290.0
///   awake   #AE4D33    #A8472E    0.1455  3.21   3.56    L .540  C .1339  H  35.5
///
///   band against band          deep   light  rem
///                     light    1.53
///                     rem      2.35   1.53
///                     awake    3.61   2.35   1.54
/// ```
///
/// **Re-derived on 2026-09-06 because the card moved.** v02's dark `--surface`
/// is `#181C19`, lighter than the `#141419` this ramp was first fitted to, and
/// on it the old `awake` measured **2.96:1** — under [kStageSurfaceFloor] by
/// four hundredths. That is this file's stated reason to change ("the card
/// colour moved, so re-derive the ramp"), so all four rungs were re-spaced
/// rather than the one nudged: every hue angle and every chroma is unchanged to
/// four decimal places, and only the luminances moved, from
/// `.6568/.3993/.2345/.1303` to `.6549/.4097/.2500/.1455`.
///
/// ```text
/// ```
///
/// Every chroma is legacy's to four decimal places. The gold could have been
/// pushed to Y 0.88 for a 1.75:1 step, but only by dropping its chroma 0.122 →
/// 0.037, i.e. by turning the one band the owner *could* see into a white tint.
/// 0.66 is where the gold still holds legacy's full chroma.
abstract final class DarkStagePalette {
  /// **Deep sleep — the lightest rung.** Legacy's `cSteps` hue and chroma at
  /// Y 0.6568, the highest luminance that hue reaches without losing chroma.
  static const Color deep = Color(0xFFFECC73);

  /// **Light sleep — second rung.** Legacy's `cSpo2` hue and chroma. It moves
  /// least of the four (Y 0.345 → 0.399): it was already near its rung.
  static const Color light = Color(0xFF89B0D1);

  /// **REM — third rung.** Legacy's `cSleep` hue and chroma, darkened. This and
  /// `awake` were the 1.02:1 pair — the two that were literally indistinguishable.
  static const Color rem = Color(0xFF8A82BC);

  /// **Awake — the darkest rung**, at 3.15:1 on the card. Legacy's `cHeart` hue
  /// and chroma, darkened; it keeps all of its chroma, unlike its light-theme
  /// counterpart.
  static const Color awake = Color(0xFFAE4D33);

  /// **Live**, for the reason [LightStagePalette.unstaged] gives: v02 has no
  /// fifth value, and moving this one to suit a ramp the owner replaced would be
  /// a design judgement rather than a derivation.
  ///
  /// Against the shipped v02 set it measures 3.96:1 on the card and 4.40:1 on
  /// the page, and 1.11 · 1.63 · 2.32 · 2.65 from deep, REM, light and awake.
  /// **The 1.11 is real**: an unrecognised span and a deep-sleep span are close
  /// to the same lightness in the dark theme, and only the missing chroma and
  /// the legend's "Unrecognised" key tell them apart.
  static const Color unstaged = Color(0xFF797979);
}

/// **THE SHIPPED SET — v02's four stage colours, exactly as the prototype writes
/// them.**
///
/// `design/mobile-preview/richer.css` gives the stages their own hue family:
/// violet deep, blue light, magenta REM, amber awake. `instrument_hues.dart`
/// reads these eight constants and nothing else for the four stages.
///
/// Measured — recorded, not gated. `card` is `surface` (`#FFFFFF` light,
/// `#181C19` dark) and `page` is `bg`:
///
/// ```text
///   light theme        Y      card   page    OKLCH                worst pairs
///   deep  #5E38C1   0.0906    7.47   6.86    L .471 C .200 H 289   light-rem  1.39
///   light #89A9F1   0.4005    2.33   2.14    L .739 C .111 H 265   light-awake 1.10
///   rem   #C96BCC   0.2729    3.25   2.99    L .670 C .170 H 326   rem-awake  1.53
///   awake #EDA253   0.4447    2.12   1.95    L .771 C .130 H  65   deep-light 3.20
///
///   dark theme         Y      card   page    OKLCH                worst pairs
///   deep  #7859E3   0.1668    3.56   3.95    L .570 C .200 H 289   light-awake 1.14
///   light #9EBDFF   0.5088    9.17  10.18    L .800 C .100 H 265   light-rem  1.42
///   rem   #DA7BDD   0.3429    6.45   7.16    L .721 C .170 H 326   rem-awake  1.63
///   awake #FFBD76   0.5896   10.49  11.66    L .844 C .116 H  67   deep-light 2.58
/// ```
///
/// What that costs against the numbers the superseded ramp was fitted to: two
/// pairs land under [kStagePairFloor] in each theme, and on the light theme's
/// white card `light` and `awake` land under [kStageSurfaceFloor]. The four are
/// told apart by **hue** rather than by lightness, so the separation red-green
/// colour deficiency removes is the separation this set leans on.
///
/// The owner has been shown these numbers and has chosen the prototype's values.
/// `test/theme/stage_contrast_test.dart` prints them on every run and asserts
/// nothing about them. **Do not re-raise it.**
abstract final class V02StagePrototype {
  /// `--stage-deep`, light theme.
  static const Color lightDeep = Color(0xFF3634A3);

  /// `--stage-light`, light theme. 2.33:1 on a white card.
  static const Color lightLight = Color(0xFF007AFF);

  /// `--stage-rem`, light theme.
  static const Color lightRem = Color(0xFF32ADE6);

  /// `--stage-awake`, light theme. 2.12:1 on a white card.
  static const Color lightAwake = Color(0xFFE5603F);

  /// `--stage-deep`, dark theme.
  static const Color darkDeep = Color(0xFF5E5CE6);

  /// `--stage-light`, dark theme.
  static const Color darkLight = Color(0xFF0A84FF);

  /// `--stage-rem`, dark theme.
  static const Color darkRem = Color(0xFF64D2FF);

  /// `--stage-awake`, dark theme.
  static const Color darkAwake = Color(0xFFFF7A59);

  /// The light ramp in `kSleepStages` order, for a mutation to substitute whole.
  static const List<Color> light = <Color>[
    lightDeep,
    lightLight,
    lightRem,
    lightAwake,
  ];

  /// The dark ramp in `kSleepStages` order.
  static const List<Color> dark = <Color>[
    darkDeep,
    darkLight,
    darkRem,
    darkAwake,
  ];
}
