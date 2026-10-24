/// `A useful question comes next` — the way from a pattern to a coach question.
///
/// Kept from the earlier Insights because it is the screen's only door to the
/// coach, and a route is not removed by a restyle. It follows the link list and
/// uses the same panel the rest of the app does.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/core/theme/type_scale.dart';
import 'package:healthee/shared/v02/panel.dart';
import 'package:healthee/shared/v02/panel_head.dart';
import 'package:healthee/shared/v02/panel_parts.dart';
import 'package:solar_icons/solar_icons.dart';

/// `A useful question comes next` — the way from a pattern to a question.
class CoachQuestionPanel extends StatelessWidget {
  /// [onOpenCoach] of null draws the panel without either action.
  const CoachQuestionPanel({this.onOpenCoach, super.key});

  /// The prototype's title.
  static const String title = 'A useful question comes next';

  /// The prototype's own question.
  static const String question = 'What would you like to understand?';

  /// The prototype's own line under it.
  static const String note =
      'Follow the evidence and your own data, with the uncertainty kept in '
      'view.';

  /// Opens the coach sheet.
  final VoidCallback? onOpenCoach;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Panel(
      tone: Tone.fitness,
      head: PanelHead(
        title: title,
        icon: SolarIconsOutline.chatRoundDots,
        actionLabel: onOpenCoach == null ? null : 'Details',
        onAction: onOpenCoach,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            question,
            style: TypeScale.entryTitle.copyWith(color: colors.ink),
          ),
          const PanelNote(note),
          if (onOpenCoach case final VoidCallback open)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: open,
                style: TextButton.styleFrom(
                  foregroundColor: colors.ink,
                  textStyle: TypeScale.textButton,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, PanelHead.actionMinHeight),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Ask your coach'),
              ),
            ),
        ],
      ),
    );
  }
}
