/// Number formats. One implementation, so two cards cannot group differently.
///
/// Hand-rolled rather than `intl` for the reason `time_labels.dart` gives: the
/// app has no localisation and would be taking a dependency for locale-aware
/// formats it has no translations for. Extracted here on its second use
/// (Standards §1) — `steps_card.dart` had the grouping inline and the Today grid
/// needed the same digits.
library;

/// `9,264` — thousands separated, so five digits read at a glance.
String groupedInt(int value) {
  final negative = value < 0;
  final digits = value.abs().toString();
  final out = StringBuffer(negative ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      out.write(',');
    }
    out.write(digits[i]);
  }
  return out.toString();
}

/// A figure whose scale is not known in advance — a trend row's value or change.
///
/// One decimal under 100 and none above it, which is the resolution the numbers
/// on this app's screens actually carry: an HRV of `47.3` is a real tenth, a
/// calorie total of `2,140.0` is a tenth nobody measured. Grouped above a
/// thousand for the same reason [groupedInt] exists.
///
/// It is a **display** rule and never a rounding of a stored value: everything
/// that decides anything reads the double.
String decimalLabel(double value) {
  if (value.abs() >= 100) {
    return groupedInt(value.round());
  }
  return value.toStringAsFixed(1);
}

/// `7:50` from a minute count — the legacy grid's sleep figure.
///
/// Deliberately NOT `durationText`'s `7 h 50 min`. A grid cell shows a figure with
/// a small unit beside it, the same shape a heart rate has, and `7h 50m` carries
/// its own units inside the number. The two live side by side rather than one
/// replacing the other: the detail card below still says `7h 50m`, which is the
/// form that reads properly in a sentence.
String clockDuration(int totalMinutes) {
  final hours = totalMinutes ~/ 60;
  final minutes = (totalMinutes % 60).toString().padLeft(2, '0');
  return '$hours:$minutes';
}
