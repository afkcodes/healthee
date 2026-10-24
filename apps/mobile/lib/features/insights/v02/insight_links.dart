/// The link list at the foot of Insights: five ways into the history, in one
/// card of hairline rows with bare icons.
///
/// Every row keeps the route and the detail line it had. Colour is not spent
/// here: a link is chrome, and the icons are secondary ink.
library;

import 'package:flutter/material.dart';
import 'package:healthee/shared/v02/link_list.dart';
import 'package:solar_icons/solar_icons.dart';

/// The card.
class InsightLinks extends StatelessWidget {
  /// A row without its callback draws without a chevron.
  const InsightLinks({
    this.onOpenTrends,
    this.onOpenLedger,
    this.onOpenJournal,
    this.onOpenSleepHistory,
    this.onOpenFitness,
    super.key,
  });

  /// Opens `Your trends`.
  final VoidCallback? onOpenTrends;

  /// Opens `Every yes, checked`.
  final VoidCallback? onOpenLedger;

  /// Opens the journal.
  final VoidCallback? onOpenJournal;

  /// Opens the sleep history.
  final VoidCallback? onOpenSleepHistory;

  /// Opens the fitness detail.
  final VoidCallback? onOpenFitness;

  @override
  Widget build(BuildContext context) => LinkListCard(
    rows: <LinkRow>[
      LinkRow(
        icon: SolarIconsOutline.chartSquare,
        title: 'Trends',
        detail: 'A week, a month or six months against the period before',
        onOpen: onOpenTrends,
      ),
      LinkRow(
        icon: SolarIconsOutline.flag,
        title: 'Every yes, checked',
        detail: 'What the strap saw for each one',
        onOpen: onOpenLedger,
      ),
      LinkRow(
        icon: SolarIconsOutline.book,
        title: 'Notable moments',
        detail: 'Your caffeine, meditation and fasting context',
        onOpen: onOpenJournal,
      ),
      LinkRow(
        icon: SolarIconsOutline.moonSleep,
        title: 'Sleep history',
        detail: 'Every night in the window, and the way into one of them',
        onOpen: onOpenSleepHistory,
      ),
      LinkRow(
        icon: SolarIconsOutline.graphUp,
        title: 'Fitness estimates',
        detail: 'VO₂max, the instrument behind it, and what it is stored as',
        onOpen: onOpenFitness,
      ),
    ],
  );
}
