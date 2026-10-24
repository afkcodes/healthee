/// `.button.full` — the one filled, full-width action a v02 screen may carry.
///
/// ```css
/// .button      { display:inline-flex; justify-content:center;
///                align-items:center; gap:8px; padding:12px 20px;
///                min-height:48px; border-radius:16px;
///                background:var(--accent); color:var(--on-accent);
///                font-weight:700; font-size:13px; }
/// .button.full { width:100%; }
/// ```
///
/// **Accent, not family.** `styles.css` paints `.button` from `--accent` and not
/// from `--family`, so a filled button inside a movement-toned screen is still
/// green — it is the app's one primary action colour rather than the category
/// of the card it happens to sit in. That is why this widget reads
/// `context.colors.accent` and takes no [Tone]: there is nothing here for a tone
/// to resolve, and giving it one would make the same control two colours on two
/// screens.
///
/// The trailing arrow is `H.link(label, route, 'button full section')` — the
/// prototype renders this control through the same helper as a text link, so it
/// keeps the link's arrow.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/shapes.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_scale.dart';
import 'package:solar_icons/solar_icons.dart';

/// A filled, full-width action with a trailing arrow.
class V02FullButton extends StatelessWidget {
  /// Builds the button. A null [onPressed] renders it disabled rather than
  /// absent — the caller decides whether the control belongs on the screen.
  const V02FullButton({required this.label, this.onPressed, super.key});

  /// `.button { min-height: 48px }`.
  static const double minHeight = 48;

  /// `.button { border-radius: 16px }`.
  static const double radius = 16;

  /// `.button { padding: 12px 20px }`.
  static const EdgeInsets padding = EdgeInsets.symmetric(
    horizontal: 20,
    vertical: 12,
  );

  /// `.button { gap: 8px }`.
  static const double gap = 8;

  /// `.icon.small { width: 16px }`.
  static const double iconSize = 16;

  /// What the button says.
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
          backgroundColor: colors.accent,
          foregroundColor: colors.onAccent,
          disabledBackgroundColor: colors.surface2,
          disabledForegroundColor: colors.ink2,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: padding,
          minimumSize: const Size(0, minHeight),
          textStyle: TypeScale.panelTitle,
          shape: hSquircle(radius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Flexible(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: gap),
            const Icon(SolarIconsOutline.arrowRight, size: iconSize),
          ],
        ),
      ),
    );
  }
}
