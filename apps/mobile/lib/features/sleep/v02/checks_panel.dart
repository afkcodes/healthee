/// `Your four sleep checks` — four independent readings, and no total.
///
/// `design/mobile-preview/screens-sleep.js::checks`, one `<li class="sleep-check">`
/// per row and the closing note:
///
/// ```js
/// ['Duration',       H.duration(minutes),        '7–9 hours',        …],
/// ['Efficiency',     efficiency + '%',           'At least 85%',     …],
/// ['Regularity · SRI', sri + ' /100',            '70 or above',      …],
/// ['Timing',         midpoint,                   'Midpoint 02:00–04:00', …],
/// H.note('Four independent checks, not a combined score. '
///        'The 7–9h check differs from the 8h sleep-need reference.')
/// ```
///
/// ## THE FOUR ARE NEVER ADDED UP
///
/// `/api/sleep` also sends `score` — how many of the four passed. It is **not
/// drawn here and must not be**: no validated instrument combines duration,
/// efficiency, regularity and timing into one number, and a reader shown `3`
/// beside four rows will take it for a mark out of four. That is the rule
/// `feedback_no_composite_score` states and the prototype's own title states it
/// too — *four* checks, not a score. `sleep_checks_test.dart` fails the build if
/// a total appears on this panel.
///
/// ## Where the mark comes from, and where the sentence comes from
///
/// The **mark** is the server's own `point_duration` / `point_efficiency` /
/// `point_timing` / `point_regularity`. That judgement is server science and is
/// not re-derived on the phone.
///
/// The **sentence under it** is arithmetic on the two numbers already on the
/// row — the reading and the published cutoff beside it — so it says how far
/// outside, in the reader's own units. If the server's mark and that distance
/// ever disagreed, this panel would show both rather than quietly picking one.
///
/// ## The cutoffs are the server's, with the prototype's wording as the fallback
///
/// `page.cutoffs` carries `duration_hours`, `efficiency_min`, `timing_hour_band`
/// and `sri_min`. A cutoff with no source is a number this app made up, so the
/// four **reference labels and the citations live in the ⓘ sheet**, off the
/// card's face, which is where the owner asked references to go.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/sleep_type_scale.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/data/honesty/reading.dart';
import 'package:healthee/data/models/sleep_night.dart';
import 'package:healthee/data/models/sleep_page.dart';
import 'package:healthee/features/sleep/v02/check_bar.dart';
import 'package:healthee/features/sleep/v02/sleep_cutoffs.dart';
import 'package:healthee/shared/format/duration.dart';
import 'package:healthee/shared/format/iso_clock.dart';
import 'package:healthee/shared/metric_info/metric_detail.dart';
import 'package:healthee/shared/usual_range.dart';
import 'package:healthee/shared/v02/key_number_card.dart';
import 'package:healthee/shared/v02/panel.dart';
import 'package:healthee/shared/v02/panel_head.dart';
import 'package:healthee/shared/v02/panel_parts.dart';
import 'package:healthee/shared/v02/range_bar.dart';
import 'package:solar_icons/solar_icons.dart';

/// The prototype's closing note, verbatim. Says the one thing that matters.
const String kFourChecksNote =
    'Four independent checks, not a combined score. The 7–9h check differs '
    'from the 8h sleep-need reference.';

/// One row: what it is, what was read, what against, and how far outside.
@immutable
class SleepCheck {
  /// A single dimension of the night.
  const SleepCheck({
    required this.name,
    required this.reading,
    required this.target,
    required this.passed,
    required this.detail,
    this.bar,
  });

  /// `Duration` · `Efficiency` · `Regularity · SRI` · `Timing`.
  final String name;

  /// The measurement, already formatted, or null when there was none.
  final String? reading;

  /// The published range it was read against.
  final String target;

  /// The server's own verdict, which may be withheld.
  final Reading<bool> passed;

  /// How far outside, in words.
  final String detail;

  /// The reading on its reference track, or null when there is no reading.
  final CheckBar? bar;
}

/// `Your four sleep checks`.
class SleepChecksPanel extends StatelessWidget {
  /// [night] is the session; [cutoffs] and [notes] are the payload's.
  const SleepChecksPanel({
    required this.night,
    required this.cutoffs,
    required this.notes,
    super.key,
  });

  /// The prototype's title.
  static const String title = 'Your four sleep checks';

  /// The night being read.
  final SleepNight night;

  /// The published cutoffs, when the server sent them.
  final SleepCutoffs? cutoffs;

  /// The research notes behind them.
  final List<String> notes;

