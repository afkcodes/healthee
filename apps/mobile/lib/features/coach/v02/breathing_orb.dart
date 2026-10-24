/// The sphere that breathes, with the phase word and countdown at its centre.
///
/// The dots are `AgeSphere`, scaled by the breath; this adds the ring and the
/// words. Under reduced motion the sphere is not scaled: the word, the number
/// and the bars still change.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/data/basics/breathing/breathing_progress.dart';
import 'package:healthee/shared/v02/instruments/age_sphere.dart';

/// The ring's diameter over the sphere canvas it holds.
const double _canvasShare = 0.94;

/// The orb for a session in [progress].
class BreathingOrb extends StatelessWidget {
  /// An orb [diameter] across.
  const BreathingOrb({
    required this.diameter,
    required this.progress,
    required this.scale,
    this.doneWord,
    super.key,
  });

  /// The ring's outer size.
  final double diameter;

  /// The session's moment.
  final ValueListenable<BreathProgress> progress;

  /// The sphere's scale, or null to hold it still.
  final ValueListenable<double>? scale;

  /// When set, shown instead of the phase and number: the session is over.
  final String? doneWord;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox.square(
      dimension: diameter,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: context.family.withValues(alpha: 0.4)),
            ),
            child: const SizedBox.expand(),
          ),
          AgeSphere(
            canvas: diameter * _canvasShare,
            useFamily: true,
            breath: scale,
            centre: ValueListenableBuilder<BreathProgress>(
              valueListenable: progress,
              builder: (context, now, _) => Semantics(
                liveRegion: true,
                label: doneWord ?? '${now.phase.kind.prompt} ${now.countdown}',
                child: ExcludeSemantics(
                  child: SizedBox(
                    width: diameter * 0.62,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            doneWord ?? now.phase.kind.prompt,
                            style: TypeLadder.title1.copyWith(
                              color: colors.ink,
                            ),
                          ),
                          if (doneWord == null)
                            Text(
                              '${now.countdown}',
                              style: TypeLadder.display.copyWith(
                                color: colors.ink,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
