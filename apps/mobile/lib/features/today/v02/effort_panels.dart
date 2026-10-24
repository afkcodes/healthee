/// The rest of `Movement → recovery`: effort in context, and the two targets.
///
/// `screens-overview.js::dayCharts`, after the steps: the load panel with its
/// fortnight of bars, then active minutes beside strength.
///
/// ## A ratio is printed only when both of its terms exist
///
/// The prototype writes `load ratio 1.0` unconditionally. Here the acute/chronic
/// line appears only when the server sent `baseline_30d` — a ratio computed
/// against a baseline that is not there is a 1.0 that means "we had nothing to
/// compare with" and reads as "you are exactly at your normal load".
///
/// ## Vigorous minutes count twice, and the note says so
///
/// `weekMin` is the moderate-equivalent total, so `120 moderate + 20 vigorous`
/// is 160. That arithmetic is invisible in the figure and is the first thing a
/// reader would get wrong, so it is written under it rather than left implied.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/data/models/activity_today.dart';
import 'package:healthee/data/models/strength.dart';
import 'package:healthee/shared/charts/v02/v02_bar_chart.dart';
import 'package:healthee/shared/metric_info/metric_detail.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:healthee/shared/v02/panel.dart';
import 'package:healthee/shared/v02/panel_head.dart';
import 'package:healthee/shared/v02/panel_parts.dart';
import 'package:solar_icons/solar_icons.dart';

/// `Effort in context` — today's load against the fortnight behind it.
class EffortPanel extends StatelessWidget {
  /// [load] is the payload's block.
  const EffortPanel({
    required this.load,
    required this.reveals,
    this.onDetails,
    super.key,
  });

  /// The prototype's title.
  static const String title = 'Effort in context';

  /// The gap above the statistics row.
  static const double statsGap = 12;

  /// Today's training load and the trend behind it.
  final CardioLoad load;

  /// Where "already revealed" is remembered.
  final RevealRegistry reveals;

  /// Opens the load metric screen.
  final VoidCallback? onDetails;

  @override
  Widget build(BuildContext context) {
    final trend = load.trend30d;
    return Panel(
      tone: Tone.load,
      label: 'Strain · cardio load',
      head: PanelHead(
        title: title,
        icon: SolarIconsOutline.heartPulse,
        infoKey: 'cardio_load',
        detail: MetricDetail(notes: load.researchNotes),
        actionLabel: onDetails == null ? null : 'Details',
        onAction: onDetails,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          PanelValue(
            load.load.round().toString(),
            unit: 'TRIMP',
            context_: _ratio(load),
          ),
          if (trend.length > 1)
            RevealOnce(
              id: 'today.cardio-load',
              registry: reveals,
              builder: (context, t) => V02BarChart(
                <double?>[for (final point in trend) point.value],
                progress: t,
                labels: <String>[
                  for (final point in trend) _dayOfMonth(point.date),
                ],
                semanticLabel: 'Training load over the recent days',
              ),
            ),
          if (_stats() case final List<Stat> stats) ...<Widget>[
            const SizedBox(height: statsGap),
            StatRow(stats),
          ],
        ],
      ),
    );
  }

  /// `Against a 30-day load of 55` — never a ratio without its denominator.
  static String? _ratio(CardioLoad load) {
    final baseline = load.baseline30d;
    if (baseline == null || baseline <= 0) {
      return null;
    }
    final over = load.baselineDaysLabel;
    return '30-day load ${baseline.round()}${over == null ? '' : ' · $over'}\n'
        'ratio ${(load.load / baseline).toStringAsFixed(1)}';
  }

  List<Stat> _stats() => <Stat>[
    if (load.strain case final double strain)
      Stat(
        'Strain index',
        strain.round().toString(),
        unit: load.strainMax == null ? null : '/${load.strainMax!.round()}',
      ),
    if (load.baseline30d case final double baseline)
      Stat('30-day load', baseline.round().toString()),
    if (load.hrMinutes case final int minutes)
      Stat('Heart-rate minutes', minutes.toString()),
  ];

  /// `2026-07-31` → `31`. A bar label, not a date.
  static String _dayOfMonth(String date) =>
      date.length >= 10 ? date.substring(8, 10) : date;
}

/// `Active minutes` — the week against the published reference.
class ActiveMinutesPanel extends StatelessWidget {
  /// [mvpa] is the payload's block.
  const ActiveMinutesPanel({required this.mvpa, this.onDetails, super.key});

  /// The prototype's title.
  static const String title = 'Active minutes';

