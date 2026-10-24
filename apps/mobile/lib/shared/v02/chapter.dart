/// The three pieces that turn a long screen into chapters you can find.
///
/// ```css
/// .chapter-nav          { display:flex; gap:6px; margin-block:20px 8px;
///                         position:sticky; top:0; padding-block:8px; }
/// .chapter-nav button   { padding:9px 12px; border:1px solid var(--line);
///                         border-radius:20px; color:var(--muted);
///                         font-size:10px; }
/// .chapter-nav button:first-child { color:var(--fitness);
///                                   border-color:var(--fitness); }
/// .chapter-heading      { display:flex; align-items:center; gap:8px;
///                         margin-top:28px; margin-bottom:4px; }
/// .chapter-heading .icon{ width:18px; height:18px; color:var(--family); }
/// .chapter-heading h2   { font-size:20px; }
/// .chapter-heading .grow{ height:1px; background:var(--line); margin-left:8px; }
/// .twin-panels          { display:grid; grid-template-columns:repeat(2,1fr);
///                         gap:10px; }
/// ```
///
/// **The nav's `position: sticky` IS reproduced.** It was skipped once, on the
/// grounds that a sticky header inside a `ListView.builder` means a
/// `SliverPersistentHeader` and a different scroll structure for the whole
/// screen. That is true, and it is what `shared/instrument_screen.dart` now
/// builds: a section declares [ChapterNav.extentOf] as its pinned extent and the
/// shell splits its list around it. Lazy building — and therefore reveal-once —
/// is unchanged, because a `SliverList.builder` destroys off-screen items on
/// exactly the same terms.
///
/// A pinned header covers the top of the viewport, so a jump has to land its
/// target BELOW it. `.chapter-heading { scroll-margin-top: 66px }` is the CSS's
/// answer and `today_chapters.dart` is ours — it subtracts this control's own
/// measured height rather than a number typed twice.
///
/// The prototype colours the FIRST button and no other, which reads as "you are
/// here" and is wrong the moment you scroll. [ChapterNav] colours [selected]
/// instead, which is the same pixels for the same default and correct after a
/// jump.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/core/theme/type_scale.dart';
import 'package:healthee/shared/page_section.dart';
import 'package:healthee/shared/v02/panel_density.dart';

/// One entry in a [ChapterNav].
@immutable
class ChapterTarget {
  /// [onJump] of null draws the button disabled rather than dead — see
  /// `today_chapters.dart` for the jump itself.
  const ChapterTarget(this.label, this.onJump);

  /// The button's words.
  final String label;

  /// What tapping it does.
  final VoidCallback? onJump;
}

/// `.chapter-nav` — the three jump buttons above the chapters.
class ChapterNav extends StatelessWidget {
  /// Builds the row; [selected] is drawn in the family colour.
  const ChapterNav(this.targets, {this.selected = 0, super.key});

  /// `.chapter-nav { gap: 6px }`.
  static const double gap = 6;

  /// `.chapter-nav { margin-block: 20px 8px }`.
  static const EdgeInsets margin = EdgeInsets.only(top: 20, bottom: 8);

  /// `.chapter-nav button { padding: 9px 12px }`, with the sides at 10. The
  /// CSS's 12 framed a 10 px label; at the ladder's 12 px caption, the 16 px
  /// this takes back across Sleep's four pills is what fits them on a 390 px
  /// phone without the last one cut at the edge (narrower phones scroll).
  static const EdgeInsets buttonPadding = EdgeInsets.symmetric(
    horizontal: 10,
    vertical: 9,
  );

  /// `.chapter-nav button { border-radius: 20px }`.
  static const double radius = 20;

  /// How tall this control is, in the context it will be drawn in.
  ///
  /// A pinned sliver declares its extent before it lays out, so the height has
  /// to be computed rather than observed. Every term is one of the constants
  /// above plus the one thing that is not fixed — the pill's line of text, which
  /// grows with the owner's text-scale setting. A literal here would clip the
  /// nav at any scale but the default, which is the failure the measurement
  /// exists to avoid.
  static double extentOf(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(text: 'Ag', style: TypeScale.chapterNav),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final line = painter.height;
    painter.dispose();
    return margin.vertical + buttonPadding.vertical + hairline * 2 + line;
  }

  /// Where each button goes.
  final List<ChapterTarget> targets;

  /// Which one is drawn as current.
  final int selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final family = context.family;
    return Padding(
      padding: margin,
      // Horizontally scrollable, because the row is three variable-width pills
      // and a narrow phone (or a large text scale) makes them wider than the
      // page. The prototype's flex row simply overflows there; a `Wrap` would
      // move the third button onto its own line and change the control's shape,
      // so the row keeps its shape and the overflow becomes a scroll.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (var i = 0; i < targets.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: gap),
              _NavButton(
                target: targets[i],
                tint: i == selected ? family : colors.ink2,
                edge: i == selected ? family : colors.line,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.target,
    required this.tint,
    required this.edge,
  });

