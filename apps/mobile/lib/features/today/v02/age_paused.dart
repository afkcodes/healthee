/// What stands under the orb when the biological age is paused.
///
/// Today's hero and the biological-age screen draw the same notice, so the two
/// cannot explain one refusal two ways. Every sentence is [agePauseOf]'s: the
/// server's own words wherever it sent any, and one of three app sentences only
/// when it sent no block at all.
///
/// ## It never waits on the profile to speak
///
/// The profile is read only when a line could need it (the block is absent, or
/// an absent term's reason is one a profile edit fixes). While it loads, or if
/// it fails, the notice draws the server's lines anyway: a spinner where the
/// reason belongs is the blank this notice exists to replace. All that waits
/// on the profile is the stale-weight caption and which field the button
/// focuses.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:healthee/core/routes.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/data/honesty/disclosure.dart';
import 'package:healthee/data/models/age_pause.dart';
import 'package:healthee/data/models/bio_age_block.dart';
import 'package:healthee/data/profile/health_profile.dart';
import 'package:healthee/data/profile/profile_repository.dart';
import 'package:healthee/shared/states/current_account_value.dart';
import 'package:healthee/shared/v02/buttons.dart';

/// The notice's heading.
const String kAgePausedTitle = 'Your age estimate is paused';

/// The button that opens the profile with no field focused.
const String kOpenProfileLabel = 'Open profile';

/// Why the estimate is paused, and the one button that would fix it.
class AgePausedNotice extends ConsumerWidget {
  /// [block] is the server's `biological_age` block, kept whole;
  /// [vo2maxWithheld] the VO2max card's own refusal, when it has one.
  const AgePausedNotice({
    required this.block,
    required this.vo2maxWithheld,
    super.key,
  });

  /// Everything the server said about the age today.
  final BioAgeBlock block;

  /// The VO2max card's refusal, which explains a missing block.
  final Disclosure? vo2maxWithheld;

  /// The gap under the heading.
  static const double headGap = 8;

  /// The gap between two lines, and above the caption and the button.
  static const double lineGap = 6;

  /// The gap above the button.
  static const double buttonGap = 16;

  /// Whether any line could need the profile to be written.
  bool get needsProfile =>
      !block.present ||
      block.absentTerms.isEmpty ||
      block.absentTerms.any((term) => kProfileReasons.contains(term.reason));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final HealthProfile? profile = needsProfile
        ? switch (currentAccountValue(ref.watch(healthProfileProvider))) {
            AsyncData<HealthProfile>(:final value) => value,
            _ => null,
          }
        : null;
    final pause = agePauseOf(
      block: block,
      vo2maxWithheld: vo2maxWithheld,
      profile: profile,
    );
    final label = buttonLabel(pause);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          kAgePausedTitle,
          textAlign: TextAlign.center,
          style: TypeLadder.headline.copyWith(color: colors.ink),
        ),
        const SizedBox(height: headGap),
        for (var i = 0; i < pause.lines.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: lineGap),
          Text(
            pause.lines[i].message,
            textAlign: TextAlign.center,
            style: TypeLadder.callout.copyWith(color: colors.ink2),
          ),
        ],
        if (pause.staleWeightDays case final int days) ...<Widget>[
          const SizedBox(height: lineGap),
          Text(
            staleWeightCaption(days),
            textAlign: TextAlign.center,
            style: TypeLadder.caption.copyWith(color: colors.ink2),
          ),
        ],
        if (label != null) ...<Widget>[
          const SizedBox(height: buttonGap),
          HButton(
            label: label,
            onPressed: () =>
                unawaited(context.push(profileLocation(focus: pause.action))),
          ),
        ],
      ],
    );
  }

  /// `Weight last updated 41 days ago`, and `1 day ago` in the singular.
  static String staleWeightCaption(int days) =>
      'Weight last updated $days ${days == 1 ? 'day' : 'days'} ago';

  /// The button's words, or null when only time fixes the pause.
  static String? buttonLabel(AgePause pause) => switch (pause.action) {
    ProfileField.weight => 'Update weight',
    ProfileField.height => 'Update height',
    ProfileField.dob => 'Update date of birth',
    ProfileField.sex => 'Update sex',
    ProfileField.activity => 'Update activity level',
    null => pause.profileAction ? kOpenProfileLabel : null,
  };
}
