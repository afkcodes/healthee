/// A screen's section list, written the way legacy writes one.
///
/// Legacy's screens are a single list literal with `SizedBox`es between the
/// cards:
///
/// ```dart
/// // healthee-legacy/app/lib/ui/today_screen.dart:246
/// if (_nums(spark['hrv_sleep_avg']).length > 2) ...[
///   const SizedBox(height: 10),
///   HModule(label: 'HRV · 14 days', …),
/// ],
/// ```
///
/// A `PageSection` carries its gap **after** it, so porting that literally means
/// writing each spacer onto the section before it — which is fine until the
/// section before it is conditional, at which point a `gap` written ahead of a
/// card that never appears leaves a stray band of nothing on the screen.
///
/// [SectionList.gap] resolves it: it sets the space under **whatever was last
/// added**, so the call sites read in legacy's own order (spacer, then card) and
/// a spacer emitted for a card that is never added simply lands on the card
/// above, which is exactly what legacy renders.
///
/// Extracted out of `features/today/` because Sleep, Activity and Insights are
/// the same list of the same literal, and three copies of this is three chances
/// for one of them to grow a different idea of where a gap belongs.
library;

import 'package:flutter/widgets.dart';
import 'package:healthee/shared/page_section.dart';

/// Builds an ordered section list one statement at a time.
class SectionList {
  final List<PageSection> _sections = <PageSection>[];

  /// Appends a section with no gap under it yet.
  void add(Widget child) => _sections.add(PageSection(child, gap: 0));

  /// Appends a section somebody else built — an error card, a pending card.
  void addSection(PageSection section) => _sections.add(section);

  /// Appends a section that **pins to the top of the scroll** rather than
  /// scrolling away, [extent] tall. See [PageSection.pinnedExtent].
  void addPinned(Widget child, SectionExtent extent) =>
      _sections.add(PageSection(child, gap: 0, pinnedExtent: extent));

  /// Appends a section drawn edge to edge. See [PageSection.bleed].
  void addBleed(Widget child) =>
      _sections.add(PageSection(child, gap: 0, bleed: true));

  /// Legacy's `SizedBox(height: amount)` between two sections.
  ///
  /// A no-op on an empty list: a spacer before anything has been added is a gap
  /// above the top of the screen, which legacy does not draw either.
  void gap(double amount) {
    if (_sections.isEmpty) {
      return;
    }
    final last = _sections.removeLast();
    // `pinnedExtent` is carried over, not dropped: a spacer written after a
    // pinned section would otherwise quietly un-pin it, and the screen would
    // still render — just without the one behaviour the section was added for.
    _sections.add(
      PageSection(
        last.child,
        gap: amount,
        pinnedExtent: last.pinnedExtent,
        bleed: last.bleed,
      ),
    );
  }

  /// The finished list.
  List<PageSection> build() => List<PageSection>.unmodifiable(_sections);
}
