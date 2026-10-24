/// Which v02 family a metric belongs to, and which glyph that family wears.
///
/// The prototype keys this off `H.metricDefinitions[id].tone` and the block at
/// the foot of `panels.js`:
///
/// ```js
/// {hr:'heart', rhr:'heart', hrv:'fitness', stress:'stress', spo2:'oxygen',
///  breathing:'oxygen', steps:'movement', energy:'movement', weight:'fitness',
///  load:'heart'}
/// ```
///
/// ## This is an IDENTITY, exactly like `hueFor`, and never a verdict
///
/// `shared/format/metric_polarity.dart` is the other table and it is the
/// opposite thing: it says which *direction* is better and it is the only thing
/// that licenses `fav`/`unf`. This one takes an id and nothing else — there is
/// no reading, no delta and no window in the signature — so a family that
/// depended on how the owner did today is not something a caller can express.
/// `instrument_hues.dart` makes the same argument for the pre-v02 hues and this
/// is the v02 restatement of it.
///
/// **An unknown metric resolves to [Tone.fitness]**, which is `richer.css`
/// `:root` — content outside any `data-tone` is the accent. That is the
/// prototype's own default rather than a colour picked here, and it is not a
/// claim: green is where the cascade starts, not a verdict about the number.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/metric_hue.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:solar_icons/solar_icons.dart';

/// The family [metric] belongs to. Never depends on its value.
///
/// Delegates to `toneFor` in `core/theme/metric_hue.dart`, the single table, so
/// one metric can never resolve to two tones.
Tone toneForMetric(String metric) => toneFor(metric);

/// The glyph the prototype draws beside a panel of [tone].
///
/// `components.js`'s icon set, mapped to the Material names this app already
/// uses for the same families on Today — one glyph per family, so a metric
/// cannot pick up an icon that disagrees with its colour.
IconData iconForTone(Tone tone) => switch (tone) {
  Tone.sleep => SolarIconsOutline.moonSleep,
  Tone.heart || Tone.load => SolarIconsOutline.heart,
  Tone.movement || Tone.activity => SolarIconsOutline.walking,
  Tone.oxygen => SolarIconsOutline.waterdrop,
  Tone.stress => SolarIconsOutline.sun,
  Tone.fitness || Tone.recovery => SolarIconsOutline.heartPulse,
};
