/// The router. Five tabs, the setup surfaces, and settings outside the shell.
///
/// The paths themselves are `core/routes.dart` — split out at the 400-line gate
/// and re-exported below, so `import 'core/router.dart'` still names them.
///
/// `docs/APP_DESIGN.md` §2 fixes the information architecture — five tabs (Today ·
/// Sleep · Activity · Insights · Actions), a Coach FAB on Today, and the owner's
/// own surfaces off the Today avatar rather than as a sixth tab. All five tabs and
/// the avatar's destination now exist; `core/tabs.dart` records what changed and
/// why.
///
/// go_router rather than `Navigator` calls: deep links (a notification opening one
/// night's sleep detail) and typed paths are both things the app will need, and
/// retrofitting a router after screens exist means touching every screen.
///
/// ## The five tabs are BRANCHES, not sibling pages
///
/// They were plain sibling `GoRoute`s, which meant every tab switch built a new
/// page and threw the old one away — scroll offset, chart reveals and provider
/// reads with it. `shared/app_shell.dart` records the measurement. They are now
/// the branches of a `StatefulShellRoute.indexedStack`, each with its own
/// `Navigator`, all kept alive — which is also what gives the Android back button
/// a per-tab stack to pop (the shell owns that rule).
///
/// ## `go` REPLACES. Every out-of-shell destination is pushed.
///
/// This shipped wrong once and the bug is worth stating in full, because the
/// mistake reads as correct: `context.go` replaces the location rather than
/// stacking on it, so a `go` into Settings left **nothing underneath**. The
/// shell's back rule then did exactly what it says — an empty branch stack, not
/// on Today, so leave — and the owner was dropped onto the Android home screen
/// from a screen they had tapped into two seconds earlier. Every out-of-shell
/// route had it, so Settings → Diagnostics → back left the app too.
///
/// The rule, and it is a rule rather than a case-by-case judgement:
///
/// | navigation | verb | why |
/// |---|---|---|
/// | tab → tab (`app_tab_bar.dart`) | `go` | a bar switches between siblings; stacking them would make back walk a history of tabs |
/// | Today → settings · sign-in | `push` | a destination the owner came from somewhere and expects to return to |
/// | settings → diagnostics · sign-in · pairing | `push` | back lands on Settings, which is what made it findable |
/// | the redirect below | replace | there is nothing to return to |
///
/// **`push` is also what draws the back arrow.** A `go`-ed screen with an
/// `AppBar` has no leading control, so those screens offered no way back at all
/// — not even a wrong one. The gesture and the affordance were missing together,
/// which is why nothing on screen looked broken.
///
/// [leaveSetup] handles the one place the two columns meet: a setup flow that
/// may be pushed *or* redirected into.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:healthee/core/routes.dart';
import 'package:healthee/core/settings_routes.dart';
import 'package:healthee/core/tabs.dart';
import 'package:healthee/core/view_date_route.dart';
import 'package:healthee/data/models/finding.dart';
import 'package:healthee/data/pairing/pairing_repository.dart';
import 'package:healthee/data/store/view_date.dart';
import 'package:healthee/features/actions/challenge_detail_screen.dart';
import 'package:healthee/features/actions/program_detail_screen.dart';
import 'package:healthee/features/actions/recommendation_history_screen.dart';
import 'package:healthee/features/activity/fitness_screen.dart';
import 'package:healthee/features/coach/breathing_plan_screen.dart';
import 'package:healthee/features/coach/breathing_player_screen.dart';
import 'package:healthee/features/coach/coach_history_screen.dart';
import 'package:healthee/features/coach/coach_screen.dart';
import 'package:healthee/features/coach/every_yes_screen.dart';
import 'package:healthee/features/gps/gps_screen.dart';
import 'package:healthee/features/gps/route_detail_screen.dart';
import 'package:healthee/features/gps/routes_screen.dart';
import 'package:healthee/features/history/history_screen.dart';
import 'package:healthee/features/history/metric_explorer_screen.dart';
import 'package:healthee/features/insights/v02/finding_detail_screen.dart';
import 'package:healthee/features/sleep/sleep_history_screen.dart';
import 'package:healthee/features/today/body_screen.dart';
import 'package:healthee/features/today/recovery_screen.dart';
import 'package:healthee/features/trends/trends_screen.dart';
import 'package:healthee/features/workouts/workout_detail_screen.dart';
import 'package:healthee/features/workouts/workout_history_screen.dart';
import 'package:healthee/shared/app_shell.dart';
import 'package:healthee/shared/foundation_screen.dart';

