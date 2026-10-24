/// One row of the Breathing card: time, name, pattern, and the round control.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:healthee/core/routes.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/data/basics/breathing/breathing_plan.dart';
import 'package:healthee/features/coach/v02/breathing_format.dart';
import 'package:healthee/features/coach/v02/breathing_play_button.dart';

/// A scheduled item with a time. The tap opens its session.
class BreathingCardRow extends StatelessWidget {
  /// A row for [item] in [state].
  const BreathingCardRow({required this.item, required this.state, super.key});

  /// The item; its time is never null for a scheduled one.
  final BreathingItem item;

  /// Where it stands today.
  final BreathingRowState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final minute = item.minuteOfDay;
    final parts = minute == null ? null : clockParts(minute);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Insets.sm),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 56,
            child: parts == null
                ? null
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        parts.time,
                        style: TypeLadder.bodyStrong.copyWith(
                          color: colors.ink,
                        ),
                      ),
                      Text(
                        parts.meridiem,
                        style: TypeLadder.micro.copyWith(color: colors.ink2),
                      ),
                    ],
                  ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${item.kind.label} · ${item.minutes} min',
                  style: TypeLadder.bodyStrong.copyWith(color: colors.ink),
                ),
                Text(
                  patternLine(item.pattern),
                  style: TypeLadder.callout.copyWith(color: colors.ink2),
                ),
              ],
            ),
          ),
          const SizedBox(width: Insets.sm),
          BreathingPlayButton(
            state: state,
            label: switch (state) {
              BreathingRowState.done => '${item.kind.label} done. Start again',
              _ => 'Start ${item.kind.label}',
            },
            onPressed: () =>
                context.push(breathingPlayerLocation(item: item.kind.name)),
          ),
        ],
      ),
    );
  }
}
