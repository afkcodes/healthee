/// The three blocks of `#sleep-history`: the month, the week, and the list.
///
/// `design/mobile-preview/sleep-history-view.js`:
///
/// ```js
/// H.screens['sleep-history'] = () =>
///   `${H.header('Sleep history','',true)}
///    ${H.historyPanel('sleep',30)}
///    ${H.panel('Seven nights of stages','sleep', stages(week) + stageLegend())}
///    ${H.section('Open a night', `<div class="card flush">${nights.map(n =>
///        `<button class="list-row" data-action="date-night" data-date="${n.date}">
///           <span class="grow"><strong>${dateLabel}</strong>
///           <small>${start} → ${end}</small></span>
///           <strong>${duration}</strong>${chevron}</button>`)}</div>`)}`;
/// H.actions['date-night'] = el => { H.setViewDate(el.dataset.date);
///                                   H.navigate('sleep'); };
/// ```
///
/// ## The night rows are buttons, and a night with no session still gets one
///
/// `docs/V02_CONNECTIVITY.md` section 0 records that these are buttons rather
/// than links — they set the viewed day and then go to Sleep. A night the strap
/// did not record draws `— → —` and no duration, exactly as the prototype does:
/// the row is the calendar, and a missing night is a fact about the calendar.
/// It still opens Sleep, which is where the absence is explained.
///
/// ## Straight segments, never a spline
///
/// One total per night. `chart_curve.dart` and `trend_panels.dart` both argue
/// it: a monotone curve between two nightly totals draws a duration nobody
/// slept.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/instrument_hues.dart';
import 'package:healthee/core/theme/stage_colors.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/core/theme/type_scale.dart';
import 'package:healthee/data/models/sleep_history.dart';
import 'package:healthee/data/models/sleep_night.dart';
import 'package:healthee/features/sleep/sleep_format.dart';
import 'package:healthee/shared/charts/h_stacked_sleep.dart';
import 'package:healthee/shared/charts/v02/chart_curve.dart';
import 'package:healthee/shared/charts/v02/v02_line_chart.dart';
import 'package:healthee/shared/format/duration.dart';
import 'package:healthee/shared/instrument/h_tap.dart';
import 'package:healthee/shared/metric_info/metric_detail.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:healthee/shared/v02/colour_key.dart';
import 'package:healthee/shared/v02/panel.dart';
import 'package:healthee/shared/v02/panel_head.dart';
import 'package:healthee/shared/v02/panel_parts.dart';
import 'package:solar_icons/solar_icons.dart';

/// `Sleep duration` — the month of nightly totals.
class SleepDurationPanel extends StatelessWidget {
  /// [nights] is newest first, the order `/api/sleep` sends.
  const SleepDurationPanel({
    required this.nights,
    required this.reveals,
    this.onDetails,
    super.key,
  });

  /// The prototype's title.
  static const String title = 'Sleep duration';

  /// The plot's height, before its readout line.
  static const double chartHeight = 150;

  /// The gap above the chart.
  static const double chartGap = 8;

  /// The window, newest first.
  final List<SleepNight> nights;

  /// Where "already revealed" is remembered.
  final RevealRegistry reveals;

  /// Opens the sleep-duration metric history.
  final VoidCallback? onDetails;

  /// Oldest first, with an unmeasured night kept as a gap.
  List<double?> get series => <double?>[
    for (final night in nights.reversed) night.tstMin.valueOrNull,
  ];

  /// One short date per night, oldest first.
  List<String> get dates => <String>[
    for (final night in nights.reversed) shortDate(night.date),
  ];

  /// How many of those nights carry a total.
  int get measured => series.where((value) => value != null).length;

  /// `30 dated samples through 31 Jul.`
  String get note {
    if (measured == 0) {
      return 'No night in this window carries a measured total.';
    }
    final through = dates.isEmpty ? '' : ' through ${dates.last}';
    return '$measured dated ${measured == 1 ? 'sample' : 'samples'}$through.';
  }

