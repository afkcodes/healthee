/// `Biological age`: the estimate, how it sits against your age, and what moves
/// it. Opened from Today's hero.
///
/// ```text
///   nav                  back, and the info sheet
///   Biological age       the title
///   Estimate, not a clinical age · Updated today
///   the sphere           the figure and the verdict inside it
///   the ruler            the estimate against your actual age
///   What moves it        a dropdown over the lever card
///   How this is calculated   a row that opens the ladder and the arithmetic
///   the footnote
/// ```
///
/// ## Each fact is said once
///
/// The delta is the sphere's verdict and the ruler's lit span, and nowhere in
/// text twice. The levers' years are in the dropdown (as one summary line when
/// it is shut, as rows when it is open). The caveats, the ladder and the
/// citations are behind the two sheets, where a reader who wants them finds them
/// and nobody else has to scroll past them.
///
/// ## An estimate that was paused still has a screen
///
/// The sphere is the same ball, dimmed and still, with no number in it and no
/// older number standing in for one. [AgePausedNotice] says why in the server's
/// own words, there is no ruler (it needs a number), and the dropdown starts
/// open so the lever that is missing is the first thing read. A lever that is
/// permanently left out of the estimate is a row of the card either way.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:healthee/core/router.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/data/history/dated_history.dart';
import 'package:healthee/data/history/history_metric.dart';
import 'package:healthee/data/honesty/disclosure.dart';
import 'package:healthee/data/honesty/reading.dart';
import 'package:healthee/data/models/biological_age.dart';
import 'package:healthee/data/models/today_snapshot.dart';
import 'package:healthee/data/today_repository.dart';
import 'package:healthee/features/today/v02/age_calculation_sheet.dart';
import 'package:healthee/features/today/v02/age_lever_sheets.dart';
import 'package:healthee/features/today/v02/age_paused.dart';
import 'package:healthee/features/today/v02/age_screen_parts.dart';
import 'package:healthee/features/today/v02/today_hero.dart';
import 'package:healthee/features/today/v02/what_moves_it.dart';
import 'package:healthee/shared/history_link.dart';
import 'package:healthee/shared/metric_info/metric_detail.dart';
import 'package:healthee/shared/metric_info/metric_info_sheet.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:healthee/shared/states/current_account_value.dart';
import 'package:healthee/shared/states/state_scaffold.dart';
import 'package:healthee/shared/v02/age_orb_hero.dart';
import 'package:healthee/shared/v02/data_footer.dart';
import 'package:healthee/shared/v02/dated_history.dart';
import 'package:healthee/shared/v02/detail_page.dart';
import 'package:healthee/shared/v02/instruments/age_ruler.dart';
import 'package:healthee/shared/v02/instruments/age_sphere.dart';
import 'package:healthee/shared/v02/view_day.dart';

/// The screen's title.
const String kBodyTitle = 'Biological age';

/// The past-day heading, with the app's own reason under it.
const String kBodyPastTitle = 'Estimated biological age';

/// The sphere's canvas on this screen, logical px; less on a narrower phone.
const double kBodySphereCanvas = 330;

/// The biological-age detail screen.
class BodyScreen extends ConsumerStatefulWidget {
  /// Builds the screen. [now] pins the clock for the "Updated" line.
  const BodyScreen({this.now, super.key});

  /// The clock; null reads the wall.
  final DateTime? now;

  @override
  ConsumerState<BodyScreen> createState() => _BodyScreenState();
}

class _BodyScreenState extends ConsumerState<BodyScreen> {
  /// Outlives every panel, which is the whole reveal-once mechanism.
  final RevealRegistry _reveals = RevealRegistry();

