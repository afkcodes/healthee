/// The card a metric's history is drawn in — the chart, its three figures, and
/// every plotted reading behind a disclosure.
///
/// `screens-explore.js::H.screens.metric`, in its order:
///
/// ```text
///   <div class="card section">
///     H.charts.line(values, …)              the series
///     <div class="three section">           Mean · Median · Change
///     H.note('Range … · N observed samples')
///     <details class="section">See dated readings</details>
/// ```
///
/// `.card` is 20 px of padding and a 22 px corner, which is `SurfaceCard` — not
/// `Panel`, whose 18 px is `richer.css`'s `.panel`. The stats are therefore
/// `.stat`'s **base** sizes (`StatBlock`) rather than `.panel .three`'s
/// overrides (`StatRow`); `stat_block.dart` records that distinction.
///
/// ## No baseline line, and therefore no legend
///
/// The prototype draws a dashed personal median for the two metrics it holds a
/// `baseline` for, captioned *"Dashed line · personal median"*. This app does
/// not draw it, because the client would have to compute it: `CLAUDE.md`'s
/// one-canonical-definition rule and `v02_line_chart.dart`'s own contract both
/// say a reference line is the **server's**, and a second, on-device median is
/// exactly the two-definitions failure that rule exists for. The three figures
/// below the chart are descriptive statistics **of the window on screen**, said
/// in words beside them, which is a different claim from a baseline the app
/// judges a reading against.
///
/// ## The Change figure is the only verdict colour on this screen
///
/// And it is drawn only where `shared/format/metric_polarity.dart` knows which
/// way is better. A metric that table has never heard of, one it knows to be
/// neutral, and a window that did not move all render in the ordinary ink —
/// visibly not a claim. Colouring by the sign of the delta would mean the app
/// telling the owner that more calories is good news.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_scale_forms.dart';
import 'package:healthee/data/history/history_statistics.dart';
import 'package:healthee/data/history/history_window.dart';
import 'package:healthee/features/history/v02/dated_readings.dart';
import 'package:healthee/shared/charts/v02/metric_series.dart';
import 'package:healthee/shared/charts/v02/v02_line_chart.dart';
import 'package:healthee/shared/format/date_labels.dart';
import 'package:healthee/shared/format/metric_names.dart';
import 'package:healthee/shared/format/metric_polarity.dart';
import 'package:healthee/shared/format/number_labels.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:healthee/shared/v02/panel_parts.dart';
import 'package:healthee/shared/v02/stat_block.dart';
import 'package:healthee/shared/v02/surfaces.dart';

/// The chart, the three figures, and the readings behind them.
class HistoryPanel extends StatelessWidget {
  /// [metric] is the server's canonical id — the key both the polarity table
  /// and the curve table are read with.
  const HistoryPanel({
    required this.metric,
    required this.unit,
    required this.window,
    required this.reveals,
    super.key,
  });

  /// `.three { gap: var(--space-sm) }`.
  static const double statGap = 8;

  /// `.section { margin-top: 24px }` — above the figures.
  static const double sectionGap = 24;

  /// The metric's canonical id.
  final String metric;

  /// Its unit, as the server names it.
  final String unit;

  /// The observations, laid out on the calendar they were measured on.
  final HistoryWindow window;

  /// Where "this chart has already been revealed" is remembered.
  final RevealRegistry reveals;

  @override
  Widget build(BuildContext context) {
    final decimals = decimalsFor(metric);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          RevealOnce(
            // The metric and the window it is drawn over. A list index would
            // make a chart "become" a different chart when the period changes
            // and would replay the reveal on every scroll.
            id: 'history:$metric:${window.days.length}',
            registry: reveals,
            builder: (context, t) => V02LineChart(
              window.values,
              progress: t,
              unit: unit,
              digits: decimals,
              curve: seriesCurveFor(metric),
              captions: window.captions,
              sampleLabels: window.sampleLabels,
              semanticLabel: window.isEmpty
                  ? null
                  : '${metricTitle(metric)}, $unit. '
                        '${window.captions.join(' to ')}.',
            ),
          ),
          if (_statistics case final HistoryStatistics stats) ...<Widget>[
            const SizedBox(height: sectionGap),
            _Figures(stats: stats, metric: metric, decimals: decimals),
            PanelNote(_rangeNote(stats)),
          ],
          DatedReadings(
            summary: 'See dated readings',
            columns: ('Date', unit.isEmpty ? 'Reading' : unit),
            rows: <ReadingRow>[
              for (var i = window.observed.length - 1; i >= 0; i--)
                ReadingRow(
                  shortDate(window.observed[i].date),
                  window.observed[i].value.toStringAsFixed(decimals),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// The window's own statistics, or null when there is nothing to describe.
  HistoryStatistics? get _statistics => window.isEmpty
      ? null
      : HistoryStatistics(<double>[
          for (final point in window.observed) point.value,
        ]);

  /// `Range 45–48 ms · 14 observed samples` — the prototype's own sentence,
  /// counting what was **measured** rather than how many slots the chart holds.
  String _rangeNote(HistoryStatistics stats) {
    final unitSuffix = unit.isEmpty ? '' : ' $unit';
    final samples = window.observed.length;
    return 'Range ${decimalLabel(stats.minimum)}–${decimalLabel(stats.maximum)}'
        '$unitSuffix · $samples observed '
        '${samples == 1 ? 'sample' : 'samples'}';
  }
}

/// `.three` — Mean, Median and Change across the card's width.
class _Figures extends StatelessWidget {
  const _Figures({
    required this.stats,
    required this.metric,
    required this.decimals,
  });

  final HistoryStatistics stats;
  final String metric;
  final int decimals;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Expanded(
        child: StatBlock(
          label: 'Mean',
          value: stats.mean.toStringAsFixed(decimals),
        ),
      ),
      const SizedBox(width: HistoryPanel.statGap),
      Expanded(
        child: StatBlock(
          label: 'Median',
          value: stats.median.toStringAsFixed(decimals),
        ),
      ),
      const SizedBox(width: HistoryPanel.statGap),
      Expanded(
        child: ChangeStat(
          metric: metric,
          delta: stats.change,
          decimals: decimals,
        ),
      ),
    ],
  );
}

/// The first-to-last change, coloured only where polarity is known.
class ChangeStat extends StatelessWidget {
  /// [metric] is read against `metric_polarity.dart` and nothing else.
  const ChangeStat({
    required this.metric,
    required this.delta,
    required this.decimals,
    super.key,
  });

  /// The canonical metric id.
  final String metric;

  /// The signed change over the window.
  final double delta;

  /// Decimal places, matching the chart's readout.
  final int decimals;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Null is the safety property: an unknown metric, a neutral one, and a flat
    // window all get the ordinary ink, which is visibly not a verdict.
    final Color? verdict = switch (verdictFor(metric, delta)) {
      TrendVerdict.favourable => colors.fav,
      TrendVerdict.unfavourable => colors.alert,
      TrendVerdict.none => null,
    };
    final sign = delta > 0 ? '+' : (delta < 0 ? '−' : '');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text('Change', style: FormType.statLabel.copyWith(color: colors.ink2)),
        Text(
          '$sign${delta.abs().toStringAsFixed(decimals)}',
          style: FormType.statNumber.copyWith(color: verdict ?? colors.ink),
          maxLines: 1,
          softWrap: false,
        ),
      ],
    );
  }
}
