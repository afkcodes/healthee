/// The two cards in the middle of the workout screen: the trace, and the zones.
///
/// `screens-explore.js::H.screens.workout`:
///
/// ```js
/// H.section('Your effort through the run', `<div class="card">
///   <div class="row between">{135 bpm Average heart rate}{badge Peak 168 bpm}</div>
///   H.charts.line(hr_series, {min:60,max:180,start:'07:00',end:'07:30'})
///   <p class="small">Minute averages. Brief low readings remain visible…</p>
/// </div>`)
/// H.section('Time in heart-rate zones', `<div class="card">
///   <div class="factor-bars">Zone 1 … Zone 5</div>
///   <p class="small">28 minutes classified…</p>
///   H.evidence('cardio_load_trimp','About training load')
/// </div>`)
/// ```
///
/// Both are `[data-tone="heart"]` by `H.toneFor('workout')`, so both declare
/// [Tone.heart] once and everything inside resolves it — the trace, the fill,
/// the zone bars. Nothing here is handed a colour.
///
/// ## A GAP BREAKS THE LINE
///
/// The wire is one entry per *recorded* minute, so a stretch the strap did not
/// sample arrives as a jump in `min` and would otherwise be drawn as a straight
/// run between the two minutes either side of it — a heart rate this app never
/// measured, drawn as confidently as the ones it did. [minuteSeries] lays the
/// samples back onto their own minute axis and leaves the unmeasured slots
/// `null`, which is the hole `V02LineChart` breaks its line at.
///
/// ## Why the trace is splined and the zones are not a chart
///
/// Heart rate is a continuous signal sampled once a minute, which is the case
/// `chart_curve.dart` allows a monotone join for; Fritsch–Carlson cannot
/// overshoot the samples, so the curve never draws a beat higher or lower than
/// one that was measured. The zone minutes are **totals**, and a total may never
/// be splined at all — they are bars.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/data/device/device_day.dart';
import 'package:healthee/data/honesty/reading.dart';
import 'package:healthee/data/workouts/workout_readings.dart';
import 'package:healthee/shared/charts/v02/chart_curve.dart';
import 'package:healthee/shared/charts/v02/v02_line_chart.dart';
import 'package:healthee/shared/format/duration.dart';
import 'package:healthee/shared/format/time_labels.dart';
import 'package:healthee/shared/metric_info/metric_detail.dart';
import 'package:healthee/shared/metric_info/metric_info_sheet.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:healthee/shared/v02/controls.dart';
import 'package:healthee/shared/v02/meters.dart';
import 'package:healthee/shared/v02/stat_block.dart';
import 'package:healthee/shared/v02/surfaces.dart';
import 'package:healthee/shared/v02/withheld_panel.dart';
import 'package:solar_icons/solar_icons.dart';

/// The prototype's own line under the trace, without its fixture's disclaimer.
///
/// *"…in this sample"* is the preview telling a reviewer its numbers are made
/// up. `DataFooter` drops the same clause for the same reason.
const String kTraceNote = 'Minute averages. Brief low readings stay visible.';

/// `H.evidence(…, 'About training load')`.
const String kZonesEvidenceLabel = 'About training load';

/// The card's own name for its reading, used by the refusal.
const String kEffortLabel = 'Heart rate · minute averages';

/// The zones card's name for its reading.
const String kZonesLabel = 'Time in heart-rate zones';

/// Where the five buckets are cut, in the ⓘ rather than on the card's face.
const String kZonesMethod =
    'The five buckets are cut at 50, 60, 70, 80 and 90 percent of HRmax. A '
    'minute under half of HRmax is counted in no bucket at all, which is why '
    'the bars can total less than the session.';

/// `Your effort through the run` — the average, the peak, and the trace.
class EffortCard extends StatelessWidget {
  /// Renders [readings]; [reveals] is the screen's registry.
  const EffortCard({required this.readings, required this.reveals, super.key});

  /// The prototype's section title.
  static const String title = 'Your effort through the run';

  /// The gap under the average/peak row.
  static const double headGap = 16;

  /// The gap between the chart and the note.
  static const double noteGap = 12;

  /// The session, with its absences.
  final WorkoutReadings readings;

  /// Where "already revealed" is remembered.
  final RevealRegistry reveals;

