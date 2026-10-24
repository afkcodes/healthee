/// A plan and a done-set for the breathing tests. **Not a test.**
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' show Fake;
import 'package:go_router/go_router.dart';
import 'package:healthee/core/routes.dart';
import 'package:healthee/core/theme/app_theme.dart';
import 'package:healthee/data/basics/breathing/breathing_done.dart';
import 'package:healthee/data/basics/breathing/breathing_history.dart';
import 'package:healthee/data/basics/breathing/breathing_plan.dart';
import 'package:healthee/data/basics/breathing/breathing_plan_builder.dart';
import 'package:healthee/data/basics/breathing/breathing_plan_provider.dart';
import 'package:healthee/data/basics/breathing/breathing_session_log.dart';
import 'package:healthee/data/basics/breathing/breathing_settings.dart';
import 'package:healthee/data/basics/breathing/breathing_settings_provider.dart';
import 'package:healthee/data/notifications/notification_providers.dart';
import 'package:healthee/data/notifications/notification_service.dart';
import 'package:healthee/data/store/local_store.dart';
import 'package:healthee/data/store/store_provider.dart';
import 'package:healthee/features/coach/breathing_plan_screen.dart';
import 'package:healthee/features/coach/breathing_player_screen.dart';
import 'package:healthee/shared/usual_range.dart';

/// The owner's morning in these tests.
final DateTime kBreathingNow = DateTime(2026, 10, 19, 9);

/// A plan built the real way from [nights] nights, with the on-demand item
/// when [stress] is true.
BreathingPlan defaultBreathingPlan({
  int nights = 14,
  bool stress = true,
  BreathingSettings settings = const BreathingSettings(),
}) => buildBreathingPlan(
  now: kBreathingNow,
  history: BreathingHistory(
    nights: [
      for (var i = 0; i < nights; i++)
        SleepNight(
          onset: DateTime(2026, 10, 18 - i, 22 + i % 2, 30),
          wake: DateTime(2026, 10, 19 - i, 8, 14 + i % 3),
        ),
    ],
    stress: stress ? [StressSample(DateTime(2026, 10, 18, 4, 30), 33)] : [],
  ),
  settings: settings,
  hrv: 43.9,
  hrvUsual: const UsualRange(low: 44, high: 57, days: 30),
);

/// A done-set that never touches the store.
class FixedBreathingDone extends BreathingDoneController {
  /// Starts as [done].
  FixedBreathingDone(this.done);

  /// What is done.
  final Set<BreathingItemKind> done;

  @override
  Future<Set<BreathingItemKind>> build() async => done;

  @override
  Future<void> mark(BreathingItemKind kind) async {
    done.add(kind);
    state = AsyncData({...done});
  }
}

/// Records the reminder syncs.
class FakeNotifications extends Fake implements NotificationService {
  /// Every plan the reminders were synced to.
  final List<BreathingPlan> synced = [];

  @override
  Future<void> syncBreathingReminders(BreathingPlan plan) async =>
      synced.add(plan);
}

/// Records the minutes logged.
class FakeSessionLog extends Fake implements BreathingSessionLog {
  /// Every whole-minute amount logged.
  final List<int> minutes = [];

  /// Throw on the next save.
  bool failNext = false;

  @override
  Future<bool> logSession(int minutes) async {
    if (failNext) {
      failNext = false;
      throw Exception('journal down');
    }
    this.minutes.add(minutes);
    return true;
  }
}

/// A host for the breathing screens over a memory store, a router that records
/// where it went, and fakes for the notifications and the journal.
class BreathingHarness {
  /// A harness over [store].
  BreathingHarness(this.store);

  /// The on-device store.
  final LocalStore store;

  /// The reminders.
  final FakeNotifications notifications = FakeNotifications();

  /// The journal.
  final FakeSessionLog log = FakeSessionLog();

  /// Locations pushed to the router.
  final List<String> visited = [];

  /// Plan items already done today.
  Set<BreathingItemKind> done = {};

  /// Builds the plan from the settings, as the real provider does.
  BreathingPlan Function(BreathingSettings) planFor = (s) =>
      defaultBreathingPlan(settings: s);

  /// [home] at `/`, with the two breathing routes wired.
  Widget app(
    Widget home, {
    String location = '/',
    Brightness brightness = Brightness.light,
    double textScale = 1,
    bool reducedMotion = false,
  }) {
    final router = GoRouter(
      initialLocation: location,
      routes: <RouteBase>[
        GoRoute(path: '/', builder: (context, state) => home),
        GoRoute(
          path: Routes.breathingPlan,
          builder: (context, state) {
            visited.add(state.uri.toString());
            return const BreathingPlanScreen();
          },
        ),
        GoRoute(
          path: Routes.breathingPlayer,
          builder: (context, state) {
            visited.add(state.uri.toString());
            return BreathingPlayerScreen(
              item: state.uri.queryParameters['item'],
              patternId: state.uri.queryParameters['pattern'],
            );
          },
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        breathingClockProvider.overrideWithValue(() => kBreathingNow),
        notificationServiceProvider.overrideWithValue(notifications),
        breathingSessionLogProvider.overrideWith((ref) async => log),
        breathingDoneProvider.overrideWith(() => FixedBreathingDone(done)),
        breathingPlanProvider.overrideWith((ref) async {
          final settings = await ref.watch(
            breathingSettingsControllerProvider.future,
          );
          return planFor(settings);
        }),
      ],
      child: MaterialApp.router(
        theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reducedMotion,
          ),
          child: child!,
        ),
      ),
    );
  }
}
