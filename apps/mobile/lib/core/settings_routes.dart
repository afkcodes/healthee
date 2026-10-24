/// The supporting surface's routes — Settings, its sub-screens, and their doors.
///
/// Split out of `router.dart` at the 400-line gate (Standards §1), and the seam
/// is a real one rather than a convenience: that file's one reason to change is
/// **the app's shape** — the tab shell, the redirect, the back rule — and this
/// one's is **which supporting screens exist**. The v02 redesign added seven of
/// them in one change and would have pushed the router past the gate again.
///
/// `leaveSetup` stays in `router.dart` because it is the back rule, which is
/// that file's subject; this list calls it.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:healthee/core/router.dart';
import 'package:healthee/features/diagnostics/diagnostics_screen.dart';
import 'package:healthee/features/journal/journal_screen.dart';
import 'package:healthee/features/pairing/pairing_screen.dart';
import 'package:healthee/features/profile/profile_screen.dart';
import 'package:healthee/features/settings/about_screen.dart';
import 'package:healthee/features/settings/appearance_screen.dart';
import 'package:healthee/features/settings/background_screen.dart';
import 'package:healthee/features/settings/data_freshness_screen.dart';
import 'package:healthee/features/settings/device_screen.dart';
import 'package:healthee/features/settings/reminders_screen.dart';
import 'package:healthee/features/settings/settings_screen.dart';
import 'package:healthee/features/signin/server_signin_screen.dart';
import 'package:healthee/features/welcome/welcome_screen.dart';

/// The supporting surface: Settings, its sub-screens, and everything they open.
///
/// **One definition, two callers.** [buildRouter] splices this into the app's
/// route list, and `test/features/_settings_harness.dart` mounts the same list
/// so a suite asking *"does this row land where it says"* is asking about the
/// routes the app actually ships. A second list in the test would answer that
/// question about the test.
///
/// The sub-screens are registered **flat** rather than as `routes:` children of
/// `/settings`. A nested route would put the index underneath every one of
/// them in the stack, and these are reached from three places — the index, the
/// device screen and the background screen — so what is underneath is whatever
/// pushed them, which is what `push` already means.
List<RouteBase> settingsRoutes() => <RouteBase>[
  GoRoute(
    path: Routes.settings,
    builder: (BuildContext context, GoRouterState state) =>
        const SettingsScreen(),
  ),
  GoRoute(
    path: Routes.appearance,
    builder: (BuildContext context, GoRouterState state) =>
        const AppearanceScreen(),
  ),
  GoRoute(
    path: Routes.reminders,
    builder: (BuildContext context, GoRouterState state) =>
        const RemindersScreen(),
  ),
  GoRoute(
    path: Routes.background,
    builder: (BuildContext context, GoRouterState state) =>
        const BackgroundScreen(),
  ),
  GoRoute(
    path: Routes.device,
    builder: (BuildContext context, GoRouterState state) =>
        const DeviceScreen(),
  ),
  GoRoute(
    path: Routes.dataFreshness,
    builder: (BuildContext context, GoRouterState state) =>
        const DataFreshnessScreen(),
  ),
  GoRoute(
    path: Routes.about,
    builder: (BuildContext context, GoRouterState state) => const AboutScreen(),
  ),
  GoRoute(
    path: Routes.welcome,
    builder: (BuildContext context, GoRouterState state) =>
        const WelcomeScreen(),
  ),
  GoRoute(
    path: Routes.profile,
    builder: (BuildContext context, GoRouterState state) =>
        ProfileScreen(focus: profileFocusOf(state.uri)),
  ),
  GoRoute(
    path: Routes.journal,
    builder: (BuildContext context, GoRouterState state) =>
        const JournalScreen(),
  ),
  GoRoute(
    path: Routes.diagnostics,
    builder: (BuildContext context, GoRouterState state) =>
        const DiagnosticsScreen(),
  ),
  GoRoute(
    path: Routes.pairing,
    builder: (BuildContext context, GoRouterState state) =>
        PairingScreen(onDone: () => leaveSetup(context)),
  ),
  GoRoute(
    path: Routes.serverSignIn,
    builder: (BuildContext context, GoRouterState state) =>
        ServerSignInScreen(onDone: () => leaveSetup(context)),
  ),
];
