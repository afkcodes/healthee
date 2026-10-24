/// `Sleep timing` — when the owner went to bed, and when they got up.
///
/// `design/mobile-preview/sleep-history-view.js`:
///
/// ```js
/// H.panel('Sleep timing','sleep',
///   `${rhythm(week)}${H.evidence('sleep_regularity_index','About regularity')}`,
///   '', 'clock')
/// ```
///
/// ## The owner asked for this chart by name
///
/// > *"the current has a graph for sleeptime vs wake time I would love to keep
/// > that graph along with all v2 sleep."*
///
/// So the plot inside this panel is the app's own [V02TimingChart] — two lines
/// on one 18:00-origin scale — rather than the prototype's `H.charts.consistency`,
/// which draws seven identical bars at fixed coordinates with no data behind
/// them. What was restyled and what was kept is recorded in that chart's own
/// docstring; the short version is that its geometry and its two series are
/// untouched and its chrome is now v02's.
///
/// ## What else is in the panel
///
/// `/api/sleep/consistency` — a **separate read that fails on its own** — carries
/// the typical onset band, the median bed and wake clocks, the nights that sit
/// outside the band and a server-authored action. All of it is drawn under the
/// chart when it arrives and none of it when it does not; the chart is the half
/// of this panel that comes from `/api/sleep` and never waits on the other read.
///
/// The SRI arrives with its own withheld block (`read/sleep_extras.py` nulls it
/// whenever it is not current and moves the value into `sri_withheld` "where it
/// carries its own date and age"), so it is rendered through `ReadingView` and a
/// stale reading says so instead of vanishing.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/core/theme/type_scale.dart';
import 'package:healthee/data/honesty/citations.dart';
import 'package:healthee/data/honesty/reading.dart';
import 'package:healthee/data/models/sleep_consistency.dart';
import 'package:healthee/features/sleep/sleep_format.dart';
import 'package:healthee/shared/charts/v02/chart_void.dart';
import 'package:healthee/shared/charts/v02/v02_timing_chart.dart';
import 'package:healthee/shared/metric_info/metric_detail.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:healthee/shared/states/grounded_text.dart';
import 'package:healthee/shared/states/reading_view.dart';
import 'package:healthee/shared/v02/colour_key.dart';
import 'package:healthee/shared/v02/panel.dart';
import 'package:healthee/shared/v02/panel_head.dart';
import 'package:healthee/shared/v02/panel_parts.dart';
import 'package:solar_icons/solar_icons.dart';

/// What a flat pair of lines means, and what a drifting pair means.
const String kTimingNote =
    'Flat lines are consistent timing; drift is circadian variability. The '
    'scale starts at 18:00 so a bedtime either side of midnight stays one run.';

/// `Sleep timing` — the bedtime and wake chart, and the regularity around it.
class SleepTimingPanel extends StatelessWidget {
  /// [bedtime] and [wake] are hours from 18:00, oldest first.
  const SleepTimingPanel({
    required this.bedtime,
    required this.wake,
    required this.dates,
    required this.consistency,
    required this.reveals,
    super.key,
  });

  /// The prototype's title.
  static const String title = 'Sleep timing';

  /// The plot's height, before its readout line.
  static const double chartHeight = 150;

  /// The gap above the legend.
  static const double legendGap = 10;

  /// The gap above the regularity block.
  static const double blockGap = 14;

  /// Sleep onset, in hours from 18:00.
  final List<double> bedtime;

  /// Wake, in the same units.
  final List<double> wake;

  /// One short date per night, for the captions and the scrub readout.
  final List<String> dates;

  /// The regularity block, or null when that read has not answered.
  final SleepConsistency? consistency;

  /// Where "already revealed" is remembered.
  final RevealRegistry reveals;