  @override
  Widget build(BuildContext context) {
    final series = readings.heartRate;
    return SurfaceCard(
      tone: Tone.heart,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _head(),
          const SizedBox(height: headGap),
          if (series case Withheld<List<DevicePoint>>(:final disclosure))
            WithheldPanel(disclosure: disclosure, label: kEffortLabel)
          else ...<Widget>[
            _trace(series.valueOrNull!),
            const SizedBox(height: noteGap),
            SmallProse(_note()),
          ],
        ],
      ),
    );
  }

  /// `.row.between` — the average on the left, the peak stamped on the right.
  Widget _head() => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: <Widget>[
      Expanded(
        child: StatBlock(
          label: 'Average heart rate',
          value: readings.avgHr.valueOrNull?.toString(),
          unit: 'bpm',
        ),
      ),
      if (readings.maxHr.valueOrNull case final int peak) ...<Widget>[
        const SizedBox(width: headGap),
        StatusBadge('Peak $peak bpm'),
      ],
    ],
  );

  Widget _trace(List<DevicePoint> points) {
    final values = minuteSeries(points);
    return RevealOnce(
      id: 'workout.hr:${points.first.at.toIso8601String()}',
      registry: reveals,
      builder: (context, t) => V02LineChart(
        values,
        progress: t,
        unit: 'bpm',
        curve: SeriesCurve.monotone,
        captions: <String>[
          clockLabel(points.first.at),
          clockLabel(points.last.at),
        ],
        sampleLabels: minuteLabels(points),
        semanticLabel:
            'Heart rate through the session, ${clockLabel(points.first.at)} '
            'to ${clockLabel(points.last.at)}',
      ),
    );
  }

  /// The prototype's sentence, plus the two derived figures it has no box for.
  ///
  /// `avg_pct_hrmax` and `intensity` are real server outputs the pre-v02 card
  /// listed. The redesign gives them no cell of their own, and deleting a
  /// reachable server field because the mock-up has no box for it is a feature
  /// removal wearing a redesign's clothes — `activity_sections.dart` makes the
  /// same call for the insight card. So they qualify the trace, in words.
  String _note() {
    final parts = <String>[kTraceNote];
    final share = readings.avgPercentHrmax.valueOrNull;
    final intensity = readings.detail.intensity;
    if (share != null) {
      parts.add(
        'The average is ${share.round()}% of your HRmax'
        '${intensity == null ? '' : ', which the server calls '
                  '${intensity.toLowerCase()}'}.',
      );
    }
    return parts.join(' ');
  }

  /// One slot per minute from the first sample to the last, holes included.
  ///
  /// Exported so the gap rule can be asserted on the data rather than inferred
  /// from a painted line.
  static List<double?> minuteSeries(List<DevicePoint> points) {
    if (points.isEmpty) {
      return const <double?>[];
    }
    final start = points.first.at;
    final slots = <int, double>{};
    for (final point in points) {
      slots[point.at.difference(start).inMinutes] = point.value;
    }
    final last = points.last.at.difference(start).inMinutes;
    return <double?>[for (var i = 0; i <= last; i++) slots[i]];
  }

  /// The clock label of each slot in [minuteSeries], measured or not.
  static List<String> minuteLabels(List<DevicePoint> points) {
    if (points.isEmpty) {
      return const <String>[];
    }
    final start = points.first.at;
    final last = points.last.at.difference(start).inMinutes;
    return <String>[
      for (var i = 0; i <= last; i++)
        clockLabel(start.add(Duration(minutes: i))),
    ];
  }
}

/// `Time in heart-rate zones` — the five buckets, in the session's own share.
class ZonesCard extends StatelessWidget {
  /// Renders [readings].
  const ZonesCard({required this.readings, super.key});

  /// The prototype's section title.
  static const String title = kZonesLabel;

  /// `.factor-bars { margin-block: 16px }` — the gap under the bars.
  static const double barsGap = 16;

  /// The explainer this card's ⓘ opens.
  static const String infoKey = 'cardio_load';

  /// The corpus note behind the load model the zones feed.
  static const String noteId = 'cardio_load_trimp';

  /// The session, with its absences.
  final WorkoutReadings readings;

  @override
  Widget build(BuildContext context) {
    final zones = readings.zones;
    if (zones case Withheld<List<int>>(:final disclosure)) {
      return SurfaceCard(
        tone: Tone.heart,
        child: WithheldPanel(disclosure: disclosure, label: kZonesLabel),
      );
    }
    final minutes = zones.valueOrNull!;
    return SurfaceCard(
      tone: Tone.heart,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          FactorBars(<Factor>[
            for (var i = 0; i < minutes.length; i++)
              Factor(
                'Zone ${i + 1}',
                _share(minutes[i]),
                tone: Tone.heart,
                reading: durationText(minutes[i]),
              ),
          ]),
          const SizedBox(height: barsGap),
          SmallProse(_note()),
          TextLink(
            label: kZonesEvidenceLabel,
            icon: SolarIconsOutline.infoCircle,
            iconLeading: true,
            onPressed: () => showMetricInfo(
              context,
              infoKey,
              detail: const MetricDetail(
                notes: <String>[noteId],
                method: <String>[kZonesMethod],
              ),
              fallbackTitle: kZonesLabel,
            ),
          ),
        ],
      ),
    );
  }

  /// The whole the bars are a share of: the session, when it was timed.
  ///
  /// The prototype divides by the session's own 30 minutes. Falling back to the
  /// classified total when there is no duration keeps the bars comparable to
  /// each other; it never invents a duration, and the note says which minutes
  /// were counted either way.
  double? _share(int minutes) {
    final whole =
        readings.durationMin.valueOrNull ?? readings.classifiedMinutes;
    return whole <= 0 ? null : minutes / whole;
  }

  /// `28 minutes classified; unclassified minutes aren’t assigned to a zone.`
  String _note() {
    final classified = readings.classifiedMinutes;
    final hrmax = readings.detail.hrmax;
    return <String>[
      '$classified ${classified == 1 ? 'minute' : 'minutes'} classified; '
          'unclassified minutes aren’t assigned to a zone.',
      if (hrmax != null) 'Cut against an HRmax of ${hrmax.round()} bpm.',
    ].join(' ');
  }
}
