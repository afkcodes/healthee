/// The five rules every program runs on. Static product copy, not data: they
/// describe how the coach behaves, the same for every program.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/shared/v02/reading_state.dart';
import 'package:healthee/shared/v02/surface_panels.dart';

/// Rule heads and bodies, in order. Rule 3 carries the red-zone word inline.
const List<(String, String)> kProgramRules = <(String, String)>[
  (
    'Miss a week, repeat it.',
    'The plan never resets to zero and never quietly lowers the bar.',
  ),
  (
    'Done by Thursday?',
    'I\'ll offer the next rung early. Say no and nothing changes.',
  ),
  ('Recovery in the ', 'red (under 34)? Walk easy instead. Still counts.'),
  (
    '10-minute floor.',
    'Travel, bad night, bad news: 10 minutes and the streak lives.',
  ),
  (
    'Press start on outdoor walks.',
    'A recorded route sharpens your VO₂max estimate, which is still a guess.',
  ),
];

/// The index of the rule whose red-zone word takes the alert colour.
const int kRedZoneRule = 2;

/// The card.
class ProgramRulesCard extends StatelessWidget {
  /// Draws the rules.
  const ProgramRulesCard({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final alert = ReadingState.worse.colourIn(colors);
    return SurfaceCard(
      child: Column(
        children: <Widget>[
          for (var i = 0; i < kProgramRules.length; i++) ...<Widget>[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Insets.md),
                child: Divider(
                  height: hairline,
                  thickness: hairline,
                  color: colors.line,
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 24,
                  child: Text(
                    '${i + 1}',
                    style: TypeLadder.body.copyWith(color: colors.ink3),
                  ),
                ),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: <InlineSpan>[
                        TextSpan(
                          text: kProgramRules[i].$1,
                          style: TypeLadder.bodyStrong.copyWith(
                            color: colors.ink,
                          ),
                        ),
                        if (i == kRedZoneRule)
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(right: Insets.xs),
                              decoration: BoxDecoration(
                                color: alert,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        TextSpan(
                          text: i == kRedZoneRule
                              ? 'red'
                              : ' ${kProgramRules[i].$2}',
                          style: i == kRedZoneRule
                              ? TypeLadder.bodyStrong.copyWith(
                                  color: colors.ink,
                                )
                              : TypeLadder.body.copyWith(color: colors.ink2),
                        ),
                        if (i == kRedZoneRule)
                          TextSpan(
                            text: kProgramRules[i].$2.substring('red'.length),
                            style: TypeLadder.body.copyWith(color: colors.ink2),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
