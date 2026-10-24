/// `Fitness` — the prototype's `#fitness`, opened from Activity and from Sleep.
///
/// `design/mobile-preview/screens-fitness.js::H.screens.fitness`, read top to
/// bottom:
///
/// ```text
///   header                        Fitness
///   Cardiorespiratory fitness     the estimate, its rail, its error magnitude
///   Your stored estimate history  every estimate the server has kept
///   Which instrument produced it? the fit behind a session-read estimate
///   context bridge                the fitness term of the age model
///   The work behind your capacity today's load against the fortnight
///   A rhythm to build on          the week's minutes, strength and steps
///   footer
/// ```
///
/// ## The two panels at the bottom read the tab's own blocks
///
/// `WorkPanel` and `RhythmPanel` draw `cardio_load`, `mvpa` and `strength` —
/// the same fields the Activity tab draws, under the prototype's own titles for
/// this screen. Neither computes a load, a week or a step count of its own,
/// which is the part CLAUDE.md's one-definition rule is about; what differs is
/// the question being asked, which is why the prototype gives them their own
/// titles and notes.
///
/// ## The bridge names a contribution only when the model sent one
///
/// `ageBridge` builds its sentence from `contributions[]`. There is no fallback:
/// a bridge that named a year figure the server did not send would be inventing
/// the one number it exists to carry.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:healthee/core/router.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/data/history/dated_history.dart';
import 'package:healthee/data/history/history_metric.dart';
import 'package:healthee/data/models/activity_today.dart';
import 'package:healthee/data/models/today_snapshot.dart';
import 'package:healthee/data/models/vo2max.dart';
import 'package:healthee/data/today_repository.dart';
import 'package:healthee/features/activity/activity_sections.dart';
import 'package:healthee/features/activity/v02/fitness_effort_panels.dart';
import 'package:healthee/features/activity/v02/fitness_panels.dart';
import 'package:healthee/shared/history_link.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:healthee/shared/states/caveat_scope.dart';
import 'package:healthee/shared/states/current_account_value.dart';
import 'package:healthee/shared/states/reading_view.dart';
import 'package:healthee/shared/states/state_scaffold.dart';
import 'package:healthee/shared/v02/context_bridge.dart';
import 'package:healthee/shared/v02/data_footer.dart';
import 'package:healthee/shared/v02/dated_history.dart';
import 'package:healthee/shared/v02/detail_page.dart';
import 'package:healthee/shared/v02/view_day.dart';
import 'package:healthee/shared/v02/withheld_panel.dart';

/// The prototype's own title for this screen.
const String kFitnessTitle = 'Fitness';

/// `screens.fitness`'s past-day heading, with the app's own reason under it.
const String kFitnessPastTitle = 'VO₂max, its instrument and its history';

/// `H.note('Historical method and uncertainty metadata are not supplied with
/// these estimates.')` — the sentence the prototype puts under the dated VO₂max
/// chart, said about this server's own wire.
///
/// It is not decoration. VO₂max is a **tiered** metric (#117): a graded session,
/// a heart-rate-reserve inversion and the non-exercise model can each have
/// produced a point on this line, and they differ by more than a fortnight of
/// real fitness change. `read/vo2max.py:180` drops the method when it builds
/// the series and `/api/history` never carried one, so a rise on this chart
/// cannot be told from a change of instrument.
/// `BACKEND_GAPS_FROM_UI.md` B2 is the entry for fixing that; until it is fixed
/// the chart says so, which is the difference between a caveat and a legend.
const String kFitnessSeriesNote =
    'Each point is the estimate stored for that day, and the wire does not say '
    'which instrument produced it. A step on this line can be a change of '
    'method rather than a change of fitness.';

/// The fitness detail screen.
class FitnessScreen extends ConsumerStatefulWidget {
  /// Builds the screen.
  const FitnessScreen({super.key});

  @override
  ConsumerState<FitnessScreen> createState() => _FitnessScreenState();
}

class _FitnessScreenState extends ConsumerState<FitnessScreen> {
  /// Outlives every panel, which is the whole reveal-once mechanism.
  final RevealRegistry _reveals = RevealRegistry();