  /// The gap above the track.
  static const double trackGap = 14;

  /// This week's moderate-to-vigorous minutes.
  final Mvpa mvpa;

  /// `H.panel(…,'activity')` — the tab this week's minutes are read on. Null
  /// draws no link.
  final VoidCallback? onDetails;

  @override
  Widget build(BuildContext context) {
    return Panel(
      tone: Tone.movement,
      label: 'Active minutes · MVPA',
      head: PanelHead(
        title: title,
        icon: SolarIconsOutline.walking,
        infoKey: 'mvpa',
        detail: MetricDetail(
          references: <String>[
            if (mvpa.weekTarget case final int target)
              'Active minutes: $target min/week',
          ],
          notes: mvpa.researchNotes,
        ),
        actionLabel: onDetails == null ? null : 'Details',
        onAction: onDetails,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          PanelValue('${mvpa.weekMin}', unit: 'min/week'),
          // The ring is drawn only against a target the SERVER sent. It used to
          // fall back to a hard-coded 150, so a payload carrying no target still
          // produced a confident percentage of a number nobody sent — with no
          // `Reading` wrapper and no withheld path to fall into.
          if (mvpa.weekProgress case final double fraction) ...<Widget>[
            const SizedBox(height: trackGap),
            ProgressTrack(fraction: fraction),
          ],
          // KEPT. The `×2` is arithmetic invisible in the figure above it: 120
          // moderate + 20 vigorous is 160, and a reader who does not see the
          // doubling gets the number wrong. That qualifies the figure on this
          // card, so it stays on this card. The reference moved to the ⓘ.
          //
          // Withheld with a reason when a day of the week carries no intensity
          // breakdown: printing the days that DO have one under a weekly label
          // would understate the split by exactly the days nobody measured.
          PanelNote(
            mvpa.hasSplit
                ? '${mvpa.weekModerateMin} moderate + '
                      '${mvpa.weekVigorousMin} vigorous ×2'
                : kMvpaSplitUnmeasuredNote,
          ),
        ],
      ),
    );
  }
}

/// Shown in place of the moderate/vigorous split when a day of the week has none.
///
/// The weekly total above it is unaffected — `mvpa_min` is stored per day and is
/// always a real sum. It is only the SPLIT that a missing breakdown makes
/// unknowable, and saying so is shorter than a total that quietly leaves days out.
const String kMvpaSplitUnmeasuredNote =
    'The moderate/vigorous split is not recorded for every day of this week, so '
    'the total above cannot be broken down.';

/// `Strength` — the other half of the same recommendation, counted separately.
class StrengthPanel extends StatelessWidget {
  /// [strength] is the payload's block.
  const StrengthPanel({required this.strength, this.onDetails, super.key});

  /// The prototype's title.
  static const String title = 'Strength';

  /// This week's strength minutes.
  final Strength strength;

  /// `H.panel(…,'workouts')` — the sessions this figure is counted from. Null
  /// draws no link.
  final VoidCallback? onDetails;

  @override
  Widget build(BuildContext context) {
    return Panel(
      tone: Tone.fitness,
      label: 'Strength · this week',
      // Strength has no `kMetricInfo` entry, and it has citations. Before this
      // sweep its sources sat on the card; without an ⓘ they would simply be
      // gone, which is the one way this change could do harm. So the head takes
      // a detail-only ⓘ: a sheet holding the reference and the source, titled
      // from the panel's own name.
      head: PanelHead(
        title: title,
        icon: SolarIconsOutline.dumbbell,
        detail: MetricDetail(
          title: title,
          references: <String>[
            'Strength: ${strength.targetLowMin}–${strength.targetHighMin} '
                'min/week',
          ],
          notes: <String>[
            if (strength.researchNote case final String note) note,
          ],
        ),
        actionLabel: onDetails == null ? null : 'Details',
        onAction: onDetails,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          PanelValue('${strength.weekMin}', unit: 'min/week'),
          const SizedBox(height: ActiveMinutesPanel.trackGap),
          ProgressTrack(
            fraction: strength.targetHighMin <= 0
                ? 0
                : strength.weekMin / strength.targetHighMin,
          ),
          // KEPT. "tracked separately" says this figure is NOT part of the
          // active-minutes total beside it — a definition of the number, not a
          // lesson about it.
          PanelNote(
            '${strength.sessions} '
            '${strength.sessions == 1 ? 'session' : 'sessions'} · '
            'tracked separately',
          ),
        ],
      ),
    );
  }
}
