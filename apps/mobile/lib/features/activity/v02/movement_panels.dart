/// The two movement panels Activity opens with.
///
/// `screens-overview.js::H.screens.activity`, top to bottom:
///
/// ```js
/// H.panel('Today’s movement','movement', value + bars + three stats, 'metric/steps','walk')
/// H.panel('Your week, by intensity','movement', value + bars + three stats + note + evidence, 'metric/mvpa','walk')
/// ```
///
/// ## The step chart here is a WEEK, not the day's buckets
///
/// Today draws `today_step_buckets` — fifteen minutes to a bar. This one draws
/// `H.demo.activity.steps.trend.slice(-7)`, one bar per day. They are different
/// claims about different windows and neither substitutes for the other, which
/// is why the two screens do not share a panel.
///
/// **The `steps_total` sparkline arrives now**, and for most of this project it
/// did not: `read/today_series.py` had no slot for it, so this chart drew
/// `ChartVoid` for every owner on every request. It still does whenever the
/// series is absent — nothing, at full height, which is the correct render of a
/// series the server did not send, and the reason nothing here pads a series to
/// reach seven bars.
///
/// ## What stays on the card
///
/// Which of the strap's TWO step numbers this is. `steps_card.dart` spent a
/// docstring on it and the memory index carries it as #121: the strap keeps a
/// since-midnight counter and a per-minute buffer that this firmware freezes
/// mid-day, and the number here is the counter. That is instrument naming, so it
/// stays where the number is (`metric_detail.dart`'s line).
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/data/device/device_day.dart';
import 'package:healthee/data/honesty/reading.dart';
import 'package:healthee/data/models/activity_today.dart';
import 'package:healthee/data/models/strength.dart';
import 'package:healthee/data/models/today_snapshot.dart';
import 'package:healthee/data/models/trend_point.dart';
import 'package:healthee/shared/charts/v02/v02_bar_chart.dart';
import 'package:healthee/shared/format/number_labels.dart';
import 'package:healthee/shared/metric_info/metric_detail.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:healthee/shared/usual_range.dart';
import 'package:healthee/shared/v02/panel.dart';
import 'package:healthee/shared/v02/panel_head.dart';
import 'package:healthee/shared/v02/panel_parts.dart';
import 'package:healthee/shared/v02/steps_bar.dart';
import 'package:solar_icons/solar_icons.dart';

/// Which step number this is, and that the kcal beside it are modelled.
///
/// KEPT ON THE CARD, both halves. The first names the instrument behind the
/// figure; the second says a modelled number is standing next to measured ones.
const String kMovementInstrumentNote =
    'The strap’s own since-midnight counter, not a sum of per-minute samples, '
    'because that stream freezes on this firmware. Energy is modelled.';

/// The `×2` is arithmetic invisible in the figure above it, and "recorded
/// separately" is a definition of the strength number rather than a lesson.
const String kIntensityNote =
    'Vigorous minutes count twice. Strength is recorded separately.';

/// What the card says when the week behind today's count is empty.
///
/// Required by `ChartVoid`'s own contract: it holds the chart's height and
/// paints nothing, so that an absent series reads as an absence rather than a
/// shorter card — and it is the panel's job to say what the absence is.
const String kNoStepWeekNote =
    'No earlier days to chart yet. The week fills in as this phone collects '
    'them.';

/// `Today’s movement` — the day's steps, the week behind them, what it cost.
class MovementPanel extends StatelessWidget {
  /// [day] is this phone's own store; [snapshot] is the server's view.
  const MovementPanel({
    required this.day,
    required this.snapshot,
    required this.reveals,
    this.onDetails,
    super.key,
  });

  /// The prototype's title.
  static const String title = 'Today’s movement';

  /// The gap above the statistics row.
  static const double statsGap = 12;

  /// How many days of steps the prototype draws.
  static const int trendDays = 7;

  /// What the strap measured, with its refusals.
  final DeviceDay day;

