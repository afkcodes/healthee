/// `Choose a day` — the calendar behind the date control.
///
/// ```css
/// .calendar-heading  { display:flex; justify-content:space-between;
///                      align-items:center; gap:12px; margin-top:24px; }
/// .calendar-heading strong { font-size:16px; }
/// .calendar-week, .date-calendar { display:grid;
///                      grid-template-columns:repeat(7,minmax(0,1fr));
///                      gap:4px; text-align:center; }
/// .calendar-week     { font-size:10px; color:var(--muted); margin:20px 0 8px; }
/// .date-calendar button { position:relative; aspect-ratio:1; min-height:36px;
///                      border-radius:12px; font-size:13px; }
/// .date-calendar button i { width:3px; height:3px; border-radius:50%;
///                      background:var(--fitness); bottom:5px; }
/// .date-calendar button[aria-current='date'] { background:var(--fitness-soft);
///                      color:var(--fitness); font-weight:700;
///                      outline:1px solid var(--fitness); }
/// .calendar-help     { font-size:11px; margin:20px 0 8px; line-height:1.7; }
/// ```
///
/// ## The dot means what this app can actually check
///
/// `date-navigation.js` marks a day with a dot when `H.validDate` says readings
/// are available, which in the prototype is a lookup into scripted sample data.
/// This app has no such index: the local tier is keyed by day, so answering
/// "which of these 60 days holds anything" is 60 queries, and answering it wrong
/// would be a calendar telling the owner a day is empty when it is not.
///
/// So the dot carries the claim this app can support without asking: **the day
/// is inside the window this phone keeps**, and [helpLine] says exactly that.
/// Tapping one that turns out to hold nothing lands on a day of withholds, which
/// is the honest answer and the one the screens are built to give.
///
/// ## The month arrows are ours, and the window is why
///
/// The prototype renders one month — the earliest — and no way to leave it. Its
/// sample data fits in one. Sixty days spans three, so a calendar with no way
/// out of its month could not reach half the window it offers. The arrows are
/// bounded by the same two dates the chevrons in the control are.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/instrument_type.dart';
import 'package:healthee/core/theme/shapes.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/core/theme/type_scale.dart';
import 'package:healthee/core/theme/type_scale_dates.dart';
import 'package:healthee/features/today/v02/date_control.dart';
import 'package:healthee/shared/instrument/h_tap.dart';
import 'package:healthee/shared/sheets/app_sheet.dart';
import 'package:solar_icons/solar_icons.dart';

/// The sheet's title.
const String kDateCalendarTitle = 'Choose a day';

/// What the dot means, said plainly. See the library docstring.
const String helpLine =
    'A dot marks a day inside the 60 days this phone keeps. A day outside that '
    'window has been pruned and cannot be shown. Your selected day follows you '
    'between screens.';

/// Opens the calendar for [date], inside [navigation]'s window.
Future<void> openDateCalendar({
  required BuildContext context,
  required String date,
  required DateNavigation navigation,
}) => showAppSheet<void>(
  context: context,
  builder: (context) => _DateCalendarSheet(date: date, navigation: navigation),
);

/// The corner on one day cell. Smaller than a card's, because a 40px square at
/// the card radius is most of the way to a circle.
const double _cellRadius = 12;

class _DateCalendarSheet extends StatefulWidget {
  const _DateCalendarSheet({required this.date, required this.navigation});

  final String date;
  final DateNavigation navigation;

  @override
  State<_DateCalendarSheet> createState() => _DateCalendarSheetState();
}

class _DateCalendarSheetState extends State<_DateCalendarSheet> {
  late DateTime _month = _monthOf(widget.date);

  static DateTime _monthOf(String day) {
    final parsed = DateTime.parse(day);
    return DateTime.utc(parsed.year, parsed.month);
  }

  /// `YYYY-MM-DD` for [day] of the month on screen.
  String _iso(int day) =>
      DateTime.utc(_month.year, _month.month, day)
          .toIso8601String()
          .substring(0, 10);

  bool _inWindow(String day) =>
      day.compareTo(widget.navigation.earliest) >= 0 &&
      day.compareTo(widget.navigation.latest) <= 0;

  /// Whether the whole previous/next month is outside the window.
  bool _canReach(int months) {
    final moved = DateTime.utc(_month.year, _month.month + months);
    final last = DateTime.utc(moved.year, moved.month + 1, 0);
    final first = moved.toIso8601String().substring(0, 10);
    final end = last.toIso8601String().substring(0, 10);
    return end.compareTo(widget.navigation.earliest) >= 0 &&
        first.compareTo(widget.navigation.latest) <= 0;
  }

