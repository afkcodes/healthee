/// A pill that names how a reading is judged: words in the state's colour on
/// its soft fill, or on the neutral well when the state spends no colour.
///
/// The one chip for the colour kit's rule 4. [ReadingState.usual] and
/// [ReadingState.noData] have no soft fill, so they sit on `surface2` with
/// secondary-ink words: "usual" and "too few" are facts, not verdicts. The
/// words wrap rather than truncate: a verdict cut to "No change over ..." at a
/// large text size says less than the chip was drawn to say.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/shared/v02/reading_state.dart';

/// The chip.
class ReadingChip extends StatelessWidget {
  /// [text] in [state]'s colour.
  const ReadingChip(this.text, {required this.state, super.key});

  /// Chip padding.
  static const EdgeInsets padding = EdgeInsets.symmetric(
    horizontal: Insets.sm + 2,
    vertical: Insets.xs - 1,
  );

  /// The words, with their arrow.
  final String text;

  /// What the chip's colour says.
  final ReadingState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: state.fillIn(colors) ?? colors.surface2,
        shape: const StadiumBorder(),
      ),
      child: Padding(
        padding: padding,
        child: Text(
          text,
          style: TypeLadder.caption.copyWith(color: state.colourIn(colors)),
        ),
      ),
    );
  }
}
