/// What a pairwise finding says in words and numbers, with no widget in it.
///
/// Pure functions, so the wording and the strength bands are asserted directly.
/// Nothing here derives a verdict from a sign: a correlation is a direction,
/// and the only colours it earns are the together and opposite hues.
library;

import 'package:flutter/painting.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/data/models/finding.dart';
import 'package:healthee/shared/format/age_lever_format.dart';
import 'package:healthee/shared/format/metric_names.dart';
import 'package:healthee/shared/v02/metric_tone.dart';

/// The fewest paired days a correlation needs to be drawn as a number. Below
/// it the row says how few there are and draws no bar.
const int kMinPairedDays = Finding.minPlottablePoints;

/// A finding that is a correlation between two metrics: both named, with an
/// effect size. An event finding compares two groups of days, so its effect is
/// not an `r` and is never drawn on the correlation scale.
bool isPair(Finding finding) =>
    finding.metricA != null &&
    finding.metricB != null &&
    finding.effectSize != null;

/// Whether [finding] has so few paired days that no number is drawn for it.
/// An unknown count is not "few": the row draws and simply states no count.
bool isTooFew(Finding finding) =>
    finding.nSamples != null && finding.nSamples! < kMinPairedDays;

/// Whether [finding] is a pair with enough paired days behind it to draw.
bool isDrawablePair(Finding finding) => isPair(finding) && !isTooFew(finding);

/// The strongest drawable pair, by magnitude, or null when there is none.
Finding? strongestPair(Iterable<Finding> findings) {
  Finding? best;
  for (final finding in findings) {
    if (!isDrawablePair(finding)) {
      continue;
    }
    if (best == null || finding.effectSize!.abs() > best.effectSize!.abs()) {
      best = finding;
    }
  }
  return best;
}

/// The conventional bands, as the row's caption words.
///
/// The old two-way split (0.6 and 0.4, "closely" and "moderately") keeps both
/// of its edges; the top band is split at 0.8 so a 0.88 reads "very strong"
/// and a 0.64 "strong".
String strengthWord(double r) {
  final size = r.abs();
  if (size >= 0.8) {
    return 'very strong';
  }
  if (size >= 0.6) {
    return 'strong';
  }
  if (size >= 0.4) {
    return 'moderate';
  }
  return 'weak';
}

/// `−0.88` or `+0.82`: a real minus, two decimals, a plus on a positive.
String signedR(double r) => signedYears(r, digits: 2);

/// [signedR] as a span whose sign is tightened against the digits.
TextSpan signedRSpan(double r, TextStyle style) =>
    signedYearsSpan(r, style, digits: 2);

/// `Move opposite · very strong` / `Move together · strong`.
String directionCaption(double r) =>
    'Move ${r < 0 ? 'opposite' : 'together'} · ${strengthWord(r)}';

/// `↑↓` for a pair that moves opposite, `↑↑` for one that moves together.
String directionGlyphs(double r) => r < 0 ? '↑↓' : '↑↑';

/// `67 days`, `1 day`.
String daysLabel(int n, {String unit = 'day'}) =>
    '$n $unit${n == 1 ? '' : 's'}';

/// Metrics measured once per night, so a pair that includes one is counted in
/// nights rather than days.
bool _overnight(String? metric) =>
    metric != null &&
    (metric.startsWith('sleep_') ||
        const <String>{
          'hrv_sleep_avg',
          'tst_min',
          'efficiency_pct',
          'respiratory_rate_sleep',
          'spo2_overnight',
          'spo2_overnight_min',
        }.contains(metric));

/// `day` or `night`: what one paired point is.
String pairUnit(Finding finding) =>
    _overnight(finding.metricA) || _overnight(finding.metricB)
    ? 'night'
    : 'day';

/// `Recovery`, `Recovery next day`, `Recovery 2 days later`: the second metric
/// with the lag the pair was strongest at.
String laggedName(Finding finding) {
  final name = pairName(finding.metricB!);
  return switch (finding.lagDays ?? 0) {
    <= 0 => name,
    1 => '$name next day',
    final lag => '$name $lag days later',
  };
}

const Map<String, String> _short = <String, String>{
  'rhr_daily': 'Resting HR',
  'hrv_sleep_avg': 'HRV',
  'recovery_score': 'Recovery',
  'sleep_regularity_index': 'Sleep regularity',
  'sleep_health_score_4dim': 'Sleep health',
  'vo2max_estimate': 'VO₂max',
};

/// The colour family a metric's name is drawn in. Recovery has no hue of its
/// own (neutral ink, judged by zone), so `recovery_score` takes that family
/// rather than the Body fallback every unlisted id would get.
Tone pairTone(String metric) =>
    metric == 'recovery_score' ? Tone.recovery : toneForMetric(metric);

/// The name as a tile label: `Resting HR`, `Recovery`, `Sleep regularity`.
String pairName(String metric) => _short[metric] ?? metricTitle(metric);

/// [pairName] mid-sentence: `RHR`, `HRV`, `recovery`.
String pairPhrase(String metric) {
  if (metric == 'rhr_daily') {
    return 'RHR';
  }
  final name = pairName(metric);
  return name.length > 1 &&
          name[1] == name[1].toUpperCase() &&
          name[1] != name[1].toLowerCase()
      ? name
      : '${name[0].toLowerCase()}${name.substring(1)}';
}

/// `Lower resting HR, higher recovery · 67 days`: the direction in plain words
/// with the number of days behind it. Never a causal verb.
String pairSentence(Finding finding) {
  final r = finding.effectSize!;
  final a = pairPhrase(finding.metricA!);
  final b = pairPhrase(finding.metricB!);
  final first = r < 0 ? 'Lower' : 'Higher';
  final n = finding.nSamples;
  final count = n == null ? '' : ' · ${daysLabel(n, unit: pairUnit(finding))}';
  return '$first $a, higher $b$count';
}
