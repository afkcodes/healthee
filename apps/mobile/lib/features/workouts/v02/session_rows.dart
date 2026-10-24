/// The workouts list's two pieces: a day of sessions, and the strength card.
///
/// `screens-explore.js::H.screens.workouts`:
///
/// ```js
/// H.link('Record a workout','record','button full')
/// <div class="section">
///   <p class="tiny-label">Friday, 31 July</p>
///   <div class="card flush section workout-row">{H.row('walk', …, 'workout')}</div>
/// </div>
/// H.section('Weekly strength', `<div class="card">
///   {45 min Recorded strength activity}
///   <p class="small section">One session…shown separately from active minutes.</p>
///   H.evidence('strength_training_mortality')
/// </div>`)
/// ```
///
/// ## The tile is `--accent` here, and that is a CSS rule rather than a choice
///
/// `H.row` puts `data-tone="heart"` on a workout row (`panels.js::H.toneFor`),
/// which would make its `.icon-tile` red — but `screens.css` overrides it:
///
/// ```css
/// .workout-row .icon-tile { background: var(--accent-soft); color: var(--accent); }
/// ```
///
/// So every tile in this card renders in the accent. [Tone.fitness] resolves
/// exactly `--accent` (`icon_tile.dart` records why), so the rendered result is
/// matched by declaring that tone on the row rather than by teaching [IconTile]
/// a second colour path.
///
/// ## The day caption uses the app's date vocabulary
///
/// The prototype writes `Friday, 31 July`; this app has [prettyDate]
/// (`FRI · JUL 31`) and [shortDate] (`31 Jul`), and a third form would be a
/// third opinion about the same day. The caption is [prettyDate] — the same form
/// every v02 header uses for the day the reader is on.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/data/models/strength.dart';
import 'package:healthee/data/workouts/workout_summary.dart';
import 'package:healthee/shared/format/date_labels.dart';
import 'package:healthee/shared/format/duration.dart';
import 'package:healthee/shared/metric_info/metric_detail.dart';
import 'package:healthee/shared/metric_info/metric_info_sheet.dart';
import 'package:healthee/shared/v02/controls.dart';
import 'package:healthee/shared/v02/labels.dart';
import 'package:healthee/shared/v02/list_rows.dart';
import 'package:healthee/shared/v02/stat_block.dart';
import 'package:healthee/shared/v02/surface_cards.dart'
    show PlainCard, SmallProse;
import 'package:solar_icons/solar_icons.dart';

/// `H.evidence(note)`'s default label.
const String kHowWeKnow = 'How we know';

/// The prototype's own sentence under the strength figure.
const String kStrengthSeparate =
    'Strength sessions are shown separately from active minutes.';

/// One local day of recorded sessions: its caption, then its rows.
class WorkoutDayGroup extends StatelessWidget {
  /// [sessions] are all on [date] and are drawn newest first.
  const WorkoutDayGroup({
    required this.date,
    required this.sessions,
    required this.onOpen,
    super.key,
  });

  /// `.card.flush.section` — the card sits 24 px under its caption.
  static const double captionGap = 24;

  /// The local calendar day, `YYYY-MM-DD`.
  final String date;

  /// The day's sessions, newest first.
  final List<WorkoutSummary> sessions;

  /// Opens one session.
  final void Function(WorkoutSummary workout) onOpen;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      TinyLabel(prettyDate(date)),
      const SizedBox(height: captionGap),
      FlushCard(
        rows: <Widget>[
          for (final session in sessions)
            V02ListRow(
              icon: SolarIconsOutline.running,
              title: session.sportName,
              detail: sessionLine(session),
              // `.workout-row .icon-tile` — see the library docstring.
              tone: Tone.fitness,
              onOpen: () => onOpen(session),
            ),
        ],
      ),
    ],
  );
}

/// `30 min · 4.2 km · 135 bpm avg`, dropping whatever the strap did not record.
///
/// **Not the same line as Activity's session rows**, and deliberately not shared
/// with them: that card reads a `DeviceWorkout` off the strap and names the
/// device's calorie count, this one reads a `WorkoutSummary` off the server and
/// names the distance. Two payloads, two lines; a shared formatter would have to
/// take a union of both types to say less than either.
String sessionLine(WorkoutSummary workout) => <String>[
  if (workout.durationMin case final int minutes) durationText(minutes),
  if (workout.distanceM case final double metres)
    '${(metres / 1000).toStringAsFixed(1)} km',
  if (workout.avgHr case final int bpm) '$bpm bpm avg',
].join(' · ');

/// `Weekly strength` — the minutes, and what they are not counted against.
class StrengthCard extends StatelessWidget {
  /// Renders [strength]. A screen with no strength block draws no card.
  const StrengthCard({required this.strength, super.key});

  /// The prototype's section title.
  static const String title = 'Weekly strength';

  /// `.small.section` — the gap between the figure and the sentence.
  static const double copyGap = 24;

  /// This week's strength minutes and the band behind them.
  final Strength strength;

  @override
  Widget build(BuildContext context) {
    final sessions = strength.sessions;
    return PlainCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          StatBlock(
            label: 'Recorded strength activity',
            value: strength.weekMin.toString(),
            unit: 'min',
          ),
          const SizedBox(height: copyGap),
          SmallProse(
            '$sessions ${sessions == 1 ? 'session' : 'sessions'} this week. '
            '$kStrengthSeparate',
          ),
          TextLink(
            label: kHowWeKnow,
            icon: SolarIconsOutline.infoCircle,
            iconLeading: true,
            onPressed: () => showMetricInfo(
              context,
              null,
              detail: MetricDetail(
                title: title,
                notes: <String>[
                  if (strength.researchNote case final String note) note,
                ],
                // The band the owner asked us to take off the card faces. It is
                // kept, one tap behind the figure — `metric_detail.dart`.
                references: <String>[
                  'Weekly band ${strength.targetLowMin}–'
                      '${strength.targetHighMin} min',
                ],
              ),
              fallbackTitle: title,
            ),
          ),
        ],
      ),
    );
  }
}

/// [sessions] grouped by their local calendar day, newest day first.
///
/// The key is the LOCAL date, because the caption above a group is the day the
/// owner ran on. A UTC key would file a 23:30 session under tomorrow for anyone
/// east of Greenwich — the calendar-date-against-instant defect this repo has
/// already paid for once.
List<({String date, List<WorkoutSummary> sessions})> byDay(
  List<WorkoutSummary> sessions,
) {
  final ordered = <WorkoutSummary>[...sessions]
    ..sort((a, b) => b.start.compareTo(a.start));
  final days = <String, List<WorkoutSummary>>{};
  for (final session in ordered) {
    final local = session.start.toLocal();
    final key =
        '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
    days.putIfAbsent(key, () => <WorkoutSummary>[]).add(session);
  }
  return <({String date, List<WorkoutSummary> sessions})>[
    for (final entry in days.entries) (date: entry.key, sessions: entry.value),
  ];
}
