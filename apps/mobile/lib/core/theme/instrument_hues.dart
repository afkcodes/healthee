/// v02's six category families as a theme extension, plus the ONE canonical
/// sleep-stage mapping every stage plot and legend draws from.
///
/// **This replaced legacy's ten per-metric hues on 2026-09-06.** The prototype in
/// `design/mobile-preview/` assigns meaning to six colours and no more, so the
/// ten collapsed: `hrv`/`readiness` → [fitness], `steps`/`calories` →
/// [movement], `respiratory`/`spo2` → [oxygen], `rem` → [sleep]. `palette.dart`
/// records the collapse; `metric_hue.dart` records which metric lands where.
///
/// **Nothing should read these fields by name.** `tone.dart` is the reader: a
/// card declares a [Tone] and its contents resolve `context.family`. The fields
/// are public only because a `ThemeExtension` cannot hide them.
///
/// ## Why still a second extension rather than fields on `HealtheeColors`
///
/// `HealtheeColors` answers *what surface am I on, what ink do I use, is this
/// reading good or bad*. This one answers *which category is this card about*.
/// Two questions, two extensions, and a reviewer can tell at the call site which
/// one is being asked.
///
/// ## The stage ramp IS v02's — `richer.css`, hex for hex
///
/// [stageDeep] and its three siblings are `--stage-deep`, `--stage-light`,
/// `--stage-rem` and `--stage-awake` exactly as the prototype ships them, in
/// both themes. They were substituted once, on accessibility grounds, for a
/// derived luminance ramp; the owner answered by restating the standing rule —
/// **`design/mobile-preview/` is the specification and we match it** — and the
/// substitution is reverted.
///
/// The measurements that motivated the substitution are **kept in full** in
/// `sleep_stage_palette.dart` and in `test/theme/stage_contrast_test.dart`, where
/// they are now *recordings* rather than gates: the suite prints every pair in
/// both themes and passes. The superseded ramp is kept beside the live one under
/// the same names it always had, labelled as superseded, so the trade stays
/// legible without being re-argued.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/palette.dart';
import 'package:healthee/core/theme/sleep_stage_palette.dart';

/// v02's category families, and the sleep-stage ramp, for one theme.
@immutable
class InstrumentHues extends ThemeExtension<InstrumentHues> {
  /// Builds a hue set. Prefer [InstrumentHues.light] / [InstrumentHues.dark].
  const InstrumentHues({
    required this.fitness, required this.fitnessSoft,
    required this.sleep, required this.sleepSoft,
    required this.heart, required this.heartSoft,
    required this.movement, required this.movementSoft,
    required this.oxygen, required this.oxygenSoft,
    required this.stress, required this.stressSoft,
    required this.strain, required this.strainSoft,
    required this.recovery, required this.recoverySoft,
    required this.stageDeep, required this.stageLight,
    required this.stageRem, required this.stageAwake,
    required this.unstaged,
  });

  /// v02's families, light, with the repaired stage ramp.
  const InstrumentHues.light()
    : fitness = LightFamilies.fitness,
      fitnessSoft = LightFamilies.fitnessSoft,
      sleep = LightFamilies.sleep,
      sleepSoft = LightFamilies.sleepSoft,
      heart = LightFamilies.heart,
      heartSoft = LightFamilies.heartSoft,
      movement = LightFamilies.movement,
      movementSoft = LightFamilies.movementSoft,
      oxygen = LightFamilies.oxygen,
      oxygenSoft = LightFamilies.oxygenSoft,
      stress = LightFamilies.stress,
      stressSoft = LightFamilies.stressSoft,
      strain = LightFamilies.strain,
      strainSoft = LightFamilies.strainSoft,
      recovery = LightPalette.ink2,
      recoverySoft = LightPalette.surface2,
      stageDeep = V02StagePrototype.lightDeep,
      stageLight = V02StagePrototype.lightLight,
      stageRem = V02StagePrototype.lightRem,
      stageAwake = V02StagePrototype.lightAwake,
      unstaged = LightStagePalette.unstaged;

