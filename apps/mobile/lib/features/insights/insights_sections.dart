/// The ordered sections of Insights. Composition only — no widget is defined here.
///
/// ```text
///   header                    day eyebrow · Insights
///   hero tiles                the strongest pattern, and fitness → age
///   Effort & stress           three readings and one linked chart
///   Longer patterns           six tiles of 14-day averages, and `All metrics`
///   What moved together       the findings, one card, never a verdict
///   links                     trends, outcomes, notable moments, sleep, fitness
///   a useful question         the way into the coach
///   footer
/// ```
///
/// ## The colour rule this screen exists to keep straight
///
/// Two blocks, two different licences for the better and worse colours:
///
/// | block | coloured? | why |
/// |---|---|---|
/// | **Longer patterns** | yes, where polarity is known | a metric moving against the owner's own past, with a table that says which way is better (`shared/format/metric_polarity.dart`) |
/// | **What moved together** | never | the sign of a rank correlation is a *direction*, together or opposite, and n-of-1 observational data cannot support "good for you"; it takes the together (blue) and opposite (orange) hues |
///
/// A neutral or unknown-polarity trend gets no colour either, which
/// `pattern_tile.dart` argues is the load-bearing case rather than the leftover.
///
/// ## Two things that are deliberately NOT here
///
/// **The recovery signal ladder is on Today and stays there.** It renders the
/// server's own `direction` field, and CLAUDE.md allows one definition per
/// metric: computing a second opinion here would be free to disagree with the
/// first.
///
/// **There is no "days that stood out" block fed by `/api/today`'s
/// `anomalies`.** That endpoint does not scan for shifts: the key used to ship
/// `[]`, which is indistinguishable from "nothing was anomalous", and is `null`
/// now beside a reason pointing at `/api/notable`
/// (`docs/BACKEND_GAPS_FROM_UI.md` A3).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthee/data/history/dated_history.dart';
import 'package:healthee/data/history/history_metric.dart';
import 'package:healthee/data/models/finding.dart';
import 'package:healthee/data/models/today_snapshot.dart';
import 'package:healthee/data/models/trend_point.dart';
import 'package:healthee/features/insights/v02/coach_question_panel.dart';
import 'package:healthee/features/insights/v02/effort_stress_card.dart';
import 'package:healthee/features/insights/v02/effort_stress_stats.dart';
import 'package:healthee/features/insights/v02/insight_links.dart';
import 'package:healthee/features/insights/v02/moved_together.dart';
import 'package:healthee/features/insights/v02/pair_reading.dart';
import 'package:healthee/features/insights/v02/pattern_panels.dart';
import 'package:healthee/features/insights/v02/section_title.dart';
import 'package:healthee/features/insights/widgets/trends_section.dart';
import 'package:healthee/shared/instrument_screen.dart';
import 'package:healthee/shared/page_section.dart';
import 'package:healthee/shared/section_list.dart';
import 'package:healthee/shared/v02/data_footer.dart';
import 'package:healthee/shared/v02/dated_history.dart';
import 'package:healthee/shared/v02/page_header.dart';
import 'package:healthee/shared/v02/past_day.dart';

/// What Insights cannot date. `screens.insights`'s own past-day heading.
const String kInsightsPastTitle = 'Patterns for this day';

/// Everything Insights needs that is not on [ScreenData].
@immutable
class InsightsExtras {
  /// The places this screen can go.
  const InsightsExtras({
    this.onOpenProfile,
    this.onOpenMetric,
    this.onOpenHistory,
    this.onOpenLedger,
    this.onOpenJournal,
    this.onOpenCoach,
    this.onOpenSleepHistory,
    this.onOpenTrends,
    this.onOpenFitness,
  });

  /// Opens settings.
  final VoidCallback? onOpenProfile;

  /// Opens one metric's own history. A pattern tile's tap.
  final void Function(String metric)? onOpenMetric;

  /// Opens the metric explorer. The section head's `All metrics`.
  final VoidCallback? onOpenHistory;

  /// Opens the challenge outcomes.
  final VoidCallback? onOpenLedger;

  /// Opens the journal.
  final VoidCallback? onOpenJournal;

  /// Opens the coach sheet.
  final VoidCallback? onOpenCoach;

  /// Opens the sleep history — every night in the window.
  final VoidCallback? onOpenSleepHistory;

  /// Opens `Your trends`.
  final VoidCallback? onOpenTrends;

  /// Opens the fitness detail — VO₂max and its instrument.
  final VoidCallback? onOpenFitness;
}

/// `history-screens.js::screens.insights` — `panels([…])`, in its order.
///
/// ```js
/// panels(['hrv','rhr','efficiency','regularity','vo2','steps'])
/// ```
///
/// Five of the six. `efficiency` is the night's efficiency percentage, which
/// this server keeps on the sleep session and not as a daily series — see
/// [kInsightsUnserved].
const List<HistoryMetric> kInsightsDatedMetrics = <HistoryMetric>[
  HistoryMetric.hrv,
  HistoryMetric.restingHr,
  HistoryMetric.sleepRegularity,
  HistoryMetric.fitness,
  HistoryMetric.steps,
];

/// The one panel `screens.insights` draws that has no dated series here.
const List<String> kInsightsUnserved = <String>[kUnservedSleepEfficiency];

