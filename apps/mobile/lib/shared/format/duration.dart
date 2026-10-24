/// The one duration format: "7 h 1 min", "8 h", "45 min".
///
/// There used to be seven formatters (`7h 05m`, `7h 5m`, `35m`, `6.3h`...). A
/// duration read two ways on one screen looks like two different measurements,
/// so this is the only definition and the number and its unit are joined with
/// U+00A0 so a unit can never wrap away from its figure.
library;

const String _nbsp = '\u00A0';
const String _minus = '\u2212';

/// A duration split into `(figure, unit)` pairs: `421` is `[(7, h), (1, min)]`.
///
/// The one place the hours/minutes rule lives, so [durationText] and a hero
/// figure that sets its units smaller (`durationSpans`) cannot disagree. The
/// figures are whole, non-negative; the sign is the caller's.
List<(int, String)> durationParts(int absMinutes) {
  final hours = absMinutes ~/ 60;
  final rest = absMinutes % 60;
  return <(int, String)>[
    if (hours > 0) (hours, 'h'),
    if (rest > 0 || hours == 0) (rest, 'min'),
  ];
}

/// [minutes] as `7 h 1 min`, `8 h` (whole hours) or `45 min` (under an hour).
///
/// Rounded to a whole minute first, so 59.6 reads `1 h`, not `60 min`. Zero is
/// `0 min`. A negative duration puts U+2212 in front of the whole of it:
/// `−30 min`, never `-30 min` and never `−1 h −5 min`.
String durationText(num minutes) {
  final whole = minutes.round();
  final sign = whole < 0 ? _minus : '';
  final parts = durationParts(whole.abs());
  return sign +
      parts.map(((int, String) p) => '${p.$1}$_nbsp${p.$2}').join(' ');
}

/// [hours] as an axis or target label: `4 h`, `7.5 h`, `10 h`.
///
/// One decimal at most, and none when the value is whole.
String hoursText(num hours) {
  final rounded = (hours * 10).round() / 10;
  final body = rounded == rounded.roundToDouble()
      ? rounded.round().toString()
      : rounded.toStringAsFixed(1);
  final sign = rounded < 0 ? _minus : '';
  return '$sign${body.replaceFirst('-', '')}${_nbsp}h';
}
