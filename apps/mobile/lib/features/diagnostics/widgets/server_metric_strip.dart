/// The server's metric cards: today's value, a sparkline, and **your** normal.
///
/// Brief §4.1's metric strip and §3's baseline comparison in one card. The
/// comparison is the app's real value — *"Below your usual range of 63 to 79
/// ms"*, your number against your normal, not a population's — so a card with no
/// baseline says so plainly rather than falling silent.
///
/// **One outer card, hairline rows.** Brief §2's first "never" is
/// card-inside-a-card, and a strip of seven framed cards is that rule broken
/// seven times. A withheld row is drawn with an inline [ValueHole] and its
/// reason, in the value's own position, rather than by nesting a `WithheldCard`
/// frame inside this one.
///
/// The `switch` over [Reading] is exhaustive by the language's own rules, so a
/// fifth honesty state stops this file compiling until somebody decides what a
/// row of it looks like.
///
/// ## Every row wears its metric's identity tag
///
/// The label and the area chart take `InstrumentHues.tagFor(card.metric)` rather than
/// the accent. Seven rows drawn in one colour made a strip of seven charts that
/// could only be told apart by reading the label above each; the tag is the same
/// one the grid cell for that metric wears, from the same table, so the two
/// cannot disagree. It is an identity, never a verdict — `palette.dart` argues
/// that at length, and the `σ` sentence beside the number is still the only thing
/// on this card allowed to say how the owner did.
///
/// [_instrumentNote] names the method behind a metric that has a second
/// definition elsewhere in the app. Only `rhr_daily` does today.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/instrument_hues.dart';
import 'package:healthee/core/theme/metric_hue.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/data/honesty/reading.dart';
import 'package:healthee/data/models/metric_card.dart';
import 'package:healthee/data/models/trend_point.dart';
import 'package:healthee/shared/charts/h_area.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:healthee/shared/states/reasoning_note.dart';
import 'package:healthee/shared/states/state_scaffold.dart';
import 'package:healthee/shared/states/value_hole.dart';

/// The server's metric cards, in one card with divided rows.
class ServerMetricStrip extends StatelessWidget {
  /// [sparklines] is keyed by metric id; a metric with none draws no chart.
  const ServerMetricStrip({
    required this.metrics,
    required this.sparklines,
    required this.reveals,
    super.key,
  });

  /// The cards, in server order.
  final List<MetricCard> metrics;

  /// Fourteen days per metric id.
  final Map<String, List<TrendPoint>> sparklines;

  /// The screen's reveal registry.
  final RevealRegistry reveals;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    if (metrics.isEmpty) {
      return const SizedBox.shrink();
    }
    return StateCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Against your own baseline', style: text.labelSmall),
          for (final card in metrics) ...[
            Divider(
              color: colors.line2,
              height: Insets.lg,
              thickness: hairline,
            ),
            _MetricRow(
              card: card,
              series: sparklines[card.metric] ?? const [],
              reveals: reveals,
            ),
          ],
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.card,
    required this.series,
    required this.reveals,
  });

  final MetricCard card;
  final List<TrendPoint> series;
  final RevealRegistry reveals;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final tag = hueFor(context.hues, card.metric);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.label,
                    style: text.titleSmall?.copyWith(color: tag),
                  ),
                  const SizedBox(height: Insets.xs),
                  Text(
                    _comparison(card),
                    style: text.bodySmall?.copyWith(color: colors.ink2),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Insets.md),
            switch (card.reading) {
              Present<double>(:final value) => _Value(card: card, value: value),
              Caveated<double>(:final value) => _Value(
                card: card,
                value: value,
              ),
              Withheld<double>() || Excluded<double>() => const Padding(
                padding: EdgeInsets.only(top: 2),
                child: ValueHole.inline(),
              ),
            },
          ],
        ),
        if (series.length >= 2) ...[
          const SizedBox(height: Insets.sm),
          RevealOnce(
            id: 'sparkline-${card.metric}',
            registry: reveals,
            builder: (context, t) => HArea(
              TrendPoint.valuesOf(series),
              color: tag,
              progress: t,
              height: 30,
              unit: card.unit ?? '',
              digits: card.median30d != null && card.median30d! < 10 ? 1 : 0,
            ),
          ),
        ],
        if (_instrumentNote(card.metric) case final String note)
          ReasoningNote(question: 'How this one is measured', answer: note),
      ],
    );
  }

  /// The method behind a metric the app measures a second way somewhere else.
  ///
  /// Null for everything else, deliberately: a note on every row would be noise,
  /// and the rows that need one are exactly the rows an owner could otherwise
  /// read as disagreeing with a number they saw elsewhere.
  static String? _instrumentNote(String metric) => switch (metric) {
    'rhr_daily' =>
      'The lowest 5-minute average heart rate inside your sleep, from the raw '
          'per-minute stream. This is the canonical resting heart rate — every '
          "judgement in the app uses it. The strap's own resting-HR estimate is "
          'below, and reads higher because it is usually sampled awake.',
    _ => null,
  };

  /// Your number against **your** normal — or an honest note that there is no
  /// normal yet. Weight never gets one, and a new owner has none for anything.
  static String _comparison(MetricCard card) {
    return switch (card.reading) {
      Withheld<double>(:final disclosure) => disclosure.message,
      Excluded<double>(:final exclusions) =>
        exclusions.isEmpty ? 'Left out of this view' : exclusions.first.message,
      _ => _baselineSentence(card),
    };
  }

  static String _baselineSentence(MetricCard card) {
    final median = card.median30d;
    if (median == null) {
      return 'No 30-day baseline for this — shown plainly, with nothing to '
          'compare it against.';
    }
    // The σ is the SERVER's, `sd_30d`, and it is stated in the metric's own
    // units rather than left as a bare multiplier (`BACKEND_GAPS_FROM_UI.md`
    // B4). A reader given "1.4σ" and nothing else cannot tell a signal that
    // moved a lot from one whose baseline barely varies, which is the whole
    // content of the score. It is never computed here: the divisor that made
    // `z` is the only one that reconciles with it.
    final spread = card.sd30d;
    final usual = spread == null
        ? 'Your usual is ${_number(median)}${_unit(card)}'
        : 'Your usual is ${_number(median)} ± ${_number(spread)}${_unit(card)}';
    final z = card.z;
    if (z == null) {
      return '$usual.';
    }
    if (z.abs() < 0.5) {
      return 'Inside your usual range. $usual.';
    }
    final side = z > 0 ? 'Above' : 'Below';
    return '$side it — ${z.abs().toStringAsFixed(1)}σ'
        '${card.anomalous ? ', outside your normal' : ''}. $usual.';
  }

  static String _unit(MetricCard card) =>
      card.unit == null ? '' : ' ${card.unit}';

  static String _number(double value) => value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(1);
}

class _Value extends StatelessWidget {
  const _Value({required this.card, required this.value});

  final MetricCard card;
  final double value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          value == value.roundToDouble()
              ? value.round().toString()
              : value.toStringAsFixed(1),
          style: text.headlineSmall,
        ),
        if (card.unit case final String unit) ...[
          const SizedBox(width: Insets.xs),
          Text(unit, style: text.labelSmall?.copyWith(color: colors.ink2)),
        ],
      ],
    );
  }
}
