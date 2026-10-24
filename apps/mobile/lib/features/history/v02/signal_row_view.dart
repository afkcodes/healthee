/// One row of the Health signals card.
///
/// ```text
///   name                 ~~~~~~~~~~~~~~      43.9 ms
///   higher is better ·   (80 px strip)       ↓ Below usual
///   usual 44 to 57
/// ```
///
/// Colour is spent in exactly three places, all from tokens: the domain hue on
/// the line, bar and pills' track; the state colour on the newest dot, the chip
/// and the pills; and nothing else. The whole row is one tap target onto that
/// metric's history, and one semantics node whose label says the verdict in
/// words.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/features/history/v02/signal_row.dart';
import 'package:healthee/features/history/v02/signal_rows.dart' show bound;
import 'package:healthee/shared/charts/v02/hatch.dart';
import 'package:healthee/shared/charts/v02/signal_spark.dart';
import 'package:healthee/shared/v02/reading_state.dart';

/// The row.
class SignalRowView extends StatelessWidget {
  /// Draws [row]; [onOpen] of null draws a row that does not navigate.
  const SignalRowView({required this.row, this.onOpen, super.key});

  /// `min-height: 64`.
  static const double minHeight = 64;

  /// Vertical padding.
  static const double padV = 14;

  /// Horizontal padding.
  static const double padH = 16;

  /// The middle column.
  static const double graphicWidth = 80;

  /// A progress bar's thickness.
  static const double barHeight = 6;

  /// What to draw.
  final SignalRow row;

  /// Opens the metric's history.
  final void Function(String metric)? onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final body = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Container(
        constraints: const BoxConstraints(minHeight: minHeight),
        padding: const EdgeInsets.symmetric(horizontal: padH, vertical: padV),
        alignment: Alignment.center,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(flex: 5, child: _Name(row: row)),
            const SizedBox(width: 12),
            SizedBox(
              width: graphicWidth,
              child: _Graphic(row: row),
            ),
            const SizedBox(width: 12),
            Expanded(flex: 4, child: _Figure(row: row)),
          ],
        ),
      ),
    );
    final open = onOpen;
    return ToneScope(
      tone: row.tone,
      child: Semantics(
        button: open != null,
        container: true,
        label: row.semanticLabel((v) => bound(row.metric, v)),
        child: ExcludeSemantics(
          child: open == null
              ? body
              : GestureDetector(
                  onTap: () => open(row.metric),
                  behavior: HitTestBehavior.opaque,
                  child: ColoredBox(color: colors.surface, child: body),
                ),
        ),
      ),
    );
  }
}

class _Name extends StatelessWidget {
  const _Name({required this.row});

  final SignalRow row;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          row.title,
          style: TypeLadder.bodyStrong.copyWith(color: colors.ink),
        ),
        if (row.caption.isNotEmpty)
          Text(
            row.caption,
            // A server refusal is printed whole; a caption is two lines.
            maxLines: row.withheld == null ? 2 : null,
            overflow: row.withheld == null ? TextOverflow.ellipsis : null,
            style: TypeLadder.caption.copyWith(color: colors.ink2),
          ),
      ],
    );
  }
}

class _Graphic extends StatelessWidget {
  const _Graphic({required this.row});

  final SignalRow row;

  @override
  Widget build(BuildContext context) => switch (row.graphic) {
    SignalGraphic.spark => SignalSpark(
      values: row.values,
      state: row.judgement.state,
      usual: row.usual,
    ),
    SignalGraphic.bar =>
      row.progress == null
          ? const SignalSpark(values: <double?>[], state: ReadingState.noData)
          : _Bar(progress: row.progress!),
    SignalGraphic.checks => _Checks(checks: row.checks),
  };
}

class _Bar extends StatelessWidget {
  const _Bar({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(SignalRowView.barHeight / 2),
      child: SizedBox(
        height: SignalRowView.barHeight,
        child: Stack(
          children: <Widget>[
            Positioned.fill(child: ColoredBox(color: colors.surface2)),
            FractionallySizedBox(
              widthFactor: progress,
              heightFactor: 1,
              child: ColoredBox(color: context.family),
            ),
          ],
        ),
      ),
    );
  }
}

class _Checks extends StatelessWidget {
  const _Checks({required this.checks});

  final List<bool?> checks;

  /// The square's side and the gap between squares.
  static const double side = 8;
  static const double gap = 4;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final slots = checks.isEmpty
        ? const <bool?>[null, null, null, null]
        : checks;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        for (var i = 0; i < slots.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: gap),
          switch (slots[i]) {
            true => _square(colors.fav),
            false => _square(colors.alert),
            null => CustomPaint(
              size: const Size(side, side),
              painter: _HatchSquare(colors.ink3),
            ),
          },
        ],
      ],
    );
  }

  static Widget _square(Color colour) => DecoratedBox(
    decoration: BoxDecoration(
      color: colour,
      borderRadius: BorderRadius.circular(2),
    ),
    child: const SizedBox(width: side, height: side),
  );
}

class _HatchSquare extends CustomPainter {
  const _HatchSquare(this.ink);

  final Color ink;

  @override
  void paint(Canvas canvas, Size size) =>
      paintHatch(canvas, Offset.zero & size, ink: ink, radius: 2, gap: 3);

  @override
  bool shouldRepaint(_HatchSquare old) => old.ink != ink;
}

class _Figure extends StatelessWidget {
  const _Figure({required this.row});

  final SignalRow row;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final figure = row.figure;
    final state = row.judgement.state;
    final fill = state.fillIn(colors);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Text.rich(
            TextSpan(
              text: figure?.text ?? '—',
              children: <InlineSpan>[
                if (figure != null && figure.unit.isNotEmpty)
                  TextSpan(
                    text: ' ${figure.unit}',
                    style: TypeLadder.callout.copyWith(color: colors.ink2),
                  ),
              ],
            ),
            maxLines: 1,
            style: TypeLadder.title2.copyWith(
              color: figure == null ? colors.ink3 : colors.ink,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Container(
          padding: fill == null
              ? EdgeInsets.zero
              : const EdgeInsets.symmetric(horizontal: 8),
          decoration: fill == null
              ? null
              : BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(999),
                ),
          child: Text(
            row.judgement.words,
            textAlign: TextAlign.right,
            style: TypeLadder.caption.copyWith(
              fontWeight: FontWeight.w600,
              fontVariations: const <FontVariation>[FontVariation('wght', 600)],
              color: state.colourIn(colors),
            ),
          ),
        ),
      ],
    );
  }
}
