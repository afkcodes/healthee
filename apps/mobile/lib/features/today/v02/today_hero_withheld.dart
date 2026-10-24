/// The biological-age hero when the server pauses the number.
///
/// ## The defect this replaces
///
/// The card used to print the names of the absent terms ("No estimate today: no
/// current value for fitness.") and keep every server sentence behind the ⓘ, and
/// it held the last number this phone had seen under a date. The reason was
/// there and could not be read; the number was there and was not today's.
///
/// ## What it draws now
///
/// The same layout as the live hero: the Label and the ⓘ, then the orb, still,
/// with nothing inside it: **no number, and no older number standing in for
/// it.** Under the orb stands [AgePausedNotice], which says why in the server's
/// own words and offers the one profile field that would fix it. A tap on the
/// orb or the notice's text opens the Biological age screen, as it does live. The ⓘ keeps the long prose (the
/// `consequence` and each term's remedy), and the permanent exclusions keep a
/// one-line signpost on the card, because a lever this number deliberately does
/// not price must stay visible.
///
/// `MetricDetail` carries one disclosure group, so the exclusions share the
/// ⓘ's group with the refusal rather than getting their own.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/data/honesty/disclosure.dart';
import 'package:healthee/data/models/bio_age_block.dart';
import 'package:healthee/features/today/v02/age_paused.dart';
import 'package:healthee/features/today/v02/today_hero.dart';
import 'package:healthee/shared/v02/age_orb_hero.dart';

/// What the ⓘ calls the server's refusal prose.
const String kWithheldSheetLabel = 'WHY THERE IS NO NUMBER TODAY';

/// What a screen reader hears for the paused orb.
const String kPausedSpoken =
    'Biological age estimate paused. Opens the breakdown.';

/// The paused biological-age hero.
class TodayBioHeroWithheld extends StatelessWidget {
  /// [withheld] is the server's own refusal, already parsed; [block] is the
  /// whole `biological_age` block; [vo2maxWithheld] the VO2max card's refusal.
  const TodayBioHeroWithheld({
    required this.withheld,
    required this.block,
    this.vo2maxWithheld,
    this.exclusions = const <Disclosure>[],
    this.onOpen,
    super.key,
  });

  /// The metric's key in `kMetricInfo`.
  static const String infoKey = 'biological_age';

  /// Why there is no number, and in its `terms` what would bring it back.
  final Disclosure withheld;

  /// Everything the server said about the age, kept whole.
  final BioAgeBlock block;

  /// The VO2max card's refusal, when it has one.
  final Disclosure? vo2maxWithheld;

  /// Levers this number permanently does not price. Signposted, never blamed.
  final List<Disclosure> exclusions;

  /// A tap on the hero: the Biological age screen.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final left = signpost(exclusions);
    return AgeOrbHero(
      value: '',
      paused: true,
      below: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AgePausedNotice(block: block, vo2maxWithheld: vo2maxWithheld),
          if (left != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              left,
              textAlign: TextAlign.center,
              style: TypeLadder.caption.copyWith(color: colors.ink2),
            ),
          ],
        ],
      ),
      infoKey: infoKey,
      modelLabel: kPopulationModelLabel,
      // A block the server sent as null has no refusal of its own: the envelope
      // fills in "a bug on our side", which is false for a state the server
      // sends on purpose, so that sentence never reaches the sheet.
      extraDisclosures: <Disclosure>[
        if (block.present) withheld,
        ...exclusions,
      ],
      disclosuresLabel: kWithheldSheetLabel,
      onOpen: onOpen,
      openSemantics: kPausedSpoken,
    );
  }

  /// `Left out of this number: regularity.`, or null when nothing is left out.
  static String? signpost(List<Disclosure> exclusions) {
    final names = <String>[
      for (final exclusion in exclusions)
        if (exclusion.term case final String name) name,
    ];
    if (names.isEmpty) {
      return null;
    }
    final list = names.length == 1
        ? names.first
        : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
    return 'Left out of this number: $list.';
  }
}
