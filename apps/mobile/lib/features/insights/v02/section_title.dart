/// A section's heading on Insights: Title2 on the left and, on the right, either
/// a quiet caption or a text link in the primary ink.
///
/// Colourless on purpose: the heading names a section, and the colour of a
/// section's contents is theirs. The link is the primary ink, never an accent:
/// buttons here are text-primary, and colour is spent on data.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_ladder.dart';

/// The heading.
class InsightSectionTitle extends StatelessWidget {
  /// [caption] and [actionLabel] are alternatives; the action wins.
  const InsightSectionTitle({
    required this.title,
    this.caption,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  /// The space between a heading and what it names.
  static const double bottomGap = Insets.md;

  /// The section's name.
  final String title;

  /// A quiet right-hand line, `your data only`.
  final String? caption;

  /// The text link's words. Null, or no [onAction], draws no link.
  final String? actionLabel;

  /// What the link does.
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final link = actionLabel;
    return Padding(
      padding: const EdgeInsets.only(bottom: bottomGap),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TypeLadder.title2.copyWith(color: colors.ink),
            ),
          ),
          if (link != null && onAction != null)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onAction,
              child: Padding(
                padding: const EdgeInsets.only(left: Insets.sm),
                child: Text(
                  link,
                  style: TypeLadder.calloutStrong.copyWith(color: colors.ink),
                ),
              ),
            )
          else if (caption != null)
            Padding(
              padding: const EdgeInsets.only(left: Insets.sm),
              child: Text(
                caption!,
                style: TypeLadder.caption.copyWith(color: colors.ink2),
              ),
            ),
        ],
      ),
    );
  }
}
