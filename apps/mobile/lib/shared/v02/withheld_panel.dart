/// `.withheld-value` — what v02 draws where a number the server refused belongs.
///
/// ```css
/// .withheld-value        { display:flex; align-items:center; gap:14px;
///                          padding:16px; border:1px dashed var(--rule);
///                          border-radius:14px; background:var(--surface-soft);
///                          color:var(--ink); margin-block:20px; }
/// .withheld-value > span { font-size:44px; color:var(--subtle); }
/// .withheld-value p      { font-size:12px; }
/// ```
///
/// The prototype has exactly one of these, in the missing-data scenario, and it
/// carries a sentence rather than a dash on its own. That is the whole design:
/// **a hole that says why it is a hole**. `states/withheld_card.dart` makes the
/// same argument at length for the pre-v02 screens and stays their carrier; this
/// is the same contract in the new geometry, so a v02 screen does not have to
/// choose between honest and consistent.
///
/// The dashed edge is load-bearing. Every other v02 container has a solid 1 px
/// line, so an outline that is visibly *broken* is the one shape on the screen
/// that reads as absence before a word is read.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/shapes.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_scale.dart';
import 'package:healthee/data/honesty/disclosure.dart';

/// A refused reading, in v02's geometry: the metric's name, a hole, the reason.
class WithheldPanel extends StatelessWidget {
  /// [label] names the metric, so a refusal is self-describing in a list.
  const WithheldPanel({required this.disclosure, this.label, super.key});

  /// `.withheld-value { padding: 16px }`.
  static const double padding = 16;

  /// `.withheld-value { border-radius: 14px }`.
  static const double radius = 14;

  /// `.withheld-value { gap: 14px }`.
  static const double gap = 14;

  /// The dash length of the broken edge, and the gap between dashes.
  static const double dash = 4;

  /// The gap under the label.
  static const double labelGap = 8;

  /// Why there is no value.
  final Disclosure disclosure;

  /// The metric's owner-facing name.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (label case final String name) ...<Widget>[
          Text(name, style: TypeScale.panelTitle.copyWith(color: colors.ink2)),
          const SizedBox(height: labelGap),
        ],
        CustomPaint(
          painter: _DashedEdge(colour: colors.rule),
          child: Container(
            padding: const EdgeInsets.all(padding),
            decoration: ShapeDecoration(
              color: colors.surface2,
              shape: hSquircle(radius),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Text(
                  '—',
                  // `.withheld-value > span`: the prototype's 44 px is the
                  // ladder's metric step, the size the refused number had.
                  style: TypeScale.panelValue.copyWith(color: colors.ink2),
                ),
                const SizedBox(width: gap),
                Expanded(
                  child: Text(
                    disclosure.message,
                    style: TypeScale.panelContext.copyWith(color: colors.ink),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// `border: 1px dashed`, which Flutter's `Border` cannot draw.
class _DashedEdge extends CustomPainter {
  const _DashedEdge({required this.colour});

  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(WithheldPanel.radius),
    );
    final paint = Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = hairline;
    for (final metric in (Path()..addRRect(rect)).computeMetrics()) {
      var at = 0.0;
      while (at < metric.length) {
        final end = (at + WithheldPanel.dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(at, end), paint);
        at = end + WithheldPanel.dash;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedEdge oldDelegate) => oldDelegate.colour != colour;
}
