/// The player's row of pattern chips. Picking one restarts the session with it.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/data/basics/breathing/breathing_pattern.dart';

/// A horizontally scrolling row of [patterns].
class BreathingPatternChips extends StatelessWidget {
  /// Chips for [patterns], [selected] filled in the Mind hue.
  const BreathingPatternChips({
    required this.patterns,
    required this.selected,
    required this.onSelect,
    super.key,
  });

  /// What can be picked.
  final List<BreathPattern> patterns;

  /// The one in use.
  final BreathPattern selected;

  /// Picks one.
  final ValueChanged<BreathPattern> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          for (final pattern in patterns) ...<Widget>[
            Semantics(
              button: true,
              selected: pattern == selected,
              label: '${pattern.name} ${pattern.counts}',
              child: ExcludeSemantics(
                child: GestureDetector(
                  onTap: () => onSelect(pattern),
                  behavior: HitTestBehavior.opaque,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: pattern == selected
                              ? context.family
                              : colors.surface2,
                          borderRadius: BorderRadius.circular(Radii.pill),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Insets.lg,
                            vertical: Insets.sm,
                          ),
                          child: Text.rich(
                            TextSpan(
                              children: <InlineSpan>[
                                TextSpan(
                                  text: pattern.name,
                                  style: TypeLadder.bodyStrong.copyWith(
                                    color: pattern == selected
                                        ? colors.onAccent
                                        : colors.ink2,
                                  ),
                                ),
                                TextSpan(
                                  text: '  ${pattern.dotted}',
                                  style: TypeLadder.callout.copyWith(
                                    color: pattern == selected
                                        ? colors.onAccent
                                        : colors.ink3,
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
              ),
            ),
            const SizedBox(width: Insets.sm),
          ],
        ],
      ),
    );
  }
}
