/// `.vitals-table` — a run of overnight measurements, each with its own
/// fortnight and its own family.
///
/// ```css
/// .vital-row { display:grid; grid-template-columns:minmax(0,1fr) 75px 66px;
///              align-items:center; gap:8px; padding-block:12px;
///              border-bottom:1px solid var(--line) }
/// .vital-row:last-child { border:0; padding-bottom:0 }
/// .vital-row .icon      { color:var(--family) }
/// .vital-row .sparkline { margin:0; height:25px }
/// @media(max-width:359px) .vital-row { grid-template-columns:minmax(0,1fr) 50px 62px }
/// ```
///
/// ## Why this is shared rather than Sleep's
///
/// `panels.js::H.overnightVitals` is called from **two** screens — the sleep
/// night and `H.screens.recovery` — with the same five rows. It was built inside
/// `features/sleep/v02/vitals_panel.dart` because Sleep was the first screen to
/// need it; a second feature reaching into Sleep for it would be the sideways
/// dependency Standards section 1 bans, and copying it would be the second
/// occurrence that section 1 says to extract instead. So the table moved here
/// and the two panels above it stayed where they are.
///
/// ## Five families in one panel, and no widget takes a colour
///
/// `data-tone` sits on the **row**, not the panel, so each row's glyph and its
/// spark are that measurement's own family while the panel head keeps its own.
/// Each row is a `ToneScope`; the sparkline reads the family out of it.
///
/// ## What the strap refused
///
/// Every figure is a [Reading]. A withheld one draws a dash in its slot, and
/// [VitalsTable.refusals] hands the caller the server's own reasons so they can
/// be written out **under** the table, naming the measurement — one note listing
/// three refusals, rather than three sentences threaded between rows where each
/// would read as a caveat on the row below it.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/sleep_type_scale.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/data/honesty/reading.dart';
import 'package:healthee/shared/charts/v02/v02_sparkline.dart';
import 'package:healthee/shared/instrument/h_tap.dart';
import 'package:healthee/shared/reveal_once.dart';

/// One row of an overnight table.
@immutable
class Vital {
  /// A measurement, its family, its fortnight and where it goes when tapped.
  const Vital({
    required this.label,
    required this.tone,
    required this.icon,
    required this.unit,
    required this.reading,
    required this.series,
    required this.metric,
    this.digits = 0,
  });

  /// What it is called.
  final String label;

  /// Which family it belongs to.
  final Tone tone;

  /// Its glyph.
  final IconData icon;

  /// The unit beside the figure.
  final String unit;

  /// Last night's value, with its honesty state.
  final Reading<double> reading;

  /// The fortnight behind it, oldest first, gaps kept as nulls.
  final List<double?> series;

  /// The metric this row opens.
  final String metric;

  /// How many decimals the figure carries.
  final int digits;
}

/// The five overnight measurements, as one table.
class VitalsTable extends StatelessWidget {
  /// [revealPrefix] namespaces each row's reveal id, so two screens drawing the
  /// same measurement do not share one "already animated" flag.
  const VitalsTable({
    required this.vitals,
    required this.reveals,
    required this.revealPrefix,
    this.onOpenMetric,
    super.key,
  });

  /// `.sparkline { height: 25px }`.
  static const double sparkHeight = 25;

  /// `.vital-row { padding-block: 12px }`.
  static const double rowPad = 12;

  /// `gap: 8px`.
  static const double columnGap = 8;

  /// `grid-template-columns: … 75px 66px`.
  static const double sparkWidth = 75;
  static const double valueWidth = 66;

  /// The same two under the prototype's 359 px breakpoint.
  static const double narrowSparkWidth = 50;
  static const double narrowValueWidth = 62;

  /// The rows, in the prototype's order.
  final List<Vital> vitals;

  /// Where "already revealed" is remembered.
  final RevealRegistry reveals;

  /// The reveal-id namespace, e.g. `sleep.vital`.
  final String revealPrefix;

  /// Opens one measurement's own history.
  final void Function(String metric)? onOpenMetric;

  /// The server's own reason for each measurement it did not send.
  static List<String> refusals(List<Vital> rows) => <String>[
    for (final vital in rows)
      if (vital.reading case Withheld<double>(:final disclosure))
        '${vital.label}: ${disclosure.message}',
  ];

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      for (var i = 0; i < vitals.length; i++)
        VitalRow(
          vital: vitals[i],
          reveals: reveals,
          revealPrefix: revealPrefix,
          last: i == vitals.length - 1,
          onOpen: onOpenMetric == null
              ? null
              : () => onOpenMetric!(vitals[i].metric),
        ),
    ],
  );
}

/// One `.vital-row`: label, fortnight, figure.
class VitalRow extends StatelessWidget {
  /// Builds the row. [last] drops its rule and its bottom padding.
  const VitalRow({
    required this.vital,
    required this.reveals,
    required this.revealPrefix,
    required this.last,
    this.onOpen,
    super.key,
  });

  /// The measurement this row draws.
  final Vital vital;

  /// Where "already revealed" is remembered.
  final RevealRegistry reveals;

  /// The reveal-id namespace.
  final String revealPrefix;

  /// Whether this is the table's last row.
  final bool last;

  /// Opens this measurement's own history.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => ToneScope(
    tone: vital.tone,
    child: Builder(builder: _body),
  );

  Widget _body(BuildContext context) {
    final colors = context.colors;
    final narrow = MediaQuery.sizeOf(context).width < SleepType.narrowWidth;
    final value = vital.reading.valueOrNull;
    final row = Padding(
      padding: EdgeInsets.only(
        top: VitalsTable.rowPad,
        bottom: last ? 0 : VitalsTable.rowPad,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(vital.icon, size: 16, color: colors.ink2),
                const SizedBox(width: VitalsTable.columnGap),
                Flexible(
                  child: Text(
                    vital.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SleepType.vitalLabel.copyWith(color: colors.ink),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: VitalsTable.columnGap),
          SizedBox(
            width: narrow
                ? VitalsTable.narrowSparkWidth
                : VitalsTable.sparkWidth,
            child: RevealOnce(
              id: '$revealPrefix.${vital.metric}',
              registry: reveals,
              builder: (context, t) => V02Sparkline(
                vital.series,
                progress: t,
                height: VitalsTable.sparkHeight,
              ),
            ),
          ),
          const SizedBox(width: VitalsTable.columnGap),
          SizedBox(
            width: narrow
                ? VitalsTable.narrowValueWidth
                : VitalsTable.valueWidth,
            child: Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  TextSpan(
                    text: value == null
                        ? '—'
                        : value.toStringAsFixed(vital.digits),
                    style: SleepType.vitalValue.copyWith(
                      color: value == null ? colors.ink2 : colors.ink,
                    ),
                  ),
                  TextSpan(
                    text: '\u00A0${vital.unit}',
                    style: SleepType.vitalUnit.copyWith(color: colors.ink2),
                  ),
                ],
              ),
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.clip,
            ),
          ),
        ],
      ),
    );
    final bordered = last
        ? row
        : DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: colors.line, width: hairline),
              ),
            ),
            child: row,
          );
    return HTap(
      onTap: onOpen,
      semanticLabel: '${vital.label} history',
      child: bordered,
    );
  }
}