/// Builds the ordered section list for one render of Insights.
List<PageSection> insightsSections(ScreenData data, InsightsExtras extras) {
  final past = data.view.isPast;
  // Null on a past day. Every correlation, trend window and hourly trace on
  // this screen is computed nightly for the current day and sent on
  // `/api/today`, which takes no day — so the only honest thing an older date
  // can do with this payload is not draw it. See `shared/v02/past_day.dart`.
  final snapshot = past ? null : data.snapshot;
  final findings = snapshot?.findings ?? const <Finding>[];
  final trends = trendsOf(snapshot?.sparklines ?? const {});
  final sections = SectionList()
    ..add(
      V02PageHeader(
        title: 'Insights',
        date: past ? data.view.day : (data.snapshot?.date ?? data.day.date),
        status: data.view.status,
      ),
    );
  if (past) {
    sections
      ..add(
        const PastDayNotice(title: kInsightsPastTitle, body: kPastDayReason),
      )
      ..gap(PageSpacing.panel);
    // `screens.insights`'s own words: *"explore the measurements available up
    // to this day"*. The correlations are refused above and stay refused; what
    // the reader gets instead is the dated series they were computed over.
    if (data.history case final AsyncValue<DatedHistory> history) {
      addDatedPanels(
        sections,
        history: history,
        metrics: kInsightsDatedMetrics,
        day: data.view.day,
        reveals: data.reveals,
        onRetry: data.onRetryHistory,
        onOpenMetric: extras.onOpenMetric,
      );
      if (unservedNotice(kInsightsUnserved) case final Widget notice) {
        sections.gap(PageSpacing.panel);
        sections.add(notice);
      }
      sections.gap(PageSpacing.block);
    }
  }
  if (!past) {
    if (data.serverFailure case final PageSection failure) {
      sections.addSection(failure);
      sections.gap(PageSpacing.panel);
    }
    if (data.serverPending case final PageSection pending) {
      sections.addSection(pending);
      sections.gap(PageSpacing.panel);
    }
  }
  if (snapshot != null) {
    // Always drawn once the payload has answered: a tile with nothing behind it
    // says so (hatched bar, "Not enough readings yet") rather than vanishing.
    sections
      ..add(
        HeroRow(
          pattern: strongestPair(findings),
          age: FitnessAge.from(snapshot.biologicalAge.valueOrNull),
        ),
      )
      ..gap(PageSpacing.block);
    if (EffortStressCard.hasSomethingToDraw(
      snapshot.hourlyHeartRate,
      snapshot.hourlyStress,
    )) {
      sections
        ..add(
          InsightSectionTitle(
            title: 'Effort & stress',
            caption: syncedWindow(
              snapshot.hourlyHeartRate,
              lastSync: data.day.sync.lastCompleteSync,
            ),
          ),
        )
        ..add(
          EffortStressCard(
            heartRate: snapshot.hourlyHeartRate,
            stress: snapshot.hourlyStress,
            reveals: data.reveals,
            restingHr: _restingHr(snapshot),
          ),
        )
        ..gap(PageSpacing.block);
    }
  }
  // A heading over no tiles reads as breakage. The honest state is silence: a
  // trend needs two days of the same metric and the server sends the window
  // once it has one.
  if (trends.isNotEmpty) {
    sections
      ..add(
        InsightSectionTitle(
          title: 'Longer patterns',
          actionLabel: 'All metrics',
          onAction: extras.onOpenHistory,
        ),
      )
      ..add(
        TrendsGrid(
          trends: trends,
          reveals: data.reveals,
          onOpenMetric: extras.onOpenMetric,
        ),
      )
      ..gap(PageSpacing.block);
  }
  if (findings.isNotEmpty) {
    sections
      ..add(
        const InsightSectionTitle(
          title: 'What moved together',
          caption: 'your data only',
        ),
      )
      ..add(MovedTogetherCard(findings: findings))
      ..gap(PageSpacing.block);
  }
  sections
    ..add(
      InsightLinks(
        onOpenTrends: extras.onOpenTrends,
        onOpenLedger: extras.onOpenLedger,
        onOpenJournal: extras.onOpenJournal,
        onOpenSleepHistory: extras.onOpenSleepHistory,
        onOpenFitness: extras.onOpenFitness,
      ),
    )
    ..gap(PageSpacing.block)
    ..add(CoachQuestionPanel(onOpenCoach: extras.onOpenCoach))
    ..gap(PageSpacing.block)
    ..add(const DataFooter());
  return sections.build();
}

/// The owner's resting heart rate for the dashed reference, from the metric
/// card the server already built for it. Null when the card has no reading.
double? _restingHr(TodaySnapshot snapshot) {
  for (final card in snapshot.metrics) {
    if (card.metric == 'rhr_daily') {
      return card.reading.valueOrNull;
    }
  }
  return null;
}

/// The tracked metrics that have a window worth drawing, in [kPatternSpecs]'
/// order.
///
/// Every spec's metric is in `kTrendMetrics` (`metric_trend_test` asserts it),
/// so a tile this screen draws is one `metric_polarity.dart` can judge.
List<MetricTrend> trendsOf(Map<String, List<TrendPoint>> sparklines) {
  return <MetricTrend>[
    for (final spec in kPatternSpecs)
      if (MetricTrend.from(spec.metric, sparklines[spec.metric] ?? const [])
          case final MetricTrend trend)
        trend,
  ];
}
