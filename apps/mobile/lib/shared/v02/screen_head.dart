/// `.page-header`, in its two shapes — the tab's and the pushed screen's.
///
/// ```css
/// .page-header        { display:flex; align-items:center;
///                       justify-content:space-between; gap:8px;
///                       margin-bottom:16px }
/// .page-header .date  { font-size:11px; color:var(--muted); margin-bottom:5px }
/// .page-header h1     { font-size:27px; letter-spacing:-1px }
/// .page-header.detail { justify-content:start; margin-left:-8px }
/// .page-header.detail h1 { font-size:23px; letter-spacing:-.8px }
/// ```
///
/// `components.js::H.header(title, subtitle, detail)` builds both: the detail
/// form puts a back control first and drops the avatar, and the non-detail form
/// keeps the avatar and no back control. Which one a screen uses is decided by
/// whether it is a tab, not by taste.
///
/// **The eyebrow is a `String?` and null draws nothing.** A header that reserved
/// its 5 px gap for a line nothing wrote would move the title down by a space
/// with no content in it, which is the empty-section rule applied to type.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/core/theme/type_scale.dart';
import 'package:solar_icons/solar_icons.dart';

/// `.page-header` — a tab's head: eyebrow, title, and whatever sits at the end.
class ScreenHead extends StatelessWidget {
  /// [trailing] is the avatar on the screens that have one.
  const ScreenHead({
    required this.title,
    this.eyebrow,
    this.trailing,
    super.key,
  });

  /// `margin-bottom: var(--space-xl)` — `styles.css` 20, `richer.css` 16.
  static const double bottomGap = 16;

  /// `.page-header .date { margin-bottom: 5px }`.
  static const double eyebrowGap = 5;

  /// `gap: var(--space-sm)`.
  static const double gap = 8;

  /// The screen's name. May be two lines; the prototype's Actions h1 is.
  final String title;

  /// The line above it.
  final String? eyebrow;

  /// The control at the end of the row.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: bottomGap),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (eyebrow case final String line) ...<Widget>[
                  Text(
                    line,
                    style: TypeScale.pageDate.copyWith(color: colors.ink2),
                  ),
                  const SizedBox(height: eyebrowGap),
                ],
                Text(
                  title,
                  style: TypeScale.pageTitle.copyWith(color: colors.ink),
                ),
              ],
            ),
          ),
          if (trailing case final Widget end) ...<Widget>[
            const SizedBox(width: gap),
            end,
          ],
        ],
      ),
    );
  }
}

/// `.page-header.detail` — a back control, the eyebrow, and a 23 px title.
class DetailHead extends StatelessWidget {
  /// [onBack] of null draws no control; every pushed screen supplies one.
  const DetailHead({
    required this.title,
    this.eyebrow,
    this.onBack,
    this.actions = const <Widget>[],
    this.large = false,
    super.key,
  });

  /// `.page-header { margin-bottom: 16px }`.
  static const double bottomGap = ScreenHead.bottomGap;

  /// `.page-header.detail { margin-left: -8px }` — the icon button's own
  /// padding, pulled back so the glyph lines up with the title's left edge.
  static const double backSize = 44;

  /// `.page-header .date { margin-bottom: 5px }`.
  static const double eyebrowGap = ScreenHead.eyebrowGap;

  /// The screen's name.
  final String title;

  /// The line above it — a date, or what kind of thing this is.
  final String? eyebrow;

  /// Goes back.
  final VoidCallback? onBack;

  /// Controls on the SCREEN itself, at the trailing edge — a new conversation,
  /// its history. Empty by default, so every screen that has none renders
  /// exactly as it did.
  ///
  /// They belong to the shared head rather than to each screen's own row,
  /// because that is what went wrong: `CoachPage` hand-rolled a raw `IconButton`
  /// beside a `Column` and got a 48 pt Material target with its own padding next
  /// to this 44 pt outdented one, so the coach's head sat a few pixels off from
  /// every other screen in the app. Use [HeaderAction], which is built to the
  /// back control's geometry.
  final List<Widget> actions;

  /// Sets the title at the Title1 step instead of the detail screens' Title2,
  /// for a screen that is a directory and opens on its name.
  final bool large;

  /// `.icon { width: 22px }`.
  static const double iconSize = 22;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: bottomGap),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          if (onBack case final VoidCallback back)
            // `margin-left: -8px` is the row's, so it is spent here rather than
            // on the whole header: a negative inset on the Column would move the
            // title too, and the prototype's title does not move.
            Transform.translate(
              offset: const Offset(-8, 0),
              child: SizedBox(
                width: backSize,
                height: backSize,
                // A bare hit area and a glyph, NOT an `IconButton`: Material
                // gives that one its own 48 pt constraints and internal padding
                // inside this 44 pt box, so the arrow rendered a few pixels off
                // its own square and off the title's baseline. That misalignment
                // is what "the header looks weird" was.
                child: _Glyph(
                  icon: SolarIconsOutline.arrowLeft,
                  onPressed: back,
                  color: colors.ink,
                  tooltip: 'Go back',
                ),
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (eyebrow case final String line) ...<Widget>[
                  Text(
                    line,
                    style: TypeScale.pageDate.copyWith(color: colors.ink2),
                  ),
                  const SizedBox(height: eyebrowGap),
                ],
                Text(
                  title,
                  style: (large ? TypeLadder.title1 : TypeScale.detailTitle)
                      .copyWith(color: colors.ink),
                ),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// A 44 pt hit area around a 22 pt glyph — the head's one control geometry.
///
/// Both the back arrow and every [HeaderAction] are built from this, so a head
/// with actions is the same height as one without and its two edges balance.
class _Glyph extends StatelessWidget {
  const _Glyph({
    required this.icon,
    required this.onPressed,
    required this.color,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final Color color;
  final String tooltip;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: tooltip,
    child: Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onPressed,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: DetailHead.backSize,
          height: DetailHead.backSize,
          child: Icon(icon, size: DetailHead.iconSize, color: color),
        ),
      ),
    ),
  );
}

/// A control on the screen itself, at the trailing edge of a [DetailHead].
///
/// Built to the back control's geometry so the head stays symmetrical. Null
/// [onPressed] renders NOTHING rather than a greyed control: a screen offering an
/// action it cannot perform is worse than one that does not offer it.
class HeaderAction extends StatelessWidget {
  /// [tooltip] is the accessible name as well as the tooltip.
  const HeaderAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    super.key,
  });

  /// The glyph.
  final IconData icon;

  /// What it does, in words.
  final String tooltip;

  /// Does it. Null draws nothing.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final press = onPressed;
    if (press == null) {
      return const SizedBox.shrink();
    }
    return _Glyph(
      icon: icon,
      onPressed: press,
      color: context.colors.ink2,
      tooltip: tooltip,
    );
  }
}