  @override
  Widget build(BuildContext context) {
    final latest = nights.isEmpty ? null : nights.first.tstMin.valueOrNull;
    return Panel(
      tone: Tone.sleep,
      label: 'Sleep duration',
      head: PanelHead(
        title: title,
        icon: SolarIconsOutline.moonSleep,
        infoKey: 'sleep',
        actionLabel: onDetails == null ? null : 'Details',
        onAction: onDetails,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          PanelValue(
            latest == null ? '—' : latest.round().toString(),
            unit: 'min',
            context_: dates.isEmpty ? null : dates.last,
          ),
          const SizedBox(height: chartGap),
          RevealOnce(
            id: 'sleep-history.duration',
            registry: reveals,
            builder: (context, t) => V02LineChart(
              series,
              progress: t,
              height: chartHeight,
              unit: 'min',
              // Nightly totals. See the library docstring.
              curve: SeriesCurve.straight,
              captions: dates.isEmpty
                  ? const <String>[]
                  : <String>[dates.first, dates.last],
              sampleLabels: dates,
              semanticLabel: 'Sleep duration in minutes, night by night',
            ),
          ),
          PanelNote(note),
        ],
      ),
    );
  }
}

/// `Seven nights of stages` — the same stacked chart the Sleep screen draws.
class NightStagesPanel extends StatelessWidget {
  /// [nights] is oldest first and never padded to reach seven.
  const NightStagesPanel({
    required this.nights,
    required this.reveals,
    super.key,
  });

  /// The prototype's title.
  static const String title = 'Seven nights of stages';

  /// The stack's height.
  static const double chartHeight = 130;

  /// The gap above the legend.
  static const double legendGap = 10;

  /// The week, oldest first.
  final List<SleepNightSummary> nights;

  /// Where "already revealed" is remembered.
  final RevealRegistry reveals;

  @override
  Widget build(BuildContext context) {
    final hues = context.hues;
    return Panel(
      tone: Tone.sleep,
      label: 'Sleep stages · seven nights',
      head: const PanelHead(
        title: title,
        icon: SolarIconsOutline.moonSleep,
        infoKey: 'sleep',
        detail: MetricDetail(
          method: <String>[
            'Each stage keeps the same colour throughout the app.',
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          RevealOnce(
            id: 'sleep-history.stage-week',
            registry: reveals,
            builder: (context, t) =>
                HStackedSleep(nights, progress: t, height: chartHeight),
          ),
          const SizedBox(height: legendGap),
          ColourKey(<ColourKeyEntry>[
            for (final stage in kSleepStages)
              ColourKeyEntry(
                sleepStageLabel(stage),
                colour: sleepStageColor(hues, stage),
              ),
          ]),
        ],
      ),
    );
  }
}

/// One `Open a night` row: the date, when the night ran, and how long it was.
///
/// No icon tile: `.list-row` here is a `.grow` span beside a trailing figure,
/// which is the prototype's own shape for this list and not the settings row.
class NightRow extends StatelessWidget {
  /// [onOpen] of null draws no chevron — a row that leads nowhere must not
  /// offer the glyph that says it does.
  const NightRow({required this.night, this.onOpen, super.key});

  /// `.list-row { min-height: 72px }`.
  static const double minHeight = 72;

  /// `.list-row { padding: 16px 20px }`.
  static const EdgeInsets padding = EdgeInsets.symmetric(
    horizontal: 20,
    vertical: 16,
  );

  /// `.list-row { gap: 12px }`.
  static const double gap = 12;

  /// `.list-row > .icon:last-child { width: 16px }`.
  static const double chevronSize = 16;

  /// The night this row opens.
  final SleepNight night;

  /// Sets the viewed day and goes to Sleep.
  final VoidCallback? onOpen;

  /// `23:00 → 06:30`, or `— → —` when the strap recorded no session.
  static String span(SleepNight night) {
    final start = night.start;
    final end = night.end;
    return '${start == null ? '—' : clock(start)} → '
        '${end == null ? '—' : clock(end)}';
  }

  /// `6h 20m`, or an em dash when nothing was measured.
  static String duration(SleepNight night) {
    final minutes = night.tstMin.valueOrNull;
    return minutes == null ? '—' : durationText(minutes);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final row = Container(
      constraints: const BoxConstraints(minHeight: minHeight),
      padding: padding,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  shortDate(night.date),
                  style: TypeScale.panelTitle.copyWith(color: colors.ink),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  span(night),
                  style: TypeScale.panelNote.copyWith(color: colors.ink2),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: gap),
          Text(
            duration(night),
            style: TypeScale.panelTitle.copyWith(color: colors.ink),
            maxLines: 1,
            overflow: TextOverflow.clip,
          ),
          if (onOpen != null) ...<Widget>[
            const SizedBox(width: gap),
            Icon(
              SolarIconsOutline.altArrowRight,
              size: chevronSize,
              color: colors.ink2,
            ),
          ],
        ],
      ),
    );
    return HTap(
      onTap: onOpen,
      semanticLabel: '${shortDate(night.date)} · ${duration(night)}',
      child: row,
    );
  }
}
