/// `.list-row` — one tappable line inside a [FlushCard]: tile, name, sentence,
/// chevron.
///
/// ```css
/// .list-row              { display: flex; align-items: center; gap: 12px;
///                          width: 100%; min-height: 72px; padding: 16px 20px;
///                          text-align: left; }
/// .list-row + .list-row  { border-top: 1px solid var(--line); }
/// .list-row strong       { display: block; font-size: 13px; font-weight: 700; }
/// .list-row small        { display: block; color: var(--muted);
///                          font-size: 11px; white-space: normal; }
/// .list-row > .icon:last-child { width: 16px; color: var(--subtle); }
/// ```
///
/// ## The title is `Expanded`, the chevron is not, and that pairing is the trap
///
/// `.grow` is `flex: 1; min-width: 0` on the middle column while the tile and the
/// chevron are `flex: 0 0 auto`. Written as a `Row` of three children the middle
/// one must be `Expanded` — **not `Flexible`**. A loose `Flexible` beside another
/// flexible child splits the free space instead of taking the remainder, which is
/// how `chapter.dart` ellipsized every heading on the installed build. Here the
/// two outer children are fixed-size, so `Expanded` is unambiguous and the
/// subtitle wraps rather than truncating: `white-space: normal` is set on
/// `.list-row small` explicitly, against the row's own `nowrap` inheritance.
///
/// ## The row declares a tone and passes no colour
///
/// `H.row(...)` writes `data-tone` onto the anchor, and `[data-tone] .icon-tile`
/// then resolves `--family`/`--family-soft`. So the row wraps itself in a
/// [ToneScope] and [IconTile] reads the cascade — the same contract every panel
/// uses. Every settings row in the prototype resolves to `fitness`, which is the
/// `:root` default, so [tone] is normally left null.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/core/theme/type_scale_forms.dart';
import 'package:healthee/shared/v02/icon_tile.dart';
import 'package:solar_icons/solar_icons.dart';

/// A settings row: an icon tile, a name, a sentence, and a chevron.
class ListRow extends StatelessWidget {
  /// Builds a row. [onTap] of null draws it **without** a chevron — a row that
  /// leads nowhere must not offer the glyph that says it does.
  const ListRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.onTap,
    this.tone,
    this.trailing,
    super.key,
  });

  /// `min-height: 72px` in the CSS, **60 here**.
  ///
  /// The prototype's row carries a sentence that wraps to two lines at phone
  /// width. These rows carry a short sentence and a value, and nine of them at
  /// 72 ran a whole section past the fold — so the row is sized to its content
  /// rather than to a floor set for wrapping prose.
  static const double minHeight = 60;

  /// `padding: 16px 20px`, tightened with [minHeight].
  static const EdgeInsets padding = EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 11,
  );

  /// `.list-row { gap: 12px }`.
  static const double gap = 12;

  /// The most the value may take before it ellipses.
  ///
  /// **Not a `Flexible`.** Two flex children in one `Row` split the free space
  /// between them, and a loose `Flexible` then draws its child at its own width
  /// inside a slot half the row wide — leaving slack that pulled the chevron
  /// off the margin on exactly the rows that carried a value. A cap shrink-wraps
  /// instead, so every chevron on the screen lands at the same x.
  static const double valueWidth = 132;

  /// `.list-row > .icon:last-child { width: 16px }`.
  static const double chevronSize = 16;

  /// The gap between the name and the sentence under it. The CSS has none —
  /// the two are block children of one `.grow` — so this is line-box spacing
  /// only, and it is zero.
  static const double titleGap = 0;

  /// The glyph in the tile.
  final IconData icon;

  /// The row's name.
  final String title;

  /// What the row leads to. **Null draws nothing** — not an empty line.
  final String? subtitle;

  /// Opens it. Null draws no chevron.
  final VoidCallback? onTap;

  /// The family for this row's tile. Null makes it CHROME, in the owner's
  /// chosen accent — see `IconTile.chrome`. Pass a tone for a row that is
  /// about a reading rather than about the app.
  final Tone? tone;

  /// Replaces the chevron — a badge, a switch's value. Null uses the chevron.
  final Widget? trailing;

  /// What this row is currently SET TO, drawn opposite [subtitle].
  ///
  /// **A settings row that describes itself makes you open it to find out.**
  /// `Appearance · Light, dark or follow your device` names the choices and not
  /// the choice; `Reminders · A gentle nudge, on your terms` is a sentence about
  /// the feature. Nine rows of that is a menu. Nine rows carrying `Dark ·
  /// Indigo`, `Off`, `On · Wi-Fi only` is a status board, and the screen answers
  /// most questions without being opened.
  ///
  /// **Null while a value is still loading, and null is drawn as nothing.** A
  /// row must not print a default as though it were the setting — that is the
  /// stale-as-current lie at the smallest possible scale.
  final String? value;

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
    final subtitle = this.subtitle;
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: minHeight),
      child: Padding(
        padding: padding,
        child: Row(
          children: <Widget>[
            // Chrome unless the row declares a reading's family.
            if (tone == null)
              IconTile.chrome(icon, boxSize: IconTile.compactSize)
            else
              IconTile(icon, boxSize: IconTile.compactSize),
            const SizedBox(width: gap),
            // Expanded, never Flexible — see the library docstring.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    title,
                    // One line. The value opposite takes width, and a title
                    // that wrapped under it made two rows out of one.
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FormType.rowTitle.copyWith(color: colors.ink),
                  ),
                  if (subtitle != null) ...<Widget>[
                    const SizedBox(height: titleGap),
                    Text(
                      subtitle,
                      // One line, so a row is one row. The sentence says what
                      // the door is for; it does not have to fit in full.
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FormType.rowSubtitle.copyWith(color: colors.ink2),
                    ),
                  ],
                ],
              ),
            ),
            if (value case final String setting) ...<Widget>[
              const SizedBox(width: gap),
              // The accent, because this is the one thing on the row that is a
              // live reading rather than a description of the door. Muted, it
              // was indistinguishable from the sentence beside it.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: valueWidth),
                child: Text(
                  setting,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FormType.rowSubtitle.copyWith(
                    color: colors.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            if (trailing case final Widget end) ...<Widget>[
              const SizedBox(width: gap),
              end,
            ] else if (onTap != null) ...<Widget>[
              const SizedBox(width: gap),
              Icon(
                SolarIconsOutline.altArrowRight,
                size: chevronSize,
                color: colors.ink2,
              ),
            ],
          ],
        ),
      ),
    );
    if (onTap == null) {
      return row;
    }
    return Semantics(
      button: true,
      label: subtitle == null ? title : '$title · $subtitle',
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(onTap: onTap, child: row),
      ),
    );
  }
}
