/// The plan screen's opening paragraph, written from the plan's own values.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/data/basics/breathing/breathing_plan.dart';
import 'package:healthee/features/coach/v02/breathing_format.dart';
import 'package:healthee/features/coach/v02/breathing_reason.dart';

/// The paragraph as runs. The minutes are bold, being the plan's own total.
///
/// Nights are the ones the plan was actually built from. The stress clause and
/// "plus one for bad nights" appear only when the on-demand item exists, and
/// the clause names the day the stress was on rather than assuming yesterday.
List<ReasonSpan> breathingIntro(BreathingPlan plan) {
  final nights = plan.nightsUsed;
  final stressDays = plan.stressDaysAgo;
  final hasOnDemand = plan.item(BreathingItemKind.onDemand) != null;
  final fixed = plan.items.where((i) => i.kind.isScheduled).length;
  final total = plan.totalMinutesPerDay;

  final String stress = !hasOnDemand
      ? ''
      : switch (stressDays) {
          null || 0 => " and this morning's stress",
          1 => " and yesterday's stress",
          final days => ' and stress from $days days ago',
        };
  final String first = nights == 0
      ? 'Not enough nights yet, so the times are defaults.'
      : 'Built from your last '
            '${nights == 1 ? 'night' : '$nights nights'}$stress.';
  return <ReasonSpan>[
    ReasonSpan('$first '),
    if (total == 0)
      const ReasonSpan('Every set time is switched off.')
    else ...<ReasonSpan>[
      ReasonSpan('$total minutes a day', bold: true),
      ReasonSpan(
        ' at ${countWord(fixed)} set times'
        '${hasOnDemand ? ', plus one for bad nights' : ''}.',
      ),
    ],
  ];
}

/// The paragraph at body size.
class BreathingIntro extends StatelessWidget {
  /// Draws the intro for [plan].
  const BreathingIntro(this.plan, {super.key});

  /// The plan.
  final BreathingPlan plan;

  @override
  Widget build(BuildContext context) =>
      SpanText(breathingIntro(plan), style: TypeLadder.body);
}