  @override
  Widget build(BuildContext context) {
    final ViewDay day = watchViewDay(ref);
    // One age-model result exists and it is dated today. `/api/today` takes no
    // day, so an older date gets the refusal rather than this morning's figure
    // under it, with the model's measured inputs, dated, below it.
    if (day.isPast) {
      return _Frame(
        date: day.day,
        status: day.status,
        children: pastDayDetail(
          refusalTitle: kBodyPastTitle,
          history: ref.watch(datedHistoryProvider),
          metrics: const <HistoryMetric>[
            HistoryMetric.fitness,
            HistoryMetric.sleepRegularity,
          ],
          unserved: const <String>[kUnservedSleepDuration],
          day: day.day,
          reveals: _reveals,
          onRetry: () => ref.invalidate(datedHistoryProvider),
          onOpenMetric: (metric) => openMetricHistory(context, metric),
        ),
      );
    }
    final view = currentAccountValue(ref.watch(todaySnapshotProvider));
    return view.when(
      skipLoadingOnRefresh: true,
      loading: () => const _Frame(
        children: <Widget>[LoadingState(label: 'Reading your estimate')],
      ),
      error: (error, stackTrace) => _Frame(
        children: <Widget>[
          ErrorState(
            message: "Couldn't reach your server for your estimate",
            detail: 'This is a connection problem, not a gap in your data.',
            onRetry: () => ref.invalidate(todaySnapshotProvider),
          ),
        ],
      ),
      data: (value) => BodyDetail(
        snapshot: value.snapshot,
        reveals: _reveals,
        now: widget.now,
      ),
    );
  }
}

/// The screen's body. Public so the screen tests can host it directly.
class BodyDetail extends StatelessWidget {
  /// Builds the detail for one render of `/api/today`.
  const BodyDetail({
    required this.snapshot,
    required this.reveals,
    this.now,
    super.key,
  });

  /// The payload every figure on this screen comes off.
  final TodaySnapshot snapshot;

  /// Where "already revealed" is remembered.
  final RevealRegistry reveals;

  /// The clock; null reads the wall.
  final DateTime? now;

  /// The levers this estimate permanently does not price, refused or not.
  ///
  /// A valued payload carries them on the parsed estimate, because the envelope
  /// folds exclusions in with the caveats and this screen has to tell the two
  /// apart (`biological_age.dart` records why). A refused one carries them on
  /// the reading, which is the case `Withheld.exclusions` exists for.
  List<Disclosure> get exclusions => switch (snapshot.biologicalAge) {
    Withheld<BiologicalAge>(:final exclusions) => exclusions,
    Excluded<BiologicalAge>(:final exclusions) => exclusions,
    Present<BiologicalAge>(:final value) => value.exclusions,
    Caveated<BiologicalAge>(:final value) => value.exclusions,
  };

  /// What tilts the estimate: the caveats, with the exclusions taken back out.
  ///
  /// They arrive merged and they are two different claims: one says which way
  /// the number leans, the other says a lever is not in it at all. The lever
  /// card draws the second, and drawing it twice would read as two exclusions.
  /// A paused day has no caveats on the reading, but the server still sent the
  /// ones that say which way the surviving terms lean; they come from the block.
  List<Disclosure> get caveats => <Disclosure>[
    for (final caveat in switch (snapshot.biologicalAge) {
      Withheld<BiologicalAge>() => snapshot.bioAgeBlock.caveats,
      final reading => reading.caveatsOrEmpty,
    })
      if (!exclusions.contains(caveat)) caveat,
  ];

