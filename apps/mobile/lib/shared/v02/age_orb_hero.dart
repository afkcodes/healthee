/// Today's biological-age hero: no card, the page itself as the ground. A
/// Label row with the ⓘ, the sphere with the figure inside it, one Callout
/// line of what moved it, and the not-clinical caption. No ruler, no stat
/// columns, no slider: the Biological age screen has those.
///
/// It is layout only. The figure, the breakdown line and the caption are the
/// caller's (`today_hero.dart`). The model line and caveats go behind the ⓘ:
/// the hero reads the `CaveatScope` it is given and routes it into that one
/// sheet. The whole face is one button to the Biological age screen.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/data/honesty/disclosure.dart';
import 'package:healthee/shared/instrument/h_tap.dart';
import 'package:healthee/shared/metric_info/metric_detail.dart';
import 'package:healthee/shared/metric_info/metric_info_sheet.dart';
import 'package:healthee/shared/states/caveat_scope.dart';
import 'package:healthee/shared/v02/instruments/age_sphere.dart';
import 'package:healthee/shared/v02/key_number_card.dart';

/// The hero's title, WHOOP's uppercase label.
const String kAgeOrbTitle = 'BIOLOGICAL AGE';

/// The sphere's radius as a share of its canvas.
const double _radiusShare = 0.425;

/// The widest the figure may paint, in radii; wider is scaled down.
const double _figureRadii = 1.4;

/// The sphere's centre and the half width it paints, for the dots to clear.
///
/// Shared by Today's hero and the biological-age screen, so the two draw the
/// same figure. The number is measured at the current text scale and, when
/// wider than 1.4 R, scaled down to that width so a large text scale never
/// clips. [paused] draws no figure and no verdict, only the spoken state.
({Widget centre, double halfWidth}) ageOrbCentre(
  BuildContext context,
  HealtheeColors colors, {
  required double canvas,
  required String value,
  required bool paused,
  Verdict? verdict,
}) {
  if (paused) {
    return (
      centre: Semantics(
        label: 'Biological age estimate paused',
        child: const SizedBox.shrink(),
      ),
      halfWidth: 0,
    );
  }
  final style = TypeLadder.display.copyWith(color: colors.ink);
  final limit = canvas * _radiusShare * _figureRadii;
  final measured = TextPainter(
    text: TextSpan(text: value, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final wide = measured.width;
  measured.dispose();
  final painted = math.min(wide, limit);
  final centre = Semantics(
    label: 'Biological age $value years',
    child: ExcludeSemantics(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: limit),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value, style: style, maxLines: 1),
            ),
            if (verdict case final Verdict said) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                said.words,
                textAlign: TextAlign.center,
                style: TypeLadder.bodyStrong.copyWith(
                  color: switch (said.tone) {
                    VerdictTone.better => colors.fav,
                    VerdictTone.worse => colors.alert,
                    VerdictTone.neutral => colors.ink2,
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
  return (centre: centre, halfWidth: painted / 2);
}

/// The hero.
class AgeOrbHero extends StatelessWidget {
  const AgeOrbHero({
    required this.value,
    this.verdict,
    this.breakdown,
    this.caption,
    this.below,
    this.infoKey = 'biological_age',
    this.modelLabel,
    this.extraDisclosures = const <Disclosure>[],
    this.disclosuresLabel,
    this.onOpen,
    this.openSemantics,
    this.paused = false,
    super.key,
  });

  /// Side padding; the hero is edge to edge.
  static const double side = 20;

  /// The sphere's canvas: 300 on Today, less on a narrower screen.
  static const double orbMax = 300;

  /// The gap between the Label row and the sphere.
  static const double headGap = 8;

  /// The gap between the sphere and the line under it.
  static const double lineGap = 4;

  /// The breakdown line's style: Callout, ink2.
  static TextStyle breakdownStyle(HealtheeColors colors) =>
      TypeLadder.callout.copyWith(color: colors.ink2);

  /// The figure, `34.3`. Also what a screen reader hears.
  final String value;

  /// Under the figure: `1.7 years younger`, coloured by which side it is.
  final Verdict? verdict;

  /// The Callout under the sphere: what moved the estimate. A span, built by
  /// the caller in [breakdownStyle] (`ageBreakdownSpan`), so its signs are
  /// tightened against the digits.
  final TextSpan? breakdown;

  /// The Caption under that: the not-clinical disclaimer.
  final String? caption;

  /// Drawn under the sphere for a hero whose number is withheld: the reason,
  /// in the caller's own widget. It holds a button, so it is not in the hero's
  /// one semantics node.
  final Widget? below;

  /// Whether the number is paused. The orb then holds nothing: no figure, no
  /// `YEARS`, and a screen reader hears that the estimate is paused rather than
  /// a number.
  final bool paused;

  final String infoKey;

  /// The model line, behind the ⓘ.
  final String? modelLabel;

  /// Disclosures the caller adds to the scope's, behind the ⓘ.
  final List<Disclosure> extraDisclosures;
  final String? disclosuresLabel;

  /// Where a tap on the hero goes: the Biological age screen.
  final VoidCallback? onOpen;

  /// The one label the hero speaks: figure, delta, breakdown, and where a tap
  /// goes.
  final String? openSemantics;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final scope = CaveatScope.of(context);
    final disclosed = <Disclosure>[...?scope?.caveats, ...extraDisclosures];
    return CaveatScope(
      caveats: const <Disclosure>[],
      child: Padding(
        padding: const EdgeInsets.fromLTRB(side, 4, side, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _head(colors, disclosed, scope?.label),
            const SizedBox(height: headGap),
            HTap(
              onTap: onOpen,
              semanticLabel: openSemantics,
              child: ExcludeSemantics(
                excluding: openSemantics != null,
                child: _face(colors),
              ),
            ),
            if (below case final Widget notice)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onOpen,
                excludeFromSemantics: true,
                child: Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: notice,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _face(HealtheeColors colors) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      LayoutBuilder(
        builder: (context, box) {
          final canvas = math.min(orbMax, box.maxWidth);
          final figure = ageOrbCentre(
            context,
            colors,
            canvas: canvas,
            value: value,
            verdict: verdict,
            paused: paused,
          );
          return Center(
            child: AgeSphere(
              canvas: canvas,
              withheld: paused,
              clearHalfWidth: figure.halfWidth,
              centre: figure.centre,
            ),
          );
        },
      ),
      if (breakdown case final TextSpan line) ...<Widget>[
        const SizedBox(height: Insets.sm),
        Text.rich(
          line,
          textAlign: TextAlign.center,
          style: breakdownStyle(colors),
        ),
      ],
      if (caption case final String line) ...<Widget>[
        const SizedBox(height: lineGap),
        Text(
          line,
          textAlign: TextAlign.center,
          style: TypeLadder.caption.copyWith(color: colors.ink2),
        ),
      ],
    ],
  );

  Widget _head(
    HealtheeColors colors,
    List<Disclosure> disclosed,
    String? label,
  ) => Row(
    children: <Widget>[
      Expanded(
        child: Text(
          kAgeOrbTitle,
          style: TypeLadder.label.copyWith(color: colors.ink2),
        ),
      ),
      MetricInfoDot(
        infoKey,
        ink: colors.ink2,
        detail: MetricDetail(
          source: modelLabel,
          disclosures: disclosed,
          disclosuresLabel: label ?? disclosuresLabel,
        ),
      ),
    ],
  );
}
