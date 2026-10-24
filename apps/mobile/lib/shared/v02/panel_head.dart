/// `.panel-head` — a panel's title row: icon, title, and one text action.
///
/// ```css
/// .panel-head  { display: flex; justify-content: space-between;
///                align-items: center; gap: 8px; margin-bottom: 12px; }
/// .panel-title { display: flex; align-items: center; gap: 8px;
///                font-size: 13px; font-weight: 700; }
/// .panel-title > .icon    { width: 17px; height: 17px; color: var(--family); }
/// .panel .text-button     { color: var(--family); min-height: 28px;
///                           font-size: 11px; }
/// ```
///
/// **The brief overrides the colours above:** the title icon is 16 px and ink2
/// (an inline icon is not a reading), and the action and fold control are the
/// accent (they are the interactive things). Family hues are for data marks.
///
/// The action is built here rather than accepted as a `Widget`, so its colour,
/// size and minimum height cannot be bypassed — the icon and the action are the
/// two places a panel's tone becomes visible, and a caller that passed its own
/// button would be the one thing in the card not following the cascade.
///
/// **28 px is under the 48 px tap target Material asks for**, and it is the
/// prototype's number. It is a secondary affordance inside a card that is itself
/// usually tappable; the size is the spec's and is flagged here rather than
/// quietly widened, because widening it would move every panel's head.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_scale.dart';
import 'package:healthee/data/honesty/disclosure.dart';
import 'package:healthee/shared/metric_info/metric_detail.dart';
import 'package:healthee/shared/metric_info/metric_info_sheet.dart';
import 'package:healthee/shared/v02/panel.dart';
import 'package:healthee/shared/v02/panel_density.dart';
import 'package:solar_icons/solar_icons.dart';

/// The head of a [Panel]: title (+ optional icon) left, optional action right.
class PanelHead extends StatelessWidget {
  /// Builds a head. [onAction] without [actionLabel] draws nothing.
  const PanelHead({
    required this.title,
    this.icon,
    this.infoKey,
    this.detail = MetricDetail.none,
    this.actionLabel,
    this.onAction,
    this.collapsed,
    this.onToggle,
    super.key,
  });

  /// An inline icon beside text is 16 px.
  static const double iconSize = 16;

  /// The `gap: 8px` shared by `.panel-head` and `.panel-title`.
  static const double gap = 8;

  /// `.panel .text-button { min-height: 28px }`.
  static const double actionMinHeight = 28;

  /// The panel's name.
  final String title;

  /// Drawn 16 px in ink2, before the title.
  final IconData? icon;

  /// Opens the plain-language explainer for this metric, when it has one.
  ///
  /// The prototype's `H.evidence(...)` — *"How we know"* with an info glyph —
  /// on every panel whose number is a model output. An unknown key draws
  /// nothing (`metric_info_sheet.dart`), so a panel naming a metric this build
  /// has no explainer for is silent rather than dead.
  final String? infoKey;

  /// This panel's OWN provenance — its references, its payload citations, and
  /// the prose that used to sit under its chart.
  ///
  /// The head owns the ⓘ, so the head is where a card hands over what the ⓘ has
  /// to carry. A non-empty detail draws the dot even for a panel with no
  /// explainer entry, because the alternative is a card whose sources became
  /// unreachable — see `metric_info_sheet.dart`.
  final MetricDetail detail;

  /// The text button's label. Null draws no action.
  final String? actionLabel;

  /// What the action does.
  final VoidCallback? onAction;

  /// Whether the panel this heads is folded shut. Null draws no fold control.
  ///
  /// **A chevron, never the words.** `reasoning_note.dart` and
  /// `insight_card.dart` both fold with a bare `altArrowUp`/`altArrowDown` and
  /// no animation, and they were here first — a third panel inventing a
  /// `Show`/`Hide` text button is a second idiom for one gesture.
  final bool? collapsed;

  /// Folds and unfolds it.
  final VoidCallback? onToggle;

  /// The fold chevron, sized with `reasoning_note.dart`'s.
  static const double foldChevron = 16;

  /// `.twin-panels .panel-head .text-button .icon { width: 13px }`.
  static const double compactActionIcon = 13;

  /// `.twin-panels .panel-title { gap: 5px }`.
  static const double compactGap = 5;

  /// Between the ⓘ and whatever follows it.
  ///
  /// Wider than [compactGap], which sets the icon-to-title distance. Five px
  /// between two 16px glyphs reads as one crowded control rather than two.
  static const double compactActionGap = 12;

  /// This head's own detail, plus whatever the card around it published.
  ///
  /// The caveats come from `Panel`, not from the call site, so a card cannot
  /// print the sentence and file it as well — and cannot drop it, because a
  /// detail holding only a disclosure is still non-empty and still draws a dot.
  /// A head given its own `detail.disclosures` keeps them: the two are merged
  /// rather than one replacing the other.
  MetricDetail _detail(BuildContext context) {
    final card = PanelOpens.of(context);
    if (card == null || card.caveats.isEmpty) {
      return detail;
    }
    return detail.withDisclosures(<Disclosure>[
      ...detail.disclosures,
      ...card.caveats,
    ], disclosuresLabel: detail.disclosuresLabel ?? card.caveatsLabel);
  }

