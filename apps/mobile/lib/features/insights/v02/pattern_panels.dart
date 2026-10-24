/// The two hero tiles at the top of Insights: the strongest pattern in the
/// owner's own history, and the fitness term of the biological-age model.
///
/// Each is a surface tile with no border, a label, one big signed figure, a
/// bar from zero and a plain-language caption. Either may be absent, and an
/// absent tile says so with a hatched bar and "Not enough readings yet" rather
/// than a number nobody measured.
///
/// ## Neither tile's colour is a verdict on a correlation
///
/// The pattern tile's bar is Strain blue when the two moved together and
/// Activity orange when they moved opposite, the colour kit's correlation
/// grammar: a direction, never good or bad. The age tile is the other thing:
/// a model's years, judged by `verdictForDelta` and coloured by the state that
/// earns (`alert` older, `fav` younger, ink about the same).
///
/// Each tile leads where the card it replaced led: the pattern to its finding
/// screen, the age to the biological-age screen.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:healthee/core/router.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/instrument_hues.dart';
import 'package:healthee/core/theme/shapes.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/data/models/biological_age.dart';
import 'package:healthee/data/models/finding.dart';
import 'package:healthee/features/insights/v02/finding_detail_screen.dart';
import 'package:healthee/features/insights/v02/pair_reading.dart';
import 'package:healthee/shared/charts/v02/diverging_bar.dart';
import 'package:healthee/shared/charts/v02/hatch.dart';
import 'package:healthee/shared/format/age_lever_format.dart';
import 'package:healthee/shared/format/metric_names.dart';
import 'package:healthee/shared/instrument/h_tap.dart';
import 'package:healthee/shared/v02/key_number_card.dart' show VerdictTone;
import 'package:healthee/shared/v02/reading_state.dart';

/// The years at which the age tile's bar is full: ten either side of zero.
const double kAgeBarSpanYears = 10;

/// What the age tile is built from: the fitness lever, and the VO₂max beside
/// the median it is scored against.
@immutable
class FitnessAge {
  /// The lever's years and the two VO₂max figures behind it.
  const FitnessAge({required this.years, this.vo2max, this.median});

  /// The lever the payload carries, or null when it has no fitness term.
  static FitnessAge? from(BiologicalAge? age) {
    for (final term in age?.contributions ?? const <AgeContribution>[]) {
      if (term.term.toLowerCase() == 'fitness' && term.deltaYears != null) {
        return FitnessAge(
          years: term.deltaYears!,
          vo2max: term.value,
          median: term.target,
        );
      }
    }
    return null;
  }

  /// Years added (positive) or removed (negative) by the fitness lever.
  final double years;

  /// The owner's measured VO₂max.
  final double? vo2max;

  /// What it is scored against.
  final double? median;

  /// `VO₂max 33.3 vs 46.5 median`, or what of it the payload carried.
  String? get caption {
    final measured = vo2max;
    if (measured == null) {
      return null;
    }
    final against = median;
    return against == null
        ? 'VO₂max ${measured.toStringAsFixed(1)}'
        : 'VO₂max ${measured.toStringAsFixed(1)} vs '
              '${against.toStringAsFixed(1)} median';
  }
}

/// The two tiles side by side. Either may be null; one draws alone full width,
/// and none draws nothing.
class HeroRow extends StatelessWidget {
  /// [pattern] is the strongest drawable pair; [age] the fitness lever.
  const HeroRow({required this.pattern, required this.age, super.key});

  /// The strongest correlation, or null.
  final Finding? pattern;

  /// The fitness term, or null.
  final FitnessAge? age;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(child: PatternHeroTile(finding: pattern)),
        const SizedBox(width: Insets.cardGap),
        Expanded(child: AgeHeroTile(age: age)),
      ],
    ),
  );
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.figure,
    required this.bar,
    required this.caption,
    this.onOpen,
    this.semanticLabel,
  });

  final Widget label;
  final Widget figure;
  final Widget bar;
  final String caption;
  final VoidCallback? onOpen;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final Widget card = Container(
      padding: const EdgeInsets.all(Insets.md),
      decoration: ShapeDecoration(
        color: colors.surface,
        shape: hSquircle(Radii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          label,
          const SizedBox(height: Insets.sm),
          figure,
          const SizedBox(height: Insets.sm),
          bar,
          const SizedBox(height: Insets.sm),
          Text(caption, style: TypeLadder.callout.copyWith(color: colors.ink2)),
        ],
      ),
    );
    return onOpen == null
        ? card
        : HTap(onTap: onOpen, semanticLabel: semanticLabel, child: card);
  }
}

