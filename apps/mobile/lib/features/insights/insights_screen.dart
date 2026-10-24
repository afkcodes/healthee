/// Insights — where the owner's own history is read back to them.
///
/// Composition only: the frame, the two data sources and the reveal registry are
/// `shared/instrument_screen.dart`'s, and `insights_sections.dart` decides what
/// this screen shows and in what order. This file is the wiring — the six places
/// the screen can reach — and nothing else.
///
/// This is `docs/APP_DESIGN.md` §2's fourth tab and legacy's (Today · Sleep ·
/// Activity · **Insights** · Actions). It holds the two things that are about
/// the *history* rather than about today: how each tracked metric has been
/// moving, and the correlations the analytics layer found in this one person's
/// data.
///
/// The findings used to be on a tab called Coach. That was wrong twice over —
/// the coach is not a tab in legacy (it is a button on Today, and it is one
/// again), and the findings are not the coach: they are the evidence a coach
/// question would be answered *from*. The prototype says the same thing in its
/// own order, by ending this screen on `A useful question comes next`.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:healthee/core/router.dart';
import 'package:healthee/features/insights/insights_sections.dart';
import 'package:healthee/shared/history_link.dart';
import 'package:healthee/shared/instrument_screen.dart';

/// The Insights tab.
class InsightsScreen extends StatelessWidget {
  /// [now] is injected by tests so the freshness labels are deterministic.
  const InsightsScreen({this.now, super.key});

  /// The instant every "x min ago" is measured against.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    return InstrumentScreen(
      now: now,
      sections: (ScreenData data) => insightsSections(
        data,
        InsightsExtras(
          // Pushed, never `go`: `go` REPLACES the location, which leaves the
          // destination with nothing beneath it and the next Back leaves the
          // app. `back_navigation_test.dart` owns that rule.
          onOpenProfile: () => unawaited(context.push(Routes.settings)),
          onOpenMetric: (metric) => openMetricHistory(context, metric),
          onOpenHistory: () => unawaited(context.push(Routes.history)),
          onOpenLedger: () => unawaited(context.push(Routes.coachLedger)),
          onOpenJournal: () => unawaited(context.push(Routes.journal)),
          // `H.panel('A useful question comes next', …, 'coach')` — the panel
          // whose Details link and whose button both open the coach. No topic:
          // the panel's own question is what would you like to understand.
          onOpenCoach: () => unawaited(context.push(Routes.coach)),
          onOpenTrends: () => unawaited(context.push(Routes.trends)),
          onOpenSleepHistory: () =>
              unawaited(context.push(Routes.sleepHistory)),
          onOpenFitness: () => unawaited(context.push(Routes.fitness)),
        ),
      ),
    );
  }
}
