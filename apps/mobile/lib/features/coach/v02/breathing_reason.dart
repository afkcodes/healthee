/// A sentence built from runs, with the owner's numbers in bold.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/data/basics/breathing/breathing_plan.dart';

/// [spans] at [style] in secondary ink, bold runs in primary ink.
class SpanText extends StatelessWidget {
  /// Draws [spans].
  const SpanText(this.spans, {this.style, super.key});

  /// The runs, from the plan builder's own structured values.
  final List<ReasonSpan> spans;

  /// The base style; defaults to the callout.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final base = (style ?? TypeLadder.callout).copyWith(color: colors.ink2);
    return Text.rich(
      TextSpan(
        style: base,
        children: <InlineSpan>[
          for (final span in spans)
            TextSpan(
              text: span.text,
              style: span.bold
                  ? base.copyWith(
                      color: colors.ink,
                      fontWeight: FontWeight.w700,
                    )
                  : null,
            ),
        ],
      ),
    );
  }
}
