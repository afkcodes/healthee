/// The labelled blocks a metric-info sheet is built from.
///
/// Split out of `metric_info_sheet.dart` at the 400-line gate (Standards §1)
/// when the sheet grew four more block kinds: the card's own references, the
/// prose moved off its face, and the server disclosures too long to print beside
/// a number.
///
/// They are one file rather than four because they are one thing — a labelled
/// run of text on a sheet — and a second copy of that geometry is a second
/// opinion about how a sheet reads.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/instrument_type.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/data/honesty/disclosure.dart';
import 'package:healthee/shared/metric_info/metric_detail.dart';
import 'package:solar_icons/solar_icons.dart';

/// One labelled block: an icon, a caps label, and the body under it.
class InfoBlock extends StatelessWidget {
  /// Builds the block. [body] is rendered verbatim.
  const InfoBlock({
    required this.icon,
    required this.label,
    required this.body,
    required this.accent,
    super.key,
  });

  /// Drawn before the label, in [accent].
  final IconData icon;

  /// The block's name, uppercased by the caller's own copy.
  final String label;

  /// The prose.
  final String body;

  /// The label's colour. Resolved by the sheet from its own tokens — a block
  /// never picks one.
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(icon, size: 15, color: accent),
            const SizedBox(width: Insets.sm),
            Flexible(child: Text(label, style: HType.label(accent))),
          ],
        ),
        const SizedBox(height: 7),
        Text(body, style: HType.sans(colors.ink, size: 14.5)),
      ],
    );
  }
}

/// A block of several lines that are each a separate fact — the references a
/// card is read against, or the sentences moved off its face.
///
/// A list rather than a joined paragraph, because `Reference ≥ 85%` and
/// `Reference 02:00–04:00` are two published thresholds and running them into
/// one sentence would read as one claim.
class InfoLines extends StatelessWidget {
  /// Builds the block. [lines] must not be empty — the sheet gates on that.
  const InfoLines({
    required this.icon,
    required this.label,
    required this.lines,
    required this.accent,
    super.key,
  });

  /// The gap between one line and the next.
  static const double lineGap = 5;

  /// Drawn before the label.
  final IconData icon;

  /// The block's name.
  final String label;

  /// Each fact on its own line, in the order the card listed them.
  final List<String> lines;

  /// The label's colour.
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(icon, size: 15, color: accent),
            const SizedBox(width: Insets.sm),
            Flexible(child: Text(label, style: HType.label(accent))),
          ],
        ),
        const SizedBox(height: 7),
        for (var i = 0; i < lines.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: lineGap),
          Text(lines[i], style: HType.sans(colors.ink, size: 14.5)),
        ],
      ],
    );
  }
}

/// The server's own disclosures, in full, on the sheet.
///
/// The prose is NOT summarised, trimmed or paraphrased — the same rule
/// `_CaveatSheet` states: an 800-character explanation of why a term cannot be
/// converted into years is exactly right for a reader who asked for it, and
/// exactly wrong printed under a hero nobody asked. Each keeps its own `term` as
/// an eyebrow so a reader can see WHICH lever each paragraph is about.
class DisclosureBlock extends StatelessWidget {
  /// Builds the block. [disclosures] must not be empty.
  const DisclosureBlock({
    required this.label,
    required this.disclosures,
    required this.accent,
    super.key,
  });

  /// The gap between one disclosure and the next.
  static const double blockGap = 14;

  /// What to call this run — "WHY THERE IS NO NUMBER", "LEFT OUT, AND WHY".
  final String label;

  /// The server's sentences, in the payload's own order.
  final List<Disclosure> disclosures;

  /// The label's colour.
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(SolarIconsOutline.infoCircle, size: 15, color: accent),
            const SizedBox(width: Insets.sm),
            Flexible(child: Text(label, style: HType.label(accent))),
          ],
        ),
        for (final disclosure in disclosures) ...<Widget>[
          const SizedBox(height: 9),
          if (disclosure.term case final String term) ...<Widget>[
            Text(term.toUpperCase(), style: HType.label(colors.ink2)),
            const SizedBox(height: 5),
          ],
          Text(disclosure.message, style: HType.sans(colors.ink, size: 14.5)),
          // The absent terms a composite names inside its own withheld block.
          // They are the "what would bring it back" half and must not be
          // flattened into the sentence above them.
          for (final term in disclosure.terms) ...<Widget>[
            const SizedBox(height: 9),
            if (term.term case final String name) ...<Widget>[
              Text(name.toUpperCase(), style: HType.label(colors.ink2)),
              const SizedBox(height: 5),
            ],
            Text(term.message, style: HType.sans(colors.ink, size: 14.5)),
          ],
        ],
      ],
    );
  }
}

/// What the sources above do **not** cover, said plainly under them.
///
/// A list of four sources beside a paragraph implies the whole paragraph is
/// sourced. Where part of it is our own arithmetic, our own threshold or our own
/// product decision, the citation row would otherwise be lending it cover it
/// does not give — and that is a worse failure than no citation at all, because
/// it is the reader's check that gets defeated.
///
/// Drawn in ordinary ink with no colour, for the reason `citation_row.dart`
/// gives about broken citations: this is a statement about our evidence, not a
/// verdict about the owner's body.
class NotCoveredNote extends StatelessWidget {
  /// Renders the uncited remainder of an explainer.
  const NotCoveredNote(this.text, {super.key});

  /// What the sources do not cover, in plain words.
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            SolarIconsOutline.infoCircle,
            size: 13,
            color: colors.ink2,
          ),
        ),
        const SizedBox(width: Insets.sm),
        Expanded(
          child: Text(
            'Not covered by those sources: $text',
            style: HType.sans(colors.ink2, size: 11.5),
          ),
        ),
      ],
    );
  }
}

/// The sheet's one onward button: closes the sheet, then goes.
class InfoActionButton extends StatelessWidget {
  /// Builds the button for [action].
  const InfoActionButton(this.action, {super.key});

  /// Its words and where it goes.
  final MetricAction action;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton(
      onPressed: () {
        Navigator.of(context).pop();
        action.onTap();
      },
      child: Text(action.label),
    ),
  );
}
