/// Your profile — `H.screens.profile`, on the real health profile.
///
/// ```js
/// H.screens.profile = () => `${H.header('Your profile.','A little context for your data',true)}
///   <form id="profile-form">
///   <div class="card"><label class="field">What should we call you?…</label>
///     <label class="field">Date of birth…</label>
///     <div class="two"><label class="field">Height · cm…</label>
///                      <label class="field">Sex for estimates…</label></div>
///     <label class="field">Usual activity…<small>…</small></label></div>
///   ${H.section('Your latest weigh-in', …)}
///   <p class="form-note">…</p>
///   <button class="button full" type="submit">Save profile</button></form>`;
/// ```
///
/// Composition only; `widgets/profile_editor.dart` holds the form and every
/// rule about what may be written.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthee/core/profile_field.dart';
import 'package:healthee/data/profile/health_profile.dart';
import 'package:healthee/data/profile/profile_repository.dart';
import 'package:healthee/features/profile/widgets/profile_editor.dart';
import 'package:healthee/shared/states/async_view.dart';
import 'package:healthee/shared/states/current_account_value.dart';
import 'package:healthee/shared/v02/settings_page.dart';

/// The owner's own details, and their latest weigh-in.
class ProfileScreen extends ConsumerWidget {
  /// The profile screen.
  const ProfileScreen({this.focus, super.key});

  /// The field a link asked to open on, or null for the plain profile.
  final ProfileField? focus;

  /// The prototype's own h1.
  static const String title = 'Your profile';

  /// Its eyebrow.
  static const String eyebrow = 'A little context for your data';

  @override
  Widget build(BuildContext context, WidgetRef ref) => SettingsPage(
    title: title,
    eyebrow: eyebrow,
    children: <Widget>[
      AsyncView<ProfileRepository>(
        value: currentAccountValue(ref.watch(profileRepositoryProvider)),
        onRetry: () => ref.invalidate(profileRepositoryProvider),
        builder: (context, repository) => AsyncView<HealthProfile>(
          value: currentAccountValue(ref.watch(healthProfileProvider)),
          onRetry: () => ref.invalidate(healthProfileProvider),
          builder: (context, profile) => ProfileEditor(
            key: ObjectKey(repository),
            repository: repository,
            profile: profile,
            focus: focus,
          ),
        ),
      ),
    ],
  );
}
