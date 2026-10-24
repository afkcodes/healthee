/// One finding, opened from the Insights relationship card.
///
/// The prototype's `H.screens.insight`. Composition only — every sentence and
/// every number on it is built in `finding_detail_parts.dart`.
///
/// ## How the screen finds its finding
///
/// **The server sends findings with no id.** `read/findings.py::_shape` emits
/// `kind`, `metric_a`, `metric_b`, `event_kind`, `lag_days` and the statistics;
/// there is no stable key to route on. So the route carries the pair itself, and
/// the finding travels alongside it in `extra`:
///
///   * a tap from the card passes the object — the screen draws immediately, and
///     what it draws is exactly what the card was showing;
///   * a cold start on the URL (a restored stack, a deep link) has no `extra`,
///     so the screen re-resolves the pair against today's findings.
///
/// If neither yields a finding the screen says so and offers the way back. It
/// does **not** synthesise one from the route: the path segment holds two metric
/// names and a lag, which is enough to name a pattern and nowhere near enough to
/// restate its strength. A screen that inferred the rest would be inventing the
/// only numbers it exists to show.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:healthee/core/router.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/data/models/finding.dart';
import 'package:healthee/data/today_repository.dart';
import 'package:healthee/features/coach/coach_topics.dart';
import 'package:healthee/features/insights/v02/finding_detail_parts.dart';
import 'package:healthee/shared/metric_info/metric_detail.dart';
import 'package:healthee/shared/metric_info/metric_info_sheet.dart';
import 'package:healthee/shared/states/current_account_value.dart';
import 'package:healthee/shared/v02/buttons.dart';
import 'package:healthee/shared/v02/data_footer.dart';
import 'package:healthee/shared/v02/detail_page.dart';
import 'package:healthee/shared/v02/full_button.dart';
import 'package:healthee/shared/v02/section_head.dart';
import 'package:healthee/shared/v02/surfaces.dart';

/// The route segment for [finding] — `metric_a~metric_b~lag`.
///
/// `~` because it is unreserved in a path segment, so the key needs no escaping
/// and reads as itself in a restored URL.
String findingKey(Finding finding) =>
    '${finding.metricA ?? ''}~${finding.metricB ?? ''}~${finding.lagDays ?? 0}';

/// The finding-detail screen.
class FindingDetailScreen extends ConsumerWidget {
  /// [routeKey] is [findingKey]'s output; [finding] is the object the tap
  /// carried, when there was one.
  const FindingDetailScreen({required this.routeKey, this.finding, super.key});

  /// The key from the path.
  final String routeKey;

  /// The finding the caller handed over, or null on a cold start.
  final Finding? finding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolved = finding ?? _fromToday(ref);
    if (resolved == null) {
      return const _NoLongerListed();
    }
    return _FindingDetail(finding: resolved);
  }

  /// Today's findings, searched for this pair. Null while loading, too — the
  /// screen only claims the pattern is gone once it has something to search.
  Finding? _fromToday(WidgetRef ref) {
    // `currentAccountValue` and not the raw provider: on an account switch the
    // stale value must not answer, and this screen would otherwise resolve a
    // pair out of the previous owner's findings.
    final view = currentAccountValue(ref.watch(todaySnapshotProvider));
    final snapshot = view.value?.snapshot;
    for (final candidate in snapshot?.findings ?? const <Finding>[]) {
      if (findingKey(candidate) == routeKey) {
        return candidate;
      }
    }
    return null;
  }
}

class _FindingDetail extends StatelessWidget {
  const _FindingDetail({required this.finding});

  final Finding finding;

  @override
  Widget build(BuildContext context) {
    final title = findingTitle(finding);
    return DetailPage(
      title: title,
      eyebrow: 'A pattern in your own history',
      children: <Widget>[
        const SizedBox(height: Insets.lg),
        Align(
          alignment: Alignment.centerLeft,
          child: StatusBadge(observationalBadge(finding), accented: true),
        ),
        ObservationBlock(
          headline: observationHeadline(finding),
          body: observationBody(finding),
        ),
        const SizedBox(height: Insets.xl),
        StatisticsCard(finding: finding),
        const SizedBox(height: Insets.xl),
        const SectionHead(title: 'A useful next step'),
        const SizedBox(height: Insets.md),
        FocusCard(
          // Not advice, and deliberately not about either metric: the app has
          // no per-finding suggestion on the wire, and inventing one from a
          // correlation is the exact over-reach this screen argues against.
          // Inviting context is a thing the owner can do; a mechanism is not a
          // thing we know.
          title: const Text('Add what was happening around it.'),
          body: const Text(
            'A pattern is easier to read next to the day it came from. '
            'What you log alongside these numbers is what makes it legible.',
          ),
          footer: _JournalLink(),
        ),
        const SizedBox(height: Insets.xl),
        Align(
          alignment: Alignment.centerLeft,
          child: MetricInfoDot(
            // No explainer key: a correlation found in one person's history is
            // not a metric the corpus has an entry for. `findings_section.dart`
            // makes the same call for the same reason.
            null,
            detail: MetricDetail(title: title, notes: finding.researchNoteIds),
            fallbackTitle: title,
          ),
        ),
        const SizedBox(height: Insets.lg),
        V02FullButton(
          label: 'Talk this through',
          // The finding is the subject. It rides in the location as the
          // conversation's opening message, which is the only place
          // `/api/coach` has for it — `coach_screen.dart` argues that.
          onPressed: () =>
              unawaited(context.push(coachLocation(findingTopic(title)))),
        ),
        const SizedBox(height: Insets.xl),
        const DataFooter(),
      ],
    );
  }
}

class _JournalLink extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Insets.sm),
    child: HLinkButton(
      label: 'Add a moment',
      onPressed: () => unawaited(context.push(Routes.journal)),
    ),
  );
}

/// What the screen shows when the pattern is not in the current results.
///
/// Findings are recomputed nightly and a pair that cleared the correction
/// yesterday may not today. That is the analysis working, not an error, so this
/// says what happened rather than showing a failure.
class _NoLongerListed extends StatelessWidget {
  const _NoLongerListed();

  @override
  Widget build(BuildContext context) => const DetailPage(
    title: 'This pattern isn’t in your current results.',
    eyebrow: 'A pattern in your own history',
    children: <Widget>[
      SizedBox(height: Insets.lg),
      Notice(
        title: 'Patterns are recomputed each night',
        body:
            'A pair that cleared the correction for the size of the search '
            'yesterday may not clear it today. Nothing is wrong — this one is '
            'simply not among the current findings.',
      ),
      SizedBox(height: Insets.xl),
      DataFooter(),
    ],
  );
}
