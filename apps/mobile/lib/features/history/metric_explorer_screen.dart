/// **Health signals** — every signal this app reads, grouped by domain, each
/// with its fortnight trend against the owner's own usual range and one chip
/// saying how it is going.
///
/// ```text
///   Sun 18 Oct · Latest sample
///   Health signals
///   [ 22 signals | 3 outside usual | 0 no reading ]
///   ▭ your usual range   trend = last 14 days
///   Heart ........................................ 5 signals
///   [ one card of hairline-divided rows ]
///   … Breathing & oxygen · Sleep · Activity · Body
///   [ Sleep history ]  [ Fitness estimates ]
/// ```
///
/// The rule the colours follow is the colour kit's: the domain hue says what a
/// number is, the state colour says how it is going, and being inside your
/// usual range is neutral, never green. `shared/v02/reading_state.dart` owns the
/// verdict; `signal_rows.dart` owns where each figure comes from.
///
/// ## Why the rows are the latest reading and say so
///
/// `/api/today` takes no day, so under a past date every row would be today's
/// figure with yesterday's caption above it, which is stale-as-current. On a
/// past day the snapshot is withheld here, every row reads "No reading", and
/// [kPastDayCaption] says why. The dated figure for any signal is one tap away
/// on its own history screen, which reads `/api/history` and can answer for a day.
///
/// ## What is not listed
///
/// Only metrics `/api/history` answers for are shown, so a row can always open
/// its history. Signals with no daily series on this server (heart rate,
/// stress, time asleep, sleep efficiency, skin temperature) have no row rather
/// than a door onto an endpoint that refuses.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:healthee/core/router.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/data/today_repository.dart';
import 'package:healthee/features/history/v02/signal_rows.dart';
import 'package:healthee/features/history/v02/signal_sections.dart';
import 'package:healthee/shared/states/current_account_value.dart';
import 'package:healthee/shared/v02/data_footer.dart';
import 'package:healthee/shared/v02/detail_page.dart';
import 'package:healthee/shared/v02/list_rows.dart';
import 'package:healthee/shared/v02/surface_cards.dart' show SmallProse;
import 'package:healthee/shared/v02/view_day.dart';
import 'package:solar_icons/solar_icons.dart';

/// What every "No reading" means on a past day.
const String kPastDayCaption =
    'This directory lists the latest reading of each signal, and the latest '
    'reading is not the reading for the day above. Open a signal to see its '
    'own dated series, which stops on the day you chose.';

/// The explorer: every signal with a history, and the way into each one.
class MetricExplorerScreen extends ConsumerWidget {
  /// Builds the screen.
  const MetricExplorerScreen({super.key});

  /// `.section { margin-top: 24px }`.
  static const double sectionGap = 24;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ViewDay day = watchViewDay(ref);
    final view = currentAccountValue(ref.watch(todaySnapshotProvider));
    // **Null on a past day, and every row then reads "No reading".** Each
    // figure is the LATEST reading off `/api/today`, which takes no day, so
    // under an older date the list would be today's numbers with yesterday's
    // caption above it. The dated figure lives one tap away, on the signal's
    // own screen, which reads `/api/history`.
    final snapshot = day.isPast ? null : view.value?.snapshot;
    final groups = signalGroups(snapshot);
    void open(String metric) => unawaited(
      context.push('${Routes.history}?metric=${Uri.encodeComponent(metric)}'),
    );
    return DetailPage(
      title: 'Health signals',
      largeTitle: true,
      eyebrow: day.isPast
          ? day.line
          : dayEyebrow(view.value?.snapshot.date, day.status),
      children: <Widget>[
        SignalSummary(tally: SignalTally.of(groups)),
        const SizedBox(height: 12),
        const SignalLegend(),
        if (day.isPast) ...<Widget>[
          const SizedBox(height: 12),
          const SmallProse(kPastDayCaption),
        ],
        for (final group in groups) ...<Widget>[
          const SizedBox(height: sectionGap),
          SignalGroupView(group: group, onOpen: open),
        ],
        const SizedBox(height: sectionGap),
        FlushCard(
          rows: <Widget>[
            // Pushed, never `go`: `go` REPLACES, which would leave the
            // destination with nothing under it and this screen unreachable by
            // Back. `out_of_shell_navigation_test.dart` owns that rule.
            V02ListRow(
              icon: SolarIconsOutline.moonSleep,
              title: 'Sleep history',
              detail: 'Duration, stages and regularity',
              tone: Tone.sleep,
              onOpen: () => unawaited(context.push(Routes.sleepHistory)),
            ),
            V02ListRow(
              icon: SolarIconsOutline.heartPulse,
              title: 'Fitness estimates',
              detail: 'VO₂max and biological age',
              tone: Tone.fitness,
              onOpen: () => unawaited(context.push(Routes.fitness)),
            ),
          ],
        ),
        const SizedBox(height: sectionGap),
        const DataFooter(),
      ],
    );
  }
}
