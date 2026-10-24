/// "What the pattern says": the server's sentence, verbatim.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/shared/v02/surface_panels.dart';

/// The card. Callers draw nothing at all when there is no pattern.
class LedgerPatternCard extends StatelessWidget {
  /// Shows [text] unchanged.
  const LedgerPatternCard({required this.text, super.key});

  /// The card's heading.
  static const String heading = 'What the pattern says';

  /// The server's words.
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: colors.ink,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: Insets.sm),
              Text(
                heading,
                style: TypeLadder.callout.copyWith(color: colors.ink2),
              ),
            ],
          ),
          const SizedBox(height: Insets.md),
          Text(text, style: TypeLadder.body.copyWith(color: colors.ink)),
        ],
      ),
    );
  }
}
