/// What moved together: the correlations found in the owner's own history, in
/// one card of hairline-divided rows.
///
/// Each row names the two metrics with a direction glyph (`↑↓` moved opposite,
/// `↑↑` moved together), prints the signed `r` in the correlation's own colour
/// and draws it from zero. Blue is together and orange is opposite; neither is
/// good or bad, so nothing here ever takes the better or worse colours.
///
/// ## What is withheld, and why
///
/// A pair with fewer than [kMinPairedDays] paired days has no number and no
/// bar, only a grey "1 entry · too few" chip: two points make a perfect line
/// whatever the data is. An event finding compares two groups of days, so its
/// effect is not an `r`: it is named, counted and left without a bar rather
/// than drawn on a scale it does not belong to.
///
/// The sources and the arithmetic are one tap away behind each row's ⓘ
/// (`FindingInfoDot`), and the footnote keeps the single-subject framing on the
/// face where it cannot be collapsed.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/instrument_hues.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/data/models/finding.dart';
import 'package:healthee/features/insights/v02/pair_reading.dart';
import 'package:healthee/shared/charts/v02/diverging_bar.dart';
import 'package:healthee/shared/findings_section.dart' show FindingInfoDot;
import 'package:healthee/shared/format/metric_names.dart';
import 'package:healthee/shared/v02/reading_chip.dart';
import 'package:healthee/shared/v02/reading_state.dart';
import 'package:healthee/shared/v02/surface_panels.dart';

/// The words under the card.
const String kObservedFootnote =
    'Observed in your history, not cause and effect.';

/// The card: one row per finding, in the order the server sent them.
class MovedTogetherCard extends StatelessWidget {
  /// [findings] may be empty, in which case nothing renders.
  const MovedTogetherCard({required this.findings, super.key});

  /// The findings, strongest first.
  final List<Finding> findings;

  @override
  Widget build(BuildContext context) {
    if (findings.isEmpty) {
      return const SizedBox.shrink();
    }
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (var i = 0; i < findings.length; i++) ...<Widget>[
                if (i > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: Insets.md),
                    child: Divider(
                      height: hairline,
                      thickness: hairline,
                      color: colors.line,
                    ),
                  ),
                MovedTogetherRow(finding: findings[i]),
              ],
            ],
          ),
        ),
        const SizedBox(height: Insets.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Insets.xs),
          child: Text(
            kObservedFootnote,
            style: TypeLadder.caption.copyWith(color: colors.ink2),
          ),
        ),
      ],
    );
  }
}

/// One finding as a row.
class MovedTogetherRow extends StatelessWidget {
  /// Draws [finding].
  const MovedTogetherRow({required this.finding, super.key});

  /// The finding.
  final Finding finding;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hues = context.hues;
    final r = isPair(finding) ? finding.effectSize : null;
    final tooFew = isTooFew(finding);
    final drawn = r != null && !tooFew ? r : null;
    final n = finding.nSamples;
    final unit = isPair(finding) ? pairUnit(finding) : 'day';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: Row(
                children: <Widget>[
                  Flexible(
                    child: Text(
                      _names(finding, drawn),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TypeLadder.calloutStrong.copyWith(
                        color: colors.ink,
                      ),
                    ),
                  ),
                  FindingInfoDot(finding),
                ],
              ),
            ),
            if (tooFew)
              ReadingChip(
                '${n == 1 ? '1 entry' : '$n entries'} · too few',
                state: ReadingState.noData,
              )
            else if (drawn != null)
              Text.rich(
                signedRSpan(
                  drawn,
                  TypeLadder.bodyStrong.copyWith(
                    color: drawn < 0 ? hues.movement : hues.strain,
                  ),
                ),
              ),
          ],
        ),
        if (drawn != null) ...<Widget>[
          const SizedBox(height: Insets.xs),
          DivergingBar(r: drawn),
          const SizedBox(height: Insets.xs),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  directionCaption(drawn),
                  style: TypeLadder.callout.copyWith(color: colors.ink2),
                ),
              ),
              if (n != null)
                Text(
                  daysLabel(n, unit: unit),
                  style: TypeLadder.callout.copyWith(color: colors.ink2),
                ),
            ],
          ),
        ] else if (!tooFew && n != null) ...<Widget>[
          const SizedBox(height: Insets.xs),
          Text(
            'Compared across ${daysLabel(n)}',
            style: TypeLadder.callout.copyWith(color: colors.ink2),
          ),
        ],
      ],
    );
  }

  /// `Resting HR ↑↓ Recovery`, or `Alcohol ↔ Sleep` where there is no `r` to
  /// give a direction.
  static String _names(Finding finding, double? r) {
    final a = pairName(finding.metricA ?? '');
    if (finding.metricB == null) {
      final event = finding.eventKind;
      final named = event == null || event.isEmpty
          ? 'its other days'
          : '${event[0].toUpperCase()}${event.substring(1)}';
      return '$a $kPairArrow $named';
    }
    final glyph = r == null ? kPairArrow : directionGlyphs(r);
    return '$a $glyph ${laggedName(finding)}';
  }
}
