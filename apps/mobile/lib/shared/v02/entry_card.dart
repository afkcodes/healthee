/// `.relationship-card` — the way out of a screen, on its family's soft ground.
///
/// ```css
/// .relationship-grid { display:grid; grid-template-columns:repeat(2,1fr);
///                      gap:10px; }
/// .relationship-card { padding:18px; border-radius:20px;
///                      background:var(--family-soft); color:var(--ink);
///                      border:1px solid
///                        color-mix(in oklch,var(--family) 25%,var(--line)); }
/// .relationship-card .icon  { color:var(--family); margin-bottom:12px; }
/// /* The brief overrides it: surface ground, NO border, padding 20, radius 20,
///    icon in ink2. The family border and glyph tint are gone. */
/// .relationship-card h3     { font-size:15px; }
/// .relationship-card p      { font-size:11px; margin-top:8px; }
/// .relationship-card .text-button { color:var(--family); }
/// ```
///
/// A card with no [onOpen] draws **no action line at all** rather than a dead
/// one. An entry point that leads nowhere is worse than an absent entry point:
/// it spends a tap to teach the reader that the screen lies about what it can
/// do.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/shapes.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/core/theme/type_scale.dart';
import 'package:solar_icons/solar_icons.dart';

/// One way out of the screen: an icon, a name, a sentence and an action.
class EntryCard extends StatelessWidget {
  /// Builds the card. [tone] declares its family; null inherits.
  const EntryCard({
    required this.title,
    required this.icon,
    this.body,
    this.actionLabel,
    this.onOpen,
    this.tone,
    super.key,
  });

  /// The brief's card padding.
  static const double padding = Insets.card;

  /// `border-radius: 20px`.
  static const double radius = 20;

  /// `.relationship-card .icon { margin-bottom: 12px }`.
  static const double iconGap = 12;

  /// The prototype's `.icon` default width.
  static const double iconSize = 22;

  /// The disclosure mark, at the size `PanelHead` draws its own.
  static const double chevronSize = 14;

  /// `p { margin-top: 8px }`.
  static const double bodyGap = 8;

  /// What is on the other side of the tap.
  final String title;

  /// Drawn above it, in the family colour.
  final IconData icon;

  /// The sentence under the title.
  final String? body;

  /// The action's words, for a screen reader only.
  ///
  /// **It is no longer printed.** The card has always been one tap target, and
  /// it drew `Open the coach` under a title reading `Ask your coach` — the same
  /// instruction twice, on a row of its own, on a half-width card. The chevron
  /// beside the icon says the card opens; this says where, to anyone who cannot
  /// see it.
  final String? actionLabel;

  /// What opening it does.
  final VoidCallback? onOpen;

  /// The family for this card. Null inherits the enclosing scope.
  final Tone? tone;

  @override
  Widget build(BuildContext context) {
    final tone = this.tone;
    return tone == null
        ? _body(context)
        : ToneScope(
            tone: tone,
            child: Builder(builder: _body),
          );
  }

  Widget _body(BuildContext context) {
    final colors = context.colors;
    final label = actionLabel;
    final open = onOpen;
    final card = Container(
      padding: const EdgeInsets.all(padding),
      decoration: ShapeDecoration(
        // **The app's surface, not the family's.** These two carried a
        // full-bleed `familySoft` ground — the largest blocks of colour on
        // Today, on its two least important cards, sitting under a screen of
        // neutral ones. It carries no border either.
        color: colors.surface,
        shape: hSquircle(radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // The glyph's row was an icon and a lot of empty width. The chevron
          // takes the far end of it, so saying the card opens costs no height —
          // the same mark `PanelHead` draws, for the same reason.
          Row(
            children: <Widget>[
              Icon(icon, size: iconSize, color: colors.ink2),
              const Spacer(),
              if (open != null)
                Icon(
                  SolarIconsOutline.altArrowRight,
                  size: chevronSize,
                  color: colors.ink2,
                ),
            ],
          ),
          const SizedBox(height: iconGap),
          Text(title, style: TypeScale.entryTitle.copyWith(color: colors.ink)),
          if (body case final String sentence) ...<Widget>[
            const SizedBox(height: bodyGap),
            Text(
              sentence,
              style: TypeScale.entryBody.copyWith(color: colors.ink2),
            ),
          ],
        ],
      ),
    );
    return open == null
        ? card
        : Semantics(
            button: true,
            label: label == null ? title : '$title. $label',
            child: GestureDetector(
              onTap: open,
              behavior: HitTestBehavior.opaque,
              child: card,
            ),
          );
  }
}

/// `.relationship-grid` — two [EntryCard]s across.
class EntryGrid extends StatelessWidget {
  /// Builds the pair.
  const EntryGrid({required this.left, required this.right, super.key});

  /// `.relationship-grid { gap: 10px }`.
  static const double gap = 10;

  /// The left card.
  final Widget left;

  /// The right card.
  final Widget right;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(child: left),
        const SizedBox(width: gap),
        Expanded(child: right),
      ],
    ),
  );
}