  /// The server's payload, or null when it has not answered.
  final TodaySnapshot? snapshot;

  /// Where "already revealed" is remembered.
  final RevealRegistry reveals;

  /// Opens the steps metric screen.
  final VoidCallback? onDetails;

  @override
  Widget build(BuildContext context) {
    final steps = day.steps.valueOrNull;
    final trend = _trend();
    return Panel(
      tone: Tone.movement,
      label: 'Steps',
      head: PanelHead(
        title: title,
        icon: SolarIconsOutline.walking,
        infoKey: 'steps_total',
        actionLabel: onDetails == null ? null : 'Details',
        onAction: onDetails,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          PanelValue(
            steps == null ? '—' : groupedInt(steps),
            unit: 'steps',
            context_: steps == null ? _refusal(day.steps) : _measured(day),
          ),
          // The redesign's grammar: today's count on the owner's own usual,
          // the same bar Today's movement card draws (`steps_bar.dart`).
          if (steps != null) ...<Widget>[
            stepsBar(steps, _band(), live: snapshot?.asOf?.isToday ?? true),
            const SizedBox(height: statsGap),
          ],
          RevealOnce(
            id: 'activity.step-week',
            registry: reveals,
            builder: (context, t) => V02BarChart(
              <double?>[for (final point in trend) point.value],
              progress: t,
              labels: <String>[
                for (final point in trend) dayOfMonth(point.date),
              ],
              semanticLabel: 'Steps over the recent days',
            ),
          ),
          // **`ChartVoid` holds the slot and draws nothing on purpose**, and
          // its contract is that the CARD supplies the words. This card did
          // not, so an empty week was a blank band the height of the chart
          // with nothing saying why — and it was empty for every owner on
          // every request, because `read/today_series.py` had no `steps_total`
          // sparkline slot at all. The slot exists now; this sentence covers
          // the case that remains, which is a phone that has not collected a
          // week yet.
          if (trend.isEmpty) const PanelNote(kNoStepWeekNote),
          if (_energy() case final List<Stat> stats
              when stats.isNotEmpty) ...<Widget>[
            const SizedBox(height: statsGap),
            StatRow(stats),
          ],
          const PanelNote(kMovementInstrumentNote),
        ],
      ),
    );
  }

  /// The middle half of the days before this one, from the server's series.
  UsualRange? _band() => switch (snapshot) {
    final TodaySnapshot payload => usualRangeOf(
      windowBefore(payload.sparkline('steps_total'), payload.date),
    ),
    null => null,
  };

  /// The last [trendDays] days of steps the server sent — never padded.
  List<TrendPoint> _trend() {
    final series = snapshot?.sparkline('steps_total') ?? const <TrendPoint>[];
    return series.length <= trendDays
        ? series
        : series.sublist(series.length - trendDays);
  }

  /// `6.71 km · 412 kcal by the strap’s count` over `Daily total`.
  ///
  /// The strap's own calorie figure is **attributed to the strap**, and that is
  /// not politeness: CLAUDE.md pins free-living energy to the server's
  /// MET-by-state model, so a kcal number measured by the device has to be
  /// unmistakably the device's and not the product's. It sits here rather than
  /// in the `.three` row because that row is the server's three figures and
  /// mixing the two instruments inside it is how they stop being distinguishable.
  ///
  /// Each half is dropped when the strap withheld it; with neither, the slot is
  /// the `Daily total` label alone.
  static String _measured(DeviceDay day) {
    final parts = <String>[
      if (day.distanceKm.valueOrNull case final double km)
        '${km.toStringAsFixed(2)} km',
      if (day.deviceCalories.valueOrNull case final int kcal)
        "$kcal kcal by the strap's own count",
    ];
    return parts.isEmpty ? 'Daily total' : '${parts.join(' · ')}\nDaily total';
  }

  /// The strap's own reason, beside the dash, when it refused the count.
  static String? _refusal(Reading<int> steps) =>
      steps is Withheld<int> ? steps.disclosure.message : null;

  /// Active energy, total energy, and today's active minutes.
  List<Stat> _energy() {
    final payload = snapshot;
    if (payload == null) {
      return const <Stat>[];
    }
    final active = payload.metric('active_calories')?.reading.valueOrNull;
    final total = payload.metric('total_calories')?.reading.valueOrNull;
    final minutes = payload.mvpa.valueOrNull?.todayMin;
    return <Stat>[
      if (active != null)
        Stat('Active energy', groupedInt(active.round()), unit: 'kcal'),
      if (total != null)
        Stat('Total energy', groupedInt(total.round()), unit: 'kcal'),
      if (minutes != null) Stat('Active today', '$minutes', unit: 'min'),
    ];
  }
}

