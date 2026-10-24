/// "Today's basics": the small things the owner logs by hand. The water card
/// and the breathing card, 12 apart.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/features/coach/v02/breathing_card.dart';
import 'package:healthee/features/coach/v02/home_head.dart';

/// The section.
class TodaysBasicsSection extends StatelessWidget {
  /// [water] is the water card, passed in by the home screen when it exists.
  const TodaysBasicsSection({this.water, super.key});

  /// The water card, or nothing until it is built.
  final Widget? water;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      CoachSectionHead.text(
        context,
        "Today's basics",
        trailing: const HeadCaption('tap to log'),
      ),
      if (water case final Widget card) ...<Widget>[
        card,
        const SizedBox(height: Insets.cardGap),
      ],
      const BreathingCard(),
    ],
  );
}
