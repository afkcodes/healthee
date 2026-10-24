/// A card of destinations: bare 24 px icons, a name over a detail, and a 24 px
/// chevron, divided by hairlines.
///
/// The icons are secondary ink and are never put in a container or tinted: a
/// link is chrome, and colour is spent on data. A row with no [LinkRow.onOpen]
/// draws no chevron, because a row that leads nowhere must not advertise that
/// it does.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/shared/v02/surface_panels.dart';
import 'package:solar_icons/solar_icons.dart';

/// The icon and chevron size.
const double kLinkGlyph = 24;

/// The card around [rows].
class LinkListCard extends StatelessWidget {
  /// An empty [rows] draws nothing: a card with no rows is a list that failed
  /// to load.
  const LinkListCard({required this.rows, super.key});

  /// The destinations, top to bottom.
  final List<LinkRow> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }
    final colors = context.colors;
    return SurfaceCard(
      flush: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var i = 0; i < rows.length; i++) ...<Widget>[
            if (i > 0)
              Divider(
                height: hairline,
                thickness: hairline,
                color: colors.line,
              ),
            rows[i],
          ],
        ],
      ),
    );
  }
}

/// One destination.
class LinkRow extends StatelessWidget {
  /// A row named [title], with an optional one-line [detail].
  const LinkRow({
    required this.icon,
    required this.title,
    this.detail,
    this.onOpen,
    super.key,
  });

  /// The row's minimum height.
  static const double minHeight = 64;

  /// The glyph, drawn bare.
  final IconData icon;

  /// What the row is.
  final String title;

  /// One line about it.
  final String? detail;

  /// Where it goes.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final row = Container(
      constraints: const BoxConstraints(minHeight: minHeight),
      padding: const EdgeInsets.symmetric(
        horizontal: Insets.card,
        vertical: Insets.md,
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: kLinkGlyph, color: colors.ink2),
          const SizedBox(width: Insets.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TypeLadder.bodyStrong.copyWith(color: colors.ink),
                ),
                if (detail case final String said)
                  Text(
                    said,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TypeLadder.callout.copyWith(color: colors.ink2),
                  ),
              ],
            ),
          ),
          if (onOpen != null) ...<Widget>[
            const SizedBox(width: Insets.md),
            Icon(
              SolarIconsOutline.altArrowRight,
              size: kLinkGlyph,
              color: colors.ink2,
            ),
          ],
        ],
      ),
    );
    return onOpen == null
        ? row
        : Semantics(
            button: true,
            label: detail == null ? title : '$title · $detail',
            child: GestureDetector(
              onTap: onOpen,
              behavior: HitTestBehavior.opaque,
              child: row,
            ),
          );
  }
}
