/// Every window the Sleep screen slices out of `/api/sleep`, computed once.
///
/// Extracted out of `sleep_sections.dart` when the v02 rebuild made that file a
/// composition list and nothing else (Standards §3). The slicing did not change:
/// the same fourteen nights, the same seven summaries, the same measured-only
/// debt window and the same 18:00-origin timings the pre-v02 screen used, so a
/// chart drawn from these is drawing the same data it always did.
///
/// Naming them here is also what lets the tests assert the windows without
/// pumping a widget — the seven-night slice appeared three times inline in the
/// screen this replaced, which is three chances for one of them to drift.
library;

import 'package:healthee/data/models/sleep_history.dart';
import 'package:healthee/data/models/sleep_night.dart';
import 'package:healthee/data/models/sleep_page.dart';
import 'package:healthee/features/sleep/sleep_format.dart';
import 'package:meta/meta.dart';

/// One night of the debt window: what was slept, and what to caption it.
typedef DebtNight = ({double totalMin, String label});

/// The slices one render of Sleep draws.
@immutable
class SleepWindows {
  /// Slices [page] against [now].
  factory SleepWindows(SleepPage page, DateTime now) =>
      SleepWindows._of(page.nights, now);

  /// [nights] is newest first, the order `/api/sleep` sends.
  factory SleepWindows._of(List<SleepNight> nights, DateTime now) {
    final latest = nights.first;
    // The nights that HAVE a total. A night with no measurement is not a night
    // of no sleep, and a zero bar would say it was.
    final debt = <DebtNight>[
      for (final night in nights.take(7).toList().reversed)
        if (night.tstMin.valueOrNull case final double minutes)
          (totalMin: minutes, label: weekdayInitials(night.date)),
    ];
    final bedtime = <double>[];
    final wake = <double>[];
    final timingDates = <String>[];
    for (final night in nights.take(29).toList().reversed) {
      final start = night.start;
      final end = night.end;
      if (start != null && end != null) {
        bedtime.add(hoursFrom6pm(start));
        wake.add(hoursFrom6pm(end));
        timingDates.add(shortDate(night.date));
      }
    }
    return SleepWindows._(
      latest: latest,
      previous: nights.length > 1 ? nights[1] : null,
      recent: nights.take(14).toList(),
      earlier: nights.skip(14).take(14).toList(),
      week: <SleepNightSummary>[
        for (final night in nights.take(7).toList().reversed)
          SleepNightSummary(
            date: night.date,
            // See `sleep_history_screen.dart`: a withheld `tst_min` stays withheld.
            durationMin: night.tstMin.valueOrNull?.round(),
            deepMin: night.stages?.deep.round(),
            lightMin: night.stages?.light.round(),
            remMin: night.stages?.rem.round(),
            awakeMin: night.stages?.awake.round(),
            deviceScore: night.deviceScore.valueOrNull?.round(),
          ),
      ],
      debt: debt,
      bedtime: bedtime,
      wake: wake,
      timingDates: timingDates,
      label: nightLabel(latest.end, now),
      stale: noSleepLastNight(latest.end, now),
    );
  }

  const SleepWindows._({
    required this.latest,
    required this.previous,
    required this.recent,
    required this.earlier,
    required this.week,
    required this.debt,
    required this.bedtime,
    required this.wake,
    required this.timingDates,
    required this.label,
    required this.stale,
  });

  /// The same slices, ending on [day] rather than on the newest night.
  ///
  /// **This closes the seam `sleep_history_screen.dart` recorded.** Its night
  /// rows already set `viewDateProvider` and pushed Sleep, and Sleep still
  /// opened on the newest night — so choosing 29 July landed on 31 July's page.
  /// `/api/sleep` sends a dated window rather than one night, so the fix is a
  /// slice and not a request: every night at or before [day] is real, measured,
  /// and already on this phone.
  ///
  /// Null when the window holds no night on or before [day]. "Nothing on or
  /// before this day" is an answer; showing the nearest LATER night would be
  /// answering with a different night under a date nobody chose, which is the
  /// same refusal `ViewDate.select` makes about clamping.
  static SleepWindows? through(SleepPage page, DateTime now, String day) {
    final nights = <SleepNight>[
      for (final night in page.nights)
        if (night.date.compareTo(day) <= 0) night,
    ];
    return nights.isEmpty ? null : SleepWindows._of(nights, now);
  }

  /// The most recent night.
  final SleepNight latest;

  /// The one before it.
  final SleepNight? previous;

  /// The last fourteen nights, newest first.
  final List<SleepNight> recent;

  /// The fourteen nights before those, newest first: the trends' usual.
  final List<SleepNight> earlier;

  /// The last seven nights, oldest first, as the stacked chart's model.
  final List<SleepNightSummary> week;

  /// The measured nights of the last seven, oldest first.
  final List<DebtNight> debt;

  /// Bedtimes on the 18:00 scale, oldest first.
  final List<double> bedtime;

  /// Wake times on the same scale.
  final List<double> wake;

  /// One short date per entry of [bedtime], so the timing chart can caption it.
  final List<String> timingDates;

  /// `Last night` · `3 nights ago`.
  final String label;

  /// Whether the latest session ended more than a day ago.
  final bool stale;

  /// The fortnight's mean total, or null when nothing in it was measured.
  double? get averageTstMin {
    final measured = <double>[
      for (final night in recent)
        if (night.tstMin.valueOrNull case final double minutes) minutes,
    ];
    return measured.isEmpty
        ? null
        : measured.reduce((a, b) => a + b) / measured.length;
  }

  /// The window the stage week covers, as the note under it says it.
  String get weekSpan => week.isEmpty
      ? ''
      : '${shortDate(week.first.date)}–${shortDate(week.last.date)}';

  /// Two is the floor for every conditional chart on this screen: one bar is
  /// not a week, and one point is not a line.
  static const int minimumNights = 2;
}