  /// The four rows, in the prototype's order.
  List<SleepCheck> get checks {
    final bands = SleepBands(cutoffs);
    return <SleepCheck>[
      SleepCheck(
        name: 'Duration',
        reading: night.tstMin.valueOrNull == null
            ? null
            : durationText(night.tstMin.valueOrNull!),
        target: bands.durationLabel,
        passed: night.pointDuration,
        detail: bands.durationDetail(night.tstMin.valueOrNull),
        bar: checkBar(
          night.tstMin.valueOrNull,
          240,
          600,
          bands.durationLowMin,
          bands.durationHighMin,
          (hoursText(4), hoursText(10)),
          '${hoursText(bands.durationLowMin / 60)} to ${hoursText(bands.durationHighMin / 60)}',
          'Under',
          'Over',
        ),
      ),
      SleepCheck(
        name: 'Efficiency',
        reading: night.efficiencyPct.valueOrNull == null
            ? null
            : '${night.efficiencyPct.valueOrNull!.toStringAsFixed(1)}%',
        target: bands.efficiencyLabel,
        passed: night.pointEfficiency,
        detail: bands.efficiencyDetail(night.efficiencyPct.valueOrNull),
        bar: checkBar(
          night.efficiencyPct.valueOrNull,
          70,
          100,
          bands.efficiencyMinPct,
          100,
          ('70%', '100%'),
          '${plainNumber(bands.efficiencyMinPct)}% or more',
          'Under',
          'Within',
        ),
      ),
      SleepCheck(
        name: 'Regularity · SRI',
        reading: night.sri.valueOrNull == null
            ? null
            : '${night.sri.valueOrNull!.round()} /100',
        target: bands.sriLabel,
        passed: night.pointRegularity,
        detail: bands.sriDetail(night.sri.valueOrNull),
        bar: checkBar(
          night.sri.valueOrNull,
          40,
          100,
          bands.sriMin,
          100,
          ('40', '100'),
          '${plainNumber(bands.sriMin)} or more',
          'Under',
          'Within',
        ),
      ),
      SleepCheck(
        name: 'Timing',
        reading: clockOfIso(night.midpointLocal.valueOrNull),
        target: bands.timingLabel,
        passed: night.pointTiming,
        detail: bands.timingDetail(night.midpointLocal.valueOrNull),
        bar: checkBar(
          sinceMidnight(
            SleepBands.midpointHour(night.midpointLocal.valueOrNull),
          ),
          0,
          8,
          bands.timingLowHour,
          bands.timingHighHour,
          ('00:00', '08:00'),
          '${clockOfHours(bands.timingLowHour)} to ${clockOfHours(bands.timingHighHour)}',
          'Early',
          'Late',
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final rows = checks;
    return Panel(
      tone: Tone.sleep,
      label: 'Sleep checks',
      head: PanelHead(
        title: title,
        icon: SolarIconsOutline.moonSleep,
        infoKey: 'sleep_health',
        detail: MetricDetail(
          references: <String>[
            for (final check in rows) '${check.name}: ${check.target}',
          ],
          notes: notes,
          method: const <String>[kFourChecksNote],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var i = 0; i < rows.length; i++)
            _CheckRow(
              check: rows[i],
              first: i == 0,
              last: i == rows.length - 1,
            ),
          const PanelNote(kFourChecksNote),
        ],
      ),
    );
  }
}

/// `.sleep-check` — the mark, the name, the reading, the range, the distance.
class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.check,
    required this.first,
    required this.last,
  });

  final SleepCheck check;
  final bool first;
  final bool last;

  /// `.sleep-check { padding:16px 0 }` with 4 at the two ends.
  static const double pad = 16;
  static const double endPad = 4;

  /// `.check-result { width:26px; height:26px; border-radius:9px }`.
  /// Between the reference line and the bar.
  static const double barGap = 10;

  /// `.sleep-check { gap:12px }`.
  static const double gap = 12;

  /// `.check-target { margin-top:4px }` · `.check-detail { margin-top:8px }`.
  static const double targetGap = 4;
  static const double detailGap = 8;

  /// The bar's own word, so the chip never contradicts the mark; a server
  /// fail the bar cannot show (a band edge rounded away) says `Missed`.
  static String _word(bool passed, String side) =>
      !passed && side == 'Within' ? 'Missed' : side;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final result = check.passed.valueOrNull;
    final row = Padding(
      padding: EdgeInsets.only(
        top: first ? endPad : pad,
        bottom: last ? endPad : pad,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: Text(
                  check.name,
                  style: SleepType.checkName.copyWith(color: colors.ink),
                ),
              ),
              const SizedBox(width: gap),
              Text(
                check.reading ?? '—',
                style: SleepType.checkValue.copyWith(
                  color: check.reading == null ? colors.ink2 : colors.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: targetGap),
          Text(
            check.target,
            style: SleepType.checkTarget.copyWith(color: colors.ink2),
          ),
          if (check.bar case final CheckBar bar) ...<Widget>[
            const SizedBox(height: barGap),
            RangeBar(
              value: bar.value,
              min: bar.min,
              max: bar.max,
              band: UsualRange(low: bar.low, high: bar.high, days: 0),
              startLabel: bar.ends.$1,
              endLabel: bar.ends.$2,
              usualLabel: bar.bandLabel,
              semanticLabel:
                  '${check.name} ${check.reading}. '
                  'Against ${check.target}.',
            ),
          ],
          const SizedBox(height: detailGap),
          // A row, not a `Wrap`: the sentence wraps BESIDE the chip, so all
          // four checks keep one shape whatever their sentence's length. A
          // `Wrap` dropped the longer sentences under the chip and left the
          // shorter ones beside it. `IntrinsicWidth` sizes the chip to its one
          // word, since a row hands a non-flex child an unbounded width.
          Row(
            children: <Widget>[
              if (result != null && check.bar != null) ...<Widget>[
                IntrinsicWidth(
                  child: VerdictChip(
                    Verdict(
                      _word(result, check.bar!.wordFor()),
                      result ? VerdictTone.neutral : VerdictTone.worse,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  check.detail,
                  style: SleepType.checkDetail.copyWith(color: colors.ink2),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    return last
        ? row
        : DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: colors.line, width: hairline),
              ),
            ),
            child: row,
          );
  }
}
