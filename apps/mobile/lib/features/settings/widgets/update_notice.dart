/// Whether a newer build is published — shown beside the one you are running.
///
/// ## Here, and not on Today
///
/// The About screen already answers *which build is this?*. "Is there a newer
/// one?" is the same question one step on, and the two belong together: a version
/// number with no way to act on it is trivia. A banner on Today would be an
/// interruption for something that is never urgent — this app is sideloaded, the
/// owner updates when they choose, and nothing breaks if they do not.
///
/// ## The app checks and tells; Android downloads and installs
///
/// Tapping opens the release page in the browser. That is a deliberate limit: the
/// alternative is `REQUEST_INSTALL_PACKAGES`, a permission that lets this app
/// install packages on the owner's phone, held forever for a courtesy check that
/// runs when they open a settings screen. Android's own installer already does
/// this job, with its own confirmation, and it verifies the signature — which is
/// the check that actually matters (`android/key.properties.example` argues it).
///
/// ## "We could not check" is shown, not swallowed
///
/// An offline phone, GitHub's anonymous rate limit and a repository with no
/// release yet all produce the same honest nothing, and it is said out loud. The
/// tempting alternative — showing "you are up to date" whenever the check fails —
/// is the app reassuring somebody about something it does not know.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthee/core/logging.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_scale_forms.dart';
import 'package:healthee/data/updates/app_release.dart';
import 'package:healthee/data/updates/release_client.dart' show kReleasesRepo;
import 'package:healthee/data/updates/update_check.dart';
import 'package:healthee/shared/v02/buttons.dart';
import 'package:url_launcher/url_launcher.dart';

/// What each state of the check says. Public so a test can pin them without
/// pumping a widget, the same shape as `settings/app_version.dart`'s.
String updateLine(AsyncValue<UpdateStatus> status) => switch (status) {
  AsyncData(value: UpdateAvailable(:final release)) =>
    'Version ${release.versionName} is available',
  AsyncData(value: UpToDate()) => 'This is the latest build',
  // An error reaching the provider and an unestablished answer say the same
  // thing, because they mean the same thing to the person reading it.
  AsyncData(value: UpdateUnknown()) || AsyncError() => "Couldn't check for updates",
  _ => 'Checking for a newer build…',
};

/// The release page for [release] — where the APK and the notes are.
///
/// The RELEASE page rather than the asset URL: a browser sent straight at a 72 MB
/// binary starts a download with no context, and the notes are the thing that
/// tells the owner whether they want it.
Uri releasePage(AppRelease release) =>
    Uri.parse('https://github.com/$kReleasesRepo/releases/tag/${release.tag}');

/// Opens [release]'s page, and says so in the log if the phone cannot.
///
/// A device with no browser is a real state, and a button that silently does
/// nothing is worse than one that never appeared. Top-level and public because
/// two surfaces send people to the same place — this notice and
/// `update_sheet.dart` — and a second copy is a second chance to send one of
/// them somewhere else.
Future<void> openReleasePage(AppRelease release) async {
  final uri = releasePage(release);
  final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!opened) {
    AppLog.info('updates', 'nothing on this phone would open the release page');
  }
}

/// The version line's companion: what is published, and the way to it.
class UpdateNotice extends ConsumerWidget {
  /// Const constructor.
  const UpdateNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final status = ref.watch(updateStatusProvider);
    final release = switch (status) {
      AsyncData(value: UpdateAvailable(:final release)) => release,
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          updateLine(status),
          style: FormType.fieldHint.copyWith(color: colors.ink2),
        ),
        if (release != null) ...<Widget>[
          const SizedBox(height: 12),
          HButton(
            label: 'Open the release',
            kind: HButtonKind.secondary,
            onPressed: () => unawaited(openReleasePage(release)),
          ),
        ],
      ],
    );
  }
}
