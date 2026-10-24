/// The ledger's summary: four numbers, one bar, the done rate.
///
/// Every figure is read off the response; the bar is drawn in proportion to the
/// totals, and with no yeses at all it is the hatched no-data strip, never an
/// empty coloured one.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/data/coach/ledger_models.dart';
import 'package:healthee/features/coach/v02/ledger_bar.dart';
import 'package:healthee/shared/v02/reading_state.dart';
import 'package:healthee/shared/v02/surface_panels.dart';

/// The card.
class LedgerSummaryCard extends StatelessWidget {
  /// Draws [ledger]'s totals.
  const LedgerSummaryCard({required this.ledger, super.key});

  /// The response.
  final CoachLedger ledger;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final totals = ledger.totals;
    final rate = ledger.doneRate;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _Figure(
                  value: ledger.yeses,
                  label: 'yeses',
                  colour: colors.ink,
                ),
                _Rule(colors.line),
                _Figure(
                  value: totals.done,
                  label: 'done',
                  colour: ReadingState.better.colourIn(colors),
                ),
                _Rule(colors.line),
                _Figure(
                  value: totals.missed,
                  label: 'missed',
                  colour: ReadingState.worse.colourIn(colors),
                ),
                _Rule(colors.line),
                _Figure(
                  value: totals.noProof,
                  label: 'no proof',
                  colour: colors.ink2,
                ),
              ],
            ),
          ),
          const SizedBox(height: Insets.lg),
          LedgerBar(totals: totals),
          const SizedBox(height: Insets.md),
          Text.rich(
            rate.provable == 0
                ? const TextSpan(
                    text: 'Nothing here the strap could prove yet.',
                  )
                : TextSpan(
                    children: <InlineSpan>[
                      const TextSpan(text: 'Done rate '),
                      TextSpan(
                        text: '${rate.done} of ${rate.provable}',
                        style: TypeLadder.calloutStrong.copyWith(
                          color: colors.ink,
                        ),
                      ),
                      const TextSpan(text: ' you could prove.'),
                    ],
                  ),
            style: TypeLadder.callout.copyWith(color: colors.ink2),
          ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.value,
    required this.label,
    required this.colour,
  });

  final int value;
  final String label;
  final Color colour;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: Insets.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '$value',
              style: TypeLadder.metric.copyWith(color: colour),
            ),
          ),
          Text(
            label,
            style: TypeLadder.callout.copyWith(color: context.colors.ink2),
          ),
        ],
      ),
    ),
  );
}

class _Rule extends StatelessWidget {
  const _Rule(this.colour);

  final Color colour;

  @override
  Widget build(BuildContext context) =>
      Container(width: hairline, color: colour);
}
