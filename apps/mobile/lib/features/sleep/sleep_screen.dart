/// Sleep — the v02 prototype's screen, on this app's own three reads.
///
/// Composition only. `sleep_sections.dart` decides what the screen shows and in
/// what order; this file is the frame around it — the reads, their failure
/// rules, the reveal registry and the five destinations the screen can reach.
///
/// ## Its own screen, not the Today shell
///
/// `shared/instrument_screen.dart` is built on `/api/today` and this phone's
/// store. Sleep is built on `/api/sleep`, `/api/sleep/consistency` and
/// `/api/sleep/insight` — **three reads that fail independently**. That is not
/// an accident of the client: `data/sleep_repository.dart` gives each its own
/// provider and its own timeout, and the regularity block feeds one panel and
/// must never be able to take the measured half of the screen down with it.
/// Bending the shared shell around a second payload would have made every other
/// screen carry a source only this one uses.
///
/// ## Reveal-once, and why the registry lives here
///
/// `CLAUDE.md`: *"Scrollable chart screens use `ListView.builder` + reveal-once
/// animation, or charts replay on every scroll."* The builder destroys an item's
/// element when it leaves the viewport, so "have I animated?" cannot live in the
/// chart. It lives in this `State` and is handed to the panels, each of which
/// wraps its own chart in a `RevealOnce` keyed to a stable id.
///
/// A refresh is the one thing that may reset the registry — new data earns a
/// fresh reveal. Scrolling never does.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:healthee/core/router.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/data/models/sleep_consistency.dart';
import 'package:healthee/data/models/sleep_page.dart';
import 'package:healthee/data/sleep_repository.dart';
import 'package:healthee/data/sync/sync_controller.dart';
import 'package:healthee/features/sleep/sleep_chapters.dart';
import 'package:healthee/features/sleep/sleep_sections.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:healthee/shared/skeletons/sleep_skeleton.dart';
import 'package:healthee/shared/states/current_account_value.dart';
import 'package:healthee/shared/states/state_scaffold.dart';
import 'package:healthee/shared/v02/view_day.dart';

/// The Sleep tab.
class SleepScreen extends ConsumerStatefulWidget {
  /// [now] is injected by tests so the night labels are deterministic.
  const SleepScreen({this.now, super.key});

  /// The instant "last night" is measured against.
  final DateTime? now;

  @override
  ConsumerState<SleepScreen> createState() => _SleepScreenState();
}

class _SleepScreenState extends ConsumerState<SleepScreen> {
  /// Outlives every list item, which is the whole reveal-once mechanism.
  final RevealRegistry _reveals = RevealRegistry();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _refresh,
          // All three states scroll, so pull-to-refresh works while the screen
          // is empty — which is exactly when it is reached for. `AsyncView` is
          // not used here only because the loading state is the content-shaped
          // `SleepSkeleton` rather than a spinner.
          child: ref
              .watch(sleepPageProvider)
              .when(
                skipLoadingOnRefresh: true,
                loading: () => const SleepSkeleton(),
                error: (error, stackTrace) => ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: SleepList.padding,
                  children: <Widget>[
                    ErrorState(
                      message: "Couldn't reach your server for your sleep",
                      detail:
                          'Your nights are safe. This is a connection problem, '
                          'not a gap in them.',
                      onRetry: () => ref.invalidate(sleepPageProvider),
                    ),
                  ],
                ),
                data: (page) => SleepList(
                  page: page,
                  view: watchViewDay(ref),
                  // Soft: the regularity block feeds one panel and must never
                  // be able to take the measured half of the screen down.
                  consistency: currentAccountValue(
                    ref.watch(sleepConsistencyProvider),
                  ).value,
                  now: widget.now ?? DateTime.now(),
                  reveals: _reveals,
                  extras: _extras(context),
                ),
              ),
        ),
      ),
    );
  }

  /// The five places this screen can go.
  ///
  /// Pushed, never `go`: `go` REPLACES the location, which leaves the
  /// destination with nothing beneath it and the next Back leaves the app.
  /// `back_navigation_test.dart` owns that rule.
  SleepExtras _extras(BuildContext context) => SleepExtras(
    onOpenProfile: () => unawaited(context.push(Routes.settings)),
    onOpenMetric: (metric) => unawaited(
      context.push('${Routes.history}?metric=${Uri.encodeComponent(metric)}'),
    ),
    onOpenJournal: () => unawaited(context.push(Routes.journal)),
    onOpenHistory: () => unawaited(context.push(Routes.sleepHistory)),
    // `Routes.history` with no `metric` IS the directory — one route, two
    // screens, as `router.dart` records.
    onOpenAllMetrics: () => unawaited(context.push(Routes.history)),
    chapters: _chapters,
  );

  /// One set of anchors for the screen's life, so a jump finds its heading.
  final SleepChapters _chapters = SleepChapters();

  /// Pull-to-refresh runs a real sync and re-reads all three payloads.
  Future<void> _refresh() async {
    await ref.read(syncControllerProvider.notifier).syncNow();
    ref
      ..invalidate(sleepPageProvider)
      ..invalidate(sleepConsistencyProvider)
      ..invalidate(sleepInsightProvider);
    _reveals.reset();
  }
}

/// The section list, scrolled. Public so the screen tests can host it directly.
class SleepList extends StatelessWidget {
  /// Builds the list for one render.
  const SleepList({
    required this.page,
    required this.consistency,
    required this.now,
    required this.reveals,
    required this.view,
    this.extras = const SleepExtras(),
    super.key,
  });

  /// `/api/sleep`.
  final SleepPage page;

  /// The night being read, and the wall-clock day it is judged against.
  final ViewDay view;

  /// `/api/sleep/consistency`, or null when that read has not answered.
  final SleepConsistency? consistency;

  /// The instant the night labels are measured against.
  final DateTime now;

  /// Where "already revealed" is remembered.
  final RevealRegistry reveals;

  /// Where the screen can go.
  final SleepExtras extras;

  /// The same gutter Today and Activity use.
  static const EdgeInsets padding = EdgeInsets.fromLTRB(
    Insets.gutter,
    Insets.gutter,
    Insets.gutter,
    120,
  );

  @override
  Widget build(BuildContext context) {
    if (page.nights.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: padding,
        children: const <Widget>[
          SizedBox(height: 200),
          EmptyState(
            message: 'No sleep recorded yet',
            hint: 'Wear the strap overnight and sync, and this fills in.',
          ),
        ],
      );
    }
    final sections = sleepSections(
      page: page,
      view: view,
      consistency: consistency,
      now: now,
      reveals: reveals,
      extras: extras,
    );
    return ListView.builder(
      // Always scrollable, so pull-to-refresh works on a short screen.
      physics: const AlwaysScrollableScrollPhysics(),
      padding: padding,
      itemCount: sections.length,
      itemBuilder: (context, index) => Padding(
        padding: EdgeInsets.only(bottom: sections[index].gap),
        child: sections[index].child,
      ),
    );
  }
}
