/// "What moves it": a heading that opens and closes the lever card.
///
/// Collapsed, it still names every term in one summary line ("Fitness -1.7,
/// Sleep 0.0, Regularity left out"), because a breakdown that is only visible
/// after a tap is a black box with a door. Open or shut is remembered across
/// launches ([WhatMovesItOpen]); on a day the number is paused the screen asks
/// for it to start open ([openByDefault]) without overwriting what was chosen
/// until the owner toggles it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/motion.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/core/what_moves_it_preference.dart';
import 'package:healthee/data/models/bio_age_block.dart';
import 'package:healthee/features/today/v02/age_levers.dart';
import 'package:healthee/shared/format/age_lever_format.dart';
import 'package:healthee/shared/instrument/h_tap.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:healthee/shared/v02/fold.dart';
import 'package:solar_icons/solar_icons.dart';

/// The header's minimum height, logical px.
const double kWhatMovesItMinHeight = 48;

/// The chevron's size, logical px.
const double kWhatMovesItChevron = 24;

/// The gap between the header and the card, logical px.
const double kWhatMovesItGap = Insets.cardGap;

/// The collapsed summary: every term the block names, in payload order.
String whatMovesItSummary(BioAgeBlock block) => _terms(
  block,
  counted: (name, delta) => '$name ${signedYears(delta)}',
  notCounted: (name) => '$name not counted',
  leftOut: (name) => '$name left out',
).join(' · ');

/// Today's one line under the sphere: `Fitness −1.7 years · Sleep 0.0 years ·
/// Regularity left out`. The same terms as [whatMovesItSummary], with the unit
/// on each figure. [spoken] words it for a screen reader instead, with `minus`
/// for the sign and lower-case names: `fitness minus 1.7 years, sleep 0.0
/// years`.
String ageBreakdownLine(BioAgeBlock block, {bool spoken = false}) {
  String name(String text) => spoken ? text.toLowerCase() : text;
  final parts = _terms(
    block,
    counted: (term, delta) => spoken
        ? '${name(term)} ${spokenYears(delta)}'
        : '$term ${signedYears(delta)} years',
    notCounted: (term) => '${name(term)} not counted',
    leftOut: (term) => '${name(term)} left out',
  );
  final line = parts.join(spoken ? ', ' : ' · ');
  return spoken && line.isNotEmpty
      ? line[0].toUpperCase() + line.substring(1)
      : line;
}

/// [whatMovesItSummary] as a span, so each signed figure goes through
/// [signedYearsSpan] and its sign is tightened against the digits (a plain
/// string leaves a visible gap after U+2212 at small sizes). [style] must carry
/// a `fontSize`. `toPlainText` is exactly [whatMovesItSummary].
TextSpan whatMovesItSummarySpan(BioAgeBlock block, TextStyle style) =>
    _termsSpan(block, style, units: false);

/// [ageBreakdownLine] as a span, tightened the same way; today's hero draws
/// it. `toPlainText` is exactly the line.
TextSpan ageBreakdownSpan(BioAgeBlock block, TextStyle style) =>
    _termsSpan(block, style, units: true);

TextSpan _termsSpan(BioAgeBlock block, TextStyle style, {required bool units}) {
  final terms = <InlineSpan>[
    for (final c in block.contributions)
      if (c.deltaYears case final double delta)
        TextSpan(
          children: <InlineSpan>[
            TextSpan(text: '${leverShortName(c.term)} '),
            signedYearsSpan(delta, style),
            if (units) const TextSpan(text: ' years'),
          ],
        )
      else
        TextSpan(text: '${leverShortName(c.term)} not counted'),
    for (final d in block.absentTerms)
      TextSpan(text: '${leverShortName(d.term ?? d.reason)} not counted'),
    for (final d in block.exclusions)
      TextSpan(text: '${leverShortName(d.term ?? d.reason)} left out'),
  ];
  return TextSpan(
    style: style,
    children: <InlineSpan>[
      for (var i = 0; i < terms.length; i++) ...<InlineSpan>[
        if (i > 0) const TextSpan(text: ' · '),
        terms[i],
      ],
    ],
  );
}

