/// `Every stage, accounted for` as the approved redesign draws it
/// (`design/mobile-preview/proposal.js::stageRows`).
///
/// One strip of the night's proportions, then one row per stage: its name, the
/// minutes it ran, its share, and a bar as long as its minutes against the
/// longest on the panel. A small ink mark on each bar is the owner's own
/// average for that stage over the fortnight before this night, and the line
/// under it says the difference in minutes. With fewer than seven earlier
/// nights staged there is no mark and no line: an average of three nights is
/// not "your average".
///
/// ## Why the strip came back
///
/// It had been cut as a second drawing of the rows' percentages. The rows now
/// carry minutes against the owner's average, so the strip is the only place
/// the four shares are seen together, and the owner approved it.
///
/// There is still no per-stage reference range: `packages/knowledge` has no
/// note for one, so the comparison is only ever with the owner's own nights.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/instrument_hues.dart';
import 'package:healthee/core/theme/sleep_type_scale.dart';
import 'package:healthee/core/theme/stage_colors.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/shared/format/duration.dart';

/// The four rows, in the order the night is read: awake at the top, deep last.
const List<String> kShareOrder = <String>['awake', 'rem', 'light', 'deep'];

/// What the mark means, said under the rows when there is one.
const String kStageAverageNote =
    'The small mark on each bar is your average for that stage over the '
    'nights before this one.';

/// The strip and the four rows.
class StageShares extends StatelessWidget {
  /// [minutes] is per stage; [total] is what the shares are taken against.
  const StageShares({
    required this.minutes,
    required this.total,
    this.averages = const <String, double>{},
    super.key,
  });

  /// Minutes per stage, in the app's own stage names.
  final Map<String, double> minutes;

  /// The denominator. Callers guarantee it is above zero.
  final double total;

  /// The owner's average minutes per stage. Empty draws no marks.
  final Map<String, double> averages;

  /// The strip's height and the bars'.
  static const double stripHeight = 10;
  static const double barHeight = 8;

  /// Between rows, and inside one.
  static const double rowGap = 16;
  static const double innerGap = 6;

  /// Under this many minutes apart, a stage is said to be about its average.
  static const double same = 5;

  @override
  Widget build(BuildContext context) {
    final longest = <double>[
      ...minutes.values,
      ...averages.values,
    ].fold<double>(1, (a, b) => a > b ? a : b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _strip(context),
        for (final stage in kShareOrder) ...<Widget>[
          const SizedBox(height: rowGap),
          _row(context, stage, longest),
        ],
      ],
    );
  }

  Widget _strip(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(stripHeight / 2),
    child: SizedBox(
      height: stripHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final stage in kShareOrder.reversed)
            if ((minutes[stage] ?? 0) > 0)
              Expanded(
                flex: (minutes[stage]! * 10).round(),
                child: ColoredBox(color: sleepStageColor(context.hues, stage)),
              ),
        ],
      ),
    ),
  );

  Widget _row(BuildContext context, String stage, double longest) {
    final colors = context.colors;
    final hue = sleepStageColor(context.hues, stage);
    final ran = minutes[stage] ?? 0;
    final average = averages[stage];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            SizedBox.square(
              dimension: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(color: hue, shape: BoxShape.circle),
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                sleepStageLabel(stage),
                style: SleepType.tableCell.copyWith(color: colors.ink2),
              ),
            ),
            Text(
              durationText(ran),
              style: SleepType.shareDuration.copyWith(color: colors.ink),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 34,
              child: Text(
                '${(100 * ran / total).round()}%',
                textAlign: TextAlign.end,
                style: SleepType.tableCell.copyWith(color: colors.ink2),
              ),
            ),
          ],
        ),
        const SizedBox(height: innerGap),
        LayoutBuilder(
          builder: (context, box) => SizedBox(
            height: 14,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: <Widget>[
                Container(
                  height: barHeight,
                  decoration: BoxDecoration(
                    color: colors.surface2,
                    borderRadius: BorderRadius.circular(barHeight / 2),
                  ),
                ),
                Container(
                  key: ValueKey<String>('stage-bar-$stage'),
                  height: barHeight,
                  width: box.maxWidth * ran / longest,
                  decoration: BoxDecoration(
                    color: hue,
                    borderRadius: BorderRadius.circular(barHeight / 2),
                  ),
                ),
                if (average != null)
                  Positioned(
                    left: (box.maxWidth * average / longest - 1).clamp(
                      0,
                      box.maxWidth - 2,
                    ),
                    top: 0,
                    bottom: 0,
                    child: SizedBox(
                      width: 2,
                      child: ColoredBox(color: colors.ink),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (average != null) ...<Widget>[
          const SizedBox(height: innerGap),
          Text(
            '${_against(ran, average)} (${durationText(average)})',
            style: SleepType.tableCell.copyWith(color: colors.ink2),
          ),
        ],
      ],
    );
  }

  static String _against(double ran, double average) {
    final gap = (ran - average).round();
    if (gap.abs() < same) {
      return 'About your average';
    }
    return '${gap.abs()} min ${gap > 0 ? 'more' : 'less'} than your average';
  }
}
