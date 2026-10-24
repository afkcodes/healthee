/// `.stat` — a label over a number, as the settings screens draw it.
///
/// ```css
/// .stat-label       { font-size:11px; color:var(--muted); }
/// .stat-number      { font-size:27px; font-weight:600; line-height:1.4;
///                     letter-spacing:-1px; }
/// .stat-number>span { font-size:11px; letter-spacing:0; margin-left:4px;
///                     font-weight:400; color:var(--muted); }
/// ```
///
/// **Not `panel_parts.dart`'s `Stat`.** That one is `.panel .stat-label` and
/// `.panel .three .stat-number` — 10 px and 22 px, the sizes `richer.css`
/// overrides them to *inside a panel*. These are the base sizes from
/// `screens.css`, and the settings screens draw them outside any panel. Two
/// transcriptions of two rules, not two opinions about one.
///
/// A null [value] draws **nothing at all** — not a dash, not an empty box. The
/// prototype's own device card prints an em dash for an unavailable battery, but
/// it prints it as a *value* with the label "Battery unavailable" beside it;
/// that is a caller's sentence, not this widget inventing a placeholder.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_scale_forms.dart';

/// One statistic: its label, its figure, and its unit.
class StatBlock extends StatelessWidget {
  /// Builds the block. A null [value] renders nothing.
  const StatBlock({
    required this.label,
    required this.value,
    this.unit,
    super.key,
  });

  /// `.stat-number > span { margin-left: 4px }`.
  static const double unitGap = 4;

  /// The gap between the label and the figure. The CSS has none; the label's
  /// own line box carries it.
  static const double labelGap = 0;

  /// What the number is.
  final String label;

  /// The number. Null renders nothing.
  final String? value;

  /// Its unit. Null draws none.
  final String? unit;

  @override
  Widget build(BuildContext context) {
    final value = this.value;
    if (value == null) {
      return const SizedBox.shrink();
    }
    final colors = context.colors;
    final unit = this.unit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label, style: FormType.statLabel.copyWith(color: colors.ink2)),
        const SizedBox(height: labelGap),
        Text.rich(
          TextSpan(
            text: value,
            style: FormType.statNumber.copyWith(color: colors.ink),
            children: <InlineSpan>[
              if (unit != null && unit.isNotEmpty)
                TextSpan(
                  text: '\u00A0$unit',
                  style: FormType.statUnit.copyWith(color: colors.ink2),
                ),
            ],
          ),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.clip,
        ),
      ],
    );
  }
}
