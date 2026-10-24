/// `.data-footer` — the line every v02 screen closes on.
///
/// ```css
/// .data-footer        { text-align:center; color:var(--subtle);
///                       font-size:10px; margin-top:32px; line-height:2; }
/// .data-footer > .icon{ width:12px; height:12px; margin-right:5px; }
/// ```
///
/// Moved out of `features/today/v02/today_header.dart` when Activity and
/// Insights grew the same footer (Standards §1, second use; §3, no cross-feature
/// imports). That file re-exports it, so Today's call sites and its order test
/// are unchanged and there is still one definition.
///
/// The prototype's second line — *"Design sample · no live measurements"* — is
/// deliberately absent: it is the preview telling a reviewer that its numbers
/// are fixtures, and printing it over real measurements would be the opposite
/// claim.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_scale.dart';
import 'package:solar_icons/solar_icons.dart';

/// The closing line, centred under the last card.
class DataFooter extends StatelessWidget {
  /// Builds the footer.
  const DataFooter({super.key});

  /// `.data-footer { margin-top: 32px }`.
  static const double topGap = 32;

  /// `.data-footer > .icon { width: 12px }`.
  static const double iconSize = 12;

  /// `.data-footer > .icon { margin-right: 5px }`.
  static const double iconGap = 5;

  /// The prototype's own closing line.
  static const String line = 'Your data. A little better understood.';

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: topGap),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            SolarIconsOutline.shieldCheck,
            size: iconSize,
            color: colors.ink2,
          ),
          const SizedBox(width: iconGap),
          Flexible(
            child: Text(
              line,
              textAlign: TextAlign.center,
              style: TypeScale.footer.copyWith(color: colors.ink2),
            ),
          ),
        ],
      ),
    );
  }
}
