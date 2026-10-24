/// The player's head: a back arrow, the session's name, its time and length.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:solar_icons/solar_icons.dart';

/// The head.
class BreathingPlayerHead extends StatelessWidget {
  /// A head for [title] and [subtitle]; [onBack] leaves or asks to end.
  const BreathingPlayerHead({
    required this.title,
    required this.subtitle,
    required this.onBack,
    super.key,
  });

  /// The session's name.
  final String title;

  /// Time and length.
  final String subtitle;

  /// Back.
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: <Widget>[
        Semantics(
          button: true,
          label: 'Back',
          child: ExcludeSemantics(
            child: GestureDetector(
              onTap: onBack,
              behavior: HitTestBehavior.opaque,
              child: SizedBox.square(
                dimension: 44,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Icon(
                    SolarIconsOutline.arrowLeft,
                    size: 22,
                    color: colors.ink,
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: TypeLadder.bodyStrong.copyWith(color: colors.ink),
              ),
              Text(
                subtitle,
                style: TypeLadder.callout.copyWith(color: colors.ink2),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