  /// v02's families, dark. Authored by the prototype, not derived from light.
  const InstrumentHues.dark()
    : fitness = DarkFamilies.fitness,
      fitnessSoft = DarkFamilies.fitnessSoft,
      sleep = DarkFamilies.sleep,
      sleepSoft = DarkFamilies.sleepSoft,
      heart = DarkFamilies.heart,
      heartSoft = DarkFamilies.heartSoft,
      movement = DarkFamilies.movement,
      movementSoft = DarkFamilies.movementSoft,
      oxygen = DarkFamilies.oxygen,
      oxygenSoft = DarkFamilies.oxygenSoft,
      stress = DarkFamilies.stress,
      stressSoft = DarkFamilies.stressSoft,
      strain = DarkFamilies.strain,
      strainSoft = DarkFamilies.strainSoft,
      recovery = DarkPalette.ink2,
      recoverySoft = DarkPalette.surface2,
      stageDeep = V02StagePrototype.darkDeep,
      stageLight = V02StagePrototype.darkLight,
      stageRem = V02StagePrototype.darkRem,
      stageAwake = V02StagePrototype.darkAwake,
      unstaged = DarkStagePalette.unstaged;

  /// Recovery, HRV, VO₂max, readiness. Also the app's accent.
  final Color fitness;

  /// The fill behind [fitness] content.
  final Color fitnessSoft;

  /// Sleep, sleep debt, sleep timing.
  final Color sleep;

  /// The fill behind [sleep] content.
  final Color sleepSoft;

  /// Heart rate, resting HR, cardio load.
  final Color heart;

  /// The fill behind [heart] content.
  final Color heartSoft;

  /// Steps, distance, calories, energy.
  final Color movement;

  /// The fill behind [movement] content.
  final Color movementSoft;

  /// Respiratory rate, blood oxygen.
  final Color oxygen;

  /// The fill behind [oxygen] content.
  final Color oxygenSoft;

  /// Stress, skin temperature.
  final Color stress;

  /// The fill behind [stress] content.
  final Color stressSoft;

  /// Cardio load and workouts: its own family, split from [heart].
  final Color strain;

  /// The fill behind [strain] content.
  final Color strainSoft;

  /// Recovery has no hue: its mark is the text-secondary ink, and its state
  /// comes from the zone (67 to 100 better, 34 to 66 watch, 0 to 33 worse).
  final Color recovery;

  /// The well behind [recovery] content.
  final Color recoverySoft;

  /// Deep sleep — `--stage-deep`, the prototype's violet.
  final Color stageDeep;

  /// Light (`core`) sleep — `--stage-light`, the prototype's blue.
  final Color stageLight;

  /// REM — `--stage-rem`, the prototype's magenta.
  final Color stageRem;

  /// Awake — `--stage-awake`, the prototype's amber.
  final Color stageAwake;

  /// A span the strap staged with a code this app cannot name. Chroma-free, so
  /// it is the one value in the set that names no stage.
  final Color unstaged;

  /// **The one sleep-stage mapping.** Every hypnogram, stacked bar and legend
  /// resolves a stage name here and nowhere else.
  ///
  /// ```text
  ///   deep          → stageDeep    violet
  ///   core / light  → stageLight   blue
  ///   rem           → stageRem     magenta
  ///   awake         → stageAwake   amber
  ///   anything else → unstaged     grey, and named "Unrecognised"
  /// ```
  ///
  /// `core` is the server's word for what the strap calls `light`; one stage,
  /// two vocabularies, one colour.
  ///
  /// The fifth row is not legacy's. Legacy defaults an unrecognised code to
  /// `cSpo2` — it draws a byte nobody has decoded **as light sleep**, which is a
  /// claim rather than a colour choice. So the fifth row is a grey and
  /// `sleepStageLabel` answers "Unrecognised" beside it.
  Color sleepStage(String stage) => switch (stage) {
    'deep' => stageDeep,
    'core' || 'light' => stageLight,
    'rem' => stageRem,
    'awake' => stageAwake,
    _ => unstaged,
  };

  /// Whether [stage] is a code this app can name. The predicate the charts and
  /// their legends share, so a grey band and its key cannot disagree.
  static bool isRecognised(String stage) =>
      const <String>{'deep', 'core', 'light', 'rem', 'awake'}.contains(stage);

