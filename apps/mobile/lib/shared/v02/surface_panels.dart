/// The v02 surfaces Actions, Journal and Coach are built out of.
///
/// `Panel` is the instrument container — a head, a figure, a chart. These are the
/// other four containers the prototype uses, transcribed from `styles.css` with
/// `richer.css`'s overrides applied on top:
///
/// **The owner's brief dropped every card and notice border** (no border, no
/// shadow, radius 20, padding 20); the CSS below is the prototype's, kept for
/// the other properties.
///
/// ```css
/// .card         { background:var(--surface); border:1px solid var(--line);
///                 border-radius:20px; padding:20px }
/// .card.flush   { padding:0; overflow:clip }
/// .notice       { display:flex; gap:10px; padding:16px; margin-bottom:16px;
///                 border:1px solid var(--line); border-radius:16px;
///                 background:var(--surface-soft) }
/// .badge        { padding:4px 8px; border-radius:7px; font:700 10px;
///                 background:var(--surface-soft); color:var(--muted) }
/// .badge.indigo { background:var(--accent-soft); color:var(--accent) }
/// .focus-card   { padding:16px 20px; border-radius:20px;
///                 background:var(--accent-soft); color:var(--ink) }
/// .sleep-hero   { padding-block:8px 24px }
/// .sleep-hero .hero-number { font-size:64px; font-weight:600;
///                            letter-spacing:-4px; margin-block:20px 8px }
///
/// /* richer.css */
/// .focus-card[data-tone] { background:var(--family-soft) }
/// .focus-card[data-tone] .focus-title, .icon, .text-button { color:var(--family) }
/// ```
///
/// **Nothing here takes a `Color`.** `.focus-card[data-tone]` is the whole reason:
/// one attribute on the container moves the ground, the eyebrow, the glyph and
/// the link together, and a parameter would let three of the four be handed a
/// hue that disagrees with the fourth. See `core/theme/tone_scope.dart`.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/shapes.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/core/theme/type_scale.dart';
import 'package:solar_icons/solar_icons.dart';

/// `HeroReading` moved to `hero_reading.dart` at the 400-line gate (Standards
/// section 1). Re-exported so every call site and its tests are unchanged.
export 'package:healthee/shared/v02/hero_reading.dart';

/// `.card` — the plain surface container.
class SurfaceCard extends StatelessWidget {
  /// Builds a card around [child]. [flush] is `.card.flush`: no padding, clipped,
  /// for a card whose contents are full-bleed rows.
  const SurfaceCard({
    required this.child,
    this.flush = false,
    this.tone,
    super.key,
  });

  /// `padding: var(--space-xl)`.
  static const double padding = Insets.card;

  /// The brief's card radius, [Radii.card].
  static const double radius = Radii.card;

  /// What is inside.
  final Widget child;

  /// `.card.flush`.
  final bool flush;

  /// The family the contents resolve. Null inherits.
  final Tone? tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final Widget card = Container(
      clipBehavior: Clip.antiAlias,
      padding: flush ? EdgeInsets.zero : const EdgeInsets.all(padding),
      decoration: ShapeDecoration(
        color: colors.surface,
        shape: hSquircle(radius),
      ),
      child: child,
    );
    final tone = this.tone;
    return tone == null ? card : ToneScope(tone: tone, child: card);
  }
}

/// `.badge` — a small stamp naming a state.
///
/// Two variants, and no more than the surfaces here use: the neutral one and
/// `.indigo`, which in v02's palette is the accent. `.good` and `.warm` exist in
/// the prototype's CSS and are not built, because a judgement colour on a screen
/// that makes no judgement would be a claim nothing sent.
class StatusBadge extends StatelessWidget {
  /// [accented] draws `.badge.indigo`.
  const StatusBadge(this.label, {this.accented = false, super.key});

  /// `padding: 4px 8px`.
  static const EdgeInsets padding = EdgeInsets.symmetric(
    horizontal: 8,
    vertical: 4,
  );

  /// `border-radius: 7px`.
  static const double radius = 7;

  /// The word.
  final String label;

  /// `.badge.indigo`.
  final bool accented;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: padding,
      decoration: ShapeDecoration(
        color: accented ? colors.accentSoft : colors.surface2,
        shape: hSquircle(radius),
      ),
      child: Text(
        label,
        style: TypeScale.badge.copyWith(
          color: accented ? colors.accent : colors.ink2,
        ),
      ),
    );
  }
}

/// `.notice` — an icon, a title and a sentence, on the recessed ground.
class Notice extends StatelessWidget {
  /// [title] is the `strong`; [body] the `p` under it.
  const Notice({required this.title, required this.body, super.key});

  /// `padding: 16px`.
  static const double padding = 16;

  /// `border-radius: 16px`.
  static const double radius = 16;

  /// `gap: 10px`.
  static const double gap = 10;

  /// `.notice > .icon { width: 18px; margin-top: 2px }`.
  static const double iconSize = 16;

