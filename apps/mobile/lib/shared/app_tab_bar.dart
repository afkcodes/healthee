/// The app frame's bottom bar — **drawn once, by the shell**.
///
/// **Ported from** the bottom bar visible in every `design_reference/project/
/// screens/v2-*.png`: icon-over-label items on the app frame, the active one in
/// the accent, the rest quiet.
///
/// ## It no longer navigates by route, and that is the whole point
///
/// This widget used to call `context.go(tab.route)` and each screen drew its own
/// copy of the bar with its own `tabIndex`. Both halves of that were wrong:
///
///   * **Five copies of one bar** is five chances for them to disagree
///     (Standards §1: second occurrence = extract). The bar is now built in
///     `shared/app_shell.dart`, once, and no screen mentions it.
///   * **`go` to a sibling route rebuilt the screen.** Under plain `GoRoute`s
///     each tab was a fresh page, so a tab switch destroyed the scroll position,
///     re-ran every `RevealOnce` animation — defeating CLAUDE.md's replay rule at
///     the navigation layer, however correct the widget — and re-read providers.
///     The router is now a `StatefulShellRoute.indexedStack`; this bar reports
///     which item was pressed and the shell moves the branch.
///
/// The active item is still not a link to itself: [onSelect] is called with the
/// current index too, and the shell reads that as "pop this tab to its root",
/// which is what a tab bar implies.
///
/// The tab list lives in `core/tabs.dart` because the router's branches are built
/// from the same list — see there for why they may not be two lists, and for why
/// the unbuilt Actions tab came out of the bar rather than being drawn dimmed.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/tabs.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_ladder.dart';

/// The bottom bar. One instance, in the shell.
class AppTabBar extends StatelessWidget {
  /// [currentIndex] is the shell's branch index; [onSelect] moves it.
  const AppTabBar({
    required this.currentIndex,
    required this.onSelect,
    super.key,
  });

  /// Which tab is active.
  final int currentIndex;

  /// Called with the pressed tab's index — including the active one.
  final void Function(int index) onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      // Opaque, by token. The bar sits under the content rather than over it —
      // it is in the `Scaffold`'s `bottomNavigationBar` slot, so the body is laid
      // out above it — and `chrome` is a solid colour in both themes so nothing
      // shows through even while a scroll overshoots.
      decoration: BoxDecoration(
        color: colors.chrome,
        border: Border(
          top: BorderSide(color: colors.line2, width: hairline),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Insets.sm),
          child: Row(
            children: [
              for (var i = 0; i < kAppTabs.length; i++)
                Expanded(
                  child: _TabItem(
                    tab: kAppTabs[i],
                    active: i == currentIndex,
                    onTap: () => onSelect(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.tab,
    required this.active,
    required this.onTap,
  });

  final AppTab tab;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tint = active ? colors.accent : colors.ink2;
    return Semantics(
      button: true,
      selected: active,
      label: tab.label,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Insets.xs),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(active ? tab.activeIcon : tab.icon, size: 20, color: tint),
                const SizedBox(height: 3),
                Text(
                  tab.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TypeLadder.caption.copyWith(color: tint),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
