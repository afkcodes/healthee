/// `Your VO₂max plan` — the projection, and the week that would get you there.
///
/// Legacy's card, rebuilt on the v02 panel set. The block behind it has been on
/// the wire the whole time with no reader; `data/models/fitness_plan.dart`
/// records that and why it matters.
///
/// ## The projection never appears without its caveat
///
/// `[[vo2max]]` D5: the typical response is stated **inside its bounds**, never
/// bare. Here that is structural rather than careful — the arrow, the gain and
/// the caveats are built in one `if` over `plan.hasProjection`, so there is no
/// arrangement of this widget that draws the number and drops the qualification.
/// When there is no age median to project against, the whole block is replaced
/// by the server's own `withheld` message, which says so in the owner's words.
///
/// ## A block with no minutes recorded draws no bar
///
/// `doneMin` null is *"the week's minutes are not known"*, and an empty bar at
/// 0% is a different claim — that nothing was done. The row prints the target
/// and says the week is unread instead.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/core/theme/type_scale.dart';
import 'package:healthee/data/models/fitness_plan.dart';
import 'package:healthee/shared/v02/panel.dart';
import 'package:healthee/shared/v02/panel_head.dart';
import 'package:healthee/shared/v02/panel_parts.dart';
import 'package:solar_icons/solar_icons.dart';

/// The plan card.
class FitnessPlanPanel extends StatelessWidget {
  /// [plan] is `/api/activity.fitness_plan`, already parsed.
  const FitnessPlanPanel({required this.plan, super.key});

  /// The card's title.
  static const String title = 'Your VO₂max plan';

  /// The gap between the projection and the week's blocks.
  static const double blocksGap = 18;

  /// The gap between two blocks.
  static const double blockGap = 14;

  /// What the plan says.
  final FitnessPlan plan;

  @override
  Widget build(BuildContext context) {
    return Panel(
      tone: Tone.fitness,
      label: 'VO₂max plan',
      head: const PanelHead(
        title: title,
        icon: SolarIconsOutline.target,
        infoKey: 'vo2max',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (plan.hasProjection)
            _Projection(plan: plan)
          else if (plan.withheld?.message case final String why)
            PanelNote(why),
          if (plan.blocks.isNotEmpty) ...<Widget>[
            const SizedBox(height: blocksGap),
            Text(
              'THIS WEEK',
              style: TypeLadder.label.copyWith(color: context.colors.ink2),
            ),
            for (final block in plan.blocks) ...<Widget>[
              const SizedBox(height: blockGap),
              _BlockRow(block: block),
            ],
          ],
          // Every caveat the server attached to the projection, drawn whenever
          // the projection is. See the library docstring.
          for (final caveat in plan.caveats)
            if (plan.hasProjection) PanelNote(caveat),
          if (plan.blocks.isEmpty &&
              !plan.hasProjection &&
              plan.withheld == null)
            const PanelNote('The server sent no plan for these weeks.'),
        ],
      ),
    );
  }
}

/// `40.9 → 45.2` and what the arrow is worth.
class _Projection extends StatelessWidget {
  const _Projection({required this.plan});

  final FitnessPlan plan;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Text(
          plan.current?.toStringAsFixed(1) ?? '—',
          style: TypeLadder.title1.copyWith(color: colors.ink2),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Icon(
            SolarIconsOutline.arrowRight,
            size: 16,
            color: colors.ink2,
          ),
        ),
        Text(
          plan.projected12wk!.toStringAsFixed(1),
          style: TypeLadder.title1.copyWith(color: colors.ink),
        ),
        const Spacer(),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '+${plan.gain!.toStringAsFixed(1)} ml/kg/min',
                maxLines: 1,
                style: TypeLadder.calloutStrong.copyWith(color: colors.ink),
              ),
              Text(
                'in ${plan.weeks ?? 12} weeks, on this plan',
                maxLines: 2,
                textAlign: TextAlign.right,
                style: TypeScale.panelNote.copyWith(color: colors.ink2),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One prescribed block: its name, its progress, its sentence.
class _BlockRow extends StatelessWidget {
  const _BlockRow({required this.block});

  static const double trackHeight = 6;
  static const double trackRadius = 4;

  final PlanBlock block;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final family = context.family;
    final fraction = block.fraction;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                block.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TypeLadder.calloutStrong.copyWith(color: colors.ink),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              // Null minutes is not zero minutes — see the library docstring.
              block.doneMin == null
                  ? 'target ${block.targetMin} min'
                  : '${block.doneMin} / ${block.targetMin} min',
              style: (block.met ? TypeLadder.calloutStrong : TypeLadder.callout)
                  .copyWith(color: block.met ? colors.ink : colors.ink2),
            ),
          ],
        ),
        if (fraction != null) ...<Widget>[
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(trackRadius),
            child: SizedBox(
              height: trackHeight,
              child: Stack(
                children: <Widget>[
                  ColoredBox(
                    color: colors.line,
                    child: const SizedBox(
                      width: double.infinity,
                      height: trackHeight,
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: fraction,
                    child: ColoredBox(
                      color: family,
                      child: const SizedBox(height: trackHeight),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (block.description case final String sentence) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            sentence,
            style: TypeScale.panelNote.copyWith(color: colors.ink2),
          ),
        ],
      ],
    );
  }
}
