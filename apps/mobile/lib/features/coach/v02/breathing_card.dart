/// The Breathing card under "Today's basics": the enabled fixed items of the
/// plan, which are done, which is next.
///
/// "Done" is what the owner did in the app today (a session from that item that
/// finished or reached a whole minute). It is not a verdict from the strap.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:healthee/core/routes.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/data/basics/breathing/breathing_done.dart';
import 'package:healthee/data/basics/breathing/breathing_plan.dart';
import 'package:healthee/data/basics/breathing/breathing_plan_provider.dart';
import 'package:healthee/features/coach/v02/breathing_card_row.dart';
import 'package:healthee/features/coach/v02/breathing_format.dart';
import 'package:healthee/features/coach/v02/breathing_play_button.dart';
import 'package:healthee/shared/v02/surface_panels.dart';

/// The fixed items shown on the card: enabled and on a schedule, in order.
List<BreathingItem> cardItems(BreathingPlan plan) => [
  for (final item in plan.items)
    if (item.enabled && item.kind.isScheduled) item,
];

/// Each shown item's state: done, then the first not done is next, the rest
/// later.
Map<BreathingItemKind, BreathingRowState> rowStates(
  List<BreathingItem> items,
  Set<BreathingItemKind> done,
) {
  final states = <BreathingItemKind, BreathingRowState>{};
  var nextTaken = false;
  for (final item in items) {
    if (done.contains(item.kind)) {
      states[item.kind] = BreathingRowState.done;
    } else if (!nextTaken) {
      nextTaken = true;
      states[item.kind] = BreathingRowState.next;
    } else {
      states[item.kind] = BreathingRowState.later;
    }
  }
  return states;
}

/// The card.
class BreathingCard extends ConsumerWidget {
  /// Reads the plan and today's done items.
  const BreathingCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(breathingPlanProvider);
    final done = ref.watch(breathingDoneProvider).value ?? const {};
    return SurfaceCard(
      tone: Tone.stress,
      child: plan.when(
        data: (plan) => _Body(items: cardItems(plan), done: done),
        loading: () => const _Message(text: 'Loading your plan.'),
        error: (error, stack) => _Message(
          text: "Couldn't load your plan.",
          onRetry: () => ref.invalidate(breathingPlanProvider),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.items, required this.done});

  final List<BreathingItem> items;
  final Set<BreathingItemKind> done;

  @override
  Widget build(BuildContext context) {
    final states = rowStates(items, done);
    final count = states.values
        .where((s) => s == BreathingRowState.done)
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Head(caption: '$count of ${items.length} today · edit plan'),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Insets.md),
            child: Text(
              'Every session is switched off. Edit the plan to turn some on.',
              style: TypeLadder.body.copyWith(color: context.colors.ink2),
            ),
          ),
        for (var i = 0; i < items.length; i++) ...<Widget>[
          if (i > 0)
            Divider(
              height: hairline,
              thickness: hairline,
              color: context.colors.line,
            ),
          BreathingCardRow(item: items[i], state: states[items[i].kind]!),
        ],
      ],
    );
  }
}

class _Head extends StatelessWidget {
  const _Head({required this.caption});

  final String caption;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      const ToneChip('Breathing'),
      const SizedBox(width: Insets.sm),
      Expanded(
        child: Semantics(
          button: true,
          label: 'Edit breathing plan. $caption',
          child: ExcludeSemantics(
            child: GestureDetector(
              onTap: () => context.push(Routes.breathingPlan),
              behavior: HitTestBehavior.opaque,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    caption,
                    textAlign: TextAlign.end,
                    style: TypeLadder.callout.copyWith(
                      color: context.colors.ink2,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.onRetry});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      const ToneChip('Breathing'),
      const SizedBox(height: Insets.md),
      Text(text, style: TypeLadder.body.copyWith(color: context.colors.ink2)),
      if (onRetry != null)
        TextButton(onPressed: onRetry, child: const Text('Try again')),
    ],
  );
}
