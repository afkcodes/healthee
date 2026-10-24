/// `.list-row`, `.card.flush` and `.timeline` — the three list shapes v02 uses.
///
/// ```css
/// .list-row              { display:flex; align-items:center; gap:12px;
///                          width:100%; min-height:72px; padding:16px 20px }
/// .list-row + .list-row  { border-top:1px solid var(--line) }
/// .list-row strong       { font:700 13px }
/// .list-row small        { font-size:11px; color:var(--muted) }
/// .list-row > .icon:last-child { width:16px; color:var(--subtle) }
///
/// .timeline              { padding:8px 0 }
/// .timeline-item         { display:flex; gap:16px; padding-bottom:28px }
/// .timeline-item:not(:last-child)::before
///                        { width:1px; background:var(--line);
///                          left:15px; top:32px; bottom:0 }
/// .timeline-item .node   { width:32px; height:32px; border-radius:50%;
///                          background:var(--surface-soft); color:var(--subtle) }
/// .timeline-item .node.active { background:var(--accent-soft);
///                               color:var(--accent) }
/// ```
///
/// **A row's icon tile takes no colour.** `H.row(...)` in the prototype sets
/// `data-tone="${H.toneFor(route)}"` on the anchor, so the tile's ink and ground
/// come from the row's own destination. [ListRow] takes a [Tone] for that reason
/// and a `Color` for no reason at all.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/core/theme/type_scale.dart';
import 'package:healthee/shared/v02/icon_tile.dart';
import 'package:healthee/shared/v02/surfaces.dart';
import 'package:solar_icons/solar_icons.dart';

/// One `.list-row`: a tile, a title over a sentence, and a trailing glyph.
class ListRow extends StatelessWidget {
  /// [onTap] of null draws the row without its chevron — a row that leads
  /// nowhere must not look like one that does.
  const ListRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.trailing,
    this.tone,
    super.key,
  });

  /// `min-height: 72px`.
  static const double minHeight = 72;

  /// `padding: var(--space-lg) var(--space-xl)`.
  static const EdgeInsets padding = EdgeInsets.symmetric(
    horizontal: 20,
    vertical: 16,
  );

  /// `gap: var(--space-md)`.
  static const double gap = 12;

  /// `.list-row > .icon:last-child { width: 16px }`.
  static const double chevronSize = 16;

  /// The glyph in the tile.
  final IconData icon;

  /// `.list-row strong`.
  final String title;

  /// `.list-row small`.
  final String subtitle;

  /// Where the row goes. Null draws no chevron.
  final VoidCallback? onTap;

  /// Replaces the chevron — the prototype's `end` slot, used for a badge.
  final Widget? trailing;

  /// The family the tile resolves. Null inherits.
  final Tone? tone;

  @override
  Widget build(BuildContext context) {
    final Widget row = Builder(builder: _row);
    final tone = this.tone;
    return tone == null ? row : ToneScope(tone: tone, child: row);
  }

  Widget _row(BuildContext context) {
    final colors = context.colors;
    final body = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: minHeight),
      child: Padding(
        padding: padding,
        child: Row(
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
                    style: TypeScale.rowTitle.copyWith(color: colors.ink),
                  ),
                  Text(
                    subtitle,
                    style: TypeScale.tinyLabel.copyWith(color: colors.ink2),
                  ),
                ],
              ),
            ),
            if (trailing case final Widget end) ...<Widget>[
              const SizedBox(width: gap),
              end,
            ] else if (onTap != null) ...<Widget>[
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
    if (onTap == null) {
      return body;
    }
    return Semantics(
      button: true,
      label: '$title. $subtitle',
      child: ExcludeSemantics(
        child: InkWell(onTap: onTap, child: body),
      ),
    );
  }
}

/// `.card.flush` holding a run of [ListRow]s, ruled between.
class RowCard extends StatelessWidget {
  /// [rows] are drawn in order with `.list-row + .list-row`'s rule between them.
  const RowCard(this.rows, {super.key});

  /// The rows. An empty list draws **nothing** — not an empty card.
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }
    final colors = context.colors;
    return SurfaceCard(
      flush: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var i = 0; i < rows.length; i++) ...<Widget>[
            if (i > 0) Container(height: hairline, color: colors.line),
            rows[i],
          ],
        ],
      ),
    );
  }
}

/// One step of a `.timeline`.
@immutable
class TimelineStep {
  /// [done] draws the node's check; [active] gives it the family ground.
  const TimelineStep({
    required this.ordinal,
    required this.title,
    required this.body,
    this.done = false,
    this.active = false,
    this.actionLabel,
    this.onAction,
  });

  /// Its number, drawn when the step is not [done].
  final String ordinal;

  /// The step's name.
  final String title;

  /// What it is.
  final String body;

  /// Whether the node draws a check instead of its number.
  final bool done;

  /// Whether the node is filled — `.node.active`.
  final bool active;

  /// A link under the step, e.g. `Review outcome`.
  final String? actionLabel;

  /// What that link opens.
  final VoidCallback? onAction;
}

/// `.timeline` — the program's steps, with the rule that joins them.
class Timeline extends StatelessWidget {
  /// Builds the steps in order.
  const Timeline(this.steps, {super.key});

  /// `.timeline { padding: 8px 0 }`.
  static const double padding = 8;

  /// `.timeline-item { gap: 16px; padding-bottom: 28px }`.
  static const double gap = 16;

  /// The same.
  static const double itemGap = 28;

  /// `.timeline-item .node { width: 32px; height: 32px }`.
  static const double nodeSize = 32;

  /// `.timeline-item::before { top: 32px }` — the rule starts under the node.
  static const double ruleTop = nodeSize;

  /// The steps.
  final List<TimelineStep> steps;

  @override
  Widget build(BuildContext context) {
    if (steps.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var i = 0; i < steps.length; i++)
            _Item(step: steps[i], last: i == steps.length - 1),
        ],
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.step, required this.last});

  final TimelineStep step;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final family = context.family;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: Timeline.nodeSize,
            child: Column(
              children: <Widget>[
                Container(
                  width: Timeline.nodeSize,
                  height: Timeline.nodeSize,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: step.active ? context.familySoft : colors.surface2,
                    shape: BoxShape.circle,
                  ),
                  child: step.done
                      ? Icon(
                          Icons.check,
                          size: 16,
                          color: step.active ? family : colors.ink2,
                        )
                      : Text(
                          step.ordinal,
                          style: TypeScale.tinyLabel.copyWith(
                            color: step.active ? family : colors.ink2,
                          ),
                        ),
                ),
                // `::before` — the joining rule, absent on the last item.
                if (!last)
                  Expanded(
                    child: Container(width: hairline, color: colors.line),
                  ),
              ],
            ),
          ),
          const SizedBox(width: Timeline.gap),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : Timeline.itemGap),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    step.title,
                    style: TypeScale.rowTitle.copyWith(color: colors.ink),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    step.body,
                    style: TypeScale.tinyLabel.copyWith(color: colors.ink2),
                  ),
                  if (step.actionLabel case final String label)
                    TextButton(
                      onPressed: step.onAction,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        label,
                        style: TypeScale.textLink.copyWith(color: family),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
