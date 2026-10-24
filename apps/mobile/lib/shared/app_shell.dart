/// The app frame the five tabs live in: one `Scaffold`, one bar, five branches,
/// one back rule, and the Coach button that belongs to Today alone.
///
/// This is the widget half of `StatefulShellRoute.indexedStack` (wired in
/// `core/router.dart`). The shell owns the only [AppTabBar] in the app and the
/// only `Scaffold` that has one; `navigationShell` is an `IndexedStack` of five
/// `Navigator`s, each keeping its own widget tree, scroll offsets and route stack
/// alive while the others are shown.
///
/// ## What the indexed stack buys, measured
///
/// Before this, each tab was a plain `GoRoute` and a tab switch built a new page:
/// scrolling Today two screenfuls, tapping Sleep and tapping Today put Today back
/// at the top. Three things went with the scroll offset, and only one of them was
/// visible:
///
///   * every `RevealOnce` chart animated again — CLAUDE.md's rule is that charts
///     must not replay, and the widget was holding it correctly while the
///     navigation layer discarded the registry it holds it in;
///   * provider reads re-ran, so a tab switch could re-hit the network;
///   * there was no per-tab back stack, so Android back did not do what a tab bar
///     implies.
///
/// ## The back rule, and why it ends where it does
///
/// Android back is answered here, in three steps, in this order:
///
/// ```text
///   1. the current tab's own Navigator can pop   →  pop it
///   2. otherwise, not on Today                   →  go to Today
///   3. otherwise (Today, nothing to pop)         →  leave the app
/// ```
///
/// Step 1 is why this reads the **branch navigators** rather than keeping a
/// history list: the branch `Navigator` already holds the truth about what a tab
/// has pushed, and a parallel list of visited tabs would be a second copy of the
/// navigation state, free to disagree with the first and impossible to keep right
/// through a deep link. `StatefulShellBranch.navigatorKey` is public API for
/// exactly this.
///
/// Step 2 is the bug this rule exists to fix: back from Sleep used to quit the
/// app. A bottom bar implies a home, and back means "up" long before it means
/// "out".
///
/// **Step 3 is a deliberate choice and the alternatives were worse.** Back on
/// Today with an empty stack exits, because:
///
///   * it is what every other tabbed Android app does, and back is the one
///     gesture whose meaning the owner brings with them rather than learns here;
///   * *"press back again to exit"* is a toast that trains people to press back
///     twice for the rest of the app's life to save an accident that costs
///     nothing — nothing is unsaved. The store is on disk, the sync controller is
///     `keepAlive` and survives the screen, and a sync in flight is not cancelled
///     by the frame being disposed;
///   * refusing to exit at all leaves the owner pressing a system button that
///     does nothing, which is the same defect as the dead Actions tab in a
///     different place.
///
/// The rule is `PopScope(canPop: false)` plus an explicit `SystemNavigator.pop()`
/// on the third branch rather than a `canPop` that flickers between true and
/// false: `canPop` is read by the framework at times we do not control, and a
/// value computed from the branch stacks would have to be recomputed on every
/// push anywhere in the app.
///
/// ## No floating button
///
/// The coach button used to float here, over Today's content. The owner found
/// it covering what it floated over, and the approved redesign moved it into
/// Today's header (`today_header.dart`). Nothing floats over a screen now.
///
/// ## The bar is in the `bottomNavigationBar` slot, not over the content
///
/// So the body is **laid out above** the bar rather than under it, which is what
/// keeps the last card off it; the bar's own `SafeArea` then adds the gesture
/// inset beneath the icons. A bar floating over the scroll would need every list
/// to know its height, which is one more number to get wrong per screen.
///
/// ## What is deliberately OUTSIDE the shell
///
/// Pairing, server sign-in, `/settings` and `/diagnostics` are full-screen routes
/// with no tab bar. Pairing and sign-in are setup flows the app redirects into — a
/// bar offering five destinations to somebody who has not paired a strap offers
/// five empty screens. Settings and diagnostics are about the app rather than
/// about a day, and lighting a tab on either (diagnostics used to light Today)
/// says the owner is somewhere they are not.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:healthee/core/tabs.dart';
import 'package:healthee/features/settings/widgets/update_sheet.dart';
import 'package:healthee/shared/app_tab_bar.dart';

/// The tab frame: the shell's current branch, over the one bar.
class AppShell extends StatelessWidget {
  /// [navigationShell] is go_router's branch container.
  const AppShell({required this.navigationShell, super.key});

  /// The indexed stack of branch navigators, and the API to move between them.
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    // Wrapped here and nowhere else: the update sheet is over the APP, so it
    // needs a context under the root navigator — the same reason `showAppSheet`
    // passes `useRootNavigator: true`. It draws nothing of its own.
    return UpdateWatcher(
      child: PopScope(
        // Always false: the three outcomes are decided below, and a `canPop`
        // computed from the branch stacks would need recomputing on every push
        // anywhere in the app. See the library docstring.
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) {
            return;
          }
          handleBack();
        },
        child: Scaffold(
          body: navigationShell,
          bottomNavigationBar: AppTabBar(
            currentIndex: navigationShell.currentIndex,
            onSelect: (index) => navigationShell.goBranch(
              index,
              // Pressing the tab you are already on resets that branch to its root,
              // which is the one thing a bottom bar universally means. Pressing any
              // other tab keeps the branch exactly as it was left.
              initialLocation: index == navigationShell.currentIndex,
            ),
          ),
        ),
      ),
    );
  }

  /// Answers one back press. Returns what it did, so a test can read the rule
  /// without driving a platform channel.
  ///
  /// Public and returning an enum rather than being a private `void`: the third
  /// outcome leaves the app, which is not a thing a widget test can observe by
  /// looking at the tree.
  BackOutcome handleBack() {
    final branch = navigationShell.route.branches[navigationShell.currentIndex];
    final navigator = branch.navigatorKey.currentState;
    if (navigator != null && navigator.canPop()) {
      navigator.pop();
      return BackOutcome.poppedRoute;
    }
    if (navigationShell.currentIndex != kHomeTabIndex) {
      navigationShell.goBranch(kHomeTabIndex);
      return BackOutcome.wentHome;
    }
    // The real thing, not a flag: `test/features/back_navigation_test.dart`
    // watches `SystemChannels.platform` for it, so the assertion is on the
    // message the platform would actually receive.
    SystemNavigator.pop();
    return BackOutcome.leftTheApp;
  }
}

/// What one back press did.
enum BackOutcome {
  /// A route pushed inside the current tab was popped.
  poppedRoute,

  /// The tab had nothing to pop and was not Today, so Today is now showing.
  wentHome,

  /// Today, nothing to pop: the app is being left. See the shell's docstring.
  leftTheApp,
}
