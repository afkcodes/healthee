/// Personal findings — the app's most personal claim, and its narrowest.
///
/// **Moved out of `features/insights/widgets/` on 2026-08-05.** `/api/sleep`
/// returns its own `findings` array — sleep-scoped correlations from the same
/// `read/findings.py::_shape`, the same `Finding` model — and Sleep may not
/// import from Insights (Standards §3: nothing reaches into another feature).
/// Two features needing one widget is what `shared/` is for; the alternative was
/// a second copy of the wording rules, which is the one thing this file's
/// docstring spends four screens arguing against.
///
/// These are correlations discovered in **this one owner's** data. Brief §5.9
/// requires the label to say so, and it is not a disclaimer bolted on: the
/// finding was found by searching many metric pairs across one person's history,
/// so the sample size and the multiple-comparison correction are part of the
/// claim rather than footnotes to it.
///
/// So the wording is **"moved with"**, never "helps" or "improves". Those are
/// causal verbs and this is an observational n-of-1 — the exact over-reach the
/// whole evidence apparatus exists to prevent.
///
/// ## What this file used to render, and why it was wrong
///
/// It printed `Finding.description` as the headline. That field is the server's
/// `description_raw`, and `analytics/correlations.py::_pairwise_finding` builds it
/// like this:
///
/// ```python
/// desc = f"Spearman({a}, {b}) = {rho:+.2f} over {n} days (p={p:.3f})"
/// ```
///
/// which reached the owner's home screen verbatim as
///
/// > Spearman(hrv_sleep_avg, recovery_score) = +0.72 over 105 days (p=0.000)
/// > — they moved together
///
/// with a second line of `spearman_r 0.72 · over 105 days · same day · q = 0.000
/// after correcting for the search` under it. Two renderings of the same numbers,
/// neither of them a sentence.
///
/// The server's own read layer calls the shape it sends *"structured fields for a
/// plain-English card"* (`read/findings.py::_shape`) and names that string `_raw`.
/// The plain-English card is this file's job and it was not doing it.
///
/// ## What it renders now, and what did NOT change
///
/// The headline is the finding in the owner's language — which two metrics, which
/// direction — with one line of context under it for the window and the lag. The
/// coefficient, the correction, the lag in full and the raw server string are all
/// still here, one tap away behind [ReasoningNote], in the same spirit as the
/// VO₂max card's "Why this instrument, and not another".
///
/// **The honesty did not move.** The single-subject/observational framing is still
/// on the surface, above the findings, where it cannot be collapsed. No verb in
/// the rewrite is causal — the metrics are joined by "moved with" and "moved
/// opposite to" — and the disclosure repeats the point in its last paragraph so a
/// reader who opens it for the arithmetic gets the caveat with it. Trading the
/// caveat for readability is the one way this change could have made things worse.
///
/// Renders nothing when there are no findings. An empty heading over a blank card
/// reads as breakage; the honest state is silence.
///
/// ## The source chips moved to the ⓘ — 2026-09-07
///
/// The owner, for the second time: *"as i have stated previously to remove that
/// reference pills from everywhere it seems you forgot that"*. This file was the
/// one still drawing them, and because **Insights and Sleep both render it**, one
/// missed widget put chips back on two screens. That is why the sweep is now a
/// gate (`test/features/citation_sweep_test.dart`) rather than another pass.
///
/// Each finding's citations went into **its own** [MetricInfoDot], not a single
/// dot on the card: two findings on one card cite different notes, and one merged
/// sheet would tell the reader that either finding is backed by either source.
/// A finding citing nothing draws no dot — there is nothing behind it, and an
/// ⓘ opening an empty sheet is worse than none.
///
/// **[kSingleSubjectFraming] did not move.** It is not provenance; it is the
/// qualification that makes every headline on the card readable, and it stays on
/// the face where it cannot be collapsed.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/data/models/finding.dart';
import 'package:healthee/shared/format/metric_names.dart';
import 'package:healthee/shared/metric_info/metric_detail.dart';
import 'package:healthee/shared/metric_info/metric_info_sheet.dart';
import 'package:healthee/shared/states/citation_row.dart';
import 'package:healthee/shared/states/state_scaffold.dart';

/// What the analytics layer found in the owner's own history.
class FindingsSection extends StatelessWidget {
  /// [findings] may be empty, in which case nothing renders.
  const FindingsSection({required this.findings, super.key});

  /// The findings, strongest first.
  final List<Finding> findings;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    if (findings.isEmpty) {
      return const SizedBox.shrink();
    }
    return StateCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('In your own data', style: text.labelSmall),
          const SizedBox(height: Insets.xs),
          // The one wording, shared with every `[personal_finding:…]` chip a
          // cited answer draws (`citation_row.dart`). Two copies of a caveat is
          // one copy that can be softened without the other moving.
          Text(
            kSingleSubjectFraming,
            style: text.bodySmall?.copyWith(color: colors.ink2),
          ),
          for (final finding in findings) ...[
            Divider(color: colors.line2, height: Insets.xl, thickness: hairline),
            _FindingRow(finding: finding),
          ],
        ],
      ),
    );
  }
}

class _FindingRow extends StatelessWidget {
  const _FindingRow({required this.finding});

  final Finding finding;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final headline = findingHeadline(finding);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // Which way they moved, as a mark rather than a clause
                  // buried mid-sentence. Five of these read as five paragraphs
                  // of near-identical prose; the chip is what makes the card
                  // scannable without touching the wording, which IS the
                  // honesty contract here.
                  _DirectionChip(effect: finding.effectSize),
                  const SizedBox(height: Insets.xs),
                  Text(headline, style: text.titleSmall),
                ],
              ),
            ),
            FindingInfoDot(finding),
          ],
        ),
        const SizedBox(height: Insets.xs),
        Text(
          findingWindow(finding),
          style: text.bodySmall?.copyWith(color: colors.ink2),
        ),
      ],
    );
  }
}

