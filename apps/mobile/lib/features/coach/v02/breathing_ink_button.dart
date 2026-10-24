/// The ink-filled controls of the breathing screens: the plan's "Accept all"
/// and the player's pause circle. Ink ground, page-coloured glyph.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/shapes.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_ladder.dart';

/// A full-width ink button.
class InkButton extends StatelessWidget {
  /// A button reading [label]. A null [onPressed] draws it disabled.
  const InkButton({required this.label, required this.onPressed, super.key});

  /// The words on it.
  final String label;

  /// What it does.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.ink,
          foregroundColor: colors.bg,
          disabledBackgroundColor: colors.surface2,
          disabledForegroundColor: colors.ink2,
          elevation: 0,
          minimumSize: const Size(0, 48),
          textStyle: TypeLadder.bodyStrong,
          shape: hSquircle(16),
        ),
        child: Text(label),
      ),
    );
  }
}

/// A round ink control with one glyph, 44 px or larger.
class InkCircleButton extends StatelessWidget {
  /// A circle of [size] showing [icon]; [label] is what a screen reader says.
  const InkCircleButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.size = 56,
    super.key,
  });

  /// The glyph.
  final IconData icon;

  /// The spoken name.
  final String label;

  /// What it does.
  final VoidCallback onPressed;

  /// The diameter.
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: onPressed,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: colors.ink,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: size * 0.4, color: colors.bg),
          ),
        ),
      ),
    );
  }
}
