/// The instrument module — legacy's `HModule`, and the three parts inside it.
///
/// **Ported from** `healthee-legacy/app/lib/ui/ui.dart` (`HModule`, `HEyebrow`,
/// `HModuleValue`, `HFoot`), geometry unchanged:
///
/// ```text
///   ┌──────────────────────────┐
///   │ SLEEP                  ⓘ │  eyebrow 9 px / 0.12 em · the one control
///   │ 7:50 hrs                 │  figure 27 px, unit 10 px on the baseline
///   │ ▁▂▃▅▃▂▁                  │  the chart
///   │ DEEP 90  REM 90          │  foot, 9 px / 0.04 em, 8 px above
///   └──────────────────────────┘
///     14 px padding · squircle at r16 · 1 px border on the strong hairline
/// ```
///
/// ## What changed from the previous revision of this file
///
/// It was already a port, from the design bundle rather than from the Flutter
/// app, and three things had drifted. All three are now legacy's: **14 px**
/// padding (was 13), a **continuous-corner squircle** (was a rounded rectangle),
/// and **[HTap]'s press-scale** instead of an `InkWell` ripple — legacy's cards
/// scale to 97.5% under the finger and never ripple.
///
/// ## THE DOT IS GONE — owner-directed, 2026-08-06
///
/// *"can we remove that colored dots from cards"*. Legacy draws a 6 px mark in
/// the metric's own hue at the top right of every module, and this port drew it
/// too; **this is an owner-directed departure from the verbatim-legacy rule**
/// (`feedback_port_legacy_design_verbatim`), recorded here at the site.
///
/// Nothing became ambiguous by losing it, and that was checked rather than
/// assumed. Every module is still named by its eyebrow, and every module that
/// had a chart still tints that chart with the same hue. The pairs that could in
/// principle have collided were **already** colliding under the dot: legacy
/// makes `cHrv` and `cReady` the same green, so HRV, VO₂max, biological age,
/// MVPA and sleep health all wore one dot between them, and `cHeart` is the same
/// value as `alert`. The dot never separated those and does not now.
///
/// [tag] stays, and is no longer painted here. It is the module's **declared**
/// hue — the identity a card and the grid cell that opens it must agree on — and
/// it is what `test/features/moved_card_tags_test.dart` reads. Deleting it would
/// delete that guard's subject, not just a decoration.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/instrument_type.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/data/honesty/disclosure.dart';
import 'package:healthee/shared/instrument/h_tap.dart';
import 'package:healthee/shared/metric_info/metric_info_sheet.dart';
import 'package:healthee/shared/states/caveat_disclosure.dart';
import 'package:healthee/shared/states/caveat_scope.dart';
import 'package:healthee/shared/states/state_scaffold.dart';

/// One cell of the Today grid.
class InstrumentModule extends StatelessWidget {
  /// [label] names the metric; [tag] tints its dot and its chart.
  const InstrumentModule({
    required this.tag,
    required this.children,
    this.label,
    this.infoKey,
    this.caveats = const <Disclosure>[],
    this.trailing,
    this.onOpen,
    this.minHeight = 118,
    this.padding = _padding,
    super.key,
  }) : assert(
         infoKey == null || label != null,
         'An infoKey with no label is a DEAD CONTROL: the header row this ⓘ '
         'lives in is only drawn when a label exists, so the explainer is '
         'unreachable and nothing on screen shows that it is. Give the card a '
         'label, or drop the infoKey — the Sleep hero did the latter.',
       ),
       assert(
         caveats.length == 0 || label != null,
         'Caveats with no label would name no metric: the sheet they open is '
         'titled by the label, so a label-less module opens a sheet about an '
         'unnamed number. Give the module a label — silently dropping the '
         'disclosure is the one failure the honesty layer exists to prevent.',
       );

  /// The metric's name. Rendered uppercase by [ModuleLabel].
  ///
  /// **Null draws no header row at all**, which is legacy's `HModule` (`label`
  /// is nullable there and the whole `Row` plus its 9 px gap sit behind an
  /// `if`). The AI-analysis card is the live case: it draws its own title inside
  /// the body and an empty eyebrow above it would be 9 px of nothing.
  final String? label;

  /// Opens the plain-language explainer for this metric, when it has one.
  ///
  /// Legacy's `HModule.infoKey` — an ⓘ sits before [trailing] or the dot, and an
  /// unknown key draws nothing (`shared/metric_info/`).
  final String? infoKey;

  /// What tilts this module's value, disclosed **inside this card**.
  ///
  /// **Not legacy's** — legacy has no surface for a caveat anywhere. Rendered as
  /// a [CaveatNote] at the bottom of the body, within the card's own bounds:
  /// `caveat_scope.dart` records why a signpost drawn *outside* the card was a
  /// misattribution rather than a style problem. A module also picks up whatever
  /// an enclosing [CaveatScope] hands it, which is how a `ReadingView` that wraps
  /// a whole card gets its disclosures into it without every card growing a
  /// parameter.
  ///
  /// There is exactly one carrier, [CaveatNote]. The fixed-height grid cell that
  /// needed a second one — a foot line, because a 92 px body has no room for a
  /// note — went with the v02 redesign, and `CaveatFoot` went with it.
  final List<Disclosure> caveats;

  /// The metric's declared hue. **No longer painted** — see the library
  /// docstring on the dot the owner removed.
  final Color? tag;

  /// The module's body, top to bottom.
  final List<Widget> children;

  /// Drawn instead of the dot, for a module whose header carries a range.
  final Widget? trailing;

