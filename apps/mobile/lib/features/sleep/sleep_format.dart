/// Every string the Sleep tab formats — **legacy's helpers, ported**.
///
/// `healthee-legacy/app/lib/ui/sleep_screen.dart:14–120`. Same rounding, same
/// separators, same clock style, so a ported card reads character-for-character
/// as the legacy card it came from.
///
/// ## The one change, and it is the port's whole point
///
/// Legacy's helpers each answered `'—'` for a null input, which is how a missing
/// number reached the screen looking like a number. **Nothing here takes a
/// nullable.** A value that might be absent is a `Reading` before it gets this
/// far, and the widget decides what an absence looks like. The dash is gone
/// because the type that produced it is gone.
library;

import 'package:healthee/core/theme/stage_colors.dart';

/// An instant → `11:30p`. Legacy's `_clock`.
String clock(DateTime at) {
  final hour = at.hour % 12 == 0 ? 12 : at.hour % 12;
  return '$hour:${at.minute.toString().padLeft(2, '0')}${at.hour < 12 ? 'a' : 'p'}';
}

/// Hours from 18:00 local, 0–24. Legacy's `_hoursFrom6pm`.
///
/// The scale runs continuously through midnight — 18:00→0, 22:00→4, midnight→6,
/// 06:00→12 — which is what lets the timing chart draw a bedtime and a wake time
/// on one axis without the line wrapping at the date boundary.
double hoursFrom6pm(DateTime at) => (at.hour + at.minute / 60.0 - 18 + 24) % 24;

/// Canonical stage normalisation. Legacy's `_normStage`, with its default fixed.
///
/// `light` becomes **`core`**, which is legacy's vocabulary rather than the
/// server's. Both resolve to the same colour in `InstrumentHues.sleepStage`, so
/// the mapping is about the word on the label and not about the paint.
///
/// **Legacy's last line was `return 'core'`** — every code it did not match came
/// back as light sleep, including an empty string and a byte nobody has decoded.
/// That is `HColors.sleepStage`'s silent-mislabel bug wearing a different hat:
/// one function turns the unknown code into a named stage and the other paints
/// it, so the grey never gets a chance to appear. Unmatched now returns
/// [kUnrecognisedStage], which paints grey and labels "Unrecognised".
String normaliseStage(String? raw) {
  final stage = (raw ?? '').toLowerCase();
  if (stage.contains('deep')) {
    return 'deep';
  }
  if (stage.contains('rem')) {
    return 'rem';
  }
  if (stage.contains('wake') || stage.contains('awake')) {
    return 'awake';
  }
  if (stage.contains('light') || stage.contains('core')) {
    return 'core';
  }
  return kUnrecognisedStage;
}

/// A nap's clock range → `2:30 pm–3:05 pm`. Legacy's `_napRange`.
///
/// Note this is a different clock format from [clock] — a space before the
/// meridiem and both letters. That is legacy's, kept.
String napRange(DateTime start, DateTime end) {
  String at(DateTime moment) {
    final hour = moment.hour % 12 == 0 ? 12 : moment.hour % 12;
    return '$hour:${moment.minute.toString().padLeft(2, '0')} '
        '${moment.hour < 12 ? 'am' : 'pm'}';
  }

  return '${at(start)}–${at(end)}';
}

/// `2026-08-04` → `4 Aug`. **The one short date on this screen.**
///
/// Legacy had two, and used both: `_napDate` gave `4 Aug` in the naps column and
/// `_shortDate` gave `Aug 4` in the odd-nights list, one card apart. Two
/// orderings for one kind of value on one screen is the sort of thing a reader
/// notices without being able to say why the page feels unfinished.
///
/// Day-month wins because it is the form the screen renders most — up to eight
/// nap rows against a handful of odd nights — so unifying changes the fewest
/// strings. An unparseable date returns the empty string, which is `_napDate`'s
/// behaviour; `_shortDate` echoed the raw ISO back, and a `2026-08-04` in a
/// 50 px column is not a date, it is a leak.
String shortDate(String? iso) {
  final day = _date(iso);
  return day == null ? '' : '${day.day} ${_months[day.month - 1]}';
}

/// `2026-08-04` → `Tu`. Legacy's `_weekday`.
String weekdayInitials(String? iso) {
  final day = _date(iso);
  return day == null ? '' : _weekdays[(day.weekday - 1) % 7];
}

/// `Last night` when the session ended this morning, else how stale it is.
///
/// Legacy's `_nightLabel`. The whole point is that a session you slept two days
/// ago must not be captioned as last night's — [now] is a parameter here rather
/// than `DateTime.now()` so a test can prove that rather than trust it.
String nightLabel(DateTime? end, DateTime now) {
  if (end == null) {
    return 'Last night';
  }
  final daysAgo = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(end.year, end.month, end.day)).inDays;
  if (daysAgo <= 0) {
    return 'Last night';
  }
  if (daysAgo == 1) {
    return 'Night before last';
  }
  return '$daysAgo nights ago';
}

/// True when the latest sleep ended 24 h ago or more. Legacy's
/// `_noSleepLastNight` — the trigger for the banner that dates the whole page.
bool noSleepLastNight(DateTime? end, DateTime now) =>
    end != null && now.difference(end).inHours >= 24;

const List<String> _months = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

const List<String> _weekdays = <String>[
  'Mo',
  'Tu',
  'We',
  'Th',
  'Fr',
  'Sa',
  'Su',
];

DateTime? _date(String? iso) => iso == null ? null : DateTime.tryParse(iso);
