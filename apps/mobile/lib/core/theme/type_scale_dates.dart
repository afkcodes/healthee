/// **v02's type scale, third seam: the date control and its calendar.**
///
/// Split out of `type_scale.dart` because that file's one reason to change is a
/// **panel's** typography, and these four roles belong to the date affordance
/// on Today — the caret, the month heading, and a day cell in its two states.
/// Each is an alias of a step on `type_ladder.dart`.
///
/// **Colourless**, like the rest of the scale: the colour arrives at the point
/// of use, so a style cannot carry a hue that disagrees with its container.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/type_ladder.dart';

/// The date control's scale. Colourless; see the library docstring.
abstract final class DateType {
  /// `.date-caret` — the chevron beside the date the reader is on.
  static final TextStyle dateCaret = TypeLadder.callout;

  /// `.calendar-heading strong` — the month a calendar is showing.
  static final TextStyle calendarMonth = TypeLadder.bodyStrong;

  /// `.date-calendar button` — one day in the grid.
  static final TextStyle calendarDay = TypeLadder.callout;

  /// `.date-calendar button[aria-current]` — the day being shown.
  static final TextStyle calendarDayCurrent = TypeLadder.calloutStrong;
}
