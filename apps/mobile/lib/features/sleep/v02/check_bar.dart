/// A sleep check's track: the reading against its reference band.
///
/// Split out of `checks_panel.dart` at the 400-line gate. The bands are the
/// server's cutoffs (`sleep_cutoffs.dart`); nothing here decides a pass or a
/// fail, which stays the server's `point_*` fields.
library;

import 'package:flutter/foundation.dart';

/// One check's track: where the reading sits against its reference band.
@immutable
class CheckBar {
  /// [value] on a [min]–[max] track with the reference [low]–[high] shaded.
  const CheckBar({
    required this.value,
    required this.min,
    required this.max,
    required this.low,
    required this.high,
    required this.ends,
    required this.bandLabel,
    required this.below,
    required this.above,
  });

  final double value;
  final double min;
  final double max;
  final double low;
  final double high;

  /// The two end labels.
  final (String, String) ends;

  /// The reference band, named under it.
  final String bandLabel;

  /// The verdict's word when the reading is under, or over, the band.
  final String below;
  final String above;

  /// `Within`, or the side's own word when outside.
  String wordFor() => value < low
      ? below
      : value > high
      ? above
      : 'Within';
}

CheckBar? checkBar(
  double? value,
  double min,
  double max,
  double low,
  double high,
  (String, String) ends,
  String bandLabel,
  String below,
  String above,
) => value == null
    ? null
    : CheckBar(
        value: value,
        min: min,
        max: max,
        low: low,
        high: high,
        ends: ends,
        bandLabel: bandLabel,
        below: below,
        above: above,
      );

/// An evening midpoint reads as before midnight: 23:30 is -0.5, not 23.5.
double? sinceMidnight(double? hour) =>
    hour == null ? null : (hour > 12 ? hour - 24 : hour);

String plainNumber(double value) => value == value.roundToDouble()
    ? value.round().toString()
    : value.toStringAsFixed(1);

String clockOfHours(double hours) =>
    '${hours.floor().toString().padLeft(2, '0')}:'
    '${((hours - hours.floor()) * 60).round().toString().padLeft(2, '0')}';
