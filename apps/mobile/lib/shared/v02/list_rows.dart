/// `.card.flush` and `.list-row` — a run of destinations inside one container.
///
/// ```css
/// .card            { background:var(--surface); color:var(--ink);
///                    border:1px solid var(--line); border-radius:22px;
///                    padding:20px; }
/// .card.flush      { padding:0; overflow:clip; }
/// .list-row        { display:flex; align-items:center; gap:12px; width:100%;
///                    min-height:72px; padding:16px 20px; text-align:left; }
/// .list-row + .list-row { border-top:1px solid var(--line); }
/// .list-row strong { font-size:13px; font-weight:700; display:block; }
/// .list-row small  { color:var(--muted); font-size:11px; display:block; }
/// .list-row > .icon:last-child { width:16px; color:var(--subtle); }
/// ```
///
/// The rule is **between** rows and not under each one, so a flush card cannot
/// end on a hairline that reads as a cut-off list.
///
/// ## The tone is per row, not per card
///
/// `H.row(...)` resolves `data-tone` from the route it points at
/// (`panels.js::H.toneFor`), so a workout row and a route row inside one card
/// carry different families — heart and movement. That is why [V02ListRow] takes
/// a [Tone] and declares its own scope: the `IconTile` inside it reads
/// `context.family` and never a colour, so one card holding two families needs
/// two scopes and no `Color` anywhere.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/shapes.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/core/theme/type_scale.dart';
import 'package:healthee/shared/v02/icon_tile.dart';
import 'package:healthee/shared/v02/panel.dart';
import 'package:solar_icons/solar_icons.dart';

/// `.card.flush` — a bordered container whose children reach its edges.
class FlushCard extends StatelessWidget {
  /// Builds the card. An empty [rows] draws nothing at all — a bordered box
  /// with no rows in it is a list that failed to load.
  const FlushCard({required this.rows, super.key});

  /// `.card, .metric-card, .challenge-card { border-radius: 22px }`.
  static const double radius = Panel.radius;

  /// The destinations, top to bottom.
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }
    final colors = context.colors;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        color: colors.surface,
        shape: hSquircle(radius),
      ),
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

/// `.list-row` — an icon tile, a name over a detail, and a chevron.
class V02ListRow extends StatelessWidget {
  /// Builds a row. [onOpen] of null draws the row without a chevron: a row that
  /// leads nowhere must not advertise that it does.
  const V02ListRow({
    required this.icon,
    required this.title,
    required this.tone,
    this.detail,
    this.onOpen,
    super.key,
  });

  /// `.list-row { min-height: 72px }`.
  static const double minHeight = 72;

  /// `.list-row { padding: 16px 20px }`.
  static const EdgeInsets padding = EdgeInsets.symmetric(
    horizontal: 20,
    vertical: 16,
  );

  /// `.list-row { gap: 12px }`.
  static const double gap = 12;

  /// `.list-row > .icon:last-child { width: 16px }`.
  static const double chevronSize = 16;

  /// The glyph in the tile.
  final IconData icon;

  /// `strong` — what this row is.
  final String title;

  /// `small` — one line about it. Null draws nothing rather than a blank line.
  final String? detail;

  /// The family this row's tile resolves. `H.toneFor(route)`.
  final Tone tone;

  /// Where the row goes.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final row = ToneScope(
      tone: tone,
      child: Container(
        constraints: const BoxConstraints(minHeight: minHeight),
        padding: padding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            IconTile(icon),
            const SizedBox(width: gap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    title,
                    style: TypeScale.panelTitle.copyWith(color: colors.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (detail case final String said)
                    Text(
                      said,
                      style: TypeScale.panelNote.copyWith(color: colors.ink2),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (onOpen != null) ...<Widget>[
              const SizedBox(width: gap),
              Icon(
                SolarIconsOutline.altArrowRight,
                size: chevronSize,
                color: colors.ink2,
              ),
            ],
          ],
        ),
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
