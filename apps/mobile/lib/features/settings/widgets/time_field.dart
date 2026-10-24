/// `<input type="time">` — a field that opens the platform's own time picker.
///
/// The prototype writes a native time input. Flutter has no such control, so the
/// substitution is a tappable box on `FieldBox`'s geometry — the same 48 px
/// minimum, 12 px padding, 12 px radius and `--rule` edge every other field
/// wears — opening `showTimePicker`. That matches the **rendered result**: a
/// field-shaped control showing a time, which opens the system picker on tap.
///
/// The value travels as a **minute of the day**, which is what
/// `ReminderPreferences` stores, so nothing here converts between two clocks. It
/// is formatted with `TimeOfDay.format`, so a phone set to a 24-hour clock shows
/// one and a phone set to AM/PM shows that — the owner's own setting, not ours.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/shapes.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_scale_forms.dart';
import 'package:healthee/shared/v02/fields.dart';
import 'package:solar_icons/solar_icons.dart';

/// A labelled time, opening the platform picker.
class TimeField extends StatelessWidget {
  /// Builds the field. [onChanged] of null draws it disabled.
  const TimeField({
    required this.label,
    required this.minuteOfDay,
    required this.onChanged,
    this.hint,
    super.key,
  });

  /// What the time is for.
  final String label;

  /// The time, as minutes since midnight.
  final int minuteOfDay;

  /// Called with the new minute of the day.
  final ValueChanged<int>? onChanged;

  /// The note under it.
  final String? hint;

  /// The value as a [TimeOfDay].
  TimeOfDay get time =>
      TimeOfDay(hour: minuteOfDay ~/ 60, minute: minuteOfDay % 60);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final change = onChanged;
    return HField(
      label: label,
      hint: hint,
      child: Semantics(
        button: true,
        label: '$label · ${time.format(context)}',
        child: GestureDetector(
          onTap: change == null ? null : () => _pick(context, change),
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
                Text(
                  time.format(context),
                  style: FormType.fieldInput.copyWith(color: colors.ink),
                ),
                Icon(
                  SolarIconsOutline.clockCircle,
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

  Future<void> _pick(BuildContext context, ValueChanged<int> change) async {
    final picked = await showTimePicker(context: context, initialTime: time);
    if (picked == null) {
      return;
    }
    change(picked.hour * 60 + picked.minute);
  }
}
