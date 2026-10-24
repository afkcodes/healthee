/// The shell every tab screen is built in: two sources, one list, one reveal.
///
/// ## Two sources, and neither may take the other down
///
/// The measured half comes from this phone's own store and renders with no
/// network at all (brief §7.4). The derived half comes from `/api/today`. They
/// are watched separately and fail separately, which is the whole reason the
/// screens are built this way:
///
///   * the server unreachable with nothing cached → the derived sections
///     collapse into ONE error card with a retry, and every measurement is still
///     on screen;
///   * the local store unreadable → that IS the screen failing, and it says so
///     with a retry rather than drawing a page of empty cards.
///
/// A page of twenty error cards would be the same news said twenty times, which
/// reads as breakage rather than as one connection problem.
///
/// ## A lazy sliver list and reveal-once
///
/// The list is a **`CustomScrollView` over lazily built slivers**, and the
/// [RevealRegistry] lives in this widget's `State`. Both halves are required and
/// neither works alone: laziness is what keeps a long list at 60 fps, and it is
/// also precisely what makes a chart's own `State` die on scroll and replay its
/// animation on the way back. `shared/reveal_once.dart` has the full argument,
/// and every ported painter takes its progress as a parameter for exactly this
/// reason.
///
/// **The restructure from `ListView.builder` did not touch that guarantee, by
/// construction.** `RevealOnce` never reads a scroll position, an index or a
/// viewport — it asks a registry that outlives the item whether this id has been
/// seen. `SliverList.builder` destroys items exactly as `ListView.builder` did,
/// so the mechanism is under the same pressure and answers the same way.
///
/// ## Why slivers, when a `ListView` was simpler
///
/// `richer.css` gives the chapter nav `position: sticky; top: 0`, and a header
/// that stays put while the list moves under it is a `SliverPersistentHeader` —
/// there is no other shape for it. A section declares
/// [PageSection.pinnedExtent] and this shell splits the list around it: an
/// ordinary run becomes one lazy `SliverList`, a pinned section becomes a header
/// between two of them. A screen with no pinned section builds exactly one
/// sliver and behaves as it always did.
///
/// **That registry is only worth anything while this `State` lives.** It used to
/// die on every tab switch, because each tab was its own page — so the rule held
/// inside a screen and was defeated between them. The tabs are branches of a
/// `StatefulShellRoute.indexedStack` now (`shared/app_shell.dart`), which is what
/// keeps this object alive across a round trip.
///
/// ## No bar here
///
/// This widget draws no bottom bar and takes no tab index. There is exactly one
/// `AppTabBar` in the app and the shell owns it; five screens each drawing their
/// own was five chances to disagree. The `Scaffold` stays because `/diagnostics`
/// renders this shell **outside** the tab shell and still needs a page.
///
/// ## No app bar, and that is legacy's shape rather than a saving
///
/// `design_reference/project/hh/screen_today.jsx` starts each scroll with its own
/// header — an eyebrow, a display-size title, a theme toggle. A Material `AppBar`
/// saying "Sleep" above a bottom bar whose Sleep tab is already lit is the same
/// word twice and 56 px of the first screen spent on it.
///
/// ## Why this is shared rather than five copies
///
/// Today, Sleep, Activity, Coach and Diagnostics all render a list of cards over
/// the same two sources with the same failure rules. Standards §1: second
/// occurrence = extract. The screens that use it are now composition only — a tab
/// index and an ordered list of sections — which is what §3 means by "a screen is
/// composition of small widgets, not one God-widget".
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/data/device/device_day.dart';
import 'package:healthee/data/device/device_repository.dart';
import 'package:healthee/data/history/dated_history.dart';
import 'package:healthee/data/sync/sync_controller.dart';
import 'package:healthee/data/today_repository.dart';
import 'package:healthee/shared/page_section.dart';
import 'package:healthee/shared/reveal_once.dart';
import 'package:healthee/shared/screen_data.dart';
import 'package:healthee/shared/states/async_view.dart';
import 'package:healthee/shared/states/current_account_value.dart';
import 'package:healthee/shared/v02/view_day.dart';

// `ScreenData` moved to its own file at the 400-line gate, and is re-exported
// because it is half of this file's public interface: a section list is a
// function OF it, and twenty screens that import the shell would otherwise each
// gain a second import to say the same thing. The split is about where the code
// lives, not about what a caller has to know.
export 'package:healthee/shared/screen_data.dart';

/// Builds the ordered sections for one render.
typedef SectionsBuilder = List<PageSection> Function(ScreenData data);

/// A tab screen: the frame, the two sources, the list.
class InstrumentScreen extends ConsumerStatefulWidget {
  /// [sections] decides everything the screen draws, in order.
  const InstrumentScreen({
    required this.sections,
    this.now,
    this.onRefreshed,
    super.key,
  });

  /// What to draw, in order.
  final SectionsBuilder sections;

  /// [now] is injected by tests so the freshness labels are deterministic.
  final DateTime? now;

  /// Run after a pull-to-refresh, for anything a screen watches that this shell
  /// does not know about. Today re-reads its push stamp here.
  final VoidCallback? onRefreshed;

