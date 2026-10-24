/// The banner that dates the whole overnight section when last night was skipped.
///
/// **Ported from** `healthee-legacy/app/lib/ui/today_screen.dart:529` —
/// `_StaleSleepBanner`. A 14 px-padded block in `cSteps` at 12% over a 35%
/// border, an 18 px bed icon, and two lines.
///
/// Legacy's own comment says what it is for: when the most recent sleep ended
/// more than 24 hours ago, *every* overnight reading below it — sleep, HRV,
/// SpO₂, breathing, and all of their charts — is from an older night. One banner
/// dates the lot, so the cards under it read as the owner's last sleep rather
/// than as today.
///
/// It is the closest thing legacy's Today has to this product's withheld card,
/// and it is kept exactly as legacy drew it.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/instrument_hues.dart';
import 'package:healthee/core/theme/instrument_type.dart';
import 'package:healthee/core/theme/shapes.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:solar_icons/solar_icons.dart';

/// "No sleep recorded last night", and which night the readings are from.
class StaleSleepBanner extends StatelessWidget {
  /// [nightLabel] is `sleepNightLabel`'s answer — "3 nights ago".
  const StaleSleepBanner({required this.nightLabel, super.key});

  /// Which night the overnight readings below actually describe.
  final String nightLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tint = context.hues.movement;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: ShapeDecoration(
        color: tint.withValues(alpha: 0.12),
        shape: hSquircle(Radii.badge),
      ),
      child: Row(
        children: [
          Icon(SolarIconsOutline.moonSleep, size: 18, color: tint),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No sleep recorded last night',
                  style: HType.sans(
                    colors.ink,
                    size: 13,
                    weight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Overnight readings below are from your last sleep · '
                  '$nightLabel',
                  style: HType.sans(colors.ink2, size: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
