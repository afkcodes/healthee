/// A Coach home section heading: Title2 on the left, one thing on the right.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_ladder.dart';

/// The heading row.
class CoachSectionHead extends StatelessWidget {
  /// A heading named [title]; [trailing] is a caption or a control.
  const CoachSectionHead({required this.title, this.trailing, super.key});

  /// A heading from plain text.
  factory CoachSectionHead.text(
    BuildContext context,
    String text, {
    Widget? trailing,
  }) => CoachSectionHead(
    title: Text(
      text,
      style: TypeLadder.title2.copyWith(color: context.colors.ink),
    ),
    trailing: trailing,
  );

  /// The section's name.
  final Widget title;

  /// What sits at the right edge.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Insets.md),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(child: title),
        if (trailing case final Widget end) ...<Widget>[
          const SizedBox(width: Insets.sm),
          end,
        ],
      ],
    ),
  );
}

/// A right-edge caption in secondary ink.
class HeadCaption extends StatelessWidget {
  /// Shows [text].
  const HeadCaption(this.text, {super.key});

  /// The words.
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TypeLadder.callout.copyWith(color: context.colors.ink2),
  );
}
