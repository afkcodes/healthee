/// `.date-navigation` — previous, the date itself, next, and the way back.
///
/// ```css
/// .date-navigation      { display:flex; align-items:center; gap:2px;
///                         margin:-4px 0 2px -6px; min-height:32px;
///                         width:max-content; max-width:100%; }
/// .date-navigation button { min-width:28px; min-height:32px; padding:4px;
///                           color:var(--muted); border-radius:8px; }
/// .date-navigation button:disabled { opacity:.28; }
/// .date-navigation .icon  { width:12px; height:12px; }
/// .date-picker-trigger    { gap:6px; padding-inline:6px; font-size:11px;
///                           color:var(--ink); white-space:nowrap; }
/// .date-caret             { font-size:13px; color:var(--subtle); }
/// .date-latest            { font-size:10px; color:var(--family);
///                           margin-left:4px; padding-inline:6px; }
/// ```
///
/// ## What the control is allowed to reach
///
/// The window is the phone's own retention — `data/store/view_date.dart` derives
/// both ends — so the two chevrons disable at the ends rather than offering a
/// day the store cannot answer for. `Latest` appears only when there is
/// somewhere to go back to, which is the prototype's own rule: it draws the
/// button when `H.isPast()` and a static `Sample` marker otherwise. There is no
/// marker here because this app has no sample data; the row simply ends.
///
/// ## The negative margins are reproduced, and they are optical
///
/// `margin-left: -6px` pulls the first chevron's 4 px padding and the button's
/// 28 px minimum back so the date sits on the same optical left edge as the
/// title beneath it, and `margin-top: -4px` absorbs the row's own min-height
/// against the header above. A `Padding` cannot take a negative inset, so this
/// is a `Transform.translate` — the same displacement, in the one widget that
/// does it without changing anyone's layout box.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/core/theme/type_scale.dart';
import 'package:healthee/core/theme/type_scale_dates.dart';
import 'package:healthee/features/today/today_labels.dart';
import 'package:healthee/features/today/v02/date_calendar_sheet.dart';
import 'package:healthee/shared/instrument/h_tap.dart';
import 'package:solar_icons/solar_icons.dart';

/// The window a date control may move within, and where a choice is sent.
///
/// One object rather than four loose parameters because the four are only
/// meaningful together: a bound with no callback is a control that cannot move,
/// and a callback with no bounds is one that can ask for a day this phone has
/// already pruned.
@immutable
class DateNavigation {
  /// [earliest] and [latest] are inclusive `YYYY-MM-DD` bounds.
  const DateNavigation({
    required this.earliest,
    required this.latest,
    required this.onSelect,
  });

  /// The oldest day the control may reach — the retention horizon.
  final String earliest;

  /// The newest, which is the wall-clock day. There is no tomorrow to show.
  final String latest;

  /// Called with the chosen `YYYY-MM-DD`.
  final ValueChanged<String> onSelect;
}

/// The previous / date / next control, with a calendar behind the date.
class DateControl extends StatelessWidget {
  /// [date] is the day currently on screen.
  const DateControl({
    required this.date,
    required this.navigation,
    this.prominent = false,
    super.key,
  });

  /// `.date-navigation { gap: 2px }`.
  static const double gap = 2;

  /// `.date-navigation button { min-width: 28px; min-height: 32px }`.
  static const Size button = Size(28, 32);

  /// `.date-navigation .icon { width: 12px }`.
  static const double iconSize = 12;

  /// `.date-navigation button:disabled { opacity: .28 }`.
  static const double disabledOpacity = 0.28;

  /// `.date-navigation { margin: -4px 0 2px -6px }`.
  static const Offset margin = Offset(-6, -4);

  /// The bottom half of that margin, which a transform cannot carry.
  static const double bottomGap = 2;

  /// The word the prototype puts on the way back to the newest day.
  static const String latestLabel = 'Latest';

  /// The back chevron. A key rather than a semantics lookup, because a disabled
  /// control has to be findable in order to assert that it is disabled.
  static const Key previousKey = ValueKey<String>('date.previous');

  /// The forward chevron.
  static const Key nextKey = ValueKey<String>('date.next');