/// The ⓘ beside a finding: its sources and its arithmetic, and nothing on the
/// face of the card.
///
/// Shared by every surface that draws a finding, so the citations and the
/// statistic are reached the same way wherever the finding appears.
class FindingInfoDot extends StatelessWidget {
  /// The dot for [finding].
  const FindingInfoDot(this.finding, {super.key});

  /// The finding it explains.
  final Finding finding;

  @override
  Widget build(BuildContext context) {
    final headline = findingHeadline(finding);
    return MetricInfoDot(
      // No explainer key: a correlation found in one person's history is not a
      // metric the corpus has an entry for. The detail IS the content, which is
      // the case `MetricInfoDot` draws itself for.
      null,
      detail: MetricDetail(
        title: headline,
        notes: finding.researchNoteIds,
        // **The arithmetic lives here, not on the face.** It was an inline `The
        // statistic behind this ⌄` on every row — five findings meant five
        // collapsed disclosures stacked down the card. The ⓘ is where every
        // other surface in this app keeps its method.
        method: findingStatistics(finding).split('\n\n'),
      ),
      fallbackTitle: headline,
    );
  }
}

/// `OPPOSITE` / `TOGETHER` — the direction, as a mark.
class _DirectionChip extends StatelessWidget {
  const _DirectionChip({required this.effect});

  static const EdgeInsets padding = EdgeInsets.symmetric(
    horizontal: 7,
    vertical: 2,
  );

  /// Signed. Null draws nothing — a finding with no effect size has no
  /// direction, and a chip guessing one would be the whole claim invented.
  final double? effect;

  @override
  Widget build(BuildContext context) {
    final size = effect;
    if (size == null) {
      return const SizedBox.shrink();
    }
    final colors = context.colors;
    final opposite = size < 0;
    // `unf`/`fav` are the app's verdict pair and this is NOT a verdict — two
    // metrics moving opposite is not bad news. The family carries it instead.
    final hue = colors.accent;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: hue.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Padding(
        padding: padding,
        child: Text(
          opposite ? 'OPPOSITE' : 'TOGETHER',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: hue,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }
}

/// The finding as a sentence: which two things, and which way they moved.
///
/// Deliberately non-causal. See the library docstring. Public because the tests
/// assert on the wording directly — the wording IS the honesty contract here, and
/// pumping a widget to read it back would test the layout instead.
String findingHeadline(Finding finding) {
  final a = finding.metricA;
  final b = finding.metricB;
  if (a == null) {
    return 'A pattern in your own data';
  }
  // An event finding carries one metric and an event kind, not a pair.
  if (b == null) {
    final event = finding.eventKind;
    return event == null
        ? 'Your ${metricName(a)}, on the days it was recorded'
        : 'Your ${metricName(a)} on $event days, against your other days';
  }
  final joiner = switch (finding.effectSize) {
    final double size when size < 0 => 'moved opposite to',
    _ => 'moved with',
  };
  return 'Your ${metricName(a)} $joiner your ${metricName(b)}';
}

/// The one line of context under the headline: how strong, over how much, at
/// what lag.
///
/// The strength is a word rather than a coefficient — the number belongs behind
/// the disclosure with the rest of the arithmetic, and "closely" is what 0.72
/// means to somebody who is not going to look it up. The bands are the
/// conventional ones for a rank correlation and nothing about this owner.
String findingWindow(Finding finding) {
  final parts = <String>[
    if (_strength(finding.effectSize) case final String word) word,
    if (finding.nSamples case final int n) 'across $n days of your own history',
    if (finding.lagDays case final int lag when lag != 0)
      'strongest $lag day${lag == 1 ? '' : 's'} apart',
  ];
  if (parts.isEmpty) {
    return 'Found in your own history.';
  }
  final first = parts.first;
  final rest = parts.skip(1);
  return '${first[0].toUpperCase()}${first.substring(1)}'
      '${rest.isEmpty ? '' : ', ${rest.join(', ')}'}.';
}

/// Everything a reader who wants the arithmetic would ask for — and, last, the
/// caveat again, so opening the numbers never means leaving the framing behind.
String findingStatistics(Finding finding) {
  final lines = <String>[
    if (finding.effectSize case final double size)
      '${finding.effectMetric ?? 'Effect'} = ${size.toStringAsFixed(2)}, on a '
          'scale from −1 to +1.',
    if (finding.nSamples case final int n)
      'Computed over $n days on which both were recorded.',
    if (finding.lagDays case final int lag)
      lag == 0
          ? 'Same day: both values come from the same calendar day.'
          : 'Lagged $lag day${lag == 1 ? '' : 's'}: the second value is taken '
                '$lag day${lag == 1 ? '' : 's'} after the first.',
    if (finding.qValue case final double q)
      'q = ${q.toStringAsFixed(3)} after correcting for the size of the search. '
          'Many pairs of metrics were tested, so an uncorrected p-value would '
          'find "significant" patterns in noise. This is the corrected one.',
    'One person, one stretch of time, nothing controlled. It says the two moved '
        'together — not that either one caused the other.',
  ];
  return lines.join('\n\n');
}

/// The conventional band for a rank correlation, as a word.
String? _strength(double? effect) {
  if (effect == null) {
    return null;
  }
  final size = effect.abs();
  if (size >= 0.6) {
    return 'closely';
  }
  if (size >= 0.4) {
    return 'moderately';
  }
  return 'weakly';
}
