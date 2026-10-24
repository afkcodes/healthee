/// `.tiny-label` and `.source` — the two smallest lines a v02 screen writes.
///
/// ```css
/// .tiny-label   { font-size: 11px; color: var(--subtle); }
/// .source       { display: flex; align-items: center; gap: var(--space-xs);
///                 font-size: 10px; color: var(--subtle);
///                 margin-top: var(--space-lg); }
/// .source .icon { width: 13px; height: 13px; }
/// ```
///
/// Both are `--subtle`, which is [HealtheeColors.ink2], and **neither takes a
/// colour** — there is nothing here for a caller to tint. `.source` owns its own
/// `margin-top` for the reason `panel_parts.dart` owns `.panel-note`'s: the gap
/// between a card's figures and its provenance is part of the card's rhythm, and
/// a call site writing its own number is a second opinion about it.
///
/// The glyph is the shield `H.source` uses (`components.js`), the same one
/// `DataFooter` closes a screen with — one mark for "where this came from",
/// rather than two that mean the same thing.
///
/// `.source` and `.form-note` are `10px` at the body's own line height, so both
/// resolve [TypeScale.formNote]. That is one style for two rules that render
/// identically, not one style asserting two rules are the same thing — the
/// distinction `stat_block.dart` draws for `.stat` inside and outside a panel,
/// where the measurements genuinely differ and two styles are therefore right.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_scale.dart';
import 'package:solar_icons/solar_icons.dart';

/// `.tiny-label` — a caption over a group, in `--subtle`.
class TinyLabel extends StatelessWidget {
  /// Builds the caption. [text] is drawn verbatim.
  const TinyLabel(this.text, {super.key});

  /// What it says.
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TypeScale.tinyLabel.copyWith(color: context.colors.ink2),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );
}

/// `.source` — a shield, then where the figures above it came from.
class SourceNote extends StatelessWidget {
  /// Builds the line. [text] names the instrument, never a research note: the
  /// sources behind a *claim* go to the ⓘ (`metric_detail.dart`), and this says
  /// which device produced the *measurements*.
  const SourceNote(this.text, {super.key});

  /// `.source { margin-top: var(--space-lg) }`.
  static const double topGap = 16;

  /// `.source .icon { width: 13px }`.
  static const double iconSize = 13;

  /// `.source { gap: var(--space-xs) }`.
  static const double gap = 4;

  /// Where the numbers came from.
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: topGap),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Icon(
            SolarIconsOutline.shieldCheck,
            size: iconSize,
            color: colors.ink2,
          ),
          const SizedBox(width: gap),
          Flexible(
            child: Text(
              text,
              style: TypeScale.formNote.copyWith(color: colors.ink2),
            ),
          ),
        ],
      ),
    );
  }
}
