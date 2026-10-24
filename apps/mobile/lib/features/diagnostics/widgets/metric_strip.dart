/// Every other stream the strap records, one card, hairline rows.
///
/// **One outer card with divided rows, never a card per metric.** Brief §2's
/// first "never" is card-inside-a-card, and a strip of seven framed cards is
/// that rule broken seven times.
///
/// ## Why the rows do not use `WithheldCard`
///
/// A withheld row is drawn here with an inline [ValueHole] and the reason beside
/// it, rather than by handing the row to the shared refusal card. That card is a
/// `StateCard` — a frame — and nesting one inside this frame would be exactly
/// the card-in-card the design forbids. The visual language is kept instead: the
/// same number-shaped hole, in the value's own position, with the reason in
/// [HealtheeColors.ink2] and no colour spent on it.
///
/// The `switch` below is exhaustive over [Reading] by the language's own rules,
/// so a fifth honesty state stops this file compiling until somebody decides
/// what a row of it looks like. That is the type doing its job at the last hop.
///
/// ## A row that shares a name with a server metric NAMES ITS INSTRUMENT
///
/// Two of these streams — resting heart rate and HRV — measure the same quantity
/// as a canonical server metric by a different method, and they disagree by
/// construction. Those rows carry `DeviceStream.instrument` behind the same kind
/// of disclosure the VO₂max card offers for its tiering: one tappable line, the
/// explanation underneath, never a modal. `diagnostics_screen.dart` has the whole
/// trace; a row that omitted the note would be a differently-defined number under
/// a familiar label, which is CLAUDE.md's first hard rule broken quietly.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/instrument_hues.dart';
import 'package:healthee/core/theme/metric_hue.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/data/device/device_metric.dart';
import 'package:healthee/data/honesty/reading.dart';
import 'package:healthee/shared/format/time_labels.dart';
import 'package:healthee/shared/states/reasoning_note.dart';
import 'package:healthee/shared/states/state_scaffold.dart';
import 'package:healthee/shared/states/value_hole.dart';

/// The strap's other streams, in one card.
class MetricStrip extends StatelessWidget {
  /// [metrics] is every entry of `kDeviceStreams`, present or withheld.
  const MetricStrip({required this.metrics, this.now, super.key});

  /// One row per stream, in server-independent display order.
  final List<DeviceMetric> metrics;

  /// The current instant.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final at = now ?? DateTime.now();
    return StateCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('From the strap', style: Theme.of(context).textTheme.labelSmall),
          for (final metric in metrics) ...[
            Divider(color: colors.line2, height: Insets.lg, thickness: hairline),
            _MetricRow(metric: metric, now: at),
          ],
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.metric, required this.now});

  final DeviceMetric metric;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final tag = hueFor(context.hues, metric.stream.metric);
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
                    metric.stream.label,
                    style: text.titleSmall?.copyWith(color: tag),
                  ),
                  const SizedBox(height: Insets.xs),
                  Text(
                    _subtitle(metric, now),
                    style: text.bodySmall?.copyWith(color: colors.ink2),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Insets.md),
            // Exhaustive by the language, not by care. A Caveated value shows its
            // number and its tilt; it is never rendered as if it were Present.
            switch (metric.reading) {
              Present<double>(:final value) => _Value(metric: metric, value: value),
              Caveated<double>(:final value) => _Value(metric: metric, value: value),
              Withheld<double>() || Excluded<double>() => const Padding(
                padding: EdgeInsets.only(top: 2),
                child: ValueHole.inline(),
              ),
            },
          ],
        ),
        if (metric.stream.instrument case final String note)
          ReasoningNote(
            question: 'Why this differs from your ${_canonicalName(metric)}',
            answer: note,
          ),
      ],
    );
  }

  /// The name the canonical metric goes by on the daily read.
  static String _canonicalName(DeviceMetric metric) =>
      switch (metric.stream.metric) {
        'resting_hr' => 'resting heart rate above',
        'hrv' => 'overnight HRV',
        _ => 'daily reading',
      };

  /// The reason when there is no value; the freshness and count when there is.
  ///
  /// The sample count is shown because one reading and four hundred are
  /// different confidences in the same displayed number, and the strap's
  /// sampling schedule is its own business.
  static String _subtitle(DeviceMetric metric, DateTime now) {
    return switch (metric.reading) {
      Withheld<double>(:final disclosure) => disclosure.message,
      Excluded<double>(:final exclusions) =>
        exclusions.isEmpty ? 'Left out of this view' : exclusions.first.message,
      _ => metric.measuredAt == null
          ? '${metric.sampleCount} samples'
          : '${clockLabel(metric.measuredAt!)} · '
                '${ageLabel(metric.measuredAt!, now: now)} · '
                '${metric.sampleCount} samples',
    };
  }
}

class _Value extends StatelessWidget {
  const _Value({required this.metric, required this.value});

  final DeviceMetric metric;
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
          value.toStringAsFixed(metric.stream.decimals),
          style: text.headlineSmall,
        ),
        if (metric.stream.unit case final String unit) ...[
          const SizedBox(width: Insets.xs),
          Text(unit, style: text.labelSmall?.copyWith(color: colors.ink2)),
        ],
      ],
    );
  }
}
