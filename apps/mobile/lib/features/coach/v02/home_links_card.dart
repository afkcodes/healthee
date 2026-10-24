/// The Coach home's link list: the ledger, the running plan, the journal.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:healthee/core/routes.dart';
import 'package:healthee/data/challenges/commitment_repository.dart';
import 'package:healthee/data/challenges/health_program.dart';
import 'package:healthee/shared/format/metric_names.dart';
import 'package:healthee/shared/v02/link_list.dart';
import 'package:solar_icons/solar_icons.dart';

/// The program row's second line, from the program's own first and last rung.
///
/// Null when there are no rungs. Nothing here is a constant: the numbers, the
/// metric and the cadence word all come from the rungs.
String? programDetail(HealthProgram program) {
  if (program.rungs.isEmpty) {
    return null;
  }
  final first = program.rungs.first;
  final last = program.rungs.last;
  String number(double v) => v == v.roundToDouble() ? '${v.round()}' : '$v';
  final per = switch (first.cadence) {
    'weekly' => ' a week',
    'daily' => ' a day',
    _ => '',
  };
  final span = first.target == last.target
      ? number(first.target)
      : '${number(first.target)} to ${number(last.target)}';
  return '$span ${metricName(first.metric)}$per';
}

/// The card.
class CoachLinksCard extends ConsumerWidget {
  /// Reads the active program.
  const CoachLinksCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final program = ref.watch(programFeedProvider).value?.data.active;
    return LinkListCard(
      rows: <LinkRow>[
        LinkRow(
          icon: SolarIconsOutline.checklist,
          title: 'Every yes, checked',
          detail: 'What the strap saw for each one',
          onOpen: () => unawaited(context.push(Routes.coachLedger)),
        ),
        if (program != null)
          LinkRow(
            icon: SolarIconsOutline.flag,
            title: program.title,
            detail: programDetail(program),
            onOpen: () =>
                unawaited(context.push('${Routes.program}/${program.id}')),
          ),
        LinkRow(
          icon: SolarIconsOutline.notebook,
          title: 'Journal',
          detail: 'Water and breathing land here too',
          onOpen: () => unawaited(context.push(Routes.journal)),
        ),
      ],
    );
  }
}
