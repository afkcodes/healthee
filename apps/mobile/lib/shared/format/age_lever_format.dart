/// The one definition of how a biological-age lever is written down: signed
/// years, the verdict a delta earns, and a lever's value, unit and name.
///
/// Here, and nowhere else, so the lever card, the Today hero, the ruler and
/// the sphere centre cannot disagree about when `-0.4 years` stops being
/// "younger". Payload units are mapped for display in [leverValue] only.
library;

import 'package:flutter/painting.dart';
import 'package:healthee/data/models/biological_age.dart';
import 'package:healthee/shared/v02/key_number_card.dart';

/// A delta of at least this many years either way is a verdict.
const double kAgeVerdictYears = 0.5;

/// Figtree's minus sign is as wide as a digit; the sign is pulled in by this
/// fraction of the font size so `-1.7` does not read as `- 1.7`.
const double kMinusTrackingEm = -0.14;

/// The true minus sign (U+2212). Never a hyphen on a number.
const String kMinus = '−';

/// A non-breaking space, joining a number to its unit.
const String kNbsp = ' ';

/// `-1.7`, `+2.1`, `0.0`: a real minus, a plus only when there is a gain, and
/// no sign at all on a value that rounds to zero.
String signedYears(double delta, {int digits = 1}) {
  final text = delta.abs().toStringAsFixed(digits);
  if (double.parse(text) == 0) {
    return 0.0.toStringAsFixed(digits);
  }
  return '${delta < 0 ? kMinus : '+'}$text';
}

/// [signedYears] as it is spoken: `minus 1.7 years`, `plus 2.1 years`,
/// `0.0 years`.
String spokenYears(double delta) {
  final text = signedYears(delta);
  if (text.startsWith(kMinus)) {
    return 'minus ${text.substring(1)} years';
  }
  return text.startsWith('+')
      ? 'plus ${text.substring(1)} years'
      : '$text years';
}

/// [signedYears] as a span whose sign is its own child, tightened by
/// [kMinusTrackingEm] of the font size. [style] must carry a `fontSize`.
TextSpan signedYearsSpan(double delta, TextStyle style, {int digits = 1}) {
  final text = signedYears(delta, digits: digits);
  final signed = text.startsWith(kMinus) || text.startsWith('+');
  if (!signed) {
    return TextSpan(text: text, style: style);
  }
  return TextSpan(
    style: style,
    children: <InlineSpan>[
      TextSpan(
        text: text.substring(0, 1),
        style: TextStyle(letterSpacing: kMinusTrackingEm * style.fontSize!),
      ),
      TextSpan(text: text.substring(1)),
    ],
  );
}

/// The verdict a delta in years earns: better at or below -0.5, worse at or
/// above +0.5, neutral between.
VerdictTone verdictForDelta(double delta) {
  if (delta <= -kAgeVerdictYears) {
    return VerdictTone.better;
  }
  if (delta >= kAgeVerdictYears) {
    return VerdictTone.worse;
  }
  return VerdictTone.neutral;
}

/// A lever's display value and unit.
///
/// Fitness is mL/kg/min. Sleep duration is read at the value the hazard curve
/// used ([AgeContribution.comparedAs]), in hours. An unknown term keeps the
/// payload's unit verbatim.
({String value, String unit}) leverValue(AgeContribution c) {
  final term = c.term.toLowerCase();
  if (term == 'fitness') {
    return (value: _one(c.value), unit: 'mL/kg/min');
  }
  if (term.contains('sleep')) {
    return (value: _one(c.comparedAs ?? c.value), unit: 'h');
  }
  return (value: _one(c.value), unit: c.unit ?? '');
}

String _one(double? v) => v == null ? '' : v.toStringAsFixed(1);

/// The row's name, to be uppercased by the Label's caller.
String leverLabel(String term) {
  final lower = term.toLowerCase();
  if (lower == 'fitness') {
    return 'Fitness · VO₂max';
  }
  if (lower.contains('sleep')) {
    return 'Sleep duration';
  }
  return _capitalised(term);
}

/// The short name used in the collapsed summary: `Fitness`, `Sleep`, or the
/// capitalised term.
String leverShortName(String term) {
  final lower = term.toLowerCase();
  if (lower == 'fitness') {
    return 'Fitness';
  }
  if (lower.contains('sleep')) {
    return 'Sleep';
  }
  return _capitalised(term);
}

String _capitalised(String term) {
  final words = term.replaceAll('_', ' ').trim();
  return words.isEmpty ? term : words[0].toUpperCase() + words.substring(1);
}

/// A whole number without decimals, else one decimal: `7`, `7.5`.
String plainNumber(double v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
