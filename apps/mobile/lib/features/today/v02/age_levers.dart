/// The lever card: what each reading did to the biological-age estimate, in
/// years. One card, no border, hairlines between rows, no card inside it.
///
/// Rows run in payload order: the levers that were counted, then the ones the
/// server withheld today ("Not counted"), then the ones the model never counts
/// ("Left out"). An excluded or withheld term is always shown with the server's
/// own words, never dropped and never drawn as a computed zero.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/shapes.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/data/models/bio_age_block.dart';
import 'package:healthee/features/today/v02/age_lever_row.dart';
import 'package:healthee/shared/reveal_once.dart';

/// The card's corner radius, logical px.
const double kLeverCardRadius = 20;

/// The hairline's thickness, logical px.
const double kLeverHairline = 1;

/// The card's vertical padding: the rows bring the rest.
const double kLeverCardPadY = 4;

/// The lever card.
class AgeLeverCard extends StatelessWidget {
  const AgeLeverCard({
    required this.block,
    required this.reveals,
    this.onOpenLever,
    this.reasonsShownAbove = false,
    super.key,
  });

  /// Identifies the card for tests.
  static const Key cardKey = ValueKey<String>('age-lever-card');

  /// What the server said about the estimate.
  final BioAgeBlock block;

  /// Where each zone bar's reveal is remembered.
  final RevealRegistry reveals;

  /// Called with a lever's term when its row is tapped.
  final void Function(String term)? onOpenLever;

  /// Whether the screen already says, above this card, why the withheld
  /// levers are not counted. Each such row then says only `Not counted` and
  /// where the reason is, rather than the server's sentence a second time.
  final bool reasonsShownAbove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final rows = <Widget>[
      for (final c in block.contributions)
        AgeLeverRow(contribution: c, reveals: reveals, onOpen: onOpenLever),
      for (final d in block.absentTerms)
        AgeAbsentRow(
          term: d.term ?? d.reason,
          absence: LeverAbsence.notCounted,
          message: reasonsShownAbove ? null : d.message,
          note: reasonsShownAbove ? kReasonAbove : null,
          onOpen: onOpenLever,
        ),
      for (final d in block.exclusions)
        AgeAbsentRow(
          term: d.term ?? d.reason,
          absence: LeverAbsence.leftOut,
          message: firstSentence(d.message),
          onOpen: onOpenLever,
        ),
    ];
    return DecoratedBox(
      key: cardKey,
      decoration: ShapeDecoration(
        color: colors.surface,
        shape: hSquircle(kLeverCardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Insets.card,
          vertical: kLeverCardPadY,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (var i = 0; i < rows.length; i++) ...<Widget>[
              if (i > 0)
                Divider(
                  height: kLeverHairline,
                  thickness: kLeverHairline,
                  color: colors.line,
                ),
              rows[i],
            ],
          ],
        ),
      ),
    );
  }
}
