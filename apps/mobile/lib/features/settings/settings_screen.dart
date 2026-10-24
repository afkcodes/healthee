/// Settings — v02's index of rows, each opening a screen of its own.
///
/// ## What changed, and what did not
///
/// **Not one row's behaviour.** Every setting this screen used to hold inline —
/// the appearance segmented button, the two expanding preference cards, the
/// server card, the strap card, the diagnostics door and the licence door — is
/// still exactly one tap from here and still writes exactly the same provider.
/// What changed is that they are now *screens* rather than cards stacked on one
/// scroll, which is what `design/mobile-preview/screens-settings.js` specifies.
///
/// The two rules the previous screen was built to keep are unchanged and are
/// now enforced one level down:
///
///   * **One source of truth per setting.** The appearance screen reads and
///     writes `themeControllerProvider`, the same object the header toggle
///     writes. Moving the control onto its own screen did not give it a copy.
///   * **No row that controls nothing.** Every row here opens a registered
///     route; `test/features/reachability_test.dart` taps all of them.
///
/// ## Every row reports what it is SET TO
///
/// `Appearance · Light, dark or follow your device` names the choices and not
/// the choice; `Reminders · A gentle nudge, on your terms` is a sentence about
/// the feature. Nine rows of that is a menu you have to open to read. So the
/// five rows that HAVE a current value print it — `System · Indigo`, `Off`,
/// `On · Wi-Fi only` — and the four that are doors keep their sentence.
///
/// **A value still loading is null, and null falls back to the sentence.**
/// Printing a default as though it were the setting is the stale-as-current lie
/// at its smallest scale, and this screen is exactly where an owner comes to
/// check.
///
/// ## One row the prototype does not have
///
/// **Instruments → `/diagnostics`.** The prototype has no diagnostics screen to
/// draw a row for, and this product does: `diagnostics_screen.dart` argues that
/// the baselines and the strap's raw streams belong somewhere the owner goes
/// when something looks wrong, and that argument *"is only sound while there is
/// a door"*. Settings is the only door. It is added inside the prototype's own
/// `Your connected device` section, because that is what it is about — the
/// section ORDER is the prototype's, and one row is added to a section rather
/// than a section invented for it.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:healthee/core/router.dart';
import 'package:healthee/core/theme/appearance_variant.dart';
import 'package:healthee/core/theme/theme_controller.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/core/theme/type_scale_forms.dart';
import 'package:healthee/data/background/background_scheduler.dart';
import 'package:healthee/data/device/device_repository.dart';
import 'package:healthee/data/notifications/notification_providers.dart';
import 'package:healthee/data/pairing/pairing_repository.dart';
import 'package:healthee/data/profile/health_profile.dart';
import 'package:healthee/data/profile/profile_repository.dart';
import 'package:healthee/features/settings/setting_values.dart';
import 'package:healthee/features/settings/widgets/support_notice.dart';
import 'package:healthee/features/today/v02/today_header.dart';
import 'package:healthee/shared/instrument/h_tap.dart';
import 'package:healthee/shared/states/current_account_value.dart';
import 'package:healthee/shared/v02/list_row.dart';
import 'package:healthee/shared/v02/section_head.dart';
import 'package:healthee/shared/v02/settings_page.dart';
import 'package:healthee/shared/v02/surfaces.dart';
import 'package:solar_icons/solar_icons.dart';

/// The index: the owner, their device, their experience, their account.
class SettingsScreen extends ConsumerWidget {
  /// [now] is threaded through; this screen quotes the strap's own sync age.
  const SettingsScreen({this.now, super.key});

  /// The screen's name — what it is, not a slogan about it.
  static const String title = 'Settings';

  /// Kept for `SettingsPage`'s signature; `DetailHeader` no longer draws it.
  static const String eyebrow = 'Profile & settings';

