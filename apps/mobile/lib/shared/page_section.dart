/// One entry in a screen's section list: a widget and the gap that follows it.
///
/// The gap belongs to the section rather than to the list because the screens
/// have two rhythms and only one of them is padding. Legacy's modules sit 10 px
/// apart inside a group and its section breaks are more than twice that; a list
/// that padded everything to one gap would read as a pile of unrelated cards,
/// which is exactly what the screen this rebuild replaced looked like.
///
/// Extracted out of `features/today/` when Sleep, Activity, Coach and
/// Diagnostics started building the same kind of list (Standards §1: second
/// occurrence = extract). A section type living in one feature would have been a
/// feature reaching sideways into another, which §1 also forbids.
library;

import 'package:flutter/widgets.dart';
import 'package:healthee/core/theme/dimensions.dart';

/// The gap under a section — **the only place a screen's vertical rhythm lives**.
///
/// ## Owner-directed departure from the verbatim-legacy rule, 2026-08-06
///
/// *"give some space between cards it looks too cramped in between"*. Legacy's
/// gaps were ported literally and they are tight: 10 px between sibling cards,
/// 14 under a chart, 16 before a related block, 24 before a section heading. All
/// four grew, and they grew **as a ladder**, because the rungs are what carry the
/// grouping — a screen that padded everything to one gap would read as a pile of
/// unrelated cards, which is what this rebuild replaced. The relationship legacy
/// encodes is preserved: a section break is still comfortably wider than a gap
/// between siblings (34 against 18, where legacy had 24 against 10).
///
/// This grew by the same repair as the caveat carrier and is not a coincidence:
/// a wider gutter is only an improvement once the gutter is EMPTY. While a
/// caveat note floated between two cards, widening the gap would have made the
/// misattribution worse rather than better. See `caveat_scope.dart`.
///
/// Call sites name a rung. A literal at a call site is how a ladder stops being
/// one, so `test/features/page_spacing_test.dart` fails the build on a screen
/// that writes its own number.
abstract final class PageSpacing {
  /// Between two cards in the same section. Legacy's 10.
  static const double card = 18;

  /// Between a card and the one it is directly about — a chart and its legend,
  /// a pair that reads as one block. Legacy's 14.
  static const double related = 22;

  /// Between two groups inside one section, where there is no heading to carry
  /// the break. Legacy's 16.
  static const double group = 26;

  /// Under the last card of a section, before the next heading. Legacy's 24.
  static const double section = 34;

  /// **v02's own two rungs, now the brief's tokens** ([Insets.cardGap] and
  /// [Insets.section]; the prototype's `richer.css` said 12 and 24).
  ///
  /// They are tighter than the four above and that is not a regression of the
  /// owner's 2026-08-06 widening. Those four space **legacy's** cards, which
  /// carry no internal rhythm of their own; a v02 panel has 20 px of padding
  /// and a 20 px corner, so 12 between two of them reads wider than legacy's 10
  /// between two flat modules. A screen uses one ladder or the other, never
  /// both — `today_order_test.dart` asserts Today uses this one.
  static const double panel = Insets.cardGap;

  /// Between two groups of panels: [Insets.section], 32.
  static const double block = Insets.section;

  /// Between ANY page-level heading and the thing it names.
  ///
  /// One constant because the two heading widgets had drifted: `SectionHead`
  /// left 12 and `ChapterHeading` left 4 — the prototype's own
  /// `.chapter-heading { margin-bottom: 4px }`, ported faithfully, which on a
  /// device reads as a title stuck to its card while every other title has
  /// room. A reader cannot see which widget drew a heading, so the two must not
  /// be able to disagree about what follows one.
  static const double afterHeading = 12;
}

/// How tall a pinned section is, measured in the context it will be drawn in.
///
/// A sliver that pins has to declare its extent **before** it lays out — that is
/// what lets the viewport hold it at the top while the rest of the list slides
/// under it — so a pinned section cannot simply be as tall as its child. The
/// context is passed because the answer depends on the text scale the owner
/// chose, and a hard-coded height would clip a pinned control at anything but
/// the default.
typedef SectionExtent = double Function(BuildContext context);

/// A section [child] followed by [gap] of space.
@immutable
class PageSection {
  /// Builds one entry of a screen's list.
  const PageSection(
    this.child, {
    this.gap = PageSpacing.card,
    this.pinnedExtent,
    this.bleed = false,
  });

  /// What to draw.
  final Widget child;

  /// The space under it.
  final double gap;

  /// Non-null makes this section **pin to the top of the scroll**, and answers
  /// how tall it is. Null is an ordinary section that scrolls away.
  ///
  /// `richer.css` gives exactly one element `position: sticky` — the chapter
  /// nav — and this is that, in the only shape a scroll view has for it. The
  /// screen shell reads it; nothing else needs to know.
  final SectionExtent? pinnedExtent;

  /// True draws [child] edge to edge, without the page's side padding: the
  /// Today hero, which fades into the page rather than sitting on it.
  final bool bleed;
}
