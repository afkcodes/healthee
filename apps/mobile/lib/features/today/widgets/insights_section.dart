/// `Insights` — the correlations found in the owner's own data.
///
/// **Ported from** `healthee-legacy/app/lib/ui/today_screen.dart:1512` —
/// `_InsightsSection`, `_describeFinding` (1477), `_trivialFinding` (1497) and
/// `_metricFriendly` (1467). One `Pattern` module per finding, at most four, each
/// with the strength in the header, the sentence at display size, and `rho 0.62 ·
/// 105 days of your data` as its foot.
///
/// ```text
///   PATTERN                                    VERY CONSISTENT
///   When your HRV is higher, your steps are usually higher the next day.
///   RHO 0.71 · 105 DAYS OF YOUR DATA
/// ```
///
/// **Two departures from legacy, both in the honesty layer and both deliberate.**
/// Legacy wrote the letter `r` into that foot whatever statistic it was, and
/// printed the server's raw `description_raw` string as the headline whenever a
/// finding carried one metric rather than a pair. See [findingFoot] and
/// [describeFinding] for what each of those said on screen and why neither is a
/// design change.
///
/// ## The trivial filter is doing real work and is ported exactly
///
/// `_trivialFinding` drops pairs that are definitionally derived from each other
/// — two activity metrics (all of which come from the same step stream), two
/// sleep-dimension metrics, a sleep dimension against regularity, and **any pair
/// with |r| ≥ 0.97**, which legacy annotates `near-perfect = definitional`. Every
/// one of those would otherwise read as a discovery about the owner rather than
/// as arithmetic.
///
/// ## What legacy's sign does and does not say, and why no colour is spent
///
/// The header chip is the accent at every strength and the row draws no verdict
/// colour at all. That is legacy's (`today_screen.dart:1540`), and it is the
/// restraint `apps/mobile/README.md` describes: the sign of a rank correlation
/// says *moved together* or *moved opposite*, which is a direction and not a
/// verdict, and a q-corrected correlation over one person's history cannot
/// support "this is good for you".
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/instrument_type.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/data/models/finding.dart';
import 'package:healthee/features/today/widgets/finding_prose.dart';
import 'package:healthee/shared/format/metric_names.dart';
import 'package:healthee/shared/instrument_module.dart';
import 'package:healthee/shared/v02/metric_tone.dart';
import 'package:solar_icons/solar_icons.dart';

/// The prose half moved to `finding_prose.dart` at the 400-line gate (Standards
/// section 1). It is a clean seam rather than a cut: those are pure functions
/// deciding WHAT a finding says, and what is left here decides how it looks.
/// Re-exported so every call site and its tests are unchanged.
export 'package:healthee/features/today/widgets/finding_prose.dart';

/// At most four non-trivial patterns, or the sentence that says there are none.
class InsightsSection extends StatelessWidget {
  /// [findings] is `top_findings`, in server order.
  const InsightsSection({required this.findings, super.key});

  /// Every finding the server raised.
  final List<Finding> findings;

  /// Legacy's `.take(4)`.
  static const int maxShown = 4;

  /// The sentence when nothing survives the filter.
  static const String nothingYet =
      'No clear patterns in your data yet — keep wearing the strap and they’ll '
      'surface here.';

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final real = [
      for (final finding in findings)
        if (!isTrivialFinding(finding)) finding,
    ].take(maxShown).toList();
    if (real.isEmpty) {
      return InstrumentModule(
        label: '',
        tag: null,
        minHeight: 0,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(nothingYet, style: HType.sans(colors.ink2, size: 13.5)),
          ),
        ],
      );
    }
    return Column(
      children: [
        for (final finding in real)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _FindingRow(finding: finding),
          ),
      ],
    );
  }
}

/// The air inside a pattern card, tighter than a lone module's.
const EdgeInsets _padding = EdgeInsets.symmetric(horizontal: 14, vertical: 11);

/// Between the subjects, the sentence and the foot.
const double _blockGap = 6;