  /// The instant a freshness label would be measured against.
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `.value?.` and never `.requireValue`: the profile is a server read, and a
    // navigation index must not wait on a network before it will draw its rows.
    final profile = currentAccountValue(ref.watch(healthProfileProvider)).value;
    final paired = ref.watch(pairingSummaryProvider).value?.strap != null;
    final day = ref.watch(deviceDayProvider).value;
    final mode = ref.watch(themeControllerProvider);
    final variant = ref.watch(appearanceControllerProvider);
    final reminders = ref.watch(reminderPreferencesProvider).value;
    final background = ref.watch(backgroundPreferencesProvider).value;
    return SettingsPage(
      title: title,
      eyebrow: eyebrow,
      children: <Widget>[
        _ProfileCard(
          profile: profile,
          onOpen: () => unawaited(context.push(Routes.profile)),
        ),
        const SectionGap(),
        // SECOND, and above every section — not first. The owner's own card is
        // what this screen is for, and an ask sitting above it read as a toll on
        // the way in. Here it is still the first thing after their own details
        // and still above the fold, which is all the visibility it needed; it
        // lived one level down on the profile screen, two taps from any tab, and
        // an ask nobody scrolls to is an ask that does not happen.
        // `support_notice.dart` argues why it stays off Today, Sleep, Activity
        // and Actions entirely.
        const SupportCard(),
        const SectionGap(),
        const SectionHead(title: 'Your connected device'),
        FlushCard(
          children: <Widget>[
            ListRow(
              icon: SolarIconsOutline.watchRound,
              title: 'Amazfit Helio Strap',
              // Short, because the value opposite carries the live half. The
              // sentence that was here truncated once the charge sat beside it.
              subtitle: paired ? 'Charge, signal and last read' : 'Not paired',
              value: strapValue(paired: paired, day: day),
              onTap: () => unawaited(context.push(Routes.device)),
            ),
            ListRow(
              icon: SolarIconsOutline.refresh,
              title: 'Data & sync',
              subtitle: 'Strap to phone to insights',
              value: syncValue(day, now ?? DateTime.now()),
              onTap: () => unawaited(context.push(Routes.dataFreshness)),
            ),
            ListRow(
              icon: SolarIconsOutline.chartSquare,
              title: 'Instruments',
              // Names what is behind it in the owner's words. "Diagnostics"
              // alone would be a control whose only documentation is the screen
              // you have to open to read it.
              subtitle: 'Every baseline and stream this phone read',
              onTap: () => unawaited(context.push(Routes.diagnostics)),
            ),
          ],
        ),
        const SectionGap(),
        const SectionHead(title: 'Your experience'),
        FlushCard(
          children: <Widget>[
            ListRow(
              icon: SolarIconsOutline.sun,
              title: 'Appearance',
              subtitle: 'Light, dark or follow your device',
              value: appearanceValue(mode, variant),
              onTap: () => unawaited(context.push(Routes.appearance)),
            ),
            ListRow(
              icon: SolarIconsOutline.bell,
              title: 'Reminders',
              subtitle: 'A gentle nudge, on your terms',
              value: remindersValue(reminders),
              onTap: () => unawaited(context.push(Routes.reminders)),
            ),
            ListRow(
              icon: SolarIconsOutline.cloud,
              title: 'Background sync',
              subtitle: 'Collection, upload and network preferences',
              value: backgroundValue(background),
              onTap: () => unawaited(context.push(Routes.background)),
            ),
            ListRow(
              icon: SolarIconsOutline.notes,
              title: 'Health journal',
              subtitle: 'The moments beyond your measurements',
              onTap: () => unawaited(context.push(Routes.journal)),
            ),
          ],
        ),
        const SectionGap(),
        const SectionHead(title: 'Your account'),
        FlushCard(
          children: <Widget>[
            ListRow(
              icon: SolarIconsOutline.shieldCheck,
              title: 'Account & server',
              subtitle: 'Your data, on your server',
              onTap: () => unawaited(context.push(Routes.serverSignIn)),
            ),
            ListRow(
              icon: SolarIconsOutline.infoCircle,
              title: 'About Healthee',
              subtitle: 'An honest health companion',
              onTap: () => unawaited(context.push(Routes.about)),
            ),
          ],
        ),
        const DataFooter(),
      ],
    );
  }
}

/// The owner's own card, above the sections.
///
/// ## It says who you are, not merely that a profile exists
///
/// The row it replaces drew a grey circle, a name and the words *"Your profile
/// & measurements"* — a label restating the destination, on the one card that
/// has real facts a tap away. So the card now prints them: age, height, the
/// latest weigh-in. They are exactly the fields the biological-age and VO₂max
/// estimates are computed from, which is what makes this card worth a glance
/// rather than only worth a tap.
///
/// **Each fact is drawn only when it is known.** A missing height is left out
/// of the line rather than shown as a dash or a default — the same rule the
/// rest of the app follows, at the smallest scale. With none of them known the
/// line falls back to naming the destination, because then that IS all there is
/// to say.
///
/// The monogram wears the owner's **accent** on `accentSoft`. Every other tile
/// on this screen resolves the accent itself; a grey circle at the top was the
/// one piece of chrome ignoring the colour chosen two rows below it.
///
/// ```css
/// .card { padding:20px; border-radius:22px; }
/// .row  { display:flex; align-items:center; gap:12px; }
/// ```
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.profile, required this.onOpen});

  static const double avatarSize = 46;
  static const double gap = 14;
  static const double chevronSize = 16;

  final HealthProfile? profile;
  final VoidCallback onOpen;

  /// Age in whole years from `dobDate`, or null when it is unset or unreadable.
  static int? _age(String? dob, DateTime now) {
    if (dob == null) {
      return null;
    }
    final born = DateTime.tryParse(dob);
    if (born == null) {
      return null;
    }
    final years = now.year - born.year;
    final hadBirthday =
        now.month > born.month ||
        (now.month == born.month && now.day >= born.day);
    return hadBirthday ? years : years - 1;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final profile = this.profile;
    final name = profile?.name?.trim();
    final named = name != null && name.isNotEmpty;
    final heading = named ? name : 'Your profile';

    final facts = <String>[
      if (_age(profile?.dobDate, DateTime.now()) case final int years) '$years',
      if (profile?.heightCm case final double cm) '${cm.round()} cm',
      if (profile?.weightKg case final double kg) '${kg.toStringAsFixed(1)} kg',
    ];
    final line = facts.isEmpty
        ? 'Your measurements and self-reports'
        : facts.join('  ·  ');

    return Semantics(
      button: true,
      label: '$heading · $line',
      child: HTap(
        onTap: onOpen,
        child: PlainCard(
          child: Row(
            children: <Widget>[
              Container(
                width: avatarSize,
                height: avatarSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.accentSoft,
                  shape: BoxShape.circle,
                ),
                // The initial when there is a name to take one from. A person's
                // own letter beats a generic silhouette, and the silhouette is
                // still there for the phone that has no name yet.
                child: named
                    ? Text(
                        heading.characters.first.toUpperCase(),
                        style: TypeLadder.title2.copyWith(color: colors.accent),
                      )
                    : Icon(SolarIconsOutline.userCircle, color: colors.accent),
              ),
              const SizedBox(width: gap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      heading,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FormType.heading3.copyWith(color: colors.ink),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FormType.small.copyWith(
                        color: facts.isEmpty ? colors.ink2 : colors.ink,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: gap),
              Icon(
                SolarIconsOutline.altArrowRight,
                size: chevronSize,
                color: colors.ink2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
