/// One definition of the steps range bar, for Today's movement card and the
/// Activity screen's movement panel.
///
/// The track runs from 0 to 12k, or past the band and the day by a margin,
/// rounded up to 2k. On a day that is not over, the band is named "by day's
/// end": a morning's count against whole days is not a verdict.
library;

import 'package:healthee/shared/format/number_labels.dart';
import 'package:healthee/shared/usual_range.dart';
import 'package:healthee/shared/v02/range_bar.dart';

/// The step track's least far end, and the step it rounds up to.
const int kStepsTrackMin = 12000;
const int kStepsTrackStep = 2000;

/// What a bar says while there is no band yet.
const String kLearningUsual = 'learning your usual';

/// The steps bar for [count] against [band]; [live] when the day is today.
RangeBar stepsBar(int count, UsualRange? band, {required bool live}) {
  final top = stepsTrackTop(count, band);
  String thousands(double steps) => '${(steps / 1000).toStringAsFixed(1)}k';
  final prefix = live ? "by day's end" : 'usual';
  return RangeBar(
    value: count.toDouble(),
    min: 0,
    max: top.toDouble(),
    band: band,
    startLabel: '0',
    endLabel: '${top ~/ 1000}k',
    usualLabel: band == null
        ? null
        : thousands(band.low) == thousands(band.high)
        ? '$prefix about ${thousands(band.low)}'
        : '$prefix ${thousands(band.low)} to ${thousands(band.high)}',
    pendingLabel: kLearningUsual,
    semanticLabel: band == null
        ? '${groupedInt(count)} steps. Your usual range is still being learned.'
        : '${groupedInt(count)} steps. Your usual range, the middle half of the '
              'last $kUsualWindowDays days, is ${groupedInt(band.low.round())} '
              'to ${groupedInt(band.high.round())} steps.',
  );
}

/// The step track's far end.
int stepsTrackTop(int count, UsualRange? band) {
  final reach = <double>[
    kStepsTrackMin.toDouble(),
    count * 1.1,
    (band?.high ?? 0) * 1.25,
  ].reduce((a, b) => a > b ? a : b);
  return (reach / kStepsTrackStep).ceil() * kStepsTrackStep;
}