/// One pattern, its sentence and its arithmetic.
class _FindingRow extends StatelessWidget {
  const _FindingRow({required this.finding});

  final Finding finding;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final effect = (finding.effectSize ?? 0).abs();
    // **No header row.** It carried the word `PATTERN` on every card, under a
    // section head that already says `Your patterns` — the same word four times
    // under its own title — and the strength chip opposite it. The strength is
    // real and stays; it joins the foot, which is where the rest of this
    // finding's provenance already is. One row saved on every card.
    return InstrumentModule(
      tag: colors.accent,
      minHeight: 0,
      // Tighter than a module's default. These stack four deep under one
      // heading, and the default padding is sized for a card that stands alone.
      padding: _padding,
      children: [
        // **The two metrics, as the card's subject.** A pattern is a
        // relationship between two of the owner's own readings, and the card
        // said so only inside a sentence — so four findings were four grey
        // boxes of prose, scannable one at a time and never as a set.
        if (_pair(finding) case final List<String> pair) ...<Widget>[
          _Subjects(pair),
          const SizedBox(height: _blockGap),
        ],
        Text(
          describeFinding(finding).headline,
          // 15/1.3, not 16/1.4. Two lines of serif is most of one of these
          // cards, so the leading is where the height is.
          style: HType.serif(colors.ink, size: 15),
        ),
        const SizedBox(height: _blockGap),
        Row(
          children: <Widget>[
            _Strength(effect),
            const SizedBox(width: 8),
            Expanded(child: ModuleFoot(findingFoot(finding))),
          ],
        ),
      ],
    );
  }
}

/// The pair this finding relates, or null when it is not about two metrics.
///
/// Both must be NAMEABLE. A chip printing `rhr_daily` is a log line where a
/// subject belongs, and the same rule already governs `signalLabel` on a
/// suggestion card: an id the app has no owner-facing word for is not shown as
/// though it were one.
List<String>? _pair(Finding finding) {
  final a = finding.metricA;
  final b = finding.metricB;
  if (a == null || b == null || !hasMetricName(a) || !hasMetricName(b)) {
    return null;
  }
  return <String>[a, b];
}

/// The two metrics, each in ITS OWN family colour.
///
/// **This is subject identity, not a verdict**, which is the only thing that
/// makes it legal here. `apps/mobile/README.md` is explicit that a finding may
/// not turn its sign into a verdict and that flipping the coefficient must
/// change no colour — these hues say *which reading*, and they are identical
/// whether the two moved together or opposite.
class _Subjects extends StatelessWidget {
  const _Subjects(this.pair);

  final List<String> pair;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Flexible(child: _Chip(pair.first)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Icon(
          SolarIconsOutline.arrowRight,
          size: 11,
          color: context.colors.ink2,
        ),
      ),
      Flexible(child: _Chip(pair.last)),
    ],
  );
}

class _Chip extends StatelessWidget {
  const _Chip(this.metric);

  final String metric;

  @override
  Widget build(BuildContext context) => ToneScope(
    tone: toneForMetric(metric),
    child: Builder(
      builder: (context) => Text(
        metricName(metric).toUpperCase(),
        style: HType.label(context.family),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
  );
}

/// The strength as four steps, at the bands [strengthLabel] already uses.
///
/// The word alone was the only thing separating a 0.79 from a 0.53, in grey, at
/// the end of a foot line — so four findings ranked by strength looked identical
/// to each other. **The bands are not a second scale**: this reads the same
/// thresholds, so the mark and the word can never disagree.
class _Strength extends StatelessWidget {
  const _Strength(this.effect);

  final double effect;

  /// Filled steps, from [strengthLabel]'s own bands.
  int get steps => switch (strengthLabel(effect)) {
    'very consistent' => 4,
    'consistent' => 3,
    'fairly consistent' => 2,
    _ => 1,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var i = 0; i < 4; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: 2),
          SizedBox(
            width: 6,
            height: 3,
            child: ColoredBox(
              color: i < steps ? colors.accent : colors.surface2,
            ),
          ),
        ],
      ],
    );
  }
}
