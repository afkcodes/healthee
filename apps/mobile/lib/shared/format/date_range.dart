/// `2026-10-12`, `2026-10-18` → `12 to 18 Oct`; across a month `28 Sep to 4 Oct`.
///
/// Sentence-case words, no dash. An unparseable edge falls back to
/// `shortDate`'s own fallback so the date is still information.
library;

import 'package:healthee/shared/format/date_labels.dart';

/// The words for a span of days.
String dateRangeLabel(String fromIso, String toIso) {
  final from = DateTime.tryParse(fromIso);
  final to = DateTime.tryParse(toIso);
  if (from == null || to == null) {
    return '${shortDate(fromIso)} to ${shortDate(toIso)}';
  }
  if (from.month == to.month && from.year == to.year) {
    return '${from.day} to ${shortDate(toIso)}';
  }
  return '${shortDate(fromIso)} to ${shortDate(toIso)}';
}
