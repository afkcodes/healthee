/// Reasoning **offered**, never forced — an inline disclosure, never a modal.
///
/// Brief §3: *"'Why debt is 120 minutes, not 1,400', 'What would restore this'
/// as an expandable, never a modal."* The distinction is the product's whole
/// posture towards depth. A modal stops the person reading their sleep and
/// demands they deal with a footnote; a line they can open is a footnote a
/// serious user will love and a casual one will never notice.
///
/// So this is an `ExpansionTile`-shaped thing built by hand, because Material's
/// own comes with a leading chevron, a divider, and a tap target sized for a
/// settings list — three pieces of chrome around one sentence.
///
/// It renders **inside** whatever card it belongs to and draws no frame of its
/// own: brief §2's first "never" is card-inside-a-card.
///
/// ## The answer goes through [GroundedProse], whoever wrote it
///
/// Most answers here are composed in Dart from typed fields and carry no
/// citation markers, so the parse is a no-op on them. One is not: a
/// recommendation's `rationale` is model prose that `jobs/recs.py` **requires**
/// to contain an inline `[note_id]` — it drops any rec whose rationale has none.
/// Routing every answer through the grounded widget rather than only that one
/// means a disclosure filled with server prose tomorrow is covered by
/// construction instead of by somebody noticing.
///
/// The same argument puts an ⓘ on the question row, carrying whatever the answer
/// cites. An answer composed in Dart cites nothing and the dot draws nothing, so
/// the cost of covering the general case is zero pixels on every surface that
/// does not need it.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/data/honesty/citations.dart';
import 'package:healthee/shared/metric_info/metric_detail.dart';
import 'package:healthee/shared/metric_info/metric_info_sheet.dart';
import 'package:healthee/shared/states/grounded_text.dart';
import 'package:solar_icons/solar_icons.dart';

/// The question row's splash corner. A row, not a chip: when the question
/// wraps, a pill radius ([Radii.chip]) would splash it as a stadium.
const double _splashRadius = 8;

/// A one-line question that opens into its answer.
class ReasoningNote extends StatefulWidget {
  /// [question] is the prompt in the owner's own words; [answer] is the body.
  const ReasoningNote({
    required this.question,
    required this.answer,
    super.key,
  });

  /// "Why debt is 120 minutes, not 1,400" — phrased as the thing somebody
  /// actually wonders, not as "Details".
  final String question;

  /// The explanation. Plain, specific, second person.
  final String answer;

  @override
  State<ReasoningNote> createState() => _ReasoningNoteState();
}

class _ReasoningNoteState extends State<ReasoningNote> {
  bool _open = false;

  /// What the answer cites. Empty for an answer composed in Dart, which is most
  /// of them — so most disclosures draw no ⓘ at all.
  MetricDetail get _detail =>
      MetricDetail.grounded(groundingOf(widget.answer), title: widget.question);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          borderRadius: BorderRadius.circular(_splashRadius),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Insets.xs),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    widget.question,
                    style: text.labelMedium?.copyWith(color: colors.accent),
                  ),
                ),
                const SizedBox(width: Insets.xs),
                Icon(
                  _open
                      ? SolarIconsOutline.altArrowUp
                      : SolarIconsOutline.altArrowDown,
                  size: 16,
                  color: colors.accent,
                ),
                if (_detail case final MetricDetail detail
                    when detail.isNotEmpty)
                  MetricInfoDot(
                    null,
                    detail: detail,
                    fallbackTitle: widget.question,
                  ),
              ],
            ),
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.only(top: Insets.xs),
            child: GroundedProse(
              text: widget.answer,
              style: text.bodySmall?.copyWith(color: colors.ink2),
            ),
          ),
      ],
    );
  }
}
