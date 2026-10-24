/// The shimmering placeholder box, and the card-shaped parts built from it.
///
/// **Ported from** `healthee-legacy/app/lib/ui/skeletons.dart` (`HSkeleton`,
/// `_card`, `_tile`, `_row2`, `_richCard`). Every width, height and radius below
/// is legacy's. The shimmer is legacy's too: 1300 ms, 250 ms of delay, and a
/// highlight of the fill lerped 22% toward [HealtheeColors.ink2].
///
/// ## The one substitution, and it is a colour that does not exist here
///
/// Legacy fills a skeleton with `HColors.sunken` — a **fourth** paper tone below
/// `paper` and `paper2`. The scaffolding the owner kept is a three-tone set
/// (page · surface · recessed), so there is no `sunken` to port and inventing one
/// would be authoring colour, which this phase may not do. The fill is therefore
/// [HealtheeColors.surface2], the scaffolding's own recessed surface, and the
/// shimmer keeps legacy's `lerp(fill, ink3, 0.22)` relationship to it.
///
/// ## Why these keep an `AnimationController` when the charts do not
///
/// `flutter_animate`'s `.shimmer(onPlay: repeat)` runs for as long as the
/// skeleton is mounted, which is the point — a loading state that stops moving
/// reads as a hang. The reveal-once rule (`shared/reveal_once.dart`) is about
/// animations that must play exactly once per datum; a skeleton has no datum and
/// is unmounted the moment one arrives.
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/shared/states/state_scaffold.dart';

/// A shimmering placeholder box.
class HSkeleton extends StatelessWidget {
  /// A null [width] fills the space it is given.
  const HSkeleton({this.width, this.height = 12, this.radius = 6, super.key});

  /// How wide, or null to expand.
  final double? width;

  /// How tall. Legacy's default.
  final double height;

  /// Its corner. Legacy's default.
  final double radius;

  /// Legacy's shimmer timings and highlight.
  static const Duration _period = Duration(milliseconds: 1300);
  static const Duration _delay = Duration(milliseconds: 250);
  static const double _highlightMix = 0.22;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: colors.surface2,
            borderRadius: BorderRadius.circular(radius),
          ),
        )
        .animate(onPlay: (controller) => controller.repeat())
        .shimmer(
          duration: _period,
          delay: _delay,
          color: Color.lerp(colors.surface2, colors.ink2, _highlightMix),
        );
  }
}

/// A card-shaped skeleton, matching an [InstrumentModule]'s shape and padding.
class SkeletonCard extends StatelessWidget {
  /// [child] is the card's placeholder content.
  const SkeletonCard({
    required this.child,
    this.padding = const EdgeInsets.all(14),
    super.key,
  });

  /// What sits inside.
  final Widget child;

  /// Legacy's `EdgeInsets.all(14)` — the module's own padding.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: colors.surface,
        shape: StateCard.shapeOf(),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// Legacy's `_tile` — a grid cell: label · value · mini-chart.
class SkeletonTile extends StatelessWidget {
  /// Draws one grid cell's placeholder.
  const SkeletonTile({super.key});

  @override
  Widget build(BuildContext context) => const SkeletonCard(
    child: SizedBox(
      height: 92,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HSkeleton(width: 56, height: 9),
          SizedBox(height: 14),
          HSkeleton(width: 64, height: 22, radius: 7),
          Spacer(),
          HSkeleton(width: double.infinity, height: 26),
        ],
      ),
    ),
  );
}

/// Legacy's `_row2` — the grid's two-up row.
class SkeletonTileRow extends StatelessWidget {
  /// Draws two [SkeletonTile]s with legacy's 10 px gutter.
  const SkeletonTileRow({super.key});

  @override
  Widget build(BuildContext context) => const Row(
    children: [
      Expanded(child: SkeletonTile()),
      SizedBox(width: 10),
      Expanded(child: SkeletonTile()),
    ],
  );
}

/// Legacy's `_richCard` — label · big value · chart block · three stats.
class SkeletonRichCard extends StatelessWidget {
  /// [chartHeight] is legacy's `chart` parameter, default 44.
  const SkeletonRichCard({this.chartHeight = 44, super.key});

  /// How tall the chart block is.
  final double chartHeight;

  @override
  Widget build(BuildContext context) => SkeletonCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const HSkeleton(width: 110, height: 10),
        const SizedBox(height: 16),
        const HSkeleton(width: 96, height: 34, radius: 8),
        const SizedBox(height: 16),
        HSkeleton(width: double.infinity, height: chartHeight, radius: 8),
        const SizedBox(height: 16),
        const Row(
          children: [
            Expanded(child: HSkeleton(height: 14)),
            SizedBox(width: 24),
            Expanded(child: HSkeleton(height: 14)),
            SizedBox(width: 24),
            Expanded(child: HSkeleton(height: 14)),
          ],
        ),
      ],
    ),
  );
}