  @override
  Widget build(BuildContext context) {
    final block = consistency;
    return Panel(
      tone: Tone.sleep,
      label: 'Bedtime · wake-time · ${bedtime.length} nights',
      head: PanelHead(
        title: title,
        icon: SolarIconsOutline.clockCircle,
        infoKey: 'sleep_consistency',
        // The server-authored action is the one string on this panel a model
        // wrote, so its sources join the explainer's in the head's ⓘ.
        detail: MetricDetail.grounded(
          groundingOf(block?.action ?? ''),
          method: const <String>[kTimingNote],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (bedtime.length < 2)
            const ChartVoid(height: chartHeight)
          else
            RevealOnce(
              id: 'sleep.timing',
              registry: reveals,
              builder: (context, t) => V02TimingChart(
                bedtime: bedtime,
                wake: wake,
                progress: t,
                captions: dates.isEmpty
                    ? const <String>[]
                    : <String>[dates.first, dates.last],
                nightLabels: dates,
                height: chartHeight,
                semanticLabel: 'Bedtime and wake time over recent nights',
              ),
            ),
          const SizedBox(height: legendGap),
          const ColourKey(<ColourKeyEntry>[
            ColourKeyEntry('Bedtime', tone: Tone.sleep),
            ColourKeyEntry('Wake-time', tone: Tone.movement),
          ]),
          if (block != null && block.hasBand) ...<Widget>[
            const SizedBox(height: blockGap),
            _BandBlock(block: block),
          ],
          if (block != null && block.irregularNights.isNotEmpty) ...<Widget>[
            const SizedBox(height: blockGap),
            _OffPattern(nights: block.irregularNights),
          ],
          if (block?.action case final String action when action.isNotEmpty)
            _Action(action: action),
          PanelNote(
            bedtime.length < 2
                ? 'Fewer than two nights carry both a bedtime and a wake time, '
                      'so there is no line to draw.'
                : kTimingNote,
          ),
        ],
      ),
    );
  }
}

/// The typical onset band, the median clocks, and the SRI beside them.
class _BandBlock extends StatelessWidget {
  const _BandBlock({required this.block});

  final SleepConsistency block;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final band = block.onsetBandH!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '${band.toStringAsFixed(1)} h',
              style: TypeScale.statValue.copyWith(color: colors.ink),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'typical bedtime band\n${block.onsetBand ?? ''}'.trim(),
                style: TypeScale.panelContext.copyWith(color: colors.ink2),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: ReadingView<double>(
                reading: block.sri,
                label: 'Sleep regularity',
                withheldBuilder: (context, disclosure) => Text(
                  'SRI —',
                  textAlign: TextAlign.right,
                  style: TypeScale.statUnit.copyWith(color: colors.ink2),
                ),
                builder: (context, sri) => Text(
                  'SRI ${sri.round()}',
                  textAlign: TextAlign.right,
                  style: TypeScale.panelTitle.copyWith(color: colors.ink),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Flexible(
              child: Text(
                _times(block),
                style: TypeScale.tinyLabel.copyWith(color: colors.ink2),
              ),
            ),
            if (block.late) ...<Widget>[
              const SizedBox(width: 8),
              Text(
                'VERY LATE',
                style: TypeLadder.label.copyWith(color: colors.alert),
              ),
            ],
          ],
        ),
        // The SRI's own reason, in words, inside the card that owns it.
        if (block.sri case Withheld<double>(:final disclosure))
          PanelNote('Sleep regularity: ${disclosure.message}'),
      ],
    );
  }

  /// Each half is dropped when it was not measured, so the line states only
  /// what there is.
  static String _times(SleepConsistency block) {
    final parts = <String>[
      if (block.medianBedtime case final String bed) 'Bed ~$bed',
      if (block.meanWake case final String wake) 'wake ~$wake',
    ];
    return parts.isEmpty ? 'No median bedtime yet' : parts.join(' · ');
  }
}

/// The nights that sit outside the band.
class _OffPattern extends StatelessWidget {
  const _OffPattern({required this.nights});

  final List<IrregularNight> nights;

  /// How many the panel shows before it stops.
  static const int shown = 4;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          'Off-pattern nights, more than two hours from your usual:',
          style: TypeScale.panelContext.copyWith(color: colors.ink2),
        ),
        const SizedBox(height: 6),
        for (final night in nights.take(shown))
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: <Widget>[
                Flexible(
                  child: Text(
                    '${shortDate(night.date)} · '
                    'bed ${night.bedtime ?? 'unrecorded'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TypeScale.tinyLabel.copyWith(color: colors.ink2),
                  ),
                ),
                const Spacer(),
                if (night.deltaH case final double delta)
                  Text(
                    '${delta > 0 ? '+' : ''}${delta.toStringAsFixed(1)} h',
                    style: TypeScale.tinyLabel.copyWith(color: colors.alert),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The server-authored line, rendered grounded so its citations resolve.
class _Action extends StatelessWidget {
  const _Action({required this.action});

  final String action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: SleepTimingPanel.blockGap),
    child: GroundedProse(
      text: action,
      style: TypeScale.panelContext.copyWith(color: context.colors.ink),
    ),
  );
}
