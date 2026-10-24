/// `.dimension-grid` — independent readings, each judged against its own cutoff.
///
/// Split out of `meters.dart` at the 400-line gate (Standards section 1), and it
/// belongs apart anyway: a meter draws a proportion of something, and these are
/// four unrelated readings that are never summed. The panel that carries them
/// says so in its own docstring — *"four readings, four cutoffs, no total"* — so
/// there is deliberately no headline figure here to add one.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_scale.dart';

/// One cell of a [DimensionGrid].
@immutable
class Dimension {
  /// [note] is the reference the reading is read against.
  const Dimension(this.label, this.value, {this.note, this.met});

  /// What is being measured.
  final String label;

  /// The reading, already formatted.
  final String value;

  /// The reference under it.
  final String? note;

  /// Whether the reading met its published cutoff, or null when nothing scored
  /// it — which is **not** the same as failing, and is not drawn as a failure.
  ///
  /// `SleepDimension.passed` has carried this since the block existed and the
  /// card threw it away: four cutoffs were evaluated on the server and the
  /// owner was shown four bare figures, so *"5h 34m"* and *"61.4%"* sat there
  /// as trivia. Reading them meant knowing four references by heart.
  ///
  /// A reading with no cutoff — the overnight breathing rate, which is on this
  /// grid but not in `sleep_health` — passes null and draws no mark. The
  /// absence is the honest signal: nothing judged it, so nothing claims to.
  final bool? met;
}

/// `.dimension-grid` — independent readings, two across, never summed.
class DimensionGrid extends StatelessWidget {
  /// Builds the grid. An empty [dimensions] draws nothing.
  const DimensionGrid(this.dimensions, {super.key});

  /// `.dimension-grid { gap: 20px 16px }` — the row half.
  static const double rowGap = 20;

  /// Its column half.
  static const double columnGap = 16;

  /// `.dimension-cell small { margin-top: 6px }`.
  static const double noteGap = 6;

  /// The air before the verdict mark, and the glyph's size.
  ///
  /// **No filled box.** A tinted squircle behind every mark turned four quiet
  /// readings into four warning badges — and on a night that misses all four,
  /// a card of amber chips reads as an alarm rather than a report. The glyph
  /// alone carries it, at the weight of the label rather than the figure.
  static const double markGap = 6;
  static const double markGlyph = 13;

  /// The readings, in payload order.
  final List<Dimension> dimensions;

  @override
  Widget build(BuildContext context) {
    if (dimensions.isEmpty) {
      return const SizedBox.shrink();
    }
    final rows = <List<Dimension>>[
      for (var i = 0; i < dimensions.length; i += 2)
        dimensions.sublist(i, (i + 2).clamp(0, dimensions.length)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var r = 0; r < rows.length; r++) ...<Widget>[
          if (r > 0) const SizedBox(height: rowGap),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: _Cell(dimension: rows[r].first)),
              const SizedBox(width: columnGap),
              Expanded(
                child: rows[r].length > 1
                    ? _Cell(dimension: rows[r][1])
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.dimension});

  final Dimension dimension;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          dimension.label,
          style: TypeScale.dimensionLabel.copyWith(color: colors.ink2),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        // **The mark trails the figure it judges.** Leading it pushed the label
        // right while the value stayed at the cell's edge, so every label sat
        // indented from the number under it and the grid read as four ragged
        // columns. Here both start at the same x and the verdict sits on the
        // value's own baseline, which is also the only place it means anything.
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Flexible(
              child: Text(
                dimension.value,
                style: TypeScale.dimensionValue.copyWith(color: colors.ink),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
              ),
            ),
            if (dimension.met case final bool met) ...<Widget>[
              const SizedBox(width: DimensionGrid.markGap),
              _Verdict(met: met),
            ],
          ],
        ),
        if (dimension.note case final String note) ...<Widget>[
          const SizedBox(height: DimensionGrid.noteGap),
          Text(
            note,
            style: TypeScale.dimensionNote.copyWith(color: colors.ink2),
          ),
        ],
      ],
    );
  }
}

/// Met or not met, as a shape AND a colour.
///
/// Two carriers on purpose. `apps/mobile/README.md` is explicit that colour may
/// never be the only one — a verdict told in green and amber alone is a claim
/// made in a language a colourblind reader does not have — so the tick and the
/// dash say it too. There is no third glyph for "not scored": that cell draws
/// no mark at all, because a symbol for absence still reads as a judgement.
class _Verdict extends StatelessWidget {
  const _Verdict({required this.met});

  final bool met;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // **A cross, never a dash.** `—` is this app's mark for a reading that does
    // not exist — the cell above prints one when a dimension has no value — so
    // a dash beside a figure that DOES exist said "no data" about data, to mean
    // "missed its cutoff". Two opposite meanings on one glyph.
    return Icon(
      met ? Icons.check : Icons.close,
      size: DimensionGrid.markGlyph,
      color: met ? colors.fav : colors.alert,
    );
  }
}
