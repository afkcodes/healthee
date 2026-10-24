/// **The tone.** v02's central idea, ported from `richer.css` lines 37-50.
///
/// In the prototype a container carries `data-tone="sleep"`, which sets one
/// custom property — `--family` — and everything inside then resolves it: the
/// line stroke, the dot, the bar fill, the area gradient's stops, the icon
/// tile's foreground and background, the progress fill. Nothing is passed a
/// colour; the colour cascades.
///
/// The Flutter equivalent is this enum plus `tone_scope.dart`. A card declares
/// its tone **once**; its contents read `context.family` / `context.familySoft`
/// and never take a `Color` parameter. That is the whole point: passing the hue
/// down is how one card ends up two colours, and it is what
/// `test/theme/tone_cascade_test.dart` exists to prevent.
///
/// ## Nine names, six families — deliberately
///
/// `richer.css` gives three families two tone names each: `fitness`/`recovery`,
/// `heart`/`load`, `movement`/`activity`. They are aliases in the CSS and they
/// are aliases here. Keeping both means a card can say what it is *about*
/// (`Tone.load`) rather than what colour it wants (`Tone.heart`), which is the
/// difference between a name that survives a palette change and one that does
/// not.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/instrument_hues.dart';

/// A card's tone: which category family everything inside it resolves to.
///
/// The default is [Tone.fitness] — `richer.css` `:root` sets
/// `--family: var(--fitness)`, so content outside any `data-tone` is green.
enum Tone {
  /// Body: biological age, weight, skin temperature. The `:root` default.
  fitness,

  /// Recovery. No hue of its own: neutral ink, judged by zone.
  recovery,

  /// Sleep, sleep debt, sleep timing.
  sleep,

  /// Heart rate, resting HR, HRV, VO₂max.
  heart,

  /// Strain: cardio load and workouts, its own family.
  load,

  /// Steps, distance, calories, energy.
  movement,

  /// Alias of [movement]. `[data-tone='activity']`.
  activity,

  /// Breathing: respiratory rate, blood oxygen.
  oxygen,

  /// Mind: stress, journal, meditation.
  stress,
}

/// Resolves a [Tone] against the active theme's [InstrumentHues].
extension ToneFamily on Tone {
  /// `--family` — the line, the dot, the icon, the number that carries identity.
  Color family(InstrumentHues hues) => switch (this) {
    Tone.fitness => hues.fitness,
    Tone.recovery => hues.recovery,
    Tone.sleep => hues.sleep,
    Tone.heart => hues.heart,
    Tone.load => hues.strain,
    Tone.movement || Tone.activity => hues.movement,
    Tone.oxygen => hues.oxygen,
    Tone.stress => hues.stress,
  };

  /// `--family-soft` — the fill behind [family]: a tile's ground, an icon tile.
  Color familySoft(InstrumentHues hues) => switch (this) {
    Tone.fitness => hues.fitnessSoft,
    Tone.recovery => hues.recoverySoft,
    Tone.sleep => hues.sleepSoft,
    Tone.heart => hues.heartSoft,
    Tone.load => hues.strainSoft,
    Tone.movement || Tone.activity => hues.movementSoft,
    Tone.oxygen => hues.oxygenSoft,
    Tone.stress => hues.stressSoft,
  };

  /// The family this tone is an alias of, so a test can enumerate the six.
  Tone get canonical => switch (this) {
    Tone.activity => Tone.movement,
    _ => this,
  };
}

/// The distinct families: the seven domain hues plus recovery's neutral. An
/// alias is **not** here; [ToneFamily.canonical] maps onto it.
const List<Tone> kToneFamilies = <Tone>[
  Tone.fitness,
  Tone.recovery,
  Tone.sleep,
  Tone.heart,
  Tone.load,
  Tone.movement,
  Tone.oxygen,
  Tone.stress,
];
