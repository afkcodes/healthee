/// The breathing player: a sphere that breathes, the phases, and the controls.
///
/// Opened for a plan item (`?item=night`) or a pattern (`?pattern=box`). There
/// is no sound: the app ships no audio, and the screen does not pretend to.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/data/basics/breathing/breathing_plan_provider.dart';
import 'package:healthee/data/basics/breathing/breathing_settings_provider.dart';
import 'package:healthee/features/coach/v02/breathing_session.dart';
import 'package:healthee/features/coach/v02/breathing_session_spec.dart';
import 'package:healthee/shared/states/state_scaffold.dart';
import 'package:healthee/shared/v02/detail_page.dart';

/// The player screen.
class BreathingPlayerScreen extends ConsumerWidget {
  /// A session for plan item [item] or pattern [patternId].
  const BreathingPlayerScreen({this.item, this.patternId, super.key});

  /// A `BreathingItemKind` name.
  final String? item;

  /// A pattern id.
  final String? patternId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(breathingSettingsControllerProvider);
    final plan = ref.watch(breathingPlanProvider).value;
    return ToneScope(
      tone: Tone.stress,
      child: settings.when(
        data: (settings) {
          final spec = resolveBreathingSession(
            settings: settings,
            plan: plan,
            item: item,
            patternId: patternId,
          );
          return spec == null
              ? const _Message(
                  child: EmptyState(
                    message: 'That session is not available',
                    hint: 'Pick one from the breathing plan.',
                  ),
                )
              : BreathingSession(spec: spec);
        },
        loading: () => const _Message(child: LoadingState()),
        error: (error, stack) => _Message(
          child: ErrorState(
            message: "Couldn't load your breathing settings.",
            onRetry: () => ref.invalidate(breathingSettingsControllerProvider),
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: 'Back',
                onPressed: () => leaveDetail(context),
                icon: const Icon(Icons.arrow_back),
              ),
            ),
            child,
          ],
        ),
      ),
    ),
  );
}