  @override
  ConsumerState<InstrumentScreen> createState() => _InstrumentScreenState();
}

class _InstrumentScreenState extends ConsumerState<InstrumentScreen> {
  /// Outlives every list item, which is the whole reveal-once mechanism.
  final RevealRegistry _reveals = RevealRegistry();

  @override
  Widget build(BuildContext context) {
    final server = currentAccountValue(ref.watch(todaySnapshotProvider));
    final view = watchViewDay(ref);
    // **The one place the past-day invariant is established.** A conditional
    // `watch` is how a provider is subscribed to only when it is needed:
    // Riverpod recomputes the dependency set on every build, so stepping onto a
    // past day subscribes and stepping back to the newest day unsubscribes.
    // `datedHistoryProvider` is `keepAlive`, so the round trip is paid once per
    // session rather than once per step. See `ScreenData.history`.
    final history = view.isPast
        ? currentAccountValue(ref.watch(datedHistoryProvider))
        : null;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        // No page chrome above the list. Today's connection strip was the only
        // thing that ever sat here and the owner asked for it gone; the ring
        // round the avatar and the data-health card carry it now, both INSIDE
        // the scroll where legacy put them.
        child: AsyncView<DeviceDay>(
          value: ref.watch(deviceDayProvider),
          loadingLabel: "Reading today's measurements",
          errorMessage: "Couldn't read this phone's own store",
          onRetry: () => ref.invalidate(deviceDayProvider),
          builder: (context, day) => RefreshIndicator(
            onRefresh: _refresh,
            child: _SectionList(
              sections: widget.sections(
                ScreenData(
                  day: day,
                  server: server,
                  reveals: _reveals,
                  view: view,
                  history: history,
                  now: widget.now,
                  onRetryServer: () => ref.invalidate(todaySnapshotProvider),
                  onRetryHistory: () => ref.invalidate(datedHistoryProvider),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Pull-to-refresh runs a real sync, a push, and a re-read. New data earns a
  /// fresh reveal, which is the one thing that may reset the registry —
  /// scrolling never does.
  Future<void> _refresh() async {
    await ref.read(syncControllerProvider.notifier).syncNow();
    ref.invalidate(todaySnapshotProvider);
    // The dated series moves when a sync lands new days, and never otherwise —
    // it is `keepAlive`, so this is the one thing that refreshes it.
    ref.invalidate(datedHistoryProvider);
    widget.onRefreshed?.call();
    _reveals.reset();
  }
}

class _SectionList extends StatelessWidget {
  const _SectionList({required this.sections});

  final List<PageSection> sections;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      // Always scrollable, so pull-to-refresh works on a short or empty day.
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: _slivers(context),
    );
  }

  /// The list, split into runs around whatever pins.
  ///
  /// The page's own padding is spacers rather than a `SliverPadding` around
  /// everything: a pinned header has to reach both edges so the content sliding
  /// under it is hidden, and it takes its own side padding instead.
  List<Widget> _slivers(BuildContext context) {
    final slivers = <Widget>[
      const SliverToBoxAdapter(child: SizedBox(height: Insets.gutter)),
    ];
    var run = <PageSection>[];

    void flush() {
      if (run.isEmpty) {
        return;
      }
      final items = run;
      run = <PageSection>[];
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: Insets.gutter),
          sliver: SliverList.builder(
            itemCount: items.length,
            itemBuilder: (context, index) => Padding(
              padding: EdgeInsets.only(bottom: items[index].gap),
              child: items[index].child,
            ),
          ),
        ),
      );
    }

    for (final section in sections) {
      if (section.bleed) {
        flush();
        slivers.add(
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(bottom: section.gap),
              child: section.child,
            ),
          ),
        );
        continue;
      }
      if (section.pinnedExtent case final SectionExtent extent) {
        flush();
        slivers.add(
          SliverPersistentHeader(
            pinned: true,
            delegate: _PinnedSection(
              // The gap below a pinned section is part of the pinned box. A gap
              // left outside it is a stripe of page the content shows through.
              extent: extent(context) + section.gap,
              background: context.colors.bg,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Insets.gutter),
                child: section.child,
              ),
            ),
          ),
        );
        continue;
      }
      run.add(section);
    }
    flush();
    return slivers
      ..add(const SliverToBoxAdapter(child: SizedBox(height: Insets.xxl)));
  }
}

/// One section held at the top of the scroll — `position: sticky; top: 0`.
class _PinnedSection extends SliverPersistentHeaderDelegate {
  const _PinnedSection({
    required this.extent,
    required this.background,
    required this.child,
  });

  /// Its height, both floors, because it neither collapses nor stretches.
  final double extent;

  /// `.chapter-nav { background: var(--background) }` — opaque, so the list
  /// passing beneath is hidden rather than showing through the control.
  final Color background;

  /// What is pinned.
  final Widget child;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => ColoredBox(color: background, child: child);

  @override
  bool shouldRebuild(_PinnedSection oldDelegate) =>
      oldDelegate.extent != extent ||
      oldDelegate.background != background ||
      oldDelegate.child != child;
}
