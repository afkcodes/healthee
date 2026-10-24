/// The plan card: four items, each with its time, pattern, reason and switch.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/data/basics/breathing/breathing_plan.dart';
import 'package:healthee/data/basics/breathing/breathing_plan_provider.dart';
import 'package:healthee/data/basics/breathing/breathing_settings_provider.dart';
import 'package:healthee/features/coach/v02/breathing_format.dart';
import 'package:healthee/features/coach/v02/breathing_reason.dart';
import 'package:healthee/features/coach/v02/breathing_run.dart';
import 'package:healthee/shared/v02/surface_panels.dart';

/// One card of rows.
class BreathingPlanItems extends ConsumerWidget {
  /// Draws [plan]'s items.
  const BreathingPlanItems({required this.plan, super.key});

  /// The plan.
  final BreathingPlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SurfaceCard(
    child: Column(
      children: <Widget>[
        for (var i = 0; i < plan.items.length; i++) ...<Widget>[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Insets.md),
              child: Divider(
                height: hairline,
                thickness: hairline,
                color: context.colors.line,
              ),
            ),
          _ItemRow(item: plan.items[i]),
        ],
      ],
    ),
  );
}

class _ItemRow extends ConsumerWidget {
  const _ItemRow({required this.item});

  final BreathingItem item;

  Future<void> _pickNightTime(BuildContext context, WidgetRef ref) async {
    final minute = item.minuteOfDay;
    if (minute == null) return;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minute ~/ 60, minute: minute % 60),
      helpText: 'Free from',
    );
    if (picked == null || !context.mounted) return;
    await runBreathingAction(context, 'save that time', () async {
      await ref
          .read(breathingSettingsControllerProvider.notifier)
          .setNightFreeFrom(picked.hour * 60 + picked.minute);
      await ref.read(breathingActionsProvider.notifier).syncReminders();
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final isNight = item.kind == BreathingItemKind.night;
    final minute = item.minuteOfDay;
    final when = minute == null
        ? 'On demand · ${item.minutes} min'
        : '${clockLabel(minute)} · ${item.minutes} min';
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: Insets.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Text(
              item.kind.label,
              style: TypeLadder.bodyStrong.copyWith(color: colors.ink),
            ),
            Text(
              when,
              style: TypeLadder.callout.copyWith(
                color: colors.ink2,
                decoration: isNight ? TextDecoration.underline : null,
                decorationColor: colors.ink2,
              ),
            ),
          ],
        ),
        Text(
          patternLine(item.pattern),
          style: TypeLadder.callout.copyWith(color: colors.ink2),
        ),
        const SizedBox(height: Insets.sm),
        SpanText(item.reasonParts),
      ],
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: isNight
              ? Semantics(
                  button: true,
                  hint: 'Change when your free time ends',
                  child: GestureDetector(
                    onTap: () => _pickNightTime(context, ref),
                    behavior: HitTestBehavior.opaque,
                    child: text,
                  ),
                )
              : text,
        ),
        const SizedBox(width: Insets.md),
        Semantics(
          label: '${item.kind.label} on',
          child: Switch(
            value: item.enabled,
            onChanged: (on) => runBreathingAction(
              context,
              'update the reminders',
              () => ref
                  .read(breathingActionsProvider.notifier)
                  .setEnabled(item.kind, on: on),
            ),
            thumbColor: WidgetStatePropertyAll<Color>(
              item.enabled ? colors.onAccent : colors.surface,
            ),
            trackColor: WidgetStatePropertyAll<Color>(
              item.enabled ? context.family : colors.rule,
            ),
            trackOutlineColor: const WidgetStatePropertyAll<Color>(
              Colors.transparent,
            ),
          ),
        ),
      ],
    );
  }
}
