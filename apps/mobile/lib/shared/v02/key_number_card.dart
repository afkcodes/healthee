/// `.p-key` — one of Today's three key numbers, read in one look.
///
/// From `design/mobile-preview/proposal.js::keyMetric`, which the owner
/// approved: the family's name and icon, a verdict in words, the reading at
/// 44 px, a [RangeBar] against the owner's own usual, and one sentence that
/// reads it. The whole card is the doorway to its screen.
///
/// ## The verdict's colour
///
/// Neutral unless the reading is on the side that is worse for the owner, which
/// draws in [HealtheeColors.alert] (the colour kit's *worse*; inside the
/// usual range stays neutral). The better side draws in
/// [HealtheeColors.fav], the token the recovery ladder already uses for "better
/// than your own normal". A card that has no verdict to give (a day still in
/// progress, a band still learning) draws a neutral chip with its own words.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/shapes.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/core/theme/type_scale_keys.dart';
import 'package:healthee/shared/instrument/h_tap.dart';
import 'package:solar_icons/solar_icons.dart';

/// How a verdict chip is coloured.
enum VerdictTone {
  /// In the usual range, or no verdict at all.
  neutral,

  /// On the side that is better for the owner.
  better,

  /// On the side that is worse for the owner. The only amber on the card.
  worse,
}

/// A verdict in words, and how loudly to say it.
@immutable
class Verdict {
  /// [words] is the whole verdict; it is never abbreviated.
  const Verdict(this.words, this.tone);

  /// `In your usual range`, `Below your usual`, `So far today`.
  final String words;

  /// Its colour.
  final VerdictTone tone;
}

/// One key number.
class KeyNumberCard extends StatelessWidget {
  /// [bar] is usually a `RangeBar`; null draws the card without one.
  const KeyNumberCard({
    required this.tone,
    required this.icon,
    required this.name,
    required this.value,
    this.unit,
    this.verdict,
    this.bar,
    this.lead,
    this.line,
    this.onOpen,
    super.key,
  });

  /// The brief's card: padding 20, radius 20, no border.
  static const EdgeInsets padding = EdgeInsets.all(Insets.card);
  static const double radius = Radii.card;

  /// An inline icon beside text is 16; the gap is 7.
  static const double iconSize = 16;
  static const double iconGap = 7;

  /// `.p-key-value { margin: 8px 0 12px }`.
  static const double valueTop = 8;
  static const double valueBottom = 12;

  /// `.p-key-line { margin-top: 10px }`.
  static const double lineGap = 10;

  /// The card's family.
  final Tone tone;

  /// Its glyph.
  final IconData icon;

  /// `Recovery`, `Sleep`, `Movement`.
  final String name;

  /// The reading, formatted. `—` when there is none.
  final String value;

  /// Drawn small after [value], ` / 100`, ` steps`.
  final String? unit;

  /// The verdict chip, or null for none.
  final Verdict? verdict;

  /// The range bar.
  final Widget? bar;

  /// The bold start of the sentence, `43 left for today.`
  final String? lead;

  /// The rest of the sentence.
  final String? line;

  /// Where the card goes. Null draws it with no tap and no chevron.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ToneScope(
      tone: tone,
      child: Builder(
        builder: (context) => HTap(
          onTap: onOpen,
          semanticLabel: _spoken(),
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: colors.surface,
              shape: hSquircle(radius),
            ),
            child: Padding(
              padding: padding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _top(context, colors),
                  const SizedBox(height: valueTop),
                  _figure(colors),
                  const SizedBox(height: valueBottom),
                  ?bar,
                  if (lead != null || line != null) ...<Widget>[
                    const SizedBox(height: lineGap),
                    _sentence(colors),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _spoken() => <String>[
    name,
    '$value${unit ?? ''}',
    ?verdict?.words,
    ?lead,
    ?line,
  ].join('. ');

  Widget _top(BuildContext context, HealtheeColors colors) {
    return Row(
      children: <Widget>[
        Icon(icon, size: iconSize, color: colors.ink2),
        const SizedBox(width: iconGap),
        Expanded(
          child: Text(name, style: KeyType.name.copyWith(color: colors.ink)),
        ),
        if (verdict case final Verdict said) VerdictChip(said),
        if (onOpen != null) ...<Widget>[
          const SizedBox(width: 8),
          Icon(SolarIconsOutline.altArrowRight, size: 14, color: colors.ink2),
        ],
      ],
    );
  }

  Widget _figure(HealtheeColors colors) => Text.rich(
    TextSpan(
      children: <InlineSpan>[
        TextSpan(
          text: value,
          style: KeyType.value.copyWith(color: colors.ink),
        ),
        if (unit case final String small)
          TextSpan(
            text: small,
            style: KeyType.unit.copyWith(color: colors.ink2),
          ),
      ],
    ),
    maxLines: 1,
    softWrap: false,
    overflow: TextOverflow.clip,
  );

  Widget _sentence(HealtheeColors colors) => Text.rich(
    TextSpan(
      style: KeyType.line.copyWith(color: colors.ink2),
      children: <InlineSpan>[
        if (lead case final String bold)
          TextSpan(
            text: line == null ? bold : '$bold ',
            style: TypeLadder.calloutStrong.copyWith(color: colors.ink),
          ),
        ?(line == null ? null : TextSpan(text: line)),
      ],
    ),
  );
}

/// `.p-chip` — a verdict in words, with a dot in its colour.
class VerdictChip extends StatelessWidget {
  /// Draws [verdict].
  const VerdictChip(this.verdict, {super.key});

  /// `.p-chip { padding: 4px 9px }`, its dot 6 and gap 6.
  static const EdgeInsets padding = EdgeInsets.symmetric(
    horizontal: 9,
    vertical: 4,
  );
  static const double dot = 6;

  /// What it says.
  final Verdict verdict;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (ink, ground) = switch (verdict.tone) {
      VerdictTone.worse => (colors.alert, colors.alertSoft),
      VerdictTone.better => (colors.fav, colors.favSoft),
      VerdictTone.neutral => (colors.ink, colors.surface2),
    };
    return DecoratedBox(
      decoration: ShapeDecoration(color: ground, shape: const StadiumBorder()),
      child: Padding(
        padding: padding,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox.square(
              dimension: dot,
              child: DecoratedBox(
                decoration: BoxDecoration(color: ink, shape: BoxShape.circle),
              ),
            ),
            const SizedBox(width: dot),
            Flexible(
              child: Text(
                verdict.words,
                style: KeyType.chip.copyWith(color: ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
