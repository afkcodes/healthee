/// `Naps & your day` — the daytime sleep around the night.
///
/// `design/mobile-preview/sleep-history-view.js`:
///
/// ```js
/// H.panel('Naps & your day','sleep',
///   `${naps.length
///       ? naps.map(n => H.note(`${localTime(n.start_iso)}–${localTime(n.end_iso)}`
///                              + ` · ${H.duration(n.duration_min)}`)).join('')
///       : H.note('No nap record included for this day.')}
///    ${H.link('Journal for this day','journal')}`,
///   'journal','moon')
/// ```
///
/// ## `naps[].stages` USED TO BE STRUCTURALLY EMPTY. IT NO LONGER IS.
///
/// `/api/sleep` shipped the raw hypnogram under the key a *night* uses for
/// per-stage minute totals, so the shape that reached the phone was empty on
/// every nap, on every day, for every owner. The pre-v02 card drew a stage bar
/// from it and rendered a strip with nothing in it; this panel drew no bar and
/// said in a sentence that the server did not send the breakdown.
///
/// The server sends it now (`docs/BACKEND_GAPS_FROM_UI.md` A1), so **that
/// sentence is gone — it had become false, which is worse than the gap it was
/// describing.**
///
/// **No bar came back with it, and that is not an oversight.** The prototype
/// (`design/mobile-preview/sleep-history-view.js`, quoted above) draws nap rows
/// as text and has no stage element on this panel at all. The old comment's
/// "when the server starts filling that field the bar can come back" was reading
/// the pre-v02 card as the specification; it is not. Adding one now would be a
/// design decision, and the design is the owner's.
///
/// What replaces the sentence is the honest half of it: [kNapsUnstagedNote] says
/// the *strap* recorded no stages, and only when that is true of every nap shown.
/// That is a fact about the recording rather than a complaint about the wire.
///
/// ## The rows are a TABLE, not the prototype's sentences
///
/// The prototype joins each nap into one middot-separated line, and sixteen of
/// those read as a paragraph: `6 Sep · 3:52 pm–4:58 pm · 1h 6m` eight times
/// over, with the day, the clock and the length landing at a different x on
/// every row because each one is a different number of characters wide. Nothing
/// can be compared down a column because there are no columns.
///
/// Three fixed columns instead — day, when, how long — so a reader scanning for
/// "which was the long one" reads one column instead of sixteen sentences. A
/// cell with nothing recorded draws the app's own [kNoReading], not a gap: a
/// blank cell in a table reads as a rendering fault, and dropping the field
/// (which the sentence did) silently reflowed the row.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/core/theme/type_scale.dart';
import 'package:healthee/data/models/sleep_page.dart';
import 'package:healthee/features/sleep/sleep_format.dart';
import 'package:healthee/shared/format/duration.dart';
import 'package:healthee/shared/v02/buttons.dart';
import 'package:healthee/shared/v02/panel.dart';
import 'package:healthee/shared/v02/panel_head.dart';
import 'package:healthee/shared/v02/panel_parts.dart';
import 'package:solar_icons/solar_icons.dart';

/// What a cell with nothing recorded draws.
///
/// The app's own mark for "no reading", the one `dated_panel.dart` uses. It is
/// deliberately not a blank: an empty cell in a table reads as a rendering
/// fault, and the sentence this table replaced simply dropped the field, which
/// silently reflowed the row into a shorter one that looked complete.
const String kNoReading = '—';

/// `H.note('No nap record included for this day.')`.
const String kNoNapsNote = 'No nap record included for this day.';

/// Shown only when the strap staged NONE of the naps listed. See the docstring.
///
/// It replaces a sentence that blamed the server for a breakdown it now sends.
/// The distinction matters to the reader: "we were not told" and "there was
/// nothing to tell" are different states, and only one of them is about them.
const String kNapsUnstagedNote =
    'The strap recorded no stage breakdown for these naps, only when they '
    'started, when they ended and how long they ran.';

/// `Naps & your day`.
class NapsPanel extends StatelessWidget {
  /// [naps] is what `/api/sleep` returned, newest first.
  const NapsPanel({required this.naps, this.onOpenJournal, super.key});

  /// The prototype's title.
  static const String title = 'Naps & your day';

  /// How many rows before the panel stops listing.
  static const int shown = 8;

