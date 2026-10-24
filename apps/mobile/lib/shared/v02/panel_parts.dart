/// The four things that sit inside a `.panel`, in the CSS's own proportions.
///
/// ```css
/// .panel-summary   { display:flex; justify-content:space-between;
///                    align-items:end; gap:12px; margin-bottom:8px; }
/// .panel-value     { font-size:36px; font-weight:600; letter-spacing:-1.8px;
///                    line-height:1.2; }
/// .panel-value>small { color:var(--muted); font-size:12px; font-weight:400;
///                      letter-spacing:0; margin-left:4px; }
/// .panel-summary p { font-size:11px; text-align:right; }
/// .panel-note      { font-size:11px; line-height:1.7; color:var(--muted);
///                    margin-top:12px; }
/// .three           { display:grid; grid-template-columns:repeat(3,1fr);
///                    gap:8px; }
/// .stat-label      { font-size:10px; color:var(--muted); }   /* in a panel */
/// .stat-number     { font-size:22px; font-weight:600; letter-spacing:-1px;
///                    line-height:1.4; }
/// .stat-number>span{ font-size:11px; margin-left:4px; color:var(--muted); }
/// .progress-track  { height:7px; background:var(--surface-soft);
///                    border-radius:8px; overflow:clip; }
/// .progress-track>i{ background:var(--family); }
/// ```
///
/// **None of these takes a `Color`.** The number is ink, the qualifier is ink2,
/// and the one coloured thing — the progress fill — resolves `context.family`
/// from the enclosing `ToneScope`. That is the whole reason a track can be
/// dropped into any panel and come out the right colour.
///
/// The vertical margins in the CSS are **owned here**, not left to the caller,
/// because `.panel-summary`'s 8 and `.panel-note`'s 12 are what make a panel's
/// interior a rhythm rather than a stack. A call site that wrote its own numbers
/// would be a second opinion about the same gap.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/shapes.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/core/theme/type_scale.dart';
import 'package:healthee/shared/v02/panel_density.dart';

/// `.panel-summary` — the number a panel exists to show, and its context.
class PanelValue extends StatelessWidget {
  /// [context_] is the right-hand qualifier; null draws none.
  const PanelValue(this.value, {this.unit, this.context_, super.key});

  /// `.panel-summary { gap: 12px }`.
  static const double gap = 12;

  /// `.panel-summary { margin-bottom: 8px }`.
  static const double bottomGap = 8;

  /// `.panel-value > small { margin-left: 4px }`.
  static const double unitGap = 4;

  /// Identifies the figure's box, so a test can measure what it was given.
  static const Key valueKey = ValueKey<String>('panel-value.figure');

  /// The figure.
  final String value;

  /// Its unit, small and beside it.
  final String? unit;

  /// The right-hand sentence — a date, a reference, a second reading.
  final String? context_;

  /// **The figure is intrinsic; only the sentence flexes.**
  ///
  /// It used to be `Flexible(figure)` beside `Flexible(sentence)`. Both default
  /// to `flex: 1`, so `RenderFlex` handed each exactly half the row — and a
  /// panel whose figure is `7h 42m` or `1,284` beside a sentence lost the end of
  /// its own number at every phone width. This is the `ChapterHeading` defect in
  /// a second place, and it is fixed the same way and for the same reason: the
  /// CSS is `space-between` over two `auto` boxes, which is "each takes what it
  /// needs", not "each takes half".
  ///
  /// Raising the figure's flex does not fix it — a loose `Flexible` that uses
  /// less than its share does not hand the surplus back, so a short figure would
  /// leave the sentence stranded in a corner. So the figure is measured and
  /// given exactly what it needs, and the sentence takes the true remainder.
  ///
  /// [available] is the row minus its [gap]. **The sentence's floor is its own
  /// min-content width — its longest word — and not a number picked here.** That
  /// is what a browser reserves for a flex item with `min-width: auto`, and it
  /// is why the CSS needs no minimum: a paragraph shrinks by wrapping until it
  /// is one word wide, and only then does the figure start to give way. A fixed
  /// reserve would have clipped a long figure on a 320 px phone in order to
  /// hold room the sentence did not need.
  double _figureWidth(BuildContext context, double available, bool compact) {
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    TextPainter painterFor(String text, TextStyle style, {int? maxLines}) =>
        TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: maxLines,
          textDirection: direction,
          textScaler: scaler,
        )..layout();

    double widthOf(String text, TextStyle style) {
      final painter = painterFor(text, style, maxLines: 1);
      final width = painter.width;
      painter.dispose();
      return width;
    }

