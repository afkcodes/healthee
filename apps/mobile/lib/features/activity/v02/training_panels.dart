/// The rest of Activity: the load, the sessions behind it, and the fitness.
///
/// `screens-overview.js::H.screens.activity`, after the intensity panel:
///
/// ```js
/// H.panel('Training load, not just time','heart', value + load bars + three stats + note, 'metric/load','heart')
/// H.section('The sessions behind it', card.flush of two rows, 'workouts')
/// H.link('Record an outdoor workout','record','button full section')
/// H.panel('Fitness with its source','fitness', value + vo2 rail + note, 'fitness')
/// ```
///
/// ## Two substitutions, recorded where they were made
///
/// **The prototype's `7-day / 28-day` pair is not on the wire.** `cardio_load`
/// carries `load` (today) and `baseline_30d`, and nothing else that averages a
/// window. Drawing a "7-day average" from the thirty-day trend would be a second
/// definition of the owner's habitual workload sitting next to the server's, free
/// to disagree with it — CLAUDE.md's one-definition rule is exactly about that.
/// So the ratio names the terms it actually has.
///
/// **The prototype's `Ratio 1.0` is unconditional.** Here it appears only when
/// `baseline_30d` came with it: a ratio against a baseline that is not there is a
/// 1.0 meaning "we had nothing to compare with" and reading as "you are exactly
/// at your normal load".
///
/// ## The error figure is an error MAGNITUDE
///
/// `standard_error` is a model's published SEE, not an interval computed for this
/// owner, and `Vo2maxRail` draws it as a magnitude and says so. That wording is
/// load-bearing and is asserted by `test/mutations.sh`.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/metric_hue.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/data/honesty/disclosure.dart';
import 'package:healthee/data/models/activity_today.dart';
import 'package:healthee/data/models/vo2max.dart';
import 'package:healthee/features/activity/v02/movement_panels.dart';
import 'package:healthee/shared/charts/v02/v02_bar_chart.dart';
import 'package:healthee/shared/format/metric_names.dart';
import 'package:healthee/shared/metric_info/metric_detail.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:healthee/shared/v02/instruments/vo2max_rail.dart';
import 'package:healthee/shared/v02/panel.dart';
import 'package:healthee/shared/v02/panel_head.dart';
import 'package:healthee/shared/v02/panel_parts.dart';
import 'package:solar_icons/solar_icons.dart';

/// The prototype's own line under the load bars.
const String kLoadNote =
    'Compare short-term effort with your established workload.';

/// `Training load, not just time` — today's effort against the habit behind it.
class TrainingLoadPanel extends StatelessWidget {
  /// [load] is the payload's block.
  const TrainingLoadPanel({
    required this.load,
    required this.reveals,
    this.onDetails,
    super.key,
  });

  /// The prototype's title.
  static const String title = 'Training load, not just time';

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
        icon: SolarIconsOutline.heart,
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
            context_: ratioLine(load),
          ),
          if (trend.length > 1)
            RevealOnce(
              id: 'activity.cardio-load',
              registry: reveals,
              builder: (context, t) => V02BarChart(
                <double?>[for (final point in trend) point.value],
                progress: t,
                labels: <String>[
                  for (final point in trend) dayOfMonth(point.date),
                ],
                semanticLabel: 'Training load over the recent days',
              ),
            ),
          if (_stats() case final List<Stat> stats
              when stats.isNotEmpty) ...<Widget>[
            const SizedBox(height: statsGap),
            StatRow(stats),
          ],
          const PanelNote(kLoadNote),
        ],
      ),
    );
  }

  /// `Ratio 1.0` over the two terms it is a ratio OF — never one without them.
  static String? ratioLine(CardioLoad load) {
    final baseline = load.baseline30d;
    if (baseline == null || baseline <= 0) {
      return null;
    }
    final over = load.baselineDaysLabel;
    return 'Ratio ${(load.load / baseline).toStringAsFixed(1)}\n'
        'today / 30-day load${over == null ? '' : ' · $over'}';
  }

  List<Stat> _stats() => <Stat>[
    if (load.baseline30d case final double baseline)
      Stat('30-day load', baseline.round().toString()),
    if (load.strain case final double strain)
      Stat(
        'Strain index',
        strain.round().toString(),
        unit: load.strainMax == null ? null : '/${load.strainMax!.round()}',
      ),
    if (load.hrMinutes case final int minutes)
      Stat('Heart-rate minutes', minutes.toString()),
  ];
}