  void _shiftMonth(int months) => setState(
    () => _month = DateTime.utc(_month.year, _month.month + months),
  );

  void _choose(String day) {
    widget.navigation.onSelect(day);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(Radii.sheet),
        ),
        border: Border.all(color: colors.line),
      ),
      padding: EdgeInsets.fromLTRB(22, 12, 22, 32 + sheetBottomInset(context)),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(
              child: Container(
                width: 36,
                height: 5,
                decoration: BoxDecoration(
                  color: colors.line,
                  borderRadius: BorderRadius.circular(Radii.pill),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(kDateCalendarTitle, style: HType.serif(colors.ink, size: 24)),
            const SizedBox(height: 24),
            _heading(context),
            const SizedBox(height: 20),
            _weekdays(context),
            const SizedBox(height: 8),
            _grid(context),
            const SizedBox(height: 20),
            Text(
              helpLine,
              style: TypeScale.panelNote.copyWith(color: colors.ink2),
            ),
          ],
        ),
      ),
    );
  }

  /// The month and its two arrows.
  ///
  /// **No `Latest` shortcut.** The grid already draws today, ringed, one tap
  /// away in a month you reach with the same two arrows — a button whose whole
  /// job is to select a cell that is visible next to it is a second way to do
  /// the thing the sheet is for.
  Widget _heading(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: <Widget>[
        _arrow(context, SolarIconsOutline.altArrowLeft, 'Previous month', -1),
        Expanded(
          child: Text(
            _monthName(_month),
            textAlign: TextAlign.center,
            style: DateType.calendarMonth.copyWith(color: colors.ink),
          ),
        ),
        _arrow(context, SolarIconsOutline.altArrowRight, 'Next month', 1),
      ],
    );
  }

  Widget _arrow(BuildContext context, IconData icon, String label, int months) {
    final enabled = _canReach(months);
    final glyph = Icon(icon, size: 16, color: context.colors.ink2);
    return enabled
        ? HTap(
            onTap: () => _shiftMonth(months),
            semanticLabel: label,
            child: glyph,
          )
        : Opacity(
            opacity: DateControl.disabledOpacity,
            child: Semantics(
              button: true,
              enabled: false,
              label: label,
              child: glyph,
            ),
          );
  }

  Widget _weekdays(BuildContext context) {
    const days = <String>['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final style = TypeScale.deviceStrip.copyWith(color: context.colors.ink2);
    return Row(
      children: <Widget>[
        for (final day in days)
          Expanded(child: Text(day, textAlign: TextAlign.center, style: style)),
      ],
    );
  }

  Widget _grid(BuildContext context) {
    // Monday-first, matching the prototype's own header row.
    final offset = (DateTime.utc(_month.year, _month.month).weekday - 1) % 7;
    final count = DateTime.utc(_month.year, _month.month + 1, 0).day;
    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      children: <Widget>[
        for (var i = 0; i < offset; i++) const SizedBox.shrink(),
        for (var day = 1; day <= count; day++) _day(context, day),
      ],
    );
  }

  Widget _day(BuildContext context, int day) {
    final colors = context.colors;
    final family = context.family;
    final iso = _iso(day);
    final available = _inWindow(iso);
    final current = iso == widget.date;
    final cell = DecoratedBox(
      decoration: ShapeDecoration(
        color: current ? context.familySoft : null,
        shape: hSquircle(
          _cellRadius,
          side: current
              ? BorderSide(color: family, width: hairline)
              : BorderSide.none,
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Text(
            '$day',
            style:
                (current
                        ? DateType.calendarDayCurrent
                        : DateType.calendarDay)
                    .copyWith(color: current ? family : colors.ink),
          ),
          if (available)
            Positioned(
              bottom: 5,
              child: Container(
                width: 3,
                height: 3,
                decoration: BoxDecoration(color: family, shape: BoxShape.circle),
              ),
            ),
        ],
      ),
    );
    return available
        ? HTap(
            key: ValueKey<String>('calendar.$iso'),
            onTap: () => _choose(iso),
            semanticLabel: iso,
            child: cell,
          )
        : Opacity(
            key: ValueKey<String>('calendar.$iso'),
            opacity: DateControl.disabledOpacity,
            child: Semantics(
              button: true,
              enabled: false,
              label: iso,
              child: cell,
            ),
          );
  }

  static String _monthName(DateTime month) {
    const months = <String>[
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[month.month - 1]} ${month.year}';
  }
}