  @override
  Widget build(BuildContext context) {
    final ViewDay day = watchViewDay(ref);
    // The estimate, its INSTRUMENT and its freshness gate all arrive on
    // `/api/today`, which takes no day, so a past date still gets the refusal.
    // The stored series is a different thing and is drawn: `derived_daily`
    // holds one VO₂max row per day, dated, and charting it claims nothing about
    // what today's tier would say.
    if (day.isPast) {
      return _Frame(
        date: day.day,
        status: day.status,
        children: pastDayDetail(
          refusalTitle: kFitnessPastTitle,
          history: ref.watch(datedHistoryProvider),
          // `panels(['vo2'])`, the note, then `panels(['load','mvpa','steps'])`.
          metrics: const <HistoryMetric>[
            HistoryMetric.fitness,
            HistoryMetric.cardioLoad,
            HistoryMetric.activeMinutes,
            HistoryMetric.steps,
          ],
          notes: const <HistoryMetric, String>{
            HistoryMetric.fitness: kFitnessSeriesNote,
          },
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
        children: <Widget>[LoadingState(label: 'Reading your fitness')],
      ),
      error: (error, stackTrace) => _Frame(
        children: <Widget>[
          ErrorState(
            message: "Couldn't reach your server for your fitness",
            detail: 'This is a connection problem, not a gap in your data.',
            onRetry: () => ref.invalidate(todaySnapshotProvider),
          ),
        ],
      ),
      data: (value) =>
          FitnessDetail(snapshot: value.snapshot, reveals: _reveals),
    );
  }
}

/// The screen's body. Public so the screen tests can host it directly.
class FitnessDetail extends StatelessWidget {
  /// Builds the detail for one render of `/api/today`.
  const FitnessDetail({
    required this.snapshot,
    required this.reveals,
    super.key,
  });

  /// Between two cards: [Insets.cardGap].
  static const double panelGap = Insets.cardGap;

  /// Between two sections: [Insets.section].
  static const double blockGap = Insets.section;

  /// The payload every figure on this screen comes off.
  final TodaySnapshot snapshot;

  /// Where "already revealed" is remembered.
  final RevealRegistry reveals;

  @override
  Widget build(BuildContext context) {
    final vo2max = snapshot.vo2max.valueOrNull;
    final years = fitnessContributionYears(snapshot.biologicalAge.valueOrNull);
    final rhythm = RhythmPanel(
      mvpa: snapshot.mvpa.valueOrNull,
      strength: snapshot.strength,
      steps: snapshot.metric('steps_total')?.reading.valueOrNull,
    );
    return _Frame(
      date: snapshot.date,
      children: <Widget>[
        ReadingView<Vo2max>(
          reading: snapshot.vo2max,
          label: 'VO₂max · estimate',
          caveatCarrier: CaveatCarrier.insideCard,
          withheldBuilder: (context, disclosure) =>
              WithheldPanel(disclosure: disclosure, label: 'VO₂max · estimate'),
          builder: (context, value) =>
              CardiorespiratoryPanel(vo2max: value, reveals: reveals),
        ),
        if (vo2max != null && vo2max.trend90d.length > 1) ...<Widget>[
          const SizedBox(height: panelGap),
          StoredHistoryPanel(
            vo2max: vo2max,
            reveals: reveals,
            onDetails: () => unawaited(
              context.push('${Routes.history}?metric=vo2max_estimate'),
            ),
          ),
        ],
        if (vo2max?.submax case final Vo2maxSubmax submax) ...<Widget>[
          const SizedBox(height: panelGap),
          InstrumentPanel(vo2max: vo2max!, submax: submax),
        ],
        if (years != null) ...<Widget>[
          // `H.bridge('fitness', …, 'body', 'Age contributions')` — the
          // sentence ends in the link, which is where the years it names are
          // worked out.
          ContextBridge.richLink(
            (style) => ageBridgeSpan(years, style),
            label: 'Age contributions',
            onOpen: () => unawaited(context.push(Routes.body)),
          ),
        ],
        const SizedBox(height: panelGap),
        ReadingView<CardioLoad>(
          reading: snapshot.cardioLoad,
          label: 'Strain · cardio load',
          caveatCarrier: CaveatCarrier.insideCard,
          withheldBuilder: (context, disclosure) => WithheldPanel(
            disclosure: disclosure,
            label: 'Strain · cardio load',
          ),
          builder: (context, load) => WorkPanel(
            load: load,
            reveals: reveals,
            onDetails: () => unawaited(context.push(Routes.activity)),
          ),
        ),
        if (rhythm.hasSomething) ...<Widget>[
          const SizedBox(height: panelGap),
          rhythm,
        ],
        const SizedBox(height: blockGap),
        const DataFooter(),
      ],
    );
  }
}

/// The page every state of this screen is drawn in, so the head and the gutter
/// cannot differ between them.
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
    title: kFitnessTitle,
    eyebrow: dayEyebrow(date, status),
    children: children,
  );
}