/// `Fitness with its source` — the estimate, its rail, and its instrument.
class FitnessSourcePanel extends StatelessWidget {
  /// [vo2max] is the payload's block.
  const FitnessSourcePanel({
    required this.vo2max,
    required this.reveals,
    this.onDetails,
    super.key,
  });

  /// The prototype's title.
  static const String title = 'Fitness with its source';

  /// The estimate and everything the server said about how it was made.
  final Vo2max vo2max;

  /// Where "already revealed" is remembered.
  final RevealRegistry reveals;

  /// Opens the fitness screen.
  final VoidCallback? onDetails;

  @override
  Widget build(BuildContext context) {
    return Panel(
      tone: toneFor('vo2max_estimate'),
      label: 'VO₂max · estimate',
      // 300+ characters of server prose about how this number was made. Printed
      // inline it is the essay the owner asked us to stop printing; dropped it
      // is a qualification silently lost. So it travels as a counted signpost
      // with the full sentence one tap behind it.
      caveats: <Disclosure>[vo2max.methodDisclosure],
      head: PanelHead(
        title: title,
        icon: SolarIconsOutline.graphUp,
        infoKey: 'vo2max',
        detail: MetricDetail(
          references: <String>[
            if (vo2max.medianForAge case final double median)
              'Age/sex reference ${median.toStringAsFixed(1)} ml/kg/min',
          ],
          notes: vo2max.researchNotes,
          source: vo2max.standardErrorSource,
        ),
        actionLabel: onDetails == null ? null : 'Details',
        onAction: onDetails,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          PanelValue(
            vo2max.estimate.toStringAsFixed(1),
            unit: 'VO₂max',
            context_: instrument(vo2max),
          ),
          RevealOnce(
            id: 'activity.vo2max-rail',
            registry: reveals,
            builder: (context, t) => Vo2maxRail(
              estimate: vo2max.estimate,
              medianForAge: vo2max.medianForAge,
              errorMagnitude: vo2max.standardErrorMlKgMin,
              progress: t,
            ),
          ),
          const PanelNote(kInstrumentNote),
        ],
      ),
    );
  }

  /// The method that produced this number, in the server's own naming.
  ///
  /// **Never the raw tier id.** `gps_graded` on a health screen is a log line
  /// where an instrument's name belongs, and [[hr_reserve_vo2max]] D4 requires
  /// the method wherever the number is.
  static String instrument(Vo2max vo2max) {
    final sessions = vo2max.sessionCount;
    return <String>[
      'Read by ${methodLabel(vo2max.method)}',
      if (sessions != null && sessions > 0)
        '$sessions recorded ${sessions == 1 ? 'session' : 'sessions'}',
    ].join('\n');
  }
}

/// The prototype's own line under the rail: this estimate is session-based, and
/// the history behind it can be a different instrument.
///
/// **What is deliberately NOT repeated here** is what the ± is not.
/// `Vo2maxRail` prints *"…is the supplied error magnitude, not a confidence
/// interval"* itself, always, and `test/mutations.sh` breaks that wording on
/// purpose. A second copy on the card is a second copy that can be softened
/// without the first moving — the argument `v02_linked_chart.dart` makes for its
/// own caveat.
const String kInstrumentNote =
    'The latest estimate is the one instrument named above. Earlier estimates '
    'can come from a different one and are never averaged with it.';
