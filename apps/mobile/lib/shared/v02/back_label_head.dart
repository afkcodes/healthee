/// A pushed screen's head with a named back control: `‹ Coach`, then a Title1.
///
/// The Coach area's two sub screens open on where they came from. The glyph and
/// its label are one 44 pt target, outdented like `DetailHead`'s so the arrow
/// lines up with the title's left edge.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:solar_icons/solar_icons.dart';

/// The head.
class BackLabelHead extends StatelessWidget {
  /// [onBack] null draws the label with no control.
  const BackLabelHead({
    required this.backLabel,
    required this.title,
    required this.onBack,
    super.key,
  });

  /// Target height.
  static const double height = 44;

  /// Where the arrow leads.
  final String backLabel;

  /// The screen's name, at Title1.
  final String title;

  /// Leaves.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Semantics(
            button: true,
            label: 'Back to $backLabel',
            child: ExcludeSemantics(
              child: GestureDetector(
                onTap: onBack,
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  height: height,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        SolarIconsOutline.arrowLeft,
                        size: 22,
                        color: colors.ink,
                      ),
                      const SizedBox(width: Insets.md),
                      Text(
                        backLabel,
                        style: TypeLadder.body.copyWith(color: colors.ink2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Text(title, style: TypeLadder.title1.copyWith(color: colors.ink)),
        ],
      ),
    );
  }
}