List<String> _terms(
  BioAgeBlock block, {
  required String Function(String name, double delta) counted,
  required String Function(String name) notCounted,
  required String Function(String name) leftOut,
}) => <String>[
  for (final c in block.contributions)
    if (c.deltaYears case final double delta)
      counted(leverShortName(c.term), delta)
    else
      notCounted(leverShortName(c.term)),
  for (final d in block.absentTerms)
    notCounted(leverShortName(d.term ?? d.reason)),
  for (final d in block.exclusions) leftOut(leverShortName(d.term ?? d.reason)),
];

/// The dropdown.
class WhatMovesIt extends ConsumerStatefulWidget {
  const WhatMovesIt({
    required this.block,
    required this.reveals,
    required this.openByDefault,
    this.onOpenLever,
    this.reasonsShownAbove = false,
    super.key,
  });

  /// Identifies the header for tests.
  static const Key headerKey = ValueKey<String>('what-moves-it-header');

  /// Identifies the summary line for tests.
  static const Key summaryKey = ValueKey<String>('what-moves-it-summary');

  /// What the server said about the estimate.
  final BioAgeBlock block;

  /// Where each zone bar's reveal is remembered.
  final RevealRegistry reveals;

  /// Starts open on this visit, whatever was remembered.
  final bool openByDefault;

  /// Called with a lever's term when its row is tapped.
  final void Function(String term)? onOpenLever;

  /// See [AgeLeverCard.reasonsShownAbove].
  final bool reasonsShownAbove;

  @override
  ConsumerState<WhatMovesIt> createState() => _WhatMovesItState();
}

class _WhatMovesItState extends ConsumerState<WhatMovesIt> {
  /// Set once the owner toggles, or at the start when [openByDefault]; from
  /// then on it, not the stored value, is what this visit shows.
  late bool? _local = widget.openByDefault ? true : null;

  /// The card is built the first time it is open and kept after that, so its
  /// zone bars reveal once and a re-open does not replay them.
  bool _built = false;

  void _toggle(bool open) {
    setState(() => _local = !open);
    ref.read(whatMovesItOpenProvider.notifier).set(open: !open);
  }

  @override
  Widget build(BuildContext context) {
    final stored = ref.watch(whatMovesItOpenProvider);
    final open = _local ?? stored;
    _built = _built || open;
    final colors = context.colors;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final duration = reduced ? Duration.zero : HMotion.base;
    final summaryStyle = TypeLadder.callout.copyWith(color: colors.ink2);
    final summary = open
        ? null
        : whatMovesItSummarySpan(widget.block, summaryStyle);
    final header = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: kWhatMovesItMinHeight),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'What moves it',
                  style: TypeLadder.title2.copyWith(color: colors.ink),
                ),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: Insets.xs,
                  children: <Widget>[
                    Text(
                      'Each reading, turned into years',
                      style: TypeLadder.caption.copyWith(color: colors.ink2),
                    ),
                    if (summary != null && summary.children!.isNotEmpty)
                      Text.rich(summary, key: WhatMovesIt.summaryKey),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: Insets.sm),
          AnimatedRotation(
            turns: open ? 0.5 : 0,
            duration: duration,
            curve: HMotion.curve,
            child: Icon(
              SolarIconsOutline.altArrowDown,
              size: kWhatMovesItChevron,
              color: colors.ink2,
            ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          container: true,
          button: true,
          label: open ? 'What moves it, expanded' : 'What moves it, collapsed',
          excludeSemantics: true,
          onTap: () => _toggle(open),
          child: HTap(
            key: WhatMovesIt.headerKey,
            onTap: () => _toggle(open),
            child: header,
          ),
        ),
        Fold(
          open: open,
          duration: duration,
          curve: HMotion.curve,
          fade: true,
          child: ExcludeSemantics(
            excluding: !open,
            child: _built
                ? Padding(
                    padding: const EdgeInsets.only(top: kWhatMovesItGap),
                    child: AgeLeverCard(
                      block: widget.block,
                      reveals: widget.reveals,
                      onOpenLever: widget.onOpenLever,
                      reasonsShownAbove: widget.reasonsShownAbove,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}
