/// `.notice` and `.badge` — the two ways a screen annotates something.
///
/// ```css
/// .notice        { display:flex; gap:10px; padding:16px; margin-bottom:16px;
///                  border:1px solid var(--line); border-radius:16px;
///                  background:var(--surface-soft); color:var(--ink); }
/// .notice > .icon{ width:18px; margin-top:2px; }
/// .notice strong { font-size:12px; }
/// .notice p      { font-size:11px; margin-top:4px; line-height:1.8; }
/// .notice.error  { background:var(--danger-soft); color:var(--danger);
///                  border:0; }
/// .notice.warm   { background:var(--caution-soft); color:var(--caution);
///                  border:0; }
/// .notice.error p, .notice.warm p { color: inherit; }
///
/// .badge         { display:inline-flex; align-items:center; gap:4px;
///                  padding:4px 8px; border-radius:7px; font-size:10px;
///                  font-weight:700; background:var(--surface-soft);
///                  color:var(--muted); white-space:nowrap; }
/// .badge.good    { background:var(--positive-soft); color:var(--positive); }
/// .badge.warm    { background:var(--caution-soft); color:var(--caution); }
/// .badge.indigo  { background:var(--accent-soft); color:var(--accent); }
/// ```
///
/// ## `.notice.error` is `--danger`, and `--danger` is this product's ONE red
///
/// `tokens.dart` reserves `alert` for the illness flag: *"the only red in the
/// product"*. A sync failure is not a fact about the owner's body, and
/// `signin_failure_card.dart` and `pairing_failure_card.dart` both already
/// refuse to tint a failure for exactly that reason.
///
/// So [NoticeKind.error] exists and is used **only** where the prototype uses
/// it — the offline banner on the data-freshness screen, which is a statement
/// about the network — and every typed sign-in and pairing failure stays
/// untinted on [NoticeKind.plain]. That keeps the prototype's pixels where the
/// prototype puts them without spending the red on a wrong password.
///
/// `.badge.warm` and `.notice.warm` map to `unf`/`unfSoft`, the *unfavourable*
/// pair — `--caution` is amber in both themes and `unf` is the role for a
/// reading that sits worse than normal, which is what a stale stream is.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/shapes.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_scale_forms.dart';
import 'package:solar_icons/solar_icons.dart';

/// Which ground a [HNotice] wears.
enum NoticeKind {
  /// `.notice` — surface-soft with a hairline. The default, and untinted.
  plain,

  /// `.notice.error` — the product's one red. See the library docstring.
  error,

  /// `.notice.warm` — the unfavourable amber.
  warm,
}

/// A banner: a glyph, a headline and a sentence.
class HNotice extends StatelessWidget {
  /// Builds the banner.
  const HNotice({
    required this.title,
    required this.body,
    this.kind = NoticeKind.plain,
    super.key,
  });

  /// `padding: 16px`.
  static const double padding = 16;

  /// `border-radius: 16px`.
  static const double radius = 16;

  /// `.notice { gap: 10px }`.
  static const double gap = 10;

  /// `.notice > .icon { width: 18px; margin-top: 2px }`.
  static const double iconSize = 18;

  /// Its optical nudge onto the first line.
  static const double iconTop = 2;

  /// `.notice p { margin-top: 4px }`.
  static const double bodyGap = 4;

  /// The headline.
  final String title;

  /// The sentence under it.
  final String body;

  /// Which ground.
  final NoticeKind kind;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (Color ground, Color mark, Color prose, Color? edge) = switch (kind) {
      NoticeKind.plain => (colors.surface2, colors.ink, colors.ink2, null),
      // `color: inherit` on the body — one colour for the whole banner.
      NoticeKind.error => (colors.alertSoft, colors.alert, colors.alert, null),
      NoticeKind.warm => (colors.unfSoft, colors.unf, colors.unf, null),
    };
    return Container(
      padding: const EdgeInsets.all(padding),
      decoration: ShapeDecoration(
        color: ground,
        shape: hSquircle(
          radius,
          side: edge == null
              ? BorderSide.none
              : BorderSide(color: edge, width: hairline),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: iconTop),
            child: Icon(
              // `H.notice` picks the cloud for an error and the info dot
              // otherwise — the glyph names the KIND of trouble, not its
              // severity.
              kind == NoticeKind.error
                  ? SolarIconsOutline.cloudCross
                  : SolarIconsOutline.infoCircle,
              size: iconSize,
              color: mark,
            ),
          ),
          const SizedBox(width: gap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(title, style: FormType.noticeTitle.copyWith(color: mark)),
                const SizedBox(height: bodyGap),
                Text(body, style: FormType.noticeBody.copyWith(color: prose)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Which ground a [HBadge] wears.
enum BadgeKind {
  /// `.badge` — surface-soft, muted ink.
  plain,

  /// `.badge.good` — the favourable pair.
  good,

  /// `.badge.warm` — the unfavourable pair.
  warm,

  /// `.badge.indigo` — accent-soft with an accent label. Named for the CSS
  /// class; the accent is green in this build, and the class name is the
  /// prototype's own.
  accent,
}

/// `.badge` — a short stamp beside a value.
class HBadge extends StatelessWidget {
  /// Builds the badge.
  const HBadge(this.label, {this.kind = BadgeKind.plain, super.key});

  /// `padding: 4px 8px`.
  static const EdgeInsets padding = EdgeInsets.symmetric(
    horizontal: 8,
    vertical: 4,
  );

  /// `border-radius: 7px`.
  static const double radius = 7;

  /// The words.
  final String label;

  /// Which ground.
  final BadgeKind kind;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (Color ground, Color mark) = switch (kind) {
      BadgeKind.plain => (colors.surface2, colors.ink2),
      BadgeKind.good => (colors.favSoft, colors.fav),
      BadgeKind.warm => (colors.unfSoft, colors.unf),
      BadgeKind.accent => (colors.accentSoft, colors.accent),
    };
    return Container(
      padding: padding,
      decoration: ShapeDecoration(color: ground, shape: hSquircle(radius)),
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.clip,
        style: FormType.badge.copyWith(color: mark),
      ),
    );
  }
}