  @override
  InstrumentHues copyWith({
    Color? fitness, Color? fitnessSoft,
    Color? sleep, Color? sleepSoft,
    Color? heart, Color? heartSoft,
    Color? movement, Color? movementSoft,
    Color? oxygen, Color? oxygenSoft,
    Color? stress, Color? stressSoft,
    Color? strain, Color? strainSoft,
    Color? recovery, Color? recoverySoft,
    Color? stageDeep, Color? stageLight,
    Color? stageRem, Color? stageAwake,
    Color? unstaged,
  }) {
    return InstrumentHues(
      fitness: fitness ?? this.fitness,
      fitnessSoft: fitnessSoft ?? this.fitnessSoft,
      sleep: sleep ?? this.sleep,
      sleepSoft: sleepSoft ?? this.sleepSoft,
      heart: heart ?? this.heart,
      heartSoft: heartSoft ?? this.heartSoft,
      movement: movement ?? this.movement,
      movementSoft: movementSoft ?? this.movementSoft,
      oxygen: oxygen ?? this.oxygen,
      oxygenSoft: oxygenSoft ?? this.oxygenSoft,
      stress: stress ?? this.stress,
      stressSoft: stressSoft ?? this.stressSoft,
      strain: strain ?? this.strain,
      strainSoft: strainSoft ?? this.strainSoft,
      recovery: recovery ?? this.recovery,
      recoverySoft: recoverySoft ?? this.recoverySoft,
      stageDeep: stageDeep ?? this.stageDeep,
      stageLight: stageLight ?? this.stageLight,
      stageRem: stageRem ?? this.stageRem,
      stageAwake: stageAwake ?? this.stageAwake,
      unstaged: unstaged ?? this.unstaged,
    );
  }

  @override
  InstrumentHues lerp(ThemeExtension<InstrumentHues>? other, double t) {
    if (other is! InstrumentHues) {
      return this;
    }
    return InstrumentHues(
      fitness: Color.lerp(fitness, other.fitness, t)!,
      fitnessSoft: Color.lerp(fitnessSoft, other.fitnessSoft, t)!,
      sleep: Color.lerp(sleep, other.sleep, t)!,
      sleepSoft: Color.lerp(sleepSoft, other.sleepSoft, t)!,
      heart: Color.lerp(heart, other.heart, t)!,
      heartSoft: Color.lerp(heartSoft, other.heartSoft, t)!,
      movement: Color.lerp(movement, other.movement, t)!,
      movementSoft: Color.lerp(movementSoft, other.movementSoft, t)!,
      oxygen: Color.lerp(oxygen, other.oxygen, t)!,
      oxygenSoft: Color.lerp(oxygenSoft, other.oxygenSoft, t)!,
      stress: Color.lerp(stress, other.stress, t)!,
      stressSoft: Color.lerp(stressSoft, other.stressSoft, t)!,
      strain: Color.lerp(strain, other.strain, t)!,
      strainSoft: Color.lerp(strainSoft, other.strainSoft, t)!,
      recovery: Color.lerp(recovery, other.recovery, t)!,
      recoverySoft: Color.lerp(recoverySoft, other.recoverySoft, t)!,
      stageDeep: Color.lerp(stageDeep, other.stageDeep, t)!,
      stageLight: Color.lerp(stageLight, other.stageLight, t)!,
      stageRem: Color.lerp(stageRem, other.stageRem, t)!,
      stageAwake: Color.lerp(stageAwake, other.stageAwake, t)!,
      unstaged: Color.lerp(unstaged, other.unstaged, t)!,
    );
  }

  /// Every hue, in declaration order. **Add new hues here too** — this backs
  /// equality, and Flutter compares theme extensions to decide whether a theme
  /// change needs a rebuild.
  List<Color> get _hues => [
    fitness, fitnessSoft, sleep, sleepSoft, heart, heartSoft,
    movement, movementSoft, oxygen, oxygenSoft, stress, stressSoft,
    strain, strainSoft, recovery, recoverySoft,
    stageDeep, stageLight, stageRem, stageAwake, unstaged,
  ];

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! InstrumentHues) {
      return false;
    }
    final mine = _hues;
    final theirs = other._hues;
    for (var i = 0; i < mine.length; i++) {
      if (mine[i] != theirs[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_hues);
}

/// Reaches the hue set from a widget: `context.hues.sleep`.
extension InstrumentHuesOf on BuildContext {
  /// The active theme's category families.
  ///
  /// Throws if the theme was built without the extension, which is the right
  /// behaviour — a silent fallback would let a screen render in colours nobody
  /// chose, and look almost right.
  InstrumentHues get hues => Theme.of(this).extension<InstrumentHues>()!;
}
