/// The round control at the end of a card row: done, next, or later.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:solar_icons/solar_icons.dart';

/// Where a plan item stands today.
enum BreathingRowState {
  /// A session from it was finished or reached a whole minute.
  done,

  /// The first one not done.
  next,

  /// Not done and after the next one.
  later,
}

/// A 40 px circle inside a 44 px target. Reads its hue from the tone above.
class BreathingPlayButton extends StatelessWidget {
  /// The control for [state]; [onPressed] starts the session.
  const BreathingPlayButton({
    required this.state,
    required this.label,
    required this.onPressed,
    super.key,
  });

  /// The circle's diameter.
  static const double diameter = 40;

  /// Where the item stands.
  final BreathingRowState state;

  /// What a screen reader says.
  final String label;

  /// Starts the session.
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (fill, border, glyph, icon) = switch (state) {
      BreathingRowState.done => (
        context.familySoft,
        null,
        context.family,
        Icons.check_rounded,
      ),
      BreathingRowState.next => (
        context.family,
        null,
        colors.onAccent,
        SolarIconsBold.play,
      ),
      BreathingRowState.later => (
        null,
        colors.rule,
        colors.ink2,
        SolarIconsBold.play,
      ),
    };
    return Semantics(
      button: true,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: onPressed,
          behavior: HitTestBehavior.opaque,
          child: SizedBox.square(
            dimension: 44,
            child: Center(
              child: Container(
                width: diameter,
                height: diameter,
                decoration: BoxDecoration(
                  color: fill,
                  shape: BoxShape.circle,
                  border: border == null ? null : Border.all(color: border),
                ),
                child: Icon(icon, size: 18, color: glyph),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
