/// `.journal-grid` — the ten things the strap cannot measure.
///
/// ```css
/// .journal-grid  { display:grid; grid-template-columns:repeat(3,minmax(0,1fr));
///                  gap:8px }
/// .journal-kind  { display:flex; flex-direction:column; align-items:center;
///                  gap:8px; padding:16px 4px; background:var(--surface);
///                  border:1px solid var(--line); border-radius:16px;
///                  font-size:11px }
/// .journal-kind .icon { color: var(--accent) }
/// ```
///
/// The order is `screens-actions.js::H.journalKinds`, and the labels are
/// [LogKind]'s own — the enum is what the endpoint accepts, so a tile that said
/// something else would be a name for a type the server has never heard of.
/// Fasting is the tenth tile and is not a [LogKind]: it is a start/end pair on
/// its own endpoint, which is why it is modelled as a null kind here.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_scale.dart';
import 'package:healthee/data/journal/log_kind.dart';
import 'package:solar_icons/solar_icons.dart';

/// One tile: a glyph, a word, and the kind it logs.
@immutable
class JournalKindTile {
  /// [kind] of null is the fasting tile — see the library docstring.
  const JournalKindTile(this.icon, this.label, this.kind);

  /// The glyph.
  final IconData icon;

  /// The word under it.
  final String label;

  /// What tapping it logs. Null is the fast.
  final LogKind? kind;
}

/// The prototype's ten, in the prototype's order.
const List<JournalKindTile> kJournalTiles = <JournalKindTile>[
  JournalKindTile(SolarIconsOutline.cupHot, 'Caffeine', LogKind.caffeine),
  JournalKindTile(SolarIconsOutline.waterdrop, 'Water', LogKind.water),
  JournalKindTile(SolarIconsOutline.smileCircle, 'Mood', LogKind.mood),
  JournalKindTile(
    SolarIconsOutline.meditation,
    'Meditation',
    LogKind.meditation,
  ),
  JournalKindTile(SolarIconsOutline.walking, 'Exercise', LogKind.exercise),
  JournalKindTile(SolarIconsOutline.weigher, 'Weight', LogKind.weight),
  JournalKindTile(SolarIconsOutline.moonSleep, 'Alcohol', LogKind.alcohol),
  JournalKindTile(SolarIconsOutline.clockCircle, 'Fasting', null),
  JournalKindTile(SolarIconsOutline.checklist, 'Habit', LogKind.habit),
  JournalKindTile(SolarIconsOutline.heart, 'Symptom', LogKind.symptom),
];

/// The three-column grid of kinds.
class JournalGrid extends StatelessWidget {
  /// [onPick] is handed the tile that was tapped.
  const JournalGrid({required this.onPick, this.fastOpen = false, super.key});

  /// `grid-template-columns: repeat(3, minmax(0, 1fr))`.
  static const int columns = 3;

  /// `gap: 8px`.
  static const double gap = 8;

  /// `padding: 16px 4px`.
  static const EdgeInsets tilePadding = EdgeInsets.symmetric(
    horizontal: 4,
    vertical: 16,
  );

  /// `border-radius: 16px`.
  static const double radius = 16;

  /// `gap: 8px` inside the tile, between the glyph and the word.
  static const double tileGap = 8;

  /// Opens the log for one kind.
  final void Function(JournalKindTile tile) onPick;

  /// Whether a fast is running — the fasting tile says which half it offers.
  final bool fastOpen;

  @override
  Widget build(BuildContext context) {
    final rows = <List<JournalKindTile>>[
      for (var i = 0; i < kJournalTiles.length; i += columns)
        kJournalTiles.sublist(i, (i + columns).clamp(0, kJournalTiles.length)),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var r = 0; r < rows.length; r++) ...<Widget>[
          if (r > 0) const SizedBox(height: gap),
          // `IntrinsicHeight` is what makes a grid row a grid row: the three
          // cells are as tall as the tallest of them. `stretch` alone asks for
          // infinite height inside a scroll, which is not a taller tile — it is
          // no layout at all.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (var c = 0; c < columns; c++) ...<Widget>[
                  if (c > 0) const SizedBox(width: gap),
                  Expanded(
                    child: c < rows[r].length
                        ? _Tile(
                            tile: rows[r][c],
                            fastOpen: fastOpen,
                            onPick: onPick,
                          )
                        // A cell with no tile draws nothing and keeps the
                        // column widths, which is what an incomplete CSS grid
                        // row does.
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.tile,
    required this.fastOpen,
    required this.onPick,
  });

  final JournalKindTile tile;
  final bool fastOpen;
  final void Function(JournalKindTile tile) onPick;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // The fasting tile names the half it offers, because it is the only tile
    // whose action depends on a state the server holds.
    final label = tile.kind == null && fastOpen ? 'End fast' : tile.label;
    return Semantics(
      button: true,
      label: label,
      child: ExcludeSemantics(
        child: Material(
          color: colors.surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(JournalGrid.radius),
          ),
          child: InkWell(
            onTap: () => onPick(tile),
            child: Padding(
              padding: JournalGrid.tilePadding,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(tile.icon, size: 22, color: colors.accent),
                  const SizedBox(height: JournalGrid.tileGap),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TypeScale.tinyLabel.copyWith(color: colors.ink),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