// The path table and the coach's location builder live in `routes.dart`
// (Standards section 1, the 400-line gate). Re-exported so this file stays
// the one import a screen needs to name a destination.
export 'package:healthee/core/routes.dart';

/// The app's router.
///
/// Every path in [Routes] is wired to a screen. That is not a coincidence to be
/// maintained by review — `test/features/reachability_test.dart` walks the tab
/// list against the wired set, because a tab pointing at an unregistered path
/// looks like nothing at all until somebody taps it.
///
/// ## Unpaired means pairing
///
/// An app holding no strap credentials has nothing to show and nothing to sync,
/// so the redirect sends it to [Routes.pairing]. Two states deliberately do NOT
/// redirect: while the keystore read is still in flight (a redirect on unknown
/// state flashes the pairing screen at an owner who is already paired), and when
/// that read failed (we do not know, and locking someone out of their own cached
/// data on a keystore hiccup would be the wrong way to be wrong). Both are
/// logged by `ProviderLogger`; neither is guessed at.
GoRouter buildRouter(WidgetRef ref) {
  // The keystore read is asynchronous, so the first redirect always runs on
  // `loading`. Without this the router would never look again and an unpaired
  // app would sit on a screen it has no data for.
  final refresh = _RouterRefresh();
  final dateLinks = ViewDateLinks();
  ref.listenManual(pairingSummaryProvider, (previous, next) => refresh.bump());
  // The date control's tap IS a navigation: `viewDateRedirect` rewrites the
  // location from the selection, and this is what makes it look again. Without
  // it the day would move on screen and the URL would keep the old one, which
  // is exactly the state a restored stack reads back.
  ref.listenManual(viewDateProvider, (previous, next) => refresh.bump());

  return GoRouter(
    initialLocation: Routes.today,
    refreshListenable: refresh,
    redirect: (BuildContext context, GoRouterState state) {
      final summary = ref.read(pairingSummaryProvider);
      if (summary.isLoading || summary.hasError) {
        return null;
      }
      if (summary.value?.strap == null &&
          state.matchedLocation != Routes.pairing) {
        return Routes.pairing;
      }
      // After the pairing gate, never before it: an app with no strap has
      // nothing to show for any day, and stamping one on the way to /pairing
      // would put a date on a screen that is not about a day at all.
      return viewDateRedirect(ref, state, dateLinks);
    },
    routes: <RouteBase>[
      GoRoute(
        path: Routes.recommendations,
        builder: (context, state) => const RecommendationHistoryScreen(),
      ),
      GoRoute(path: Routes.gps, builder: (context, state) => const GpsScreen()),
      GoRoute(
        path: Routes.routes,
        builder: (context, state) => const RoutesScreen(),
      ),
      GoRoute(
        path: '${Routes.route}/:id',
        builder: (context, state) =>
            RouteDetailScreen(id: state.pathParameters['id']!),
      ),
      // The tabs. Branch order IS `kAppTabs` order, by construction rather than
      // by agreement — the bar moves by index, so two lists would be a defect
      // that compiles.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          for (final AppTab tab in kAppTabs)
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: tab.route,
                  builder: (BuildContext context, GoRouterState state) =>
                      tab.screen(),
                ),
              ],
            ),
        ],
      ),
      GoRoute(
        path: Routes.devFoundation,
        builder: (BuildContext context, GoRouterState state) =>
            const FoundationScreen(),
      ),
      GoRoute(
        path: '${Routes.challenge}/:id',
        builder: (context, state) => ChallengeDetailScreen(
          id: int.tryParse(state.pathParameters['id'] ?? '') ?? -1,
        ),
      ),
      GoRoute(
        path: '${Routes.program}/:id',
        builder: (context, state) => ProgramDetailScreen(
          id: int.tryParse(state.pathParameters['id'] ?? '') ?? -1,
        ),
      ),
      GoRoute(
        path: Routes.coachLedger,
        builder: (context, state) => const EveryYesScreen(),
      ),
      GoRoute(
        path: Routes.coach,
        // `coachTopicOf` is `coachLocation` read back, and both live in
        // `routes.dart` so the round trip has one owner.
        builder: (context, state) =>
            CoachScreen(topic: coachTopicOf(state.uri)),
      ),
      GoRoute(
        path: Routes.coachHistory,
        builder: (context, state) => const CoachHistoryScreen(),
      ),
      GoRoute(
        path: Routes.breathingPlan,
        builder: (context, state) => const BreathingPlanScreen(),
      ),
      GoRoute(
        path: Routes.breathingPlayer,
        builder: (context, state) => BreathingPlayerScreen(
          item: state.uri.queryParameters['item'],
          patternId: state.uri.queryParameters['pattern'],
        ),
      ),
      GoRoute(
        path: Routes.body,
        builder: (context, state) => const BodyScreen(),
      ),
      GoRoute(
        path: Routes.fitness,
        builder: (context, state) => const FitnessScreen(),
      ),
      GoRoute(
        path: Routes.recovery,
        builder: (context, state) => const RecoveryScreen(),
      ),
      GoRoute(
        path: Routes.trends,
        builder: (context, state) => const TrendsScreen(),
      ),
      GoRoute(
        path: Routes.sleepHistory,
        builder: (context, state) => const SleepHistoryScreen(),
      ),
      GoRoute(
        path: Routes.workouts,
        builder: (context, state) => const WorkoutHistoryScreen(),
      ),
      GoRoute(
        path: Routes.workout,
        builder: (context, state) => WorkoutDetailScreen(
          start: state.uri.queryParameters['start'] ?? '',
        ),
      ),
      GoRoute(
        path: '${Routes.insight}/:key',
        // The finding rides in `extra` when a tap opened this, and the path key
        // re-resolves it when nothing did. The screen owns that fallback; the
        // router only hands over what it was given.
        builder: (BuildContext context, GoRouterState state) =>
            FindingDetailScreen(
              routeKey: state.pathParameters['key'] ?? '',
              finding: state.extra is Finding ? state.extra! as Finding : null,
            ),
      ),
      GoRoute(
        path: Routes.history,
        // One route, two screens. With no `metric` it is the explorer — the
        // directory of every signal the app holds a history for, which is what
        // `H.link('All measurements', 'metrics')` opens in the prototype. With
        // one, it is that metric's own dated series. A second path would mean
        // two names for one destination and a second thing to keep reachable.
        builder: (context, state) {
          final metric = state.uri.queryParameters['metric'];
          return metric == null
              ? const MetricExplorerScreen()
              : HistoryScreen(initialMetric: metric);
        },
      ),
      ...settingsRoutes(),
    ],
  );
}

/// Leaves a setup screen the way the owner came into it.
///
/// The two setup flows are reachable **two ways**, and "Done" cannot mean one
/// thing for both:
///
///   * **Pushed** from Settings, by somebody who went looking for it. There is a
///     screen underneath and they expect to come back to it, so Done pops.
///   * **Redirected into** by the router, because the app holds no strap
///     credentials and has nothing to show. Nothing is underneath, so Done goes
///     to Today — which the redirect will now allow, because pairing succeeded.
///
/// `canPop()` is the question that distinguishes them, and it is the router's
/// own rather than a flag threaded down through the screens: a parameter saying
/// "you were pushed" is a second copy of a fact the navigator already holds, and
/// it would be wrong the first time a third caller forgot to set it.
void leaveSetup(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(Routes.today);
  }
}

/// Lets [buildRouter] tell go_router that the pairing state moved.
/// `notifyListeners` is protected, so poking a bare `ChangeNotifier` from
/// outside is not something the analyzer allows — this is the sanctioned shape.
class _RouterRefresh extends ChangeNotifier {
  void bump() => notifyListeners();
}
