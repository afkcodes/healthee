/// The three jump targets, and the one hard part about them.
///
/// `screens-overview.js` puts a `.chapter-nav` above the chapters and gives each
/// button `data-action="jump"`, which in a document is `scrollIntoView` on an
/// element that always exists.
///
/// ## In a `ListView.builder` the target usually does not exist yet
///
/// The list destroys an item when it scrolls out of view and has not built the
/// ones below the cache extent at all — which is the whole reason
/// `reveal_once.dart` exists and is not negotiable. So a `GlobalKey` on the
/// third chapter heading has **no context** until something has scrolled near
/// it, and `Scrollable.ensureVisible` on a null context is a dead button.
///
/// [TodayChapters.jumpTo] walks instead: it looks for the anchor, and while it
/// cannot find one it scrolls the enclosing viewport forward by nine tenths of
/// itself and looks again. Each step builds the items it passes, so the anchor
/// appears within a bounded number of hops and the last hop centres it. The loop
/// stops at the end of the list, so a chapter that genuinely is not on the
/// screen — a night with no data draws no night chapter — costs one scroll to
/// the bottom rather than an infinite one.
///
/// The keys are **per instance**, not module-level finals. Two live Today
/// screens with one set of `GlobalKey`s between them is a duplicate-key crash,
/// and a widget test that pumps the screen twice is exactly that case.
///
/// ## The nav pins, so the landing has to allow for it
///
/// The control is a pinned sliver (`shared/instrument_screen.dart`), which means
/// it covers the top of the viewport for the whole scroll. `Scrollable.
/// ensureVisible` puts its target at the very top — **underneath** the pinned
/// nav, where nobody can read it. `.chapter-heading { scroll-margin-top: 66px }`
/// is the prototype's answer to the same problem, and [_landing] is ours: the
/// offset that would reveal the heading, minus the nav's own measured height.
/// Measured rather than typed, so the two cannot drift apart.
library;

import 'package:flutter/material.dart';
import 'package:healthee/shared/v02/chapter.dart';
import 'package:healthee/shared/v02/chapter_jump.dart';

/// The three anchors Today's chapter nav jumps to.
class TodayChapters {
  /// `Last night → today`.
  final GlobalKey night = GlobalKey(debugLabel: 'today.chapter.night');

  /// `Movement → recovery`.
  final GlobalKey day = GlobalKey(debugLabel: 'today.chapter.day');

  /// `Patterns → small changes`.
  final GlobalKey longer = GlobalKey(debugLabel: 'today.chapter.longer');

  /// Scrolls until [key]'s heading is on screen, from [from]'s viewport.
  Future<void> jumpTo(BuildContext from, GlobalKey key) =>
      jumpToChapter(from, key);
}

/// `.chapter-nav`, wired to [chapters].
///
/// A widget rather than three callbacks built in the section list, because the
/// scroll it walks is the one **this button** is inside — and only a widget has
/// a `BuildContext` to find it from.
class TodayChapterNav extends StatelessWidget {
  /// Builds the nav.
  const TodayChapterNav({required this.chapters, super.key});

  /// The prototype's own three labels.
  static const List<String> labels = <String>[
    'Your night',
    'Your day',
    'Longer view',
  ];

  /// Where the three anchors are.
  final TodayChapters chapters;

  @override
  Widget build(BuildContext context) {
    final keys = <GlobalKey>[chapters.night, chapters.day, chapters.longer];
    return ChapterNav(<ChapterTarget>[
      for (var i = 0; i < labels.length; i++)
        ChapterTarget(labels[i], () => chapters.jumpTo(context, keys[i])),
    ]);
  }
}
