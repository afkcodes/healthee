/// "Breath 23 of 60", the time left, and the overall progress bar.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/data/basics/breathing/breathing_progress.dart';

/// The two lines under the phase bar.
class BreathingProgressLines extends StatelessWidget {
  /// Lines driven by [progress].
  const BreathingProgressLines({required this.progress, super.key});

  /// The session's moment.
  final ValueListenable<BreathProgress> progress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ValueListenableBuilder<BreathProgress>(
      valueListenable: progress,
      builder: (context, now, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Breath ${now.breath} of ${now.totalBreaths}',
                  style: TypeLadder.bodyStrong.copyWith(color: colors.ink),
                ),
              ),
              Text(
                '${now.leftLabel} left',
                style: TypeLadder.callout.copyWith(color: colors.ink2),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Stack(
              children: <Widget>[
                Container(height: 6, color: colors.rule),
                FractionallySizedBox(
                  widthFactor: now.fraction.clamp(0.0, 1.0),
                  child: Container(
                    height: 6,
                    color: context.family.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
