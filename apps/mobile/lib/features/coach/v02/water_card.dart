/// The water card of Today's basics: glasses drunk today, tap to log or undo.
///
/// Self-contained: it reads the journal feed, the owner's glass count and the
/// optimistic taps itself. The count is the owner's own; nothing here says how
/// much anyone should drink (`hydration_everyday`, `hydration_8x8_rule`).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/data/api/server_snapshot.dart';
import 'package:healthee/data/basics/water/water_controller.dart';
import 'package:healthee/data/basics/water/water_day.dart';
import 'package:healthee/data/basics/water/water_format.dart';
import 'package:healthee/data/basics/water/water_settings.dart';
import 'package:healthee/data/basics/water/water_settings_provider.dart';
import 'package:healthee/data/journal/journal_feed.dart';
import 'package:healthee/data/journal/journal_repository.dart';
import 'package:healthee/features/coach/v02/water_glasses.dart';
import 'package:healthee/features/coach/v02/water_target_sheet.dart';
import 'package:healthee/shared/skeletons/h_skeleton.dart';
import 'package:healthee/shared/states/current_account_value.dart';
import 'package:healthee/shared/v02/surface_panels.dart';

/// The line under the glasses.
const String kWaterCaption =
    'Tap the next glass to log 250 ml. Tap a full one to undo. '
    'Tea and coffee count.';

/// The water card.
class WaterCard extends ConsumerWidget {
  /// The card; it reads its own providers.
  const WaterCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = currentAccountValue(ref.watch(journalFeedProvider));
    final settings = ref.watch(waterSettingsProvider);
    final ops = ref.watch(waterControllerProvider);
    final now = ref.watch(waterClockProvider)();
    void retry() {
      ref
        ..invalidate(journalFeedProvider)
        ..invalidate(waterSettingsProvider);
    }

    final Widget body;
    if (feed.hasError || settings.hasError) {
      body = _ErrorLine(onRetry: retry);
    } else if (feed.value == null || settings.value == null) {
      body = const _Skeleton();
    } else {
      final ServerSnapshot<JournalFeed> snapshot = feed.requireValue;
      body = _Loaded(
        day: WaterDay.from(snapshot, ops, now),
        settings: settings.requireValue,
      );
    }
    return ToneScope(
      tone: Tone.fitness,
      child: SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[body],
        ),
      ),
    );
  }
}

class _Loaded extends ConsumerWidget {
  const _Loaded({required this.day, required this.settings});

  final WaterDay day;
  final WaterSettings settings;

  Future<void> _run(
    BuildContext context,
    Future<String?> Function() act,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final problem = await act();
    if (problem != null) {
      messenger?.showSnackBar(SnackBar(content: Text(problem)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final controller = ref.read(waterControllerProvider.notifier);
    final target = settings.target;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                color: context.familySoft,
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Insets.md,
                  vertical: Insets.xs,
                ),
                child: Text(
                  'Water',
                  style: TypeLadder.calloutStrong.copyWith(
                    color: context.family,
                  ),
                ),
              ),
            ),
            const Spacer(),
            Flexible(
              child: Semantics(
                button: true,
                excludeSemantics: true,
                label:
                    'Change the number of glasses. '
                    '${settings.isSet ? 'Set by you' : 'Default'}, '
                    '$target glasses',
                child: InkWell(
                  onTap: () => unawaited(showWaterTargetSheet(context, target)),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        '${settings.isSet ? 'set by you' : 'default'} · change',
                        textAlign: TextAlign.right,
                        style: TypeLadder.callout.copyWith(color: colors.ink2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: Insets.sm,
          children: <Widget>[
            Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  TextSpan(
                    text: '${day.filled}',
                    style: TypeLadder.metric.copyWith(color: colors.ink),
                  ),
                  TextSpan(
                    text: ' of $target glasses',
                    style: TypeLadder.headline.copyWith(
                      color: colors.ink2,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: Insets.sm),
              child: Text(
                '${groupedMl(day.totalMl)} of '
                '${groupedMl(target * kGlassMl)} ml',
                style: TypeLadder.callout.copyWith(color: colors.ink2),
              ),
            ),
          ],
        ),
        const SizedBox(height: Insets.sm),
        WaterGlasses(
          day: day,
          target: target,
          onLog: () => unawaited(_run(context, controller.addGlass)),
          onUndo: () =>
              unawaited(_run(context, () => controller.undoLatest(day))),
        ),
        const SizedBox(height: Insets.sm),
        Text(
          kWaterCaption,
          style: TypeLadder.callout.copyWith(color: colors.ink2),
        ),
      ],
    );
  }
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            'Could not load your water log.',
            style: TypeLadder.body.copyWith(color: colors.ink),
          ),
        ),
        TextButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading your water log',
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        HSkeleton(height: 24, width: 80),
        SizedBox(height: Insets.md),
        HSkeleton(height: 40, width: 160),
        SizedBox(height: Insets.md),
        HSkeleton(height: 32),
      ],
    ),
  );
}
