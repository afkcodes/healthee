/// Today's head: the day on the left, you on the right. Two objects, one row.
///
/// ```css
/// .page-header       { display:flex; align-items:center;
///                      justify-content:space-between; gap:8px;
///                      margin-bottom:16px; }
/// .page-header .date { font-size:11px; color:var(--muted); margin-bottom:5px; }
/// .page-header h1    { font-size:27px; letter-spacing:-1px; line-height:1.2;
///                      font-weight:600; }
/// .device-strip      { display:flex; align-items:center; gap:7px;
///                      color:var(--subtle); font-size:10px;
///                      margin-bottom:20px; }
/// .device-strip .icon{ width:15px; height:15px; }
/// .status-dot        { width:5px; height:5px; background:var(--positive);
///                      border-radius:50%; }
/// ```
///
/// ## The greeting is gone, the title after it, and now the strip too
///
/// The screen this replaces opened with a two-line 42px *"Good morning, there."*
/// — legacy's `_GreetingHeader`, including legacy's degraded fallback for an
/// owner whose name nothing stores. v02 replaced it with **Today** over the
/// date, and the README records why: *"replaces generic main-screen slogans
/// with direct labels such as Today, Sleep, Activity"*. A salutation to nobody
/// was the largest type on the screen and said the least.
///
/// **Four rows became one, in three steps.** The 27px `Today` went because the
/// tab bar already names this screen, in the accent, with a filled glyph — and
/// because the word was only true until midnight. `dayTitle` folds the title
/// and the date into one control that says **Today** on the newest day the
/// window reaches and names the day on any other, which is the case where a
/// header has something to tell you.
///
/// The device strip went because it ended in `Data & sync ›`, and that is a row
/// inside Settings — a second door to the same place, given a row of its own.
/// The avatar has always opened Settings, so the strap moved onto the avatar.
///
/// ## What is left is two objects, and each is one tap
///
///   * [DayPill] — the day, in a filled pill with a caret, because a date is
///     not a title: it is the one thing on this screen you can change. The
///     month grid behind it replaces two 28px chevrons that moved one day per
///     press.
///   * [OwnerMark] — the strap's glyph, its charge, and the face, opening the
///     screen that holds all three subjects.
///
/// ## The ring stays, because it is the only connection chrome there is
///
/// `sync_ring.dart` is unchanged and still wraps the avatar: one classification,
/// one ring — and it says whether a sync is RUNNING, which is a different
/// question from whether the strap is healthy. That second question is the
/// watch glyph's tint, and it is `fav` only when the link is actually quiet. A
/// green watch beside a strap that has not been heard from in two days is the
/// flattery this product exists not to do.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_scale.dart';
import 'package:healthee/data/sync/connection_health.dart';
import 'package:healthee/features/coach/widgets/coach_fab.dart';
import 'package:healthee/features/today/today_labels.dart';
import 'package:healthee/features/today/v02/date_calendar_sheet.dart';
import 'package:healthee/features/today/v02/date_control.dart';
import 'package:healthee/shared/connection/sync_ring.dart';
import 'package:healthee/shared/instrument/h_icon_badge.dart';
import 'package:healthee/shared/instrument/h_tap.dart';
import 'package:solar_icons/solar_icons.dart';

/// `DataFooter` moved to `shared/v02/` when Activity and Insights grew the same
/// footer (Standards §1, second use). Re-exported so Today's call sites and its
/// order test are unchanged and there is still one definition.
export 'package:healthee/shared/v02/data_footer.dart' show DataFooter;

/// The day, and the owner — with the strap folded into the owner.
class TodayHeader extends StatelessWidget {
  /// [date] is the payload's own `YYYY-MM-DD`.
  const TodayHeader({
    required this.date,
    required this.now,
    this.health,
    this.navigation,
    this.batteryPercent,
    this.onOpenProfile,
    this.onOpenCoach,
    super.key,
  });

  /// Between the coach button and the owner's mark.
  static const double coachGap = 10;

  /// The gap under the head. It is the whole head now, so it ends once.
  static const double bottomGap = 20;

  /// The day this screen describes, as the server dated it.
  final String date;

  /// The instant the screen is being read at. Kept because the header is where
  /// a "this is not today" line will land; nothing draws it yet.
  final DateTime now;

  /// The classified connection, or null when nothing has classified one. Null
  /// draws no ring rather than a reassuring one.
  final ConnectionHealth? health;

  /// Where the date may move to, and who to tell. **Null draws the day as a
  /// plain label** — a screen that cannot change the day it is showing should
  /// not offer a control that does nothing.
  final DateNavigation? navigation;

  /// The strap's charge at the last sync. Null prints no charge.
  final int? batteryPercent;

  /// Opens the owner's own screen, which is where `Data & sync` lives.
  final VoidCallback? onOpenProfile;

