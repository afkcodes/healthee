/// Today — what the strap measured, and what the server made of it.
///
/// Composition only. The frame, the two data sources, the failure rules and the
/// reveal registry all live in `shared/instrument_screen.dart`, which four other
/// screens use for the same reasons; `today_sections.dart` decides what Today
/// shows and in what order. This file is the wiring between them plus the four
/// things only Today holds — the push stamp, the server session, the classified
/// connection those two feed, and the chapter anchors.
///
/// ## The connection surface is assembled here, from one classification
///
/// `connectionHealth(...)` is called once, in this build, and the answer goes to
/// three places: the ring round the avatar, the dot on the device strip, and the
/// data-health card under it. One call, three readers, and none of them may
/// decide "quiet" for itself.
///
/// ## Why this is stateful now
///
/// The chapter nav jumps to three headings, and a heading is found through a
/// `GlobalKey` that must be **the same object across rebuilds** — a key created
/// in `build` would move the anchor every frame and would collide with a second
/// live Today in a test. `TodayChapters` owns those three keys, so it has to
/// outlive a build: it is a `final` field of this `State`.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:healthee/core/router.dart';
import 'package:healthee/data/api/server_session.dart';
import 'package:healthee/data/challenges/commitment_repository.dart';
import 'package:healthee/data/device/device_repository.dart';
import 'package:healthee/data/push/push_stamp_provider.dart';
import 'package:healthee/data/sleep_repository.dart';
import 'package:healthee/data/store/store_provider.dart';
import 'package:healthee/data/store/view_date.dart';
import 'package:healthee/data/sync/connection_health.dart';
import 'package:healthee/data/sync/sync_controller.dart';
import 'package:healthee/features/today/today_sections.dart';
import 'package:healthee/features/today/v02/date_control.dart';
import 'package:healthee/features/today/v02/today_chapters.dart';
import 'package:healthee/shared/history_link.dart';
import 'package:healthee/shared/instrument_screen.dart';

/// The app's home screen.
class TodayScreen extends ConsumerStatefulWidget {
  /// [now] is injected by tests so the freshness labels are deterministic.
  const TodayScreen({this.now, super.key});

  /// The instant every "x min ago" is measured against.
  final DateTime? now;

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  /// The three jump anchors. Per screen, and outliving every build — see the
  /// library docstring.
  final TodayChapters _chapters = TodayChapters();

  @override
  Widget build(BuildContext context) {
    final at = widget.now ?? DateTime.now();
    // The wall-clock day, NOT the selection: it is the control's forward bound
    // and the day `Latest` returns to, so it has to keep meaning "now".
    final today = ref.watch(todayProvider);
    // Held, not watched: the Sleep key number's usual is built from these
    // nights, and the card is a list item that unmounts when scrolled away.
    // Without a listener here the page would be dropped and fetched again
    // every time the card came back into view.
    ref.listen(sleepPageProvider, (_, _) {});
    final push = ref.watch(pushStampProvider).value;
    // `.value?.signedIn` and not `.requireValue`: while the keystore read is in
    // flight this is null, which the data-health strip reads as "not yet known"
    // and stays silent about. Guessing "signed out" for a frame would flash an
    // invitation at an owner who already is.
    final signedIn = ref.watch(serverSessionProvider).value?.signedIn;
    final health = connectionHealth(
      link: ref.watch(syncControllerProvider),
      now: at,
      push: push,
      signedIn: signedIn,
      lastStrapSync: ref.watch(deviceDayProvider).value?.sync.lastCompleteSync,
    );
    return InstrumentScreen(
      now: widget.now,
      onRefreshed: () {
        ref.invalidate(pushStampProvider);
        ref.invalidate(challengeFeedProvider);
        ref.invalidate(sleepConsistencyProvider);
      },
      sections: (data) => todaySections(
        data,
        TodayExtras(
          push: push,
          signedIn: signedIn,
          health: health,
          batteryPercent: ref.watch(deviceDayProvider).value?.batteryPercent,
          chapters: _chapters,
          navigation: DateNavigation(
            // The wall clock bounds the forward end and the retention horizon
            // the backward one, so the control can only ask for a day this
            // phone is able to answer for. `view_date.dart` owns both.
            earliest: earliestViewableDay(today),
            latest: today,
            onSelect: ref.read(viewDateProvider.notifier).select,
          ),
          // Pushed, so back returns to Today. `go` would replace the
          // location and leave the sign-in screen with nothing beneath it.
          onSignIn: () => unawaited(context.push(Routes.serverSignIn)),
          onOpenProfile: () => unawaited(context.push(Routes.settings)),
          // The coach is a route now — the header's button pushes the same
          // one, so the entry card and the button cannot drift apart. No topic:
          // this card asks nothing in particular.
          onOpenCoach: () => unawaited(context.push(Routes.coach)),
          onOpenActions: () => context.go(Routes.actions),
          // The three key numbers and the biological-age hero. Pushed,
          // because they are destinations the owner came from Today and
          // expects to return to; the two that ARE tabs use `go`, because a
          // bar switches between siblings (`router.dart`'s table).
          onOpenRecovery: () => unawaited(context.push(Routes.recovery)),
          onOpenBody: () => unawaited(context.push(Routes.body)),
          onOpenSleep: () => context.go(Routes.sleep),
          onOpenActivity: () => context.go(Routes.activity),
          onOpenTrends: () => unawaited(context.push(Routes.trends)),
          // Every panel's `Details` link. The two tabs above use `go` because a
          // bar switches between siblings; everything below is a destination
          // the owner came from Today and expects to come back to, so it is
          // pushed (`router.dart`'s table).
          onOpenMetric: (metric) => openMetricHistory(context, metric),
          onOpenFitness: () => unawaited(context.push(Routes.fitness)),
          onOpenWorkouts: () => unawaited(context.push(Routes.workouts)),
        ),
      ),
    );
  }
}
