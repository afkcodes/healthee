/// `.field` — a label, a control, and the note under it.
///
/// ```css
/// .field        { display:grid; gap:8px; margin-bottom:16px; font-size:12px;
///                 font-weight:600; }
/// .field input, .field select, .field textarea
///               { width:100%; min-width:0; min-height:48px; padding:12px;
///                 border-radius:12px; border:1px solid var(--rule);
///                 background:var(--surface); color:var(--ink);
///                 font-weight:400; font-size:16px; }
/// .field small  { color:var(--muted); font-weight:400; font-size:10px;
///                 min-height:1.6em; }
/// .field input:user-invalid { border-color:var(--danger);
///                             background:var(--danger-soft); }
/// .two          { display:grid; grid-template-columns:repeat(2,1fr);
///                 gap:12px; }
/// ```
///
/// ## `min-height: 1.6em` on the hint is load-bearing and is reproduced
///
/// A field with a note and a field without one are the same height in the
/// prototype, because the note's box is reserved whether or not it has words in
/// it. That is what keeps the two halves of a `.two` row aligned when only one
/// of them explains itself. [HField] reserves it the same way — an absent hint
/// still occupies its line — and a hint of `null` **on a field that stands
/// alone** collapses, because there is nothing to align with.
///
/// The invalid state is `--danger`, which is this product's `alert` — the one
/// red. `notices.dart` argues that a failed request may not spend it. A field
/// the owner has typed a bad number into is different: it is a correction they
/// can make right now, on the control they are looking at, and the prototype
/// tints it. So [HField.invalid] paints the edge and the ground, and nothing
/// else on these screens does.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_scale_forms.dart';
import 'package:healthee/shared/instrument/h_tap.dart';
import 'package:healthee/shared/metric_info/metric_detail.dart';
import 'package:healthee/shared/metric_info/metric_info_sheet.dart';
import 'package:healthee/shared/v02/choice_sheet.dart';
import 'package:solar_icons/solar_icons.dart';

/// `.field` — the wrapper around one labelled control.
class HField extends StatelessWidget {
  /// Builds the field. [hint] of null with [reserveHint] false collapses it.
  const HField({
    required this.label,
    required this.child,
    this.hint,
    this.reserveHint = false,
    this.detail = MetricDetail.none,
    super.key,
  });

  /// `.field { gap: 8px }`.
  static const double gap = 8;

  /// `.field { margin-bottom: 16px }`.
  static const double bottomGap = 16;

  /// `.field small { min-height: 1.6em }` at 10 px.
  static const double hintMinHeight = 16;

  /// What the control is for.
  final String label;

  /// The control.
  final Widget child;

  /// The note under it.
  final String? hint;

  /// Holds the hint's line open even when there is no hint, so a field beside
  /// one that explains itself stays aligned.
  final bool reserveHint;

  /// This field's own provenance, bound for the ⓘ beside its label.
  ///
  /// A control whose answer feeds a published number has sources, and they are
  /// not card decoration — `activity_level_field.dart` is the live one, and its
  /// five labels are the reference levels a fitness model was fitted against.
  /// The default is empty, and `MetricInfoDot` then draws **nothing at all**, so
  /// every field without one keeps the label row it has to the pixel.
  final MetricDetail detail;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hint = this.hint;
    return Padding(
      padding: const EdgeInsets.only(bottom: bottomGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Flexible(
                child: Text(
                  label,
                  style: FormType.fieldLabel.copyWith(color: colors.ink),
                ),
              ),
              MetricInfoDot(null, detail: detail, fallbackTitle: label),
            ],
          ),
          const SizedBox(height: gap),
          child,
          if (hint != null || reserveHint) ...<Widget>[
            const SizedBox(height: gap),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: hintMinHeight),
              child: Text(
                hint ?? '',
                style: FormType.fieldHint.copyWith(color: colors.ink2),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The geometry every control inside a [HField] wears.
abstract final class FieldBox {
  /// `min-height: 48px`.
  static const double minHeight = 48;

  /// `padding: 12px`.
  static const double padding = 12;

  /// `border-radius: 12px`.
  static const double radius = 12;

  /// The `InputDecoration` a `TextField` needs to land on the CSS's box.
  ///
  /// [invalid] paints the danger edge and ground — see the library docstring
  /// for why this is the one place on these screens that spends the red.
  static InputDecoration decoration(
    BuildContext context, {
    String? hintText,
    Widget? suffixIcon,
    bool invalid = false,
  }) {
    final colors = context.colors;
    final edge = invalid ? colors.alert : colors.rule;
    OutlineInputBorder border(Color colour) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius),
      borderSide: BorderSide(color: colour, width: hairline),
    );
    return InputDecoration(
      isDense: true,
      hintText: hintText,
      hintStyle: FormType.fieldInput.copyWith(color: colors.ink2),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: invalid ? colors.alertSoft : colors.surface,
      constraints: const BoxConstraints(minHeight: minHeight),
      contentPadding: const EdgeInsets.all(padding),
      border: border(edge),
      enabledBorder: border(edge),
      focusedBorder: border(invalid ? colors.alert : colors.accent),
      disabledBorder: border(colors.line),
    );
  }
}