  final ChapterTarget target;
  final Color tint;
  final Color edge;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: target.onJump,
        // Border only, no fill: without this the tappable part is the outline
        // and the letters, with a hole through the middle of the control.
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: ChapterNav.buttonPadding,
          decoration: BoxDecoration(
            border: Border.all(color: edge, width: hairline),
            borderRadius: BorderRadius.circular(ChapterNav.radius),
          ),
          child: Text(
            target.label,
            style: TypeScale.chapterNav.copyWith(color: tint),
          ),
        ),
      ),
    );
  }
}

/// `.chapter-heading` — an icon, a name, and a rule running to the edge.
class ChapterHeading extends StatelessWidget {
  /// Builds the heading. [tone] declares the family for the icon and the rule.
  const ChapterHeading({
    required this.title,
    required this.icon,
    this.tone,
    super.key,
  });

  /// `.chapter-heading { margin-top: 28px }`.
  ///
  /// **The bottom is `PageSpacing.afterHeading`, not the CSS's 4px.** The
  /// prototype's 4 put the chapter title against the top of its first card
  /// while every `SectionHead` on the same screen left 12, and the owner read
  /// the difference as a bug rather than as two stylesheets. One heading gap,
  /// shared, so they cannot drift again.
  static const EdgeInsets margin = EdgeInsets.only(
    top: 28,
    bottom: PageSpacing.afterHeading,
  );

  /// An inline icon beside text is 16 px (the brief), in ink2 not the family.
  static const double iconSize = 16;

  /// `.chapter-heading { gap: 8px }` and the rule's own `margin-left: 8px`.
  static const double gap = 8;

  /// The chapter's name.
  final String title;

  /// Drawn before it, 16 px in ink2.
  final IconData icon;

  /// The family for this heading. Null inherits.
  final Tone? tone;

  @override
  Widget build(BuildContext context) {
    final tone = this.tone;
    return tone == null
        ? _body(context)
        : ToneScope(
            tone: tone,
            child: Builder(builder: _body),
          );
  }

  /// The shortest the rule is allowed to get before the title gives way.
  ///
  /// `.chapter-heading .grow` has no minimum in the CSS because a browser never
  /// needs one — the `h2` is `width: auto` and simply takes what it needs. Here
  /// it is the graceful-degradation floor: a title too long for the row keeps
  /// this much rule and ellipsizes into the rest, rather than pushing the rule
  /// to nothing or overflowing the row.
  static const double minRule = 24;

  /// Identifies the rule, so a test can measure where it ends.
  static const Key ruleKey = ValueKey<String>('chapter-heading.rule');

  /// **The title is intrinsic; only the rule flexes.**
  ///
  /// It used to be `Flexible(title)` beside `Expanded(rule)`. Both default to
  /// `flex: 1`, so `RenderFlex` split the free space **equally** — on a 390 px
  /// phone the title's half is about 148 px and `Last night → today` at
  /// 18 px/-0.6 needs about 160, so every chapter title on the installed build
  /// ellipsized while the rule ran half the row. The owner: *"these header texts
  /// in web looks right but in app its getting clipped of or truncated"*.
  ///
  /// Raising the title's flex does not fix it: a LOOSE `Flexible` that uses less
  /// than its share does not hand the surplus back, so the title comes out whole
  /// and the rule comes out stubby — wrong in the other direction, and only
  /// visible at some widths.
  ///
  /// So the title is measured and given exactly what it needs, and the rule
  /// takes the true remainder — which is what `width: auto` beside `flex: 1`
  /// does in the prototype. `TextPainter` rather than `IntrinsicWidth` because
  /// the row must also know when the title does NOT fit, and because intrinsics
  /// inside a `ListView.builder` cost a second layout pass per item.
  Widget _body(BuildContext context) {
    final colors = context.colors;
    final style = TypeScale.chapterTitle.copyWith(color: colors.ink);
    return Padding(
      padding: margin,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final room =
              constraints.maxWidth - iconSize - gap - gap * 2 - minRule;
          final painter = TextPainter(
            text: TextSpan(text: title, style: style),
            maxLines: 1,
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout();
          final wanted = painter.width;
          painter.dispose();
          return Row(
            children: <Widget>[
              Icon(icon, size: iconSize, color: colors.ink2),
              const SizedBox(width: gap),
              SizedBox(
                width: wanted < room ? wanted : (room < 0 ? 0 : room),
                child: Text(
                  title,
                  style: style,
                  maxLines: 1,
                  // The floor, not the normal case: a title that fits is given
                  // its own width above and never reaches this.
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: gap * 2),
              Expanded(
                child: SizedBox(
                  key: ruleKey,
                  height: hairline,
                  child: ColoredBox(color: colors.line),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// `.twin-panels` — two panels sharing a row, each at half width.
///
/// Declares [PanelDensityLevel.compact] for both, which is the whole reason the
/// two halves come out at the CSS's smaller type instead of a full-width panel's
/// squeezed into half the space.
class TwinPanels extends StatelessWidget {
  /// Builds the pair. Both children stretch to the taller one.
  const TwinPanels({required this.left, required this.right, super.key});

  /// `.twin-panels { gap: 10px }`.
  static const double gap = 10;

  /// The left panel.
  final Widget left;

  /// The right panel.
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return PanelDensity(
      level: PanelDensityLevel.compact,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(child: left),
            const SizedBox(width: gap),
            Expanded(child: right),
          ],
        ),
      ),
    );
  }
}