/// A tile's one big figure, scaled down rather than wrapped or clipped when the
/// text scale is large.
class _Figure extends StatelessWidget {
  const _Figure({required this.span, this.unit});

  final InlineSpan span;
  final String? unit;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerLeft,
    child: Text.rich(
      TextSpan(
        children: <InlineSpan>[
          span,
          if (unit != null)
            TextSpan(
              text: ' $unit',
              style: TypeLadder.callout.copyWith(color: context.colors.ink2),
            ),
        ],
      ),
    ),
  );
}

/// The strongest correlation in the owner's history.
class PatternHeroTile extends StatelessWidget {
  /// [finding] null draws the honest empty state.
  const PatternHeroTile({required this.finding, super.key});

  /// The empty tile's words.
  static const String emptyCaption = 'Not enough readings yet';

  /// The empty tile's label.
  static const String emptyLabel = 'Strongest pattern';

  /// The pair behind the tile, or null.
  final Finding? finding;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final pair = finding;
    if (pair == null) {
      return _Tile(
        label: Text(
          emptyLabel,
          style: TypeLadder.calloutStrong.copyWith(color: colors.ink2),
        ),
        figure: _Figure(
          span: TextSpan(
            text: '—',
            style: TypeLadder.metric.copyWith(color: colors.ink3),
          ),
        ),
        bar: const HatchStrip(),
        caption: emptyCaption,
      );
    }
    final r = pair.effectSize!;
    final hues = context.hues;
    TextSpan name(String metric) => TextSpan(
      text: pairName(metric),
      style: TextStyle(color: pairTone(metric).family(hues)),
    );
    return _Tile(
      label: Text.rich(
        TextSpan(
          style: TypeLadder.calloutStrong.copyWith(color: colors.ink2),
          children: <InlineSpan>[
            name(pair.metricA!),
            const TextSpan(text: ' $kPairArrow '),
            name(pair.metricB!),
          ],
        ),
      ),
      figure: _Figure(
        span: signedRSpan(r, TypeLadder.metric.copyWith(color: colors.ink)),
      ),
      bar: DivergingBar(r: r),
      caption: pairSentence(pair),
      semanticLabel:
          '${pairName(pair.metricA!)} and ${pairName(pair.metricB!)}, '
          '${directionCaption(r)}',
      // Carries the finding so the screen draws the same numbers this tile
      // shows, without a second fetch.
      onOpen: () => unawaited(
        context.push('${Routes.insight}/${findingKey(pair)}', extra: pair),
      ),
    );
  }
}

/// The fitness term of the biological-age model, in years.
class AgeHeroTile extends StatelessWidget {
  /// [age] null draws the honest empty state.
  const AgeHeroTile({required this.age, super.key});

  /// The tile's label.
  static const String label = 'Fitness → age';

  /// The fitness lever, or null.
  final FitnessAge? age;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fitness = Tone.fitness.family(context.hues);
    final labelText = Text(
      label,
      style: TypeLadder.calloutStrong.copyWith(color: fitness),
    );
    final lever = age;
    if (lever == null) {
      return _Tile(
        label: labelText,
        figure: _Figure(
          span: TextSpan(
            text: '—',
            style: TypeLadder.metric.copyWith(color: colors.ink3),
          ),
        ),
        bar: const HatchStrip(),
        caption: PatternHeroTile.emptyCaption,
      );
    }
    final state = switch (verdictForDelta(lever.years)) {
      VerdictTone.better => ReadingState.better,
      VerdictTone.worse => ReadingState.worse,
      VerdictTone.neutral => ReadingState.usual,
    };
    return _Tile(
      label: labelText,
      figure: _Figure(
        span: signedYearsSpan(
          lever.years,
          TypeLadder.metric.copyWith(color: state.dotIn(colors)),
        ),
        unit: 'yrs',
      ),
      bar: DivergingBar(r: lever.years / kAgeBarSpanYears, state: state),
      caption: lever.caption ?? 'Model contribution',
      semanticLabel: 'Fitness and biological age, ${spokenYears(lever.years)}',
      onOpen: () => unawaited(context.push(Routes.body)),
    );
  }
}