/// `.field input` — a single-line text control on the CSS's box.
class HTextField extends StatelessWidget {
  /// Builds the control.
  const HTextField({
    required this.controller,
    this.enabled = true,
    this.invalid = false,
    this.hintText,
    this.keyboardType,
    this.obscure = false,
    this.suffixIcon,
    this.onChanged,
    this.onSubmitted,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.focusNode,
    this.autofocus = false,
    super.key,
  });

  /// What holds the text.
  final TextEditingController controller;

  /// False greys it out while work is in flight.
  final bool enabled;

  /// Paints the danger edge — `:user-invalid`.
  final bool invalid;

  /// Placeholder text.
  final String? hintText;

  /// Which keyboard.
  final TextInputType? keyboardType;

  /// Whether the text is hidden. Used only by the token field.
  final bool obscure;

  /// A trailing control — the token field's reveal eye.
  final Widget? suffixIcon;

  /// Fires on every edit.
  final ValueChanged<String>? onChanged;

  /// Fires on the keyboard's done key.
  final ValueChanged<String>? onSubmitted;

  /// Restricts what may be typed.
  final List<TextInputFormatter>? inputFormatters;

  /// Whether the keyboard auto-capitalises.
  final TextCapitalization textCapitalization;

  /// The field's focus, when the caller needs to read or move it.
  final FocusNode? focusNode;

  /// Whether the field takes focus when it first appears. Off by default: a
  /// screen that opens with the keyboard up is a choice a caller makes.
  final bool autofocus;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    focusNode: focusNode,
    autofocus: autofocus,
    enabled: enabled,
    obscureText: obscure,
    keyboardType: keyboardType,
    onChanged: onChanged,
    onSubmitted: onSubmitted,
    inputFormatters: inputFormatters,
    textCapitalization: textCapitalization,
    autocorrect: false,
    enableSuggestions: false,
    maxLines: 1,
    style: FormType.fieldInput.copyWith(color: context.colors.ink),
    decoration: FieldBox.decoration(
      context,
      hintText: hintText,
      suffixIcon: suffixIcon,
      invalid: invalid,
    ),
  );
}

/// `.field select` — a chooser on the same box as [HTextField].
///
/// **Tapping it opens a sheet, not Material's overlay menu.** See
/// `choice_sheet.dart` for why: the menu covered the label of the field it
/// belonged to, truncated the longest option, and was the last control in the
/// app still painting a Material splash. The box, the border and the chevron
/// are unchanged — only what happens when it is pressed.
class HSelect<T> extends StatelessWidget {
  /// Builds the chooser. A null [value] shows [placeholder].
  const HSelect({
    required this.value,
    required this.items,
    required this.onChanged,
    required this.title,
    this.placeholder,
    super.key,
  });

  /// What is chosen. Null draws [placeholder].
  final T? value;

  /// The options, in order, each with its own words.
  final List<(T, String)> items;

  /// Sets it. Null disables the control.
  final ValueChanged<T?>? onChanged;

  /// The sheet's heading — normally the enclosing [HField]'s own label, so the
  /// sheet says which field it is answering.
  final String title;

  /// What an unanswered chooser says. **Never a guessed default** — a
  /// self-reported field the owner has not answered is unanswered.
  final String? placeholder;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final onChanged = this.onChanged;
    final chosen = items
        .where((entry) => entry.$1 == value)
        .map((entry) => entry.$2)
        .firstOrNull;
    final box = Container(
      constraints: const BoxConstraints(minHeight: FieldBox.minHeight),
      padding: const EdgeInsets.symmetric(
        horizontal: FieldBox.padding,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: onChanged == null ? colors.bg : colors.surface,
        borderRadius: BorderRadius.circular(FieldBox.radius),
        border: Border.all(
          color: onChanged == null ? colors.line : colors.rule,
          width: hairline,
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              chosen ?? placeholder ?? '',
              // Two lines, not one: `Usual activity` is a self-report whose
              // whole meaning is in the wording, and the field is where the
              // answer has to stay readable once the sheet has closed.
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: FormType.fieldInput.copyWith(
                color: chosen == null ? colors.ink2 : colors.ink,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Icon(SolarIconsOutline.altArrowDown, color: colors.ink2),
        ],
      ),
    );
    if (onChanged == null) {
      return box;
    }
    return Semantics(
      button: true,
      label: '$title · ${chosen ?? placeholder ?? ''}',
      child: HTap(
        onTap: () async {
          final picked = await chooseInSheet<T>(
            context: context,
            title: title,
            items: items,
            value: value,
          );
          // Null is a DISMISSAL, not a choice of null — see `chooseInSheet`.
          if (picked != null) {
            onChanged(picked);
          }
        },
        child: box,
      ),
    );
  }
}