  /// `.notice p { margin-top: 4px }`.
  static const double bodyGap = 4;

  /// The heading.
  final String title;

  /// The sentence.
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(padding),
      decoration: ShapeDecoration(
        color: colors.surface2,
        shape: hSquircle(radius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              SolarIconsOutline.infoCircle,
              size: iconSize,
              color: colors.ink2,
            ),
          ),
          const SizedBox(width: gap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  style: TypeScale.noticeTitle.copyWith(color: colors.ink),
                ),
                const SizedBox(height: bodyGap),
                Text(
                  body,
                  style: TypeScale.noticeBody.copyWith(color: colors.ink2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// `.focus-card` — the suggestion block, on its family's soft ground.
///
/// The eyebrow, the trailing glyph and anything the caller puts in [footer] all
/// resolve `--family` from this card's own [tone]; see the library docstring.
class FocusCard extends StatelessWidget {
  /// [eyebrow] is `.focus-title`, [title] the `h3`, [body] the `p`.
  const FocusCard({
    this.eyebrow,
    required this.title,
    this.icon,
    this.action,
    this.body,
    this.footer,
    this.tone,
    super.key,
  });

  /// `padding: 16px 20px`.
  static const EdgeInsets padding = EdgeInsets.symmetric(
    horizontal: 20,
    vertical: 16,
  );

  /// `border-radius: 20px`.
  static const double radius = 20;

  /// `.focus-card h3 { margin-top: 8px }`.
  static const double titleGap = 8;

  /// `.focus-card p { margin-top: 5px }`.
  static const double bodyGap = 5;

  /// `.focus-title` — what kind of thing this is.
  ///
  /// Nullable: the prototype's finding-detail card carries no eyebrow, because
  /// the section head above it (`A useful next step`) already says what the card
  /// is. Drawing an empty one there would spend the eyebrow's line box and its
  /// gap on nothing.
  final String? eyebrow;

  /// The suggestion itself.
  final Widget title;

  /// The glyph on the eyebrow row, in the family colour.
  final IconData? icon;

  /// A control on the eyebrow row, before [icon].
  ///
  /// **A whole row of card height, reclaimed.** `Why this suggestion ⓘ` used to
  /// sit at the bottom of the footer as a labelled link — a line of its own plus
  /// its gap, on a card that already ran to six blocks. Every other card in the
  /// app puts "what backs this" as a dot on its head; this lets a focus card do
  /// the same, and the eyebrow row was already drawn and half empty.
  final Widget? action;

  /// The sentence under the title.
  final Widget? body;

  /// The check-action and the evidence link, when there are any.
  final Widget? footer;

  /// The family this card resolves.
  final Tone? tone;

  /// `.focus-card .icon { width: 16px }` — `.icon.small`.
  static const double iconSize = 16;

  /// Between the eyebrow's control and the card's glyph.
  static const double actionGap = 10;

  @override
  Widget build(BuildContext context) {
    // A `Builder` under the scope, not a colour read above it: the eyebrow, the
    // glyph and whatever the footer holds must all resolve the tone THIS card
    // declared, from their own context. See the library docstring.
    final Widget body = Builder(builder: _body);
    final tone = this.tone;
    return tone == null ? body : ToneScope(tone: tone, child: body);
  }

  Widget _body(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: padding,
      decoration: ShapeDecoration(
        color: colors.surface,
        shape: hSquircle(radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (eyebrow != null || icon != null) ...<Widget>[
            Row(
              children: <Widget>[
                if (eyebrow case final String label)
                  Expanded(
                    child: Text(
                      label,
                      style: TypeScale.focusEyebrow.copyWith(
                        color: colors.ink2,
                      ),
                    ),
                  )
                else
                  const Spacer(),
                if (action case final Widget control) control,
                if (icon case final IconData glyph) ...<Widget>[
                  if (action != null) const SizedBox(width: actionGap),
                  Icon(glyph, size: iconSize, color: colors.ink2),
                ],
              ],
            ),
            const SizedBox(height: titleGap),
          ],
          DefaultTextStyle(
            style: TypeScale.focusTitle.copyWith(color: colors.ink),
            child: title,
          ),
          if (body case final Widget sentence) ...<Widget>[
            const SizedBox(height: bodyGap),
            DefaultTextStyle(
              style: TypeScale.noticeBody.copyWith(color: colors.ink2),
              child: sentence,
            ),
          ],
          if (footer case final Widget action) action,
        ],
      ),
    );
  }
}

/// `.sleep-hero` — the one large figure a detail screen opens on.
///
/// ```css
/// .sleep-hero { padding-block: 8px 24px }
/// .sleep-hero .hero-number { font-size:64px; font-weight:600;
///                            letter-spacing:-4px; margin-block:20px 8px }
/// .hero-number .duration-unit { font-size:30px; color:var(--muted);
///                               letter-spacing:-1px; margin-inline:2px 8px }
