/// The segmented phase bar under the sphere: one segment per phase, widths in
/// proportion to seconds, the current one filling in the Mind hue.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/data/basics/breathing/breathing_pattern.dart';
import 'package:healthee/data/basics/breathing/breathing_progress.dart';

/// The label under a segment: "In 4", "Hold 4".
String phaseLabel(BreathPhase phase) =>
    '${phase.kind.shortLabel} ${phase.seconds}';

/// Phase segments for [pattern], driven by [progress].
class BreathingPhaseBar extends StatelessWidget {
  /// A bar for [pattern].
  const BreathingPhaseBar({
    required this.pattern,
    required this.progress,
    super.key,
  });

  /// Its timeline gives the segments.
  final BreathPattern pattern;

  /// The session's moment.
  final ValueListenable<BreathProgress> progress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final timeline = pattern.timeline;
    return ValueListenableBuilder<BreathProgress>(
      valueListenable: progress,
      builder: (context, now, _) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (var i = 0; i < timeline.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              flex: timeline[i].seconds,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _Segment(
                    fill: i < now.phaseIndex
                        ? 1
                        : i == now.phaseIndex
                        ? now.phaseFraction
                        : 0,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    phaseLabel(timeline[i]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TypeLadder.caption.copyWith(color: colors.ink2),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.fill});

  final double fill;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(3),
    child: Stack(
      children: <Widget>[
        Container(height: 6, color: context.colors.rule),
        FractionallySizedBox(
          widthFactor: fill.clamp(0.0, 1.0),
          child: Container(height: 6, color: context.family),
        ),
      ],
    ),
  );
}
