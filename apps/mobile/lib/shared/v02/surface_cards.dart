/// `.card`, `.card.flush` and `.divider` — the containers the settings screens
/// are built out of.
///
/// The owner's brief replaced the prototype's frame: a card is the surface
/// colour with NO border and NO shadow, radius 20 ([Radii.card]), padding 20.
///
/// ```css
/// .card         { background: var(--surface); color: var(--ink);
///                 border-radius: 20px; padding: 20px; }
/// .card.flush   { padding: 0; overflow: clip; }
/// .card .divider{ margin-inline: -20px; }
/// .divider      { border: 0; height: 1px; background: var(--line);
///                 margin-block: 16px; }
/// .form-note    { font-size: 10px; margin-block: 16px; }
/// ```
///
/// **`.card` is not `Panel`.** They are two containers in the prototype with two
/// paddings (20 against a compact 16), and `Panel` additionally carries a
/// caveat scope, a tone declaration and a head. A settings card holds rows and prose, has no
/// number in it and therefore has nothing to disclose; borrowing the instrument
/// container for it would put a disclosure carrier around a list of links.
///
/// The radius is shared, and shared deliberately: every card and panel takes
/// [Radii.card], so one corner runs through the whole product.
///
/// [FlushCard] draws the hairline BETWEEN its children rather than asking each
/// child to draw its own top border. `.list-row + .list-row` is a sibling
/// selector: the rule belongs to the gap, not to the row, and a row that drew it
/// would draw one too many the moment it was used on its own.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/shapes.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_scale_forms.dart';

/// `.card` — a padded surface, no edge.
class PlainCard extends StatelessWidget {
  /// Wraps [child] in the card frame.
  const PlainCard({required this.child, this.inset, super.key});

  /// `padding: 20px` — `--space-xl`.
  static const double padding = 20;

  /// The brief's card radius.
  static const double radius = Radii.card;

  /// Overrides the card's inset. Null takes [padding].
  ///
  /// 20 all round is sized for a card whose content is a reading. A row in a
  /// list is not, and a list of them at 20 is mostly inset.
  final double? inset;

  /// The card's contents.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      clipBehavior: Clip.antiAlias,
      padding: EdgeInsets.all(inset ?? padding),
      decoration: ShapeDecoration(
        color: colors.surface,
        shape: hSquircle(radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[child],
      ),
    );
  }
}

/// `.card.flush` — the same frame with no padding, holding divided rows.
class FlushCard extends StatelessWidget {
  /// Builds the card. An empty [children] draws **nothing** — a bordered box
  /// with no rows in it is a control surface that controls nothing.
  const FlushCard({required this.children, super.key});

  /// The rows, in order. Hairlines are drawn between them, never above the
  /// first or below the last.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }
    final colors = context.colors;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        color: colors.surface,
        shape: hSquircle(PlainCard.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var i = 0; i < children.length; i++) ...<Widget>[
            if (i > 0)
              SizedBox(
                height: hairline,
                child: ColoredBox(color: colors.line),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// `.divider` — a full-bleed hairline inside a [PlainCard].
///
/// `margin-inline: -20px` in the CSS: the rule reaches the card's edges rather
/// than stopping at its padding, which is what makes it read as a division of
/// the card instead of a line drawn on its contents.
///
/// **Flutter has no negative padding** — `Padding` asserts its insets are
/// non-negative — so the outdent is an `OverflowBox` widened by exactly
/// `2 × PlainCard.padding` and centred. [PlainCard] clips, so the surplus stops
/// at the card's own rounded edge rather than painting over the page. That is
/// the substitution: the CSS declares a negative margin, this declares the
/// rendered result.
class CardDivider extends StatelessWidget {
  /// Builds the rule.
  const CardDivider({super.key});

  /// `.divider { margin-block: 16px }`.
  static const double margin = 16;

  /// The same rule under the name the Actions surfaces used for it.
  static const double gap = margin;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: margin),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bleed = constraints.maxWidth + PlainCard.padding * 2;
          return SizedBox(
            height: hairline,
            // **`minWidth` as well as `maxWidth`.** `OverflowBox` hands its
            // child LOOSE constraints, and a `ColoredBox` with no child takes
            // the minimum — which is zero, and painted a rule 0 px wide in the
            // middle of the card. Both bounds pin it.
            child: OverflowBox(
              minWidth: bleed,
              maxWidth: bleed,
              child: ColoredBox(color: colors.line),
            ),
          );
        },
      ),
    );
  }
}

/// `.form-note` — the quiet sentence under a form or a screen.
class FormNote extends StatelessWidget {
  /// [centred] matches `.form-note.center`, used on Pairing and Welcome.
  const FormNote(this.text, {this.centred = false, super.key});

  /// `.form-note { margin-block: 16px }`.
  static const double margin = 16;

  /// What it says.
  final String text;

  /// Whether the sentence is centred.
  final bool centred;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: margin),
    child: Text(
      text,
      textAlign: centred ? TextAlign.center : TextAlign.start,
      style: FormType.formNote.copyWith(color: context.colors.ink2),
    ),
  );
}

/// `p.small` — the standing paragraph under a heading, in `--muted`.
class SmallProse extends StatelessWidget {
  /// [centred] matches `.small.center`.
  const SmallProse(this.text, {this.centred = false, super.key});

  /// The sentence.
  final String text;

  /// Whether it is centred.
  final bool centred;

  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: centred ? TextAlign.center : TextAlign.start,
    style: FormType.small.copyWith(color: context.colors.ink2),
  );
}
