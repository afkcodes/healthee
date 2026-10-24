/// Date labels. One implementation, so two headers cannot word a day differently.
///
/// Extracted out of `features/today/today_labels.dart` on its second use
/// (Standards §1): Activity and Insights draw the same `.page-header` date as
/// Today, and `features/` may not reach into another feature (Standards §3). The
/// original file re-exports this one, so every existing call site is unchanged
/// and there is still exactly one definition.
library;

/// `2026-08-04` → `TUE · AUG 4`. Legacy's `_prettyDate`.
///
/// Falls back to the raw string uppercased when the date will not parse, which
/// is legacy's own `catch` — an unparseable date is still information, and a
/// blank where a date belongs reads as a broken header.
String prettyDate(String iso) {
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) {
    return iso.toUpperCase();
  }
  const days = <String>['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
  const months = <String>[
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
  ];
  return '${days[parsed.weekday - 1]} · ${months[parsed.month - 1]} ${parsed.day}';
}

/// `2026-08-04` → `Tue 4 Aug`. The sentence-case day line of a redesigned head.
String dayDateLine(String iso) {
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) {
    return iso;
  }
  const days = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return '${days[parsed.weekday - 1]} ${shortDate(iso)}';
}

/// `2026-07-18` → `18 Jul`. The prototype's chart captions and table rows.
///
/// `history-data.js`: `Intl.DateTimeFormat('en-GB', {day:'numeric',
/// month:'short'})`. Separate from [prettyDate] because they answer different
/// questions — a header names the day the reader is on, and a chart caption
/// names an edge of a window — and one form used for both would either put a
/// weekday on thirty axis labels or take it off the header that needs it.
///
/// Same fallback as [prettyDate]: an unparseable date is still information.
String shortDate(String iso) {
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) {
    return iso.toUpperCase();
  }
  const months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${parsed.day} ${months[parsed.month - 1]}';
}

/// The word for a day when the day itself is the header.
///
/// `Today` on the newest day the window reaches, `WED · SEP 9` on any other.
/// The screen's name used to be a fixed `Today` in 27px type over a separate
/// date line; folding the two together is what makes the head one row, and it
/// stops the largest word on the screen being one that is only true until
/// midnight — on a day the owner has stepped back to, it now says which day.
String dayTitle(String iso, {required String latest}) =>
    iso == latest ? 'Today' : prettyDate(iso);