  /// The gap between two nap rows.
  static const double rowGap = 10;

  /// The day column.
  static const double dayWidth = 56;

  /// The length column, right-aligned.
  static const double lengthWidth = 62;

  /// A table cell's own breathing room, top and bottom.
  static const double cellPad = 9;

  /// The gap above the header row.
  static const double tableTop = 6;

  /// The gap above the journal link.
  static const double linkGap = 6;

  /// The recorded naps.
  final List<SleepNap> naps;

  /// Opens the journal.
  final VoidCallback? onOpenJournal;

  /// Total minutes napped across [naps].
  double get totalMin =>
      naps.fold<double>(0, (sum, nap) => sum + (nap.tibMin ?? 0));

  /// Whether the strap staged none of the naps shown.
  ///
  /// Every one, not any one: a note that fired because a single short nap went
  /// unstaged would be describing the panel wrongly whenever another nap on it
  /// carries a full breakdown.
  bool get noneStaged =>
      naps.take(shown).every((nap) => nap.stages?.isEmpty ?? true);

  @override
  Widget build(BuildContext context) {
    return Panel(
      tone: Tone.sleep,
      label: 'Naps',
      head: PanelHead(
        title: title,
        icon: SolarIconsOutline.moonSleep,
        infoKey: 'sleep',
        actionLabel: onOpenJournal == null ? null : 'Journal',
        onAction: onOpenJournal,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (naps.isEmpty)
            const PanelNote(kNoNapsNote)
          else ...<Widget>[
            PanelValue(
              durationText(totalMin),
              unit: naps.length == 1 ? 'in 1 nap' : 'in ${naps.length} naps',
            ),
            const SizedBox(height: tableTop),
            const _NapHead(),
            for (final nap in naps.take(shown)) _NapRow(nap: nap),
            if (noneStaged) const PanelNote(kNapsUnstagedNote),
          ],
          if (onOpenJournal != null) ...<Widget>[
            const SizedBox(height: linkGap),
            HLinkButton(
              label: 'Journal for this day',
              onPressed: onOpenJournal,
            ),
          ],
        ],
      ),
    );
  }

  /// The day, or [kNoReading] when the payload carried none.
  static String day(SleepNap nap) {
    final date = shortDate(nap.date);
    return date.isEmpty ? kNoReading : date;
  }

  /// The clock range, or [kNoReading] when either end is missing. **Both or
  /// neither** — a range drawn from one end is a half-measurement wearing a
  /// full one's shape.
  static String when(SleepNap nap) {
    final start = nap.start;
    final end = nap.end;
    return start == null || end == null ? kNoReading : napRange(start, end);
  }

  /// How long it ran, or [kNoReading].
  static String length(SleepNap nap) => switch (nap.tibMin) {
    final double minutes => durationText(minutes),
    null => kNoReading,
  };
}

/// The column names, once, above the rows.
class _NapHead extends StatelessWidget {
  const _NapHead();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = TypeLadder.label.copyWith(color: colors.ink2);
    return Padding(
      padding: const EdgeInsets.only(bottom: NapsPanel.cellPad),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: NapsPanel.dayWidth,
            child: Text('DAY', style: style),
          ),
          Expanded(child: Text('WHEN', style: style)),
          SizedBox(
            width: NapsPanel.lengthWidth,
            child: Text('LENGTH', textAlign: TextAlign.right, style: style),
          ),
        ],
      ),
    );
  }
}

/// One nap, in three columns.
class _NapRow extends StatelessWidget {
  const _NapRow({required this.nap});

  final SleepNap nap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final cell = TypeScale.panelContext.copyWith(color: colors.ink2);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colors.line, width: hairline),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: NapsPanel.cellPad),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: NapsPanel.dayWidth,
              child: Text(
                NapsPanel.day(nap),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: cell,
              ),
            ),
            Expanded(
              child: Text(
                NapsPanel.when(nap),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: cell,
              ),
            ),
            SizedBox(
              width: NapsPanel.lengthWidth,
              child: Text(
                NapsPanel.length(nap),
                textAlign: TextAlign.right,
                maxLines: 1,
                // The one figure a reader scans this table FOR, so it is the
                // one in full ink.
                style: TypeLadder.calloutStrong.copyWith(color: colors.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
