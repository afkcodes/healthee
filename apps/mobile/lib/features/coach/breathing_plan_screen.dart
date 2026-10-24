/// The breathing plan: what the plan is built from, the four items with a
/// switch each, and the patterns.
///
/// Every sentence about the owner comes from the plan's own values. Nothing
/// here is asked of the server.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/data/basics/breathing/breathing_pattern.dart';
import 'package:healthee/data/basics/breathing/breathing_plan_provider.dart';
import 'package:healthee/features/coach/v02/breathing_ink_button.dart';
import 'package:healthee/features/coach/v02/breathing_intro.dart';
import 'package:healthee/features/coach/v02/breathing_patterns_card.dart';
import 'package:healthee/features/coach/v02/breathing_plan_items.dart';
import 'package:healthee/features/coach/v02/breathing_run.dart';
import 'package:healthee/features/coach/v02/home_head.dart';
import 'package:healthee/shared/states/state_scaffold.dart';
import 'package:healthee/shared/v02/back_label_head.dart';
import 'package:healthee/shared/v02/detail_page.dart';

/// The screen's title.
const String kBreathingPlanTitle = 'Breathing plan';

/// The line under the accept button.
const String kBreathingAcceptNote =
    'Reminders at these times. Every session logs to your journal as '
    'meditation.';

/// The plan screen.
class BreathingPlanScreen extends ConsumerWidget {
  /// Opens on today's plan.
  const BreathingPlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(breathingPlanProvider);
    final colors = context.colors;
    return ToneScope(
      tone: Tone.stress,
      child: DetailPage(
        title: kBreathingPlanTitle,
        head: (context, onBack) => BackLabelHead(
          backLabel: 'Coach',
          title: kBreathingPlanTitle,
          onBack: onBack,
        ),
        children: <Widget>[
          ...plan.when(
            data: (plan) => <Widget>[
              BreathingIntro(plan),
              const SizedBox(height: Insets.lg),
              BreathingPlanItems(plan: plan),
              const SizedBox(height: Insets.md),
              InkButton(
                label: 'Accept all ${plan.items.length}',
                onPressed: () => runBreathingAction(
                  context,
                  'set the reminders',
                  () => ref.read(breathingActionsProvider.notifier).acceptAll(),
                ),
              ),
              const SizedBox(height: Insets.md),
              Text(
                kBreathingAcceptNote,
                textAlign: TextAlign.center,
                style: TypeLadder.callout.copyWith(color: colors.ink2),
              ),
            ],
            loading: () => const <Widget>[LoadingState()],
            error: (error, stack) => <Widget>[
              ErrorState(
                message: "Couldn't load your plan.",
                onRetry: () => ref.invalidate(breathingPlanProvider),
              ),
            ],
          ),
          const SizedBox(height: Insets.section),
          CoachSectionHead.text(context, 'Patterns'),
          const BreathingPatternsCard(),
          const SizedBox(height: Insets.md),
          Text(
            kBreathingFootnote,
            style: TypeLadder.callout.copyWith(color: colors.ink2),
          ),
        ],
      ),
    );
  }
}
