/// The frame every pushed v02 screen shares: no app bar, a `.page-header.detail`
/// inside the scroll, and the page's own padding.
///
/// `richer.css`: `#main { padding: 20px 16px 112px }`. The app's own rung for the
/// same measure is `Insets.lg` / `Insets.xxl`, which is what `InstrumentScreen`
/// spends and therefore what a pushed screen spends too — one page rhythm, not
/// two.
///
/// **No `AppBar`.** `instrument_screen.dart` argues it for the tabs and the same
/// argument holds here: the prototype's detail screens open with their own back
/// control and a 23 px title inside the scroll, and a Material bar above that
/// would be the screen's name twice and 56 px spent on the second one.
///
/// ## Back pops, and lands on the screen's home tab when there is nothing to pop
///
/// This used to read `canPop() ? pop : null` — **no control at all** on an empty
/// stack. Every one of these screens is normally pushed, so the arrow was there
/// whenever anyone looked; a deep link, a notification or a restored process
/// opens the same screen with nothing underneath, and the owner was then stuck
/// on it. `core/parent_tabs.dart` carries the prototype's own answer
/// (`app.js::H.back`) and the reasoning.
///
/// The decision is made **when the control is pressed**, not when it is built:
/// the stack a page sits on can grow after its head is laid out, and a captured
/// `canPop` would send the owner to a tab from a screen that had since become
/// poppable.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:healthee/core/parent_tabs.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/shared/v02/screen_head.dart';

/// A pushed screen: head, body, footer, all in one scroll.
class DetailPage extends StatelessWidget {
  /// [children] are laid out in order under the head, with no gap of their own —
  /// each decides the space beneath it, as `SectionList` does for a tab.
  const DetailPage({
    required this.title,
    required this.children,
    this.actions = const <Widget>[],
    this.eyebrow,
    this.head,
    this.gutter = Insets.gutter,
    this.largeTitle = false,
    super.key,
  });

  /// The screen's name.
  final String title;

  /// The line above it.
  final String? eyebrow;

  /// The body.
  final List<Widget> children;

  /// Draws the head itself, given the way back (null when there is none), so a
  /// screen can own its nav row and its title. The back rule, the pop gesture
  /// and the page's scroll stay this page's. Null draws the usual head.
  final Widget Function(BuildContext context, VoidCallback? onBack)? head;

  /// The page's side padding.
  final double gutter;

  /// Sets the title at Title1. See [DetailHead.large].
  final bool largeTitle;

  /// Controls on the screen itself, at the head's trailing edge. Empty by
  /// default, so every existing screen renders exactly as it did.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    // A page hosted with no router and no stack can go nowhere, and draws no
    // control rather than a dead one. That is the case a widget test builds,
    // never a case the app reaches: `buildRouter` is above every real screen.
    final bool stacked = Navigator.of(context).canPop();
    final bool canLeave = stacked || GoRouter.maybeOf(context) != null;
    return PopScope<Object?>(
      // The gesture takes the same door as the glyph. Last time these two went
      // missing together, which is why nothing on screen looked broken; a fix
      // that restored only the arrow would leave the system back button doing
      // nothing at all on the very screen the map exists for.
      //
      // `canPop` is only false with an empty stack, so an ordinary pushed
      // screen is untouched and the framework pops it as it always did.
      canPop: stacked,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) {
          leaveDetail(context);
        }
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              gutter,
              Insets.gutter,
              gutter,
              Insets.section,
            ),
            children: <Widget>[
              if (head case final head?)
                head(context, canLeave ? () => leaveDetail(context) : null)
              else
                DetailHead(
                  title: title,
                  eyebrow: eyebrow,
                  onBack: canLeave ? () => leaveDetail(context) : null,
                  actions: actions,
                  large: largeTitle,
                ),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// Leaves a detail screen: pop if there is a stack, else go to its home tab.
///
/// Public because `SettingsPage` and any screen supplying its own `onBack` want
/// the same rule, and two copies of a back rule is how one of them ends up
/// stranding somebody. `core/parent_tabs.dart` owns the map.
void leaveDetail(BuildContext context) {
  final NavigatorState navigator = Navigator.of(context);
  if (navigator.canPop()) {
    navigator.pop();
    return;
  }
  final GoRouter? router = GoRouter.maybeOf(context);
  if (router == null) {
    return;
  }
  // `go`, not `push`: there is nothing under this screen, so the tab replaces
  // it rather than stacking on top of a page the owner has just left.
  router.go(parentTabFor(router.state.matchedLocation));
}