  /// Opens the coach. Null draws no coach button.
  final VoidCallback? onOpenCoach;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: bottomGap),
    // **`Expanded` + `Align`.** A loose `Flexible` is allocated the whole free
    // space and keeps what it does not use as slack INSIDE ITS OWN SLOT, so a
    // `Spacer` beside it lands that slack after the last child and the mark
    // stops short of the margin. `Expanded` fills the slot and `Align` puts the
    // day at its left, so the mark begins where the slot ends.
    child: Row(
      children: <Widget>[
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: DayPill(date: date, navigation: navigation),
          ),
        ),
        if (onOpenCoach case final VoidCallback open) ...<Widget>[
          CoachFab(onTap: open),
          const SizedBox(width: coachGap),
        ],
        OwnerMark(
          health: health,
          batteryPercent: batteryPercent,
          onOpen: onOpenProfile,
        ),
      ],
    ),
  );
}

/// The day, and the caret that says it opens.
///
/// **It was a filled pill and it is not any more.** A pill reads as a button,
/// and a button at the top of a screen competes with the screen — the day is
/// what you are looking at, not an action offered to you. The caret carries the
/// affordance on its own, which is the same bargain every date field in the app
/// makes, and the month grid behind it is a better stepper than two 28px
/// chevrons: the retention window and every day in it, in one place, instead of
/// one day per press.
class DayPill extends StatelessWidget {
  /// [navigation] of null draws a label — there is nowhere for the day to go.
  const DayPill({required this.date, this.navigation, super.key});

  /// The hit area, held open around type that is only 17px tall.
  static const EdgeInsets padding = EdgeInsets.symmetric(vertical: 8);

  /// Between the day and its caret.
  static const double gap = 6;

  /// The caret, at the size the date's own type is set in.
  static const double caretSize = 16;

  /// The day on screen, `YYYY-MM-DD`.
  final String date;

  /// Where it may go, and who to tell.
  final DateNavigation? navigation;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final window = navigation;
    final label = window == null
        ? prettyDate(date)
        : dayTitle(date, latest: window.latest);
    final words = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TypeScale.pageDateStrong.copyWith(color: colors.ink),
    );
    if (window == null) {
      return words;
    }
    return HTap(
      onTap: () =>
          openDateCalendar(context: context, date: date, navigation: window),
      semanticLabel: 'Choose a day, ${prettyDate(date)}',
      child: Padding(
        padding: padding,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Flexible(child: words),
            const SizedBox(width: gap),
            Icon(
              SolarIconsOutline.altArrowDown,
              size: caretSize,
              color: colors.ink2,
            ),
          ],
        ),
      ),
    );
  }
}

/// You, and the strap on your wrist — one control, opening one screen.
///
/// The strap used to have a row of its own ending in `Data & sync ›`, which is
/// a row inside Settings and therefore a second door to the same place. The
/// avatar has always opened Settings, so the strap moved onto it: the glyph and
/// the charge sit beside the face, and the whole cluster is the one tap.
///
/// **The glyph carries the health, so there is no dot.** It takes `fav` only
/// when the classification found nothing to say — `alerts` is the union of the
/// link's own faults and the data's, so an empty one is the whole surface
/// agreeing that the strap is being heard from. A green watch beside a strap
/// nobody has heard from in two days is the flattery this product exists not to
/// do, and the full sentence is on the data-health card either way.
class OwnerMark extends StatelessWidget {
  /// [batteryPercent] of null prints no charge; nothing has read one.
  const OwnerMark({this.health, this.batteryPercent, this.onOpen, super.key});

  /// The mark's own circle. Legacy's avatar was 38: this is chrome beside a
  /// 44px pill, not the subject of the screen.
  static const double markSize = 28;

  /// The ring around it, clearing the mark by 3 a side.
  static const double ringSize = 34;

  /// The ring's own weight, scaled with it.
  static const double ringStroke = 1.5;

  /// Between the charge and the mark.
  static const double chargeGap = 8;

  /// **The mark shrank; the tap target did not.** The glyph is 30px across and
  /// the row is shorter than that, so the hit area is held open here — a
  /// control small enough to look tidy is not automatically one you can hit.
  static const double tapHeight = 44;

  /// The strap this app talks to. One device, named — in the semantics.
  static const String deviceName = 'Helio Strap';

  /// Where the mark leads, and what it holds.
  static const String action = 'Settings, data and sync';

  /// The classified connection. Null tints the glyph neutral, never green.
  final ConnectionHealth? health;

  /// The strap's charge at the last sync.
  final int? batteryPercent;

  /// Opens the owner's screen.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final state = health;
    final healthy = state != null && state.alerts.isEmpty;
    final mark = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (batteryPercent case final int percent) ...<Widget>[
          Text(
            '$percent%',
            // The charge takes the health colour. The glyph is inside the
            // circle now and wears the accent, so the tint had to move to the
            // one element beside it that is still free to carry a state — and
            // it is `fav` only when the classification found nothing to say.
            style: TypeScale.deviceStrip.copyWith(
              color: healthy ? colors.fav : colors.ink2,
            ),
          ),
          const SizedBox(width: chargeGap),
        ],
        SyncRing(
          health: health,
          diameter: ringSize,
          stroke: ringStroke,
          child: const HStrapMark(size: markSize),
        ),
      ],
    );
    final sized = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: tapHeight),
      child: Center(widthFactor: 1, child: mark),
    );
    return onOpen == null
        ? sized
        : Semantics(
            button: true,
            label: '$deviceName · $action',
            child: GestureDetector(
              onTap: onOpen,
              behavior: HitTestBehavior.opaque,
              child: sized,
            ),
          );
  }
}
