/// The v02 controls that CHOOSE: `.check-action`, `.prompt-button`, `.segment`.
///
/// Split out of `controls.dart` at the 400-line gate (Standards §1), and the
/// seam is a real one: that file holds the controls that DO something — a
/// button, a link, an icon button — and this one holds the three that record or
/// select. Both halves read the tone cascade and neither takes a `Color`.
///
/// ```css
/// .check-action      { display:flex; gap:12px; width:100%; padding-block:16px;
///                      text-align:left }
/// .check-action .checkbox { width:24px; height:24px; border:1px solid
///                      var(--rule); border-radius:8px; color:var(--accent) }
/// .check-action[aria-pressed='true'] .checkbox
///                    { background:var(--accent-soft); border-color:var(--accent) }
/// .prompt-button     { display:flex; justify-content:space-between;
///                      width:100%; padding:16px; margin-top:10px;
///                      border:1px solid var(--line); border-radius:14px;
///                      background:var(--surface); font-size:11px }
/// .segment           { display:flex; gap:4px; background:var(--surface-soft);
///                      padding:4px; border-radius:12px }
/// .segment button    { flex:1; min-height:36px; border-radius:9px;
///                      font:700 12px }
/// ```
///
/// The accent inside a toned container **is** the family: `richer.css` gives
/// `.focus-card[data-tone] .text-button { color: var(--family) }`, and the check
/// action lives inside exactly such a card. So it reads the cascade rather than
/// taking a colour, and moved into a differently-toned card it follows.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/shapes.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/core/theme/type_scale.dart';
import 'package:solar_icons/solar_icons.dart';

/// `.check-action` — the box, what taking it on says, and what it does not say.
///
/// The prototype's own copy is the reason this is its own control:
/// *"An intention, not a completed action."* Adopting records intent, and the
/// second line is not decoration on the first.
class CheckAction extends StatelessWidget {
  /// [pressed] is `aria-pressed`.
  const CheckAction({
    required this.pressed,
    required this.title,
    this.note,
    required this.onPressed,
    super.key,
  });

  /// `padding-block: 16px`.
  static const double verticalPadding = 16;

  /// `gap: 12px`.
  static const double gap = 12;

  /// `.checkbox { width: 24px; height: 24px }`.
  static const double boxSize = 24;

  /// `.checkbox { border-radius: 8px }`.
  static const double boxRadius = 8;

  /// `.check-action small { margin-top: 3px }`.
  static const double noteGap = 3;

  /// Whether the intention is recorded.
  final bool pressed;

  /// The `strong`.
  final String title;

  /// The `small` under it.
  /// The line under [title]. **Nullable, and usually null now.**
  ///
  /// It carried `One manageable change to start with.` on every suggestion the
  /// app has ever drawn — the same sentence under every card, costing a line
  /// and its gap each time. A subtitle that cannot differ between two cards is
  /// not telling the reader about either of them.
  final String? note;

  /// Toggles it. Null while a write is in flight.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final family = context.family;
    return Semantics(
      button: true,
      toggled: pressed,
      label: note == null ? title : '$title. $note',
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: verticalPadding),
            child: Row(
              children: <Widget>[
                Container(
                  width: boxSize,
                  height: boxSize,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: pressed ? context.familySoft : null,
                    border: Border.all(
                      color: pressed ? family : colors.rule,
                      width: hairline,
                    ),
                    borderRadius: BorderRadius.circular(boxRadius),
                  ),
                  child: Icon(
                    pressed ? Icons.check : Icons.add,
                    size: 16,
                    color: family,
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
                        style: TypeScale.rowTitle.copyWith(color: colors.ink),
                      ),
                      if (note case final String under) ...<Widget>[
                        const SizedBox(height: noteGap),
                        Text(
                          under,
                          style: TypeScale.tinyLabel.copyWith(
                            color: colors.ink2,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `.prompt-button` — one of the coach's opening questions.
class PromptButton extends StatelessWidget {
  /// [prompt] is both the label and what is asked.
  const PromptButton({
    required this.prompt,
    required this.onPressed,
    super.key,
  });

  /// `padding: 16px`.
  static const double padding = 16;

  /// `border-radius: 14px`.
  static const double radius = 14;

  /// `margin-top: 10px`.
  static const double topGap = 10;

  /// `.prompt-button .icon { width: 16px }`.
  static const double iconSize = 16;

  /// The question.
  final String prompt;

  /// Asks it.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: topGap),
      child: Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(padding),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    prompt,
                    style: TypeScale.tinyLabel.copyWith(color: colors.ink),
                  ),
                ),
                Icon(
                  SolarIconsOutline.arrowRight,
                  size: iconSize,
                  color: colors.ink,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `.segment` — one choice out of a small set, on the recessed ground.
///
/// ```css
/// .segment        { display:flex; gap:4px; background:var(--surface-soft);
///                   padding:4px; border-radius:12px }
/// .segment button { flex:1; min-height:36px; border-radius:9px;
///                   font:700 12px }
/// .segment button[aria-pressed='true'] { background:var(--surface);
///                                        color:var(--ink) }
/// ```
class Segment<T> extends StatelessWidget {
  /// [options] are drawn in order; [selected] is the pressed one.
  const Segment({
    required this.options,
    required this.selected,
    required this.onSelect,
    super.key,
  });

  /// `padding: var(--space-xs)`.
  static const double padding = 4;

  /// `gap: var(--space-xs)`.
  static const double gap = 4;

  /// `border-radius: 12px`.
  static const double radius = 12;

  /// `.segment button { min-height: 36px; border-radius: 9px }`.
  static const double optionHeight = 36;

  /// The same.
  static const double optionRadius = 9;

  /// Value and label, in order.
  final List<(T, String)> options;

  /// Which one is pressed.
  final T selected;

  /// Chooses one.
  final ValueChanged<T> onSelect;

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
        children: <Widget>[
          for (final (value, label) in options) ...<Widget>[
            if (value != options.first.$1) const SizedBox(width: gap),
            Expanded(
              child: Semantics(
                button: true,
                selected: value == selected,
                label: label,
                child: ExcludeSemantics(
                  child: Material(
                    color: value == selected ? colors.surface : colors.surface2,
                    borderRadius: BorderRadius.circular(optionRadius),
                    child: InkWell(
                      onTap: () => onSelect(value),
                      borderRadius: BorderRadius.circular(optionRadius),
                      child: SizedBox(
                        height: optionHeight,
                        child: Center(
                          child: Text(
                            label,
                            style: TypeScale.textLink.copyWith(
                              color: value == selected
                                  ? colors.ink
                                  : colors.ink2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
