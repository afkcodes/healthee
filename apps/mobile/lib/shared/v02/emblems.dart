/// The four drawn figures the supporting screens open with.
///
/// ```css
/// .device-visual      { display:grid; place-items:center; width:112px;
///                       height:136px; margin:24px auto; border-radius:40px;
///                       background:var(--surface-soft); color:var(--accent); }
/// .device-visual .icon{ width:90px; height:110px; stroke-width:.8; }
/// .coach-symbol       { display:grid; place-items:center; width:56px;
///                       height:56px; border-radius:20px;
///                       background:var(--accent-soft); color:var(--accent);
///                       margin-bottom:20px; }
/// .coach-symbol .icon { width:28px; height:28px; }
/// .sync-stages        { display:flex; align-items:center;
///                       justify-content:space-between; padding-block:24px; }
/// .sync-stages > div  { display:flex; flex-direction:column; align-items:center;
///                       gap:8px; font-size:10px; color:var(--muted); }
/// .sync-stages .icon  { width:26px; height:26px; color:var(--accent); }
/// .sync-stages > .icon{ width:16px; color:var(--rule); }
/// .timeline           { padding:8px 0; }
/// .timeline-item      { display:flex; gap:16px; position:relative;
///                       padding-bottom:28px; }
/// .timeline-item:not(:last-child)::before
///                     { width:1px; background:var(--line); left:15px;
///                       top:32px; bottom:0; }
/// .timeline-item .node{ display:grid; place-items:center; width:32px;
///                       height:32px; border-radius:50%;
///                       background:var(--surface-soft); color:var(--subtle);
///                       font-size:11px; }
/// .timeline-item .node.active { background:var(--accent-soft);
///                               color:var(--accent); }
/// ```
///
/// `stroke-width: .8` on the device glyph is a **stroke** width, and Flutter's
/// `Icon` has no stroke — the glyph is a filled path in a font. So the device
/// figure is drawn at its size and the hairline weight is not reproducible; the
/// substitution is recorded here rather than approximated with a thinner glyph
/// that does not exist in the icon set.
///
/// The timeline's connector runs from the bottom of one node to the top of the
/// next, and the LAST item draws none — `:not(:last-child)` in the CSS, and the
/// same condition here. A rule hanging off the final step would point at
/// nothing.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_scale_forms.dart';
import 'package:solar_icons/solar_icons.dart';

/// `.device-visual` — the strap, large; no recessed ground (the brief).
class DeviceVisual extends StatelessWidget {
  /// Builds the figure.
  const DeviceVisual({super.key});

  /// `width: 112px`.
  static const double width = 112;

  /// `height: 136px`.
  static const double height = 136;

  /// `border-radius: 40px`.
  static const double radius = 40;

  /// `margin: 24px auto`.
  static const double margin = 24;

  /// `.device-visual .icon { height: 110px }`. See the library docstring on the
  /// stroke width, which does not survive the port.
  static const double iconSize = 110;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: margin),
      child: Center(
        // Bare: the strap's glyph on the page, with no recessed ground.
        child: SizedBox(
          width: width,
          height: height,
          child: Icon(
            SolarIconsOutline.watchRound,
            size: iconSize,
            color: colors.ink2,
          ),
        ),
      ),
    );
  }
}

/// `.coach-symbol` — the small rounded emblem About and Welcome open with.
class CoachSymbol extends StatelessWidget {
  /// Builds the emblem around [icon].
  const CoachSymbol(this.icon, {super.key});

  /// `width: 56px; height: 56px`.
  static const double size = 56;

  /// `border-radius: 20px`.
  static const double radius = 20;

  /// `.coach-symbol .icon { width: 28px }`.
  static const double iconSize = 28;

  /// `margin-bottom: 20px`.
  static const double bottomGap = 20;

  /// The glyph.
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: bottomGap),
      child: Align(
        alignment: Alignment.centerLeft,
        // Bare: an icon is never drawn inside a tile, a circle or a tint.
        child: Icon(icon, size: iconSize, color: colors.ink2),
      ),
    );
  }
}

/// `.sync-stages` — strap → phone → server, as three labelled glyphs.
class SyncStages extends StatelessWidget {
  /// Builds the row from [stages], each an icon and its name.
  const SyncStages(this.stages, {super.key});

  /// `padding-block: 24px`.
  static const double padding = 24;

  /// `.sync-stages > div { gap: 8px }`.
  static const double gap = 8;

  /// `.sync-stages .icon { width: 26px }`.
  static const double stageIcon = 26;

  /// `.sync-stages > .icon { width: 16px }` — the arrow between stages.
  static const double arrowIcon = 16;

  /// The stages, in order.
  final List<(IconData, String)> stages;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: padding),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          for (var i = 0; i < stages.length; i++) ...<Widget>[
            if (i > 0)
              Icon(
                SolarIconsOutline.arrowRight,
                size: arrowIcon,
                color: colors.rule,
              ),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(stages[i].$1, size: stageIcon, color: colors.accent),
                  const SizedBox(height: gap),
                  Text(
                    stages[i].$2,
                    textAlign: TextAlign.center,
                    style: FormType.syncStage.copyWith(color: colors.ink2),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One step of a [HTimeline].
@immutable
class TimelineStep {
  /// [active] lights the node in the accent — the step being done now.
  const TimelineStep({
    required this.title,
    required this.body,
    this.active = false,
  });

  /// What this step is.
  final String title;

  /// What happens in it.
  final String body;

  /// Whether this is where the owner is.
  final bool active;
}

/// `.timeline` — the numbered steps of the pairing journey.
class HTimeline extends StatelessWidget {
  /// Builds the timeline from [steps].
  const HTimeline(this.steps, {super.key});

  /// `.timeline { padding: 8px 0 }`.
  static const double padding = 8;

  /// `.timeline-item { gap: 16px }`.
  static const double gap = 16;

  /// `.timeline-item { padding-bottom: 28px }`.
  static const double stepGap = 28;

  /// `.node { width: 32px; height: 32px }`.
  static const double nodeSize = 32;

  /// `::before { left: 15px }` — the connector's centre.
  static const double ruleLeft = 15;

  /// `::before { top: 32px }` — it starts at the node's bottom edge.
  static const double ruleTop = nodeSize;

  /// `.timeline-item p { margin-top: 4px }`.
  static const double bodyGap = 4;

  /// The steps, in order. Numbered from one.
  final List<TimelineStep> steps;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var i = 0; i < steps.length; i++)
            IntrinsicHeight(
              child: Stack(
                children: <Widget>[
                  // `:not(:last-child)` — the final step connects to nothing.
                  if (i < steps.length - 1)
                    Positioned(
                      left: ruleLeft,
                      top: ruleTop,
                      bottom: 0,
                      width: hairline,
                      child: ColoredBox(color: colors.line),
                    ),
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: i < steps.length - 1 ? stepGap : 0,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Container(
                          width: nodeSize,
                          height: nodeSize,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: steps[i].active
                                ? colors.accentSoft
                                : colors.surface2,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${i + 1}',
                            style: FormType.timelineNode.copyWith(
                              color: steps[i].active
                                  ? colors.accent
                                  : colors.ink2,
                            ),
                          ),
                        ),
                        const SizedBox(width: gap),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                steps[i].title,
                                style: FormType.timelineTitle.copyWith(
                                  color: colors.ink,
                                ),
                              ),
                              const SizedBox(height: bodyGap),
                              Text(
                                steps[i].body,
                                style: FormType.timelineBody.copyWith(
                                  color: colors.ink2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
