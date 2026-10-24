/// The owner's usual for a nightly measurement, from the Sleep page's nights.
///
/// `usual_range.dart` holds the one definition of the band; this only says
/// which nights feed it: the [kUsualWindowDays] nights filed before [day], the
/// night itself left out. Shared by the reading at the top of Sleep and the
/// overnight vitals, so both draw the same window.
library;

import 'package:healthee/data/models/sleep_night.dart';
import 'package:healthee/shared/usual_range.dart';

/// The usual range of [pick] over the nights before [day], or null when fewer
/// than `kUsualMinDays` of them carry a value.
UsualRange? usualOfNights(
  Iterable<SleepNight> nights,
  String day,
  double? Function(SleepNight night) pick,
) {
  final end = DateTime.parse(day);
  final start = end.subtract(const Duration(days: kUsualWindowDays));
  return usualRangeOf(<double>[
    for (final night in nights)
      if (DateTime.tryParse(night.date) case final DateTime date
          when date.isBefore(end) && !date.isBefore(start))
        ?pick(night),
  ]);
}