    var wanted = widthOf(
      value,
      compact ? TypeScale.panelValueCompact : TypeScale.panelValue,
    );
    if (unit case final String unit) {
      wanted +=
          unitGap +
          widthOf(
            unit,
            compact ? TypeScale.panelUnitCompact : TypeScale.panelUnit,
          );
    }
    var floor = 0.0;
    if (context_ case final String side) {
      final painter = painterFor(side, TypeScale.panelContext);
      floor = painter.minIntrinsicWidth;
      painter.dispose();
    }
    final room = available - floor;
    if (wanted < room) {
      return wanted;
    }
    return room < 0 ? 0 : room;
  }

  @override
  Widget build(BuildContext context) {
    final side = context_;
    return Padding(
      padding: const EdgeInsets.only(bottom: bottomGap),
      child: side == null
          // Nothing to share the row with, so the figure simply takes it —
          // `Flexible` rather than a measurement, because there is no second
          // box whose share could be got wrong.
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Flexible(key: valueKey, child: _figure(context)),
              ],
            )
          : LayoutBuilder(
              builder: (context, constraints) => Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  SizedBox(
                    key: valueKey,
                    width: _figureWidth(
                      context,
                      constraints.maxWidth - gap,
                      context.compactPanel,
                    ),
                    child: _figure(context),
                  ),
                  const SizedBox(width: gap),
                  Expanded(
                    child: Text(
                      side,
                      textAlign: TextAlign.right,
                      style: TypeScale.panelContext.copyWith(
                        color: context.colors.ink2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  /// The figure and its unit, on one baseline. Intrinsically as wide as it
  /// wants; the box around it decides how much of that it gets.
  Widget _figure(BuildContext context) {
    final colors = context.colors;
    final compact = context.compactPanel;
    final unit = this.unit;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
        Flexible(
          child: Text(
            value,
            style:
                (compact ? TypeScale.panelValueCompact : TypeScale.panelValue)
                    .copyWith(color: colors.ink),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
          ),
        ),
        if (unit != null) ...<Widget>[
          const SizedBox(width: unitGap),
          Text(
            unit,
            style: (compact ? TypeScale.panelUnitCompact : TypeScale.panelUnit)
                .copyWith(color: colors.ink2),
          ),
        ],
      ],
    );
  }
}

/// `.panel-note` — the sentence a panel discloses in, inside its own bounds.
class PanelNote extends StatelessWidget {
  /// Builds the note. [text] is drawn verbatim.
  const PanelNote(this.text, {super.key});

  /// `.panel-note { margin-top: 12px }`, or 8 in a twin panel.
  static const double topGap = 12;

  /// `.twin-panels .panel-note { margin-top: 8px }`.
  static const double compactTopGap = 8;

  /// What the panel has to say about its own number.
  final String text;

  @override
  Widget build(BuildContext context) {
    final compact = context.compactPanel;
    return Padding(
      padding: EdgeInsets.only(top: compact ? compactTopGap : topGap),
      child: Text(
        text,
        style: (compact ? TypeScale.panelNoteCompact : TypeScale.panelNote)
            .copyWith(color: context.colors.ink2),
      ),
    );
  }
}

/// One cell of a [StatRow]: a label over a number with an optional unit.
@immutable
class Stat {
  /// Builds a statistic.
  const Stat(this.label, this.value, {this.unit});

  /// `.stat-label` — what the number is.
  final String label;

  /// `.stat-number` — the number.
  final String value;

  /// `.stat-number > span` — its unit.
  final String? unit;
}

/// `.three` — up to three [Stat]s across a panel's width.
class StatRow extends StatelessWidget {
  /// Builds the row. An empty [stats] draws nothing at all.
  const StatRow(this.stats, {super.key});

  /// `.three { gap: 8px }`.
  static const double gap = 8;

  /// `.stat-number > span { margin-left: 4px }`.
  static const double unitGap = 4;

  /// The statistics, left to right.
  final List<Stat> stats;

  @override
  Widget build(BuildContext context) {
    if (stats.isEmpty) {
      return const SizedBox.shrink();
    }
    final colors = context.colors;
    // A row of labels over a row of numbers, not a column per cell: a label
    // that wraps grows the label row for every cell, and bottom-aligned labels
    // keep each number under its own, so the figures share one baseline.
    Widget across(CrossAxisAlignment align, Widget Function(Stat) cell) => Row(
      crossAxisAlignment: align,
      children: <Widget>[
        for (var i = 0; i < stats.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: gap),
          Expanded(child: cell(stats[i])),
        ],
      ],
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        across(
          CrossAxisAlignment.end,
          (stat) => Text(
            stat.label,
            style: TypeScale.statLabel.copyWith(color: colors.ink2),
            // A third of a row: the label wraps rather than being cut.
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        across(
          CrossAxisAlignment.start,
          (stat) => Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Flexible(
                child: Text(
                  stat.value,
                  style: TypeScale.statValue.copyWith(color: colors.ink),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.clip,
                ),
              ),
              if (stat.unit case final String unit) ...<Widget>[
                const SizedBox(width: unitGap),
                Text(
                  unit,
                  style: TypeScale.statUnit.copyWith(color: colors.ink2),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// `.progress-track` — one continuous fill, in the enclosing family.
///
/// [fraction] is clamped to 0–1 rather than allowed to overflow: a bar longer
/// than its track is a reading drawn outside the scale it is read against, and
/// the panel's own words are where "over the reference" belongs.
class ProgressTrack extends StatelessWidget {
  /// Builds a track filled to [fraction] of its width.
  const ProgressTrack({required this.fraction, super.key});

  /// `.progress-track { height: 7px }`.
  static const double height = 7;

  /// `.progress-track { border-radius: 8px }`.
  static const double radius = 8;

  /// How much of the track is filled, 0–1.
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final filled = fraction.isFinite ? fraction.clamp(0.0, 1.0) : 0.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        height: height,
        child: ColoredBox(
          color: context.colors.surface2,
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: filled,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: context.family,
                shape: hSquircle(radius),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The window a group of figures belongs to — `Last night`, `The measured week`.
///
/// **A panel that stacks two windows must name them.** `need_panel.dart`
/// carried a seven-night debt, two last-night statistics and a seven-night
/// chart in one column with nothing between them, and on the owner's own data
/// the last-night gap landed eight minutes from the weekly mean nobody had
/// computed — so the wrong reading was indistinguishable from the right one.
/// The label costs one line and removes the ambiguity entirely.
///
/// Set in ink3: the brief reserves family hues for data marks, so a label names
/// its group in the quietest text colour rather than tinting itself.
class WindowLabel extends StatelessWidget {
  /// Names the window.
  const WindowLabel(this.text, {super.key});

  /// The window's name, set uppercase as a [TypeLadder.label]: structure, not
  /// prose.
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: TypeLadder.label.copyWith(color: context.colors.ink2),
  );
}
