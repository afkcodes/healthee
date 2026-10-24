/// `.toggle-row` and `.switch` — one preference and the control that sets it.
///
/// ```css
/// .toggle-row   { display:flex; align-items:center;
///                 justify-content:space-between; gap:16px; padding:16px 20px; }
/// .toggle-row + .toggle-row { border-top: 1px solid var(--line); }
/// .toggle-row strong { font-size:12px; display:block; }
/// .toggle-row p      { font-size:10px; margin-top:3px; }
/// .switch        { position:relative; width:42px; height:26px;
///                  border-radius:20px; flex:0 0 auto; background:var(--rule);
///                  border:1px solid var(--subtle); }
/// .switch::after { left:3px; top:3px; height:18px; width:18px;
///                  border-radius:50%; background:var(--surface);
///                  transition: transform 180ms var(--ease-out); }
/// .switch[aria-checked='true']        { background:var(--accent);
///                                       border-color:var(--accent); }
/// .switch[aria-checked='true']::after { transform:translateX(16px);
///                                       background:var(--on-accent); }
/// ```
///
/// **This is not a Material `Switch`.** Material's is 52 × 32 with its own thumb
/// travel, elevation and ripple; the prototype's is 42 × 26 with a 18 px knob
/// that moves exactly 16. Wrapping Material's and restyling it cannot reach
/// those numbers — the geometry is baked into `SwitchThemeData`'s painter — so
/// the control is drawn, and the drawing is three boxes.
///
/// The 180 ms `--ease-out` transition is `Curves.easeOutExpo`'s closest
/// available match, `cubic-bezier(.16, 1, .3, 1)`, declared as a [Cubic] rather
/// than approximated by name.
///
/// The whole row is the hit target, not just the switch: 42 × 26 is under any
/// tap-target guidance, and the prototype's row is 72 px tall with the label
/// beside it. Tapping the words toggles the switch, which is what a person does.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/shapes.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_scale_forms.dart';

/// `--ease-out` — `cubic-bezier(.16, 1, .3, 1)`, the prototype's own curve.
const Cubic kEaseOut = Cubic(0.16, 1, 0.3, 1);

/// One switched preference: a name, a sentence, and a switch.
class ToggleRow extends StatelessWidget {
  /// Builds the row. [onChanged] of null draws the switch disabled.
  const ToggleRow({
    required this.title,
    required this.body,
    required this.value,
    required this.onChanged,
    super.key,
  });

  /// `padding: 16px 20px`.
  static const EdgeInsets padding = EdgeInsets.symmetric(
    horizontal: 20,
    vertical: 16,
  );

  /// `.toggle-row { gap: 16px }`.
  static const double gap = 16;

  /// `.toggle-row p { margin-top: 3px }`.
  static const double bodyGap = 3;

  /// What the preference is called.
  final String title;

  /// What turning it on does.
  final String body;

  /// Whether it is on.
  final bool value;

  /// Sets it. Null disables the control.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final change = onChanged;
    return Semantics(
      toggled: value,
      label: '$title · $body',
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: change == null ? null : () => change(!value),
          child: Padding(
            padding: padding,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        title,
                        style: FormType.toggleTitle.copyWith(color: colors.ink),
                      ),
                      const SizedBox(height: bodyGap),
                      Text(
                        body,
                        style: FormType.toggleBody.copyWith(color: colors.ink2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: gap),
                ExcludeSemantics(
                  child: HSwitch(value: value, enabled: change != null),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `.switch` — the drawn control. See the library docstring for why it is drawn.
class HSwitch extends StatelessWidget {
  /// Renders the switch at [value]. It takes no gesture; [ToggleRow] owns that.
  const HSwitch({required this.value, this.enabled = true, super.key});

  /// `width: 42px`.
  static const double width = 42;

  /// `height: 26px`.
  static const double height = 26;

  /// `border-radius: 20px`.
  static const double radius = 20;

  /// `::after { width: 18px; height: 18px }`.
  static const double knob = 18;

  /// `::after { left: 3px; top: 3px }`.
  static const double inset = 3;

  /// `::after { transform: translateX(16px) }`.
  static const double travel = 16;

  /// `transition: transform 180ms`.
  static const Duration duration = Duration(milliseconds: 180);

  /// Whether it is on.
  final bool value;

  /// False dims it, matching `button:disabled { opacity: .45 }` on the row.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: AnimatedContainer(
        duration: duration,
        curve: kEaseOut,
        width: width,
        height: height,
        decoration: ShapeDecoration(
          color: value ? colors.accent : colors.rule,
          shape: hSquircle(
            radius,
            side: BorderSide(
              color: value ? colors.accent : colors.ink2,
              width: hairline,
            ),
          ),
        ),
        child: Stack(
          children: <Widget>[
            AnimatedPositioned(
              duration: duration,
              curve: kEaseOut,
              left: value ? inset + travel : inset,
              top: inset,
              width: knob,
              height: knob,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: value ? colors.onAccent : colors.surface,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