  /// The disclosure chevron's size, and the air before it.
  ///
  /// Both smaller than the ⓘ's, and deliberately: this is a hint, not a control
  /// beside a control. At [compactActionGap] and 16px it ate enough of the row
  /// to ellipsize `Overnight HRV` on a half-width card — a mark that costs the
  /// card its own name is not worth the affordance it buys.
  static const double chevronSize = 14;

  /// The gap before it.
  static const double chevronGap = 6;

  /// The mark that says the CARD leads somewhere.
  ///
  /// **Not a button, and that is the difference.** The `Details →` it replaces
  /// was an accent-coloured control sitting beside the ⓘ, so the head carried
  /// two things to press and they crowded each other. This has no gesture: the
  /// card is the target (`Panel.onOpen`), and this is the standard disclosure
  /// mark saying so — muted, because it is a property of the card rather than
  /// an action offered by it.
  ///
  /// It cannot be forgotten and it cannot lie: `PanelOpens` carries the same
  /// field that makes the card tappable, so a tappable card always draws it and
  /// a card that goes nowhere never can.
  Widget _chevron(HealtheeColors colors) => Padding(
    padding: const EdgeInsets.only(left: chevronGap),
    child: Icon(
      SolarIconsOutline.altArrowRight,
      size: chevronSize,
      color: colors.ink2,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final compact = context.compactPanel;
    final label = actionLabel;
    if (compact) {
      return _compact(context, colors.ink, label);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: iconSize, color: colors.ink2),
                const SizedBox(width: gap),
              ],
              Flexible(
                child: Text(
                  title,
                  style: TypeScale.panelTitle.copyWith(color: colors.ink),
                  // Two lines before an ellipsis: a metric's own name wraps at
                  // 320 rather than being cut (`typography_test.dart`).
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        if (_detail(context) case final MetricDetail detail
            when MetricInfoDot.draws(infoKey, detail))
          MetricInfoDot(infoKey, detail: detail, fallbackTitle: title),
        if (PanelOpens.opensOf(context)) _chevron(colors),
        if (collapsed case final bool folded) ...<Widget>[
          const SizedBox(width: gap),
          IconButton(
            onPressed: onToggle,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: actionMinHeight,
              minHeight: actionMinHeight,
            ),
            tooltip: folded ? 'Show' : 'Hide',
            icon: Icon(
              folded
                  ? SolarIconsOutline.altArrowDown
                  : SolarIconsOutline.altArrowUp,
              size: foldChevron,
              color: colors.accent,
            ),
          ),
        ],
        if (label != null) ...<Widget>[
          const SizedBox(width: gap),
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: colors.accent,
              textStyle: TypeScale.textButton,
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, actionMinHeight),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(label),
          ),
        ],
      ],
    );
  }

  /// The half-width head: a smaller title, and an action reduced to its arrow.
  ///
  /// `font-size: 0` on the text button is the prototype deleting the words and
  /// keeping the glyph. A `Text('')` would do the same thing and would still be
  /// read aloud as an empty button, so the label travels as the icon's semantic
  /// label instead — the control keeps its name for anyone who cannot see the
  /// arrow.
  Widget _compact(BuildContext context, Color ink, String? label) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, size: iconSize, color: colors.ink2),
          const SizedBox(width: compactGap),
        ],
        Expanded(
          child: Text(
            title,
            style: TypeScale.panelTitleCompact.copyWith(color: ink),
            // Half a row is narrow: the name wraps rather than being cut.
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (_detail(context) case final MetricDetail detail
            when MetricInfoDot.draws(infoKey, detail))
          MetricInfoDot(infoKey, detail: detail, fallbackTitle: title),
        if (PanelOpens.opensOf(context)) _chevron(colors),
        if (collapsed case final bool folded) ...<Widget>[
          const SizedBox(width: gap),
          IconButton(
            onPressed: onToggle,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: actionMinHeight,
              minHeight: actionMinHeight,
            ),
            tooltip: folded ? 'Show' : 'Hide',
            icon: Icon(
              folded
                  ? SolarIconsOutline.altArrowDown
                  : SolarIconsOutline.altArrowUp,
              size: foldChevron,
              color: colors.accent,
            ),
          ),
        ],
        if (label != null) ...<Widget>[
          const SizedBox(width: compactActionGap),
          Semantics(
            button: true,
            label: label,
            child: GestureDetector(
              onTap: onAction,
              // The child is a bare glyph, so `deferToChild` makes the tap
              // target the 16 px of ink and nothing around it.
              behavior: HitTestBehavior.opaque,
              child: Icon(
                SolarIconsOutline.arrowRight,
                size: compactActionIcon,
                color: colors.accent,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
