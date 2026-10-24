/// The date-of-birth field, and the two rules the profile form shares.
///
/// Split from `profile_editor.dart` at the length gate (Standards §1); the seam
/// is that the editor owns the *write* and this owns the two controls that have
/// their own reason to exist.
///
/// ## A birthday is picked, never typed
///
/// `<input type="date">` in the prototype. Flutter has no such control, so the
/// substitution is a field-shaped box on `FieldBox`'s geometry opening
/// `showDatePicker` — the same rendered result. It stores `YYYY-MM-DD`, which
/// is what the server's `dob_date` is, so nothing here converts between two
/// date formats.
///
/// ## A birthday held only by the old server says so
///
/// `HealthProfile.legacyBirthdayPresent` is true when the account has a stored
/// birthday that the current API does not hand back. The field then says
/// *"Stored on your server · tap to confirm"* rather than showing an empty box,
/// which would read as "we do not have one" and invite a re-entry that
/// overwrites a value nobody checked.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/shapes.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_scale_forms.dart';
import 'package:healthee/shared/v02/fields.dart';
import 'package:solar_icons/solar_icons.dart';

/// The two numbers and the gaps the profile form shares.
abstract final class ProfileFields {
  /// `.two { gap: 12px }`.
  static const double columnGap = 12;

  /// `.section { margin-top: 24px }`, used inside a card.
  static const double blockGap = 24;

  /// Whether [text] is blank, or parses to a positive number at most [maximum].
  ///
  /// Blank is valid and means *unanswered*, which is a different thing from
  /// zero: a profile with no height is an ordinary profile, and a height of 0
  /// would be a measurement.
  static bool validNumber(String text, double? value, double maximum) =>
      text.trim().isEmpty ||
      (value != null && value.isFinite && value > 0 && value <= maximum);
}

/// The date of birth, as a field that opens the platform picker.
class BirthdayField extends StatefulWidget {
  /// Builds the field. [value] is `YYYY-MM-DD` or null.
  const BirthdayField({
    required this.value,
    required this.legacyStored,
    required this.enabled,
    required this.onChanged,
    this.autoOpen = false,
    super.key,
  });

  /// The stored date, `YYYY-MM-DD`, or null.
  final String? value;

  /// Whether the account holds one this API does not return.
  final bool legacyStored;

  /// False while a save is in flight.
  final bool enabled;

  /// Called with the picked `YYYY-MM-DD`.
  final ValueChanged<String> onChanged;

  /// Whether the picker opens by itself after the first frame, for a link that
  /// asked for this field (`/profile?focus=dob`).
  final bool autoOpen;

  @override
  State<BirthdayField> createState() => _BirthdayFieldState();
}

class _BirthdayFieldState extends State<BirthdayField> {
  @override
  void initState() {
    super.initState();
    if (widget.autoOpen && widget.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_pick(context));
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final value = widget.value;
    final shown =
        value ??
        (widget.legacyStored
            ? 'Stored on your server · tap to confirm'
            : 'Not provided');
    return HField(
      label: 'Date of birth',
      hint: 'Used by some reference estimates.',
      child: Semantics(
        button: true,
        label: 'Date of birth · $shown',
        child: GestureDetector(
          onTap: widget.enabled ? () => _pick(context) : null,
          behavior: HitTestBehavior.opaque,
          child: Container(
            constraints: const BoxConstraints(minHeight: FieldBox.minHeight),
            padding: const EdgeInsets.all(FieldBox.padding),
            decoration: ShapeDecoration(
              color: colors.surface,
              shape: hSquircle(
                FieldBox.radius,
                side: BorderSide(color: colors.rule),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Flexible(
                  child: Text(
                    shown,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FormType.fieldInput.copyWith(
                      color: value == null ? colors.ink2 : colors.ink,
                    ),
                  ),
                ),
                Icon(
                  SolarIconsOutline.calendarMark,
                  size: 18,
                  color: colors.ink2,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: widget.value == null ? now : DateTime.parse(widget.value!),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked == null) {
      return;
    }
    widget.onChanged(picked.toIso8601String().substring(0, 10));
  }
}
