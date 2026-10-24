/// The ledger's bar: done, partial and missed in state colours, hatched grey
/// for what the strap could not prove. Widths are proportional to the counts.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/data/coach/ledger_models.dart';
import 'package:healthee/shared/charts/v02/hatch.dart';
import 'package:healthee/shared/v02/reading_state.dart';

/// The bar.
class LedgerBar extends StatelessWidget {
  /// Draws [totals].
  const LedgerBar({required this.totals, super.key});

  /// Bar thickness.
  static const double thickness = 8;

  /// The counts.
  final LedgerTotals totals;

  /// The segments in order, as (count, kind) with zero-count ones dropped.
  static List<(int, LedgerVerdict)> segments(LedgerTotals t) =>
      <(int, LedgerVerdict)>[
        (t.done, LedgerVerdict.done),
        (t.partial, LedgerVerdict.partial),
        (t.missed, LedgerVerdict.missed),
        (t.noProof, LedgerVerdict.noData),
      ].where((s) => s.$1 > 0).toList();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final parts = segments(totals);
    if (parts.isEmpty) {
      return const HatchStrip(height: thickness);
    }
    return ExcludeSemantics(
      child: SizedBox(
        height: thickness,
        width: double.infinity,
        child: CustomPaint(
          painter: _BarPainter(
            parts: parts,
            fav: ReadingState.better.colourIn(colors),
            watch: ReadingState.watch.colourIn(colors),
            alert: ReadingState.worse.colourIn(colors),
            hatch: colors.ink3,
          ),
        ),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  const _BarPainter({
    required this.parts,
    required this.fav,
    required this.watch,
    required this.alert,
    required this.hatch,
  });

  final List<(int, LedgerVerdict)> parts;
  final Color fav;
  final Color watch;
  final Color alert;
  final Color hatch;

  static const double _gap = 2;

  @override
  void paint(Canvas canvas, Size size) {
    final total = parts.fold<int>(0, (sum, p) => sum + p.$1);
    final room = size.width - _gap * (parts.length - 1);
    var x = 0.0;
    for (final (count, kind) in parts) {
      final width = room * count / total;
      final rect = Rect.fromLTWH(x, 0, width, size.height);
      x += width + _gap;
      if (kind == LedgerVerdict.noData) {
        paintHatch(canvas, rect, ink: hatch, radius: 2);
        continue;
      }
      final colour = switch (kind) {
        LedgerVerdict.done => fav,
        LedgerVerdict.partial => watch,
        _ => alert,
      };
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        Paint()..color = colour,
      );
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.parts != parts ||
      old.fav != fav ||
      old.watch != watch ||
      old.alert != alert ||
      old.hatch != hatch;
}