  /// What the module opens, or null when it is not a door.
  ///
  /// Legacy's grid cells all carry one (`onTap: () => onOpen('sleep')`) and its
  /// full-width modules do not — a 24-hour heart-rate strip is the detail, not
  /// an index of it.
  final VoidCallback? onOpen;

  /// The floor every grid cell shares, so a row's two cards match.
  final double minHeight;

  /// Inside the card. Legacy's `HModule` takes this too and three of its call
  /// sites pass their own — the readiness block at 18, the actions header at
  /// 15/13 (`today_screen.dart:572 · 922 · 973`).
  final EdgeInsets padding;

  /// Legacy's `EdgeInsets.all(14)`.
  static const EdgeInsets _padding = EdgeInsets.all(14);

  /// Legacy's `SizedBox(height: 9)` between the eyebrow row and the body.
  static const double _headerGap = 9;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Whatever a `ReadingView` above handed down, plus whatever this module was
    // given directly. One list, so the count in the signpost is the truth.
    final scope = CaveatScope.of(context);
    final disclosed = <Disclosure>[...caveats, ...?scope?.caveats];
    final named = label ?? scope?.label;
    // Shadowed for the subtree: a module nested inside this one must not render
    // the same disclosure a second time.
    return CaveatScope(
      caveats: const <Disclosure>[],
      child: _card(context, colors, disclosed, named),
    );
  }

  Widget _card(
    BuildContext context,
    HealtheeColors colors,
    List<Disclosure> disclosed,
    String? named,
  ) {
    return HTap(
      onTap: onOpen,
      semanticLabel: onOpen == null ? null : '$label — open',
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: colors.surface,
          shape: StateCard.shapeOf(),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: Padding(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (label case final String name when name.isNotEmpty) ...[
                  Row(
                    children: [
                      Expanded(child: ModuleLabel(name)),
                      // Legacy's `[HInfoDot(infoKey), SizedBox(width: 8)]`.
                      if (infoKey case final String key) ...[
                        MetricInfoDot(key),
                        const SizedBox(width: Insets.sm),
                      ],
                      if (trailing case final Widget end) end,
                    ],
                  ),
                  const SizedBox(height: _headerGap),
                ],
                ...children,
                // Inside the card, under the number it is about. See
                // `caveat_scope.dart` for why "inside" is the whole point.
                if (disclosed.isNotEmpty)
                  CaveatNote(caveats: disclosed, label: named),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Legacy's `HEyebrow` — uppercase, tracked, quiet.
///
/// The ladder's label step (`HType.label`), in [HealtheeColors.ink2]. Legacy's
/// 9 px at 0.12 em and weight 400 snapped to that step with the type ladder.
///
/// The caps are **visual only**: the [Semantics] label carries the text as
/// written, because several screen readers spell an all-caps run out letter by
/// letter and "S-L-E-E-P" is not what this says.
class ModuleLabel extends StatelessWidget {
  /// Renders [text] as a module eyebrow.
  const ModuleLabel(this.text, {this.color, super.key});

  /// The label, in any case — this widget uppercases it.
  final String text;

  /// Overrides [HealtheeColors.ink2].
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      label: text,
      child: ExcludeSemantics(
        child: Text(
          text.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: HType.label(color ?? colors.ink2),
        ),
      ),
    );
  }
}

/// Legacy's `HModuleValue` — a figure with a small unit on its baseline.
class ModuleValue extends StatelessWidget {
  /// [value] is already formatted; this widget does not round.
  const ModuleValue({
    required this.value,
    this.unit,
    this.color,
    this.size = 27,
    super.key,
  });

  /// The formatted number.
  final String value;

  /// Its unit, or null when there is none.
  final String? unit;

  /// Overrides [HealtheeColors.ink] on the figure.
  final Color? color;

  /// The figure's requested size, snapped to the ladder by `HType.number`.
  /// 27 is legacy's grid module.
  final double size;

  /// Legacy's unit: a small weight-400 figure in ink3, 3 px after the figure.
  /// Its 10 px request snaps to the ladder's caption.
  static const double _unitSize = 10;
  static const double _unitGap = 3;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: HType.number(color ?? colors.ink, size: size),
          ),
        ),
        if (unit case final String symbol) ...[
          const SizedBox(width: _unitGap),
          Text(
            symbol,
            style: HType.number(
              colors.ink2,
              size: _unitSize,
              weight: FontWeight.w400,
            ),
          ),
        ],
      ],
    );
  }
}

/// Legacy's `HFoot` — the one context line under a module's chart.
///
/// The ladder's label step, in ink3, with 8 px of air above it. Pushed to the bottom of
/// the module by a [Spacer] in the caller, exactly as legacy's `marginTop: auto`
/// did, so every card in a row aligns its foot.
class ModuleFoot extends StatelessWidget {
  /// Renders [text] as a module's foot.
  const ModuleFoot(this.text, {super.key});

  /// The context line — a median, a goal, a stage split.
  final String text;

  /// Legacy's `EdgeInsets.only(top: 8)`.
  static const EdgeInsets _padding = EdgeInsets.only(top: 8);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: _padding,
      child: Semantics(
        label: text,
        child: ExcludeSemantics(
          child: Text(
            text.toUpperCase(),
            // Two lines, where legacy had one. Its feet were `GOAL 10,000 · 84%`;
            // several of ours have to name an instrument as well as a number
            // (`SINCE-MIDNIGHT COUNTER · 09:12`), and an attribution clipped to
            // an ellipsis is an attribution that did not happen. This is honesty
            // wording, which is the one category of change the port allows.
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: HType.label(colors.ink2),
          ),
        ),
      ),
    );
  }
}