/// `Your week, by intensity` — the moderate-equivalent week, and its parts.
class IntensityPanel extends StatelessWidget {
  /// [mvpa] is the payload's block; [strength] may be absent.
  const IntensityPanel({
    required this.mvpa,
    required this.strength,
    required this.reveals,
    this.onDetails,
    super.key,
  });

  /// The prototype's title.
  static const String title = 'Your week, by intensity';

  /// The gap above the statistics row.
  static const double statsGap = 12;

  /// This week's moderate-to-vigorous minutes.
  final Mvpa mvpa;

  /// This week's strength minutes, when the payload carried them.
  final Strength? strength;

  /// Where "already revealed" is remembered.
  final RevealRegistry reveals;

  /// Opens the active-minutes metric screen.
  final VoidCallback? onDetails;

  @override
  Widget build(BuildContext context) {
    final week = strength;
    return Panel(
      tone: Tone.movement,
      label: 'Active minutes · MVPA',
      head: PanelHead(
        title: title,
        icon: SolarIconsOutline.walking,
        infoKey: 'mvpa',
        // The reference used to be a pill on the card's face. It is kept, one
        // tap away, rather than deleted: a cutoff with no source is a number
        // this app made up.
        detail: MetricDetail(
          references: <String>[
            'Active minutes: ${mvpa.weekTarget} min/week',
            if (week != null)
              'Strength: ${week.targetLowMin}–${week.targetHighMin} min/week',
          ],
          notes: <String>[
            ...mvpa.researchNotes,
            if (week?.researchNote case final String note) note,
          ],
        ),
        actionLabel: onDetails == null ? null : 'Details',
        onAction: onDetails,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          PanelValue('${mvpa.weekMin}', unit: 'equivalent min'),
          RevealOnce(
            id: 'activity.intensity-week',
            registry: reveals,
            builder: (context, t) => V02BarChart(
              <double?>[for (final day in mvpa.daily) day.mvpaMin.toDouble()],
              progress: t,
              labels: <String>[
                for (final day in mvpa.daily) weekdayInitial(day.date),
              ],
              semanticLabel: 'Moderate-equivalent minutes over the recent days',
            ),
          ),
          const SizedBox(height: statsGap),
          StatRow(<Stat>[
            Stat('Moderate', '${mvpa.weekModerateMin}', unit: 'min'),
            Stat('Vigorous', '${mvpa.weekVigorousMin}', unit: 'min'),
            if (week != null) Stat('Strength', '${week.weekMin}', unit: 'min'),
          ]),
          const PanelNote(kIntensityNote),
        ],
      ),
    );
  }
}

/// `2026-07-31` → `31`. A bar label, not a date.
String dayOfMonth(String date) =>
    date.length >= 10 ? date.substring(8, 10) : date;

/// `2026-07-31` → `F`. The prototype's `M T W T F` axis.
///
/// Falls back to the day of the month when the date will not parse, which is a
/// label that is still true rather than a blank tick.
String weekdayInitial(String date) {
  final parsed = DateTime.tryParse(date);
  if (parsed == null) {
    return dayOfMonth(date);
  }
  const initials = <String>['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  return initials[parsed.weekday - 1];
}