  /// The date itself, which opens the calendar.
  static const Key triggerKey = ValueKey<String>('date.trigger');

  /// The way back to the newest day. Absent when already on it.
  static const Key latestKey = ValueKey<String>('date.latest');

  /// The day on screen, `YYYY-MM-DD`.
  final String date;

  /// Where it may go, and who to tell.
  final DateNavigation navigation;

  /// Whether this control IS the header rather than a line above one.
  ///
  /// Today's head is one row, so the date carries it: `Today` on the newest day
  /// and the dated form on any other, at [TypeScale.pageDateStrong]. Every other
  /// screen still draws the small date under its own title.
  final bool prominent;

  /// Whether there is an older day inside the window.
  bool get hasPrevious => date.compareTo(navigation.earliest) > 0;

  /// Whether there is a newer one.
  bool get hasNext => date.compareTo(navigation.latest) < 0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: bottomGap),
      child: Transform.translate(
        offset: margin,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _step(
              context,
              key: previousKey,
              icon: SolarIconsOutline.altArrowLeft,
              label: 'Previous day',
              onTap: hasPrevious ? () => _move(-1) : null,
            ),
            const SizedBox(width: gap),
            Flexible(child: _trigger(context)),
            const SizedBox(width: gap),
            _step(
              context,
              key: nextKey,
              icon: SolarIconsOutline.altArrowRight,
              label: 'Next day',
              onTap: hasNext ? () => _move(1) : null,
            ),
            // Only when there is somewhere to return to. A `Latest` sitting on
            // the latest day is a button that says nothing happened.
            if (hasNext) ...<Widget>[
              const SizedBox(width: 4),
              HTap(
                key: latestKey,
                onTap: () => navigation.onSelect(navigation.latest),
                semanticLabel: 'Show the latest day',
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Text(
                    latestLabel,
                    style: TypeScale.deviceStrip.copyWith(
                      color: context.family,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// One day forward or back, clamped by the caller's own window.
  void _move(int days) {
    final anchor = DateTime.parse(date);
    final moved = DateTime.utc(anchor.year, anchor.month, anchor.day)
        .add(Duration(days: days))
        .toIso8601String()
        .substring(0, 10);
    navigation.onSelect(moved);
  }

  Widget _step(
    BuildContext context, {
    required Key key,
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    final colors = context.colors;
    final chevron = SizedBox(
      width: button.width,
      height: button.height,
      child: Icon(icon, size: iconSize, color: colors.ink2),
    );
    // `:disabled` rather than absent. The prototype dims the chevron at the end
    // of its window and leaves it in place, which is what tells a reader the
    // window HAS an end — a button that vanished would read as a layout shift.
    return onTap == null
        ? Opacity(
            key: key,
            opacity: disabledOpacity,
            child: Semantics(
              button: true,
              enabled: false,
              label: label,
              child: chevron,
            ),
          )
        : HTap(key: key, onTap: onTap, semanticLabel: label, child: chevron);
  }

  /// `.date-picker-trigger` — the date, and the caret that says it opens.
  Widget _trigger(BuildContext context) {
    final colors = context.colors;
    return HTap(
      key: triggerKey,
      onTap: () => openDateCalendar(
        context: context,
        date: date,
        navigation: navigation,
      ),
      semanticLabel: 'Choose a day, ${prettyDate(date)}',
      // No `alignment:` — a `Container` given one wraps its child in an `Align`,
      // which expands to the widest constraint it is offered. Inside the header's
      // `Expanded` that was the whole row, so the forward chevron ended up at the
      // far side of the screen with a lake between it and the date.
      child: Container(
        constraints: BoxConstraints(minHeight: button.height),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Flexible(
              child: Text(
                prominent
                    ? dayTitle(date, latest: navigation.latest)
                    : prettyDate(date),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style:
                    (prominent
                            ? TypeScale.pageDateStrong
                            : TypeScale.pageDate)
                        .copyWith(color: colors.ink),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '⌄',
              style: DateType.dateCaret.copyWith(color: colors.ink2),
            ),
          ],
        ),
      ),
    );
  }
}