  @override
  Widget build(BuildContext context) {
    final BiologicalAge? age = snapshot.biologicalAge.valueOrNull;
    final block = snapshot.bioAgeBlock;
    final paused = snapshot.biologicalAge is Withheld<BiologicalAge>;
    final chronological = age?.chronologicalAge;
    final notes = age?.researchNotes ?? block.researchNotes;
    final colors = context.colors;
    return DetailPage(
      title: kBodyTitle,
      gutter: Insets.gutter,
      head: (context, onBack) => AgeNavRow(
        onBack: onBack,
        onInfo: () => showMetricInfo(
          context,
          'biological_age',
          detail: MetricDetail(
            source: age?.disclaimer ?? block.disclaimer,
            disclosures: caveats,
            notes: notes,
          ),
        ),
      ),
      children: <Widget>[
        const SizedBox(height: Insets.sm),
        Text(kBodyTitle, style: TypeLadder.title1.copyWith(color: colors.ink)),
        const SizedBox(height: Insets.xs),
        Text(
          ageUpdatedLine(snapshot.asOf?.derivedAt, now ?? DateTime.now()),
          style: TypeLadder.callout.copyWith(color: colors.ink2),
        ),
        const SizedBox(height: Insets.md),
        _Sphere(age: age, reveals: reveals),
        if (age == null) ...<Widget>[
          const SizedBox(height: Insets.md),
          AgePausedNotice(
            block: block,
            vo2maxWithheld: snapshot.vo2maxWithheld,
          ),
        ],
        if (age != null && chronological != null) ...<Widget>[
          const SizedBox(height: Insets.lg),
          RevealOnce(
            id: 'body.age-ruler',
            registry: reveals,
            builder: (context, t) => AgeRuler(
              estimate: age.biologicalAge,
              actual: chronological,
              progress: t,
            ),
          ),
        ],
        const SizedBox(height: Insets.section),
        WhatMovesIt(
          block: block,
          reveals: reveals,
          openByDefault: paused,
          // The notice above says why in the server's words; the rows say
          // only that the term is not counted.
          reasonsShownAbove: age == null,
          onOpenLever: (term) => openAgeLever(
            context,
            term,
            block: block,
            caveats: caveats,
            vo2max: snapshot.vo2max.valueOrNull,
            openSleep: () => unawaited(context.push(Routes.sleep)),
            openFitness: () => unawaited(context.push(Routes.fitness)),
          ),
        ),
        const SizedBox(height: Insets.cardGap),
        AgeCalculationCard(
          onTap: () => openAgeCalculation(
            context,
            age: age,
            caveats: caveats,
            researchNotes: notes,
          ),
        ),
        const SizedBox(height: Insets.cardGap),
        Text(
          kAgeFootnote,
          style: TypeLadder.caption.copyWith(color: colors.ink2),
        ),
        const SizedBox(height: Insets.section),
        const DataFooter(),
      ],
    );
  }
}

/// The sphere, with the figure and the verdict in it, or nothing in it when
/// the estimate is paused.
class _Sphere extends StatelessWidget {
  const _Sphere({required this.age, required this.reveals});

  final BiologicalAge? age;
  final RevealRegistry reveals;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final estimate = age;
    return LayoutBuilder(
      builder: (context, box) {
        final canvas = math.min(kBodySphereCanvas, box.maxWidth);
        final figure = ageOrbCentre(
          context,
          colors,
          canvas: canvas,
          value: estimate == null
              ? ''
              : TodayBioHero.figureOf(estimate.biologicalAge),
          verdict: estimate == null ? null : TodayBioHero.verdictOf(estimate),
          paused: estimate == null,
        );
        return Center(
          child: AgeSphere(
            canvas: canvas,
            withheld: estimate == null,
            clearHalfWidth: figure.halfWidth,
            centre: figure.centre,
            revealId: 'body.sphere',
            reveals: reveals,
          ),
        );
      },
    );
  }
}

/// The page the loading, error and past-day states are drawn in, so the head
/// and the gutter cannot differ between them.
class _Frame extends StatelessWidget {
  const _Frame({
    required this.children,
    this.date,
    this.status = kLatestSample,
  });

  final List<Widget> children;
  final String? date;

  /// `Latest sample` unless the caller says otherwise: the body below is
  /// `/api/today`'s, which is the current day by construction.
  final String? status;

  @override
  Widget build(BuildContext context) => DetailPage(
    title: kBodyTitle,
    eyebrow: dayEyebrow(date, status),
    children: children,
  );
}
