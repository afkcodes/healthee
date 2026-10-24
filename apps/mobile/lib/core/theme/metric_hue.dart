/// Which v02 tone a metric belongs to — the one table, so a metric cannot be two
/// colours on two screens.
///
/// **This was a metric → `Color` table and is now a metric → [Tone] table.** The
/// change is the point of the tone system: a screen that asks for a tone gets a
/// name it can hand to a `ToneScope`, and everything inside the card then
/// resolves the same family. [hueFor] survives as the thin resolver for the
/// screens that have not been redesigned yet, so no call site had to move.
///
/// ## What the migration collapsed, and what it did not
///
/// v02 has six families where legacy had ten hues, so pairs merged: HRV and
/// readiness are both [Tone.recovery]; steps and calories are both
/// [Tone.movement]; respiratory rate and SpO₂ are both [Tone.oxygen]. Nothing
/// changed family beyond that forced collapse **except stress**, and that one is
/// deliberate: legacy drew its stress card in `cCal` — the calories hue, which
/// its own port docstring flagged as odd — and v02 gives stress a family of its
/// own (`--stress`, "warm"). Skin temperature moves with it, since it was on
/// legacy's `cStress` already.
///
/// ## The two conflicts legacy had with itself are still resolved the same way
///
/// Cardio load was `cHeart` on Today and `cReady` on Activity; blood oxygen was
/// `cResp` on Today and `cSpo2` on Sleep. Today wins in both — it is the screen
/// the owner opens — and under v02 the second conflict disappears entirely,
/// because `cResp` and `cSpo2` are now one family.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/instrument_hues.dart';
import 'package:healthee/core/theme/tone.dart';

/// The tone for a canonical metric id.
///
/// Ids are the server's (`rhr_daily`, `steps_total`) and the strap's
/// (`resting_hr`, `spo2`), because both halves of Today draw modules and a second
/// table keyed by a second vocabulary is how one metric ends up two colours.
///
/// **The tone is a function of the metric's identity and nothing else.** There is
/// deliberately no overload taking a reading, a z-score or a direction: a caller
/// able to pass a value would turn every card into a verdict by accident, and
/// v02 keeps identity ([Tone]) and judgement (`fav` / `unf` / `alert`) in
/// separate token sets precisely so that cannot happen.
///
/// An unlisted id gets [Tone.fitness] — the `:root` default in `richer.css`, and
/// the same colour legacy's own fallback resolved to.
Tone toneFor(String metric) => switch (metric) {
  'sleep' ||
  'sleep_debt' ||
  'sleep_debt_min' ||
  'sleep_duration' ||
  'tst_min' ||
  'sri' ||
  'sleep_health' ||
  'sleep_health_score_4dim' => Tone.sleep,
  'hrv' ||
  'hrv_sleep_avg' ||
  'rhr_daily' ||
  'resting_hr' ||
  'hr' ||
  'heart_rate' ||
  'max_hr' ||
  'vo2max_estimate' ||
  'vo2max_submax' => Tone.heart,
  'cardio_load' || 'cardio_load_trimp' || 'workouts' => Tone.load,
  'steps_total' ||
  'steps' ||
  'steps_per_minute' ||
  'distance_m' ||
  'distance_m_daily' ||
  'active_calories' ||
  'total_calories' ||
  'mvpa_min' ||
  'moderate_min' ||
  'vigorous_min' => Tone.movement,
  'respiratory_rate' ||
  'respiratory_rate_sleep' ||
  'spo2' ||
  'spo2_overnight' ||
  'spo2_overnight_min' => Tone.oxygen,
  'stress' || 'stress_daily' || 'journal' || 'meditation' => Tone.stress,
  'biological_age' ||
  'weight' ||
  'basal_calories' ||
  'temperature_c' ||
  'skin_temp_c' => Tone.fitness,
  'recovery' || 'readiness' => Tone.recovery,
  _ => Tone.fitness,
};

Color hueFor(InstrumentHues hues, String metric) =>
    toneFor(metric).family(hues);
