/// How water numbers and times are written. Pure, so tests need no widgets.
library;

/// `2000` as `2,000`.
String groupedMl(int value) {
  final digits = value.abs().toString();
  final out = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// `13:05` as `1:05`: 12 hour, no am or pm, as the glass labels are drawn.
String glassTime(DateTime at) {
  final local = at.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  return '$hour:${local.minute.toString().padLeft(2, '0')}';
}
