/// The week a coach review is FOR, mirrored from the server.
///
/// `jobs/coach_kv.py::week_bounds`: on a Sunday the review sets next week's job,
/// so the week is the one starting tomorrow; any other day it is this week.
/// Monday to Sunday, ISO dates.
library;

/// A day as `yyyy-MM-dd`.
String isoDay(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// The Monday on or before [day], at midnight.
DateTime mondayOf(DateTime day) {
  final date = DateTime(day.year, day.month, day.day);
  return DateTime(date.year, date.month, date.day - (date.weekday - 1));
}

/// Monday and Sunday of the week the review is for, given the owner's [today].
({String from, String to}) coachWeekBounds(DateTime today) {
  final date = DateTime(today.year, today.month, today.day);
  final target = date.weekday == DateTime.sunday
      ? DateTime(date.year, date.month, date.day + 1)
      : date;
  final monday = mondayOf(target);
  final sunday = DateTime(monday.year, monday.month, monday.day + 6);
  return (from: isoDay(monday), to: isoDay(sunday));
}
