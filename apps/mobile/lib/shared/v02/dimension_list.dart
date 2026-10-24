/// Four readings, each beside the reference that judges it.
///
/// **The grid this replaces printed the readings alone.** `5h 34m`, `61.4%`,
/// `60`, `06:51` — four figures whose meaning lived in the ⓘ, so the card could
/// only be read by someone who already knew four published cutoffs by heart.
/// It was not a table of numbers by accident; it was a table of numbers with
/// the comparison taken out of it.
///
/// Each row now carries the reading, what it is measured against, and whether it
/// got there. Nothing here is computed: the reference is `SleepDimension.cutoff`
/// and the verdict is `passed`, both off the wire.
///
/// There is still **no total**. `SleepHealthPanel` says why — *"four readings,
/// four cutoffs, no total"* — and a count of ticks would be the composite score
/// CLAUDE.md forbids without a documented methodology.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_scale.dart';

/// One judged reading.
@immutable
class DimensionRow {
  /// [against] of null draws no reference — nothing published one.
  const DimensionRow(this.label, this.value, {this.against, this.met});

  /// What was measured.
  final String label;

  /// Its reading, already formatted.
  final String value;

  /// The published cutoff it is read against, already formatted.
  final String? against;

  /// Whether it got there. Null when nothing scored it, which is not a failure.
  final bool? met;
}

/// The rows, separated by the app's own hairline.
class DimensionList extends StatelessWidget {
  /// Builds the list. An empty [rows] draws nothing.
  const DimensionList(this.rows, {super.key});

  /// Air above and below each row's content.
  static const double rowPad = 13;

  /// The least space between a name and the reading opposite it.
  static const double readingGap = 12;

  /// Between the name and the reference under it.
  static const double referenceGap = 3;

  /// The readings, in payload order.
  final List<DimensionRow> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var i = 0; i < rows.length; i++) ...<Widget>[
          if (i > 0)
            SizedBox(
              height: hairline,
              child: ColoredBox(color: colors.line),
            ),
          _Row(row: rows[i], first: i == 0, last: i == rows.length - 1),
        ],
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.row, required this.first, required this.last});

  final DimensionRow row;
  final bool first;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final verdict = row.met;
    return Padding(
      padding: EdgeInsets.only(
        top: first ? 0 : DimensionList.rowPad,
        bottom: last ? 0 : DimensionList.rowPad,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  row.label,
                  style: TypeScale.rowTitle.copyWith(color: colors.ink),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (row.against case final String against) ...<Widget>[
                  const SizedBox(height: DimensionList.referenceGap),
                  Text(
                    against,
                    // 11, not the grid's 9: this line is the comparison the
                    // card exists to make, and it was set at caption size.
                    style: TypeScale.dimensionLabel.copyWith(
                      color: colors.ink2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: DimensionList.readingGap),
          Text(
            row.value,
            style: TypeScale.dimensionReading.copyWith(
              // **Colour is not the only carrier here, and that is why there is
              // no tick or cross.** The README forbids a claim told in colour
              // alone — but the reference sits under the name, so `60` beside
              // `≥ 70` and `06:51` beside `02:00–04:00` state the verdict in
              // figures a reader can check. The tint reinforces what the two
              // numbers already say; it does not carry it. A glyph as well was
              // a third telling of one fact.
              color: switch (verdict) {
                true => colors.fav,
                false => colors.alert,
                null => colors.ink,
              },
            ),
            maxLines: 1,
            softWrap: false,
          ),
        ],
      ),
    );
  }
}
