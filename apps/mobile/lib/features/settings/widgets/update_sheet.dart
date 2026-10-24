/// The sheet that says a newer build exists, the first time the app learns it.
///
/// ## Why this overrides what `update_notice.dart` argues
///
/// That file says a banner would be "an interruption for something that is never
/// urgent", and puts the answer on About. The owner's call is that About is
/// somewhere you have to already suspect an update to visit — a notice nobody is
/// told about is a notice that does not happen — so the app now says it once,
/// unprompted, and then never again for that release.
///
/// Both surfaces stay. This one is the telling; About is the looking.
///
/// ## The three rules it keeps
///
///   * **Only a real [UpdateAvailable] opens it.** `UpdateUnknown` — offline,
///     rate-limited, no release published — opens nothing. An app that
///     interrupts you to say it could not check has interrupted you for nothing,
///     and the honest third answer exists precisely so it is not dressed up as
///     one of the other two.
///   * **Once per release**, recorded when the sheet OPENS. See
///     `update_prompt_store.dart` for why "Not now" is an answer rather than a
///     postponement.
///   * **It never installs anything.** Same limit as the About notice: the
///     button opens the release page, Android's own installer does the rest with
///     its own confirmation and its own signature check. Holding
///     `REQUEST_INSTALL_PACKAGES` forever for a courtesy notice is not a trade
///     this app makes.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_scale.dart';
import 'package:healthee/data/store/store_provider.dart';
import 'package:healthee/data/updates/app_release.dart';
import 'package:healthee/data/updates/update_check.dart';
import 'package:healthee/data/updates/update_prompt_store.dart';
import 'package:healthee/features/settings/widgets/update_notice.dart';
import 'package:healthee/shared/sheets/app_sheet.dart';
import 'package:healthee/shared/v02/buttons.dart';

/// The heading the sheet carries. Public so a test can pin it.
const String kUpdateSheetTitle = 'A newer build is out';

/// What the sheet says under the version. Public so a test can pin it.
///
/// It names the limit rather than hiding it: tapping through leaves the app, and
/// the phone's own installer is what actually installs. Somebody who expected a
/// one-tap in-app update should find that out here, not after a browser opens.
const String kUpdateSheetBody =
    'Opening this takes you to the release page in your browser. Android '
    'installs it, with its own confirmation.';

/// Shows [release] once, over the whole app rather than over one tab.
Future<void> showUpdateSheet(BuildContext context, AppRelease release) =>
    showAppSheet<void>(
      context: context,
      builder: (context) => _UpdateSheet(release: release),
    );

class _UpdateSheet extends StatelessWidget {
  const _UpdateSheet({required this.release});

  final AppRelease release;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: EdgeInsets.only(bottom: sheetBottomInset(context)),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(top: BorderSide(color: colors.line, width: hairline)),
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(Radii.sheet),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Insets.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  kUpdateSheetTitle,
                  style: TypeScale.detailTitle.copyWith(color: colors.ink),
                ),
                const SizedBox(height: Insets.sm),
                Text(
                  'Version ${release.versionName}',
                  style: TypeScale.rowTitle.copyWith(color: colors.ink2),
                ),
                const SizedBox(height: Insets.md),
                Text(
                  kUpdateSheetBody,
                  style: TypeScale.small.copyWith(color: colors.ink2),
                ),
                const SizedBox(height: Insets.xl),
                HButton(
                  label: 'Open the release',
                  onPressed: () {
                    Navigator.of(context).pop();
                    unawaited(openReleasePage(release));
                  },
                ),
                const SizedBox(height: Insets.sm),
                HLinkButton(
                  label: 'Not now',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Watches the update check and opens the sheet once, from the app frame.
///
/// A widget rather than a call in `main`, because it needs a `BuildContext` under
/// the root `Navigator` and a frame to have been drawn — a sheet pushed during
/// the first build has nothing to sit on. It draws [child] and nothing else.
class UpdateWatcher extends ConsumerStatefulWidget {
  /// Wraps [child], which is drawn unchanged.
  const UpdateWatcher({required this.child, super.key});

  /// The app frame underneath.
  final Widget child;

  @override
  ConsumerState<UpdateWatcher> createState() => _UpdateWatcherState();
}

class _UpdateWatcherState extends ConsumerState<UpdateWatcher> {
  /// Guards against a second sheet while the first is still deciding.
  ///
  /// `ref.listen` can fire again before the await chain has written the mark —
  /// a rebuild, a provider refresh — and two sheets stacked on one release is
  /// the nag this is built to avoid, in its most obvious form.
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<UpdateStatus>>(updateStatusProvider, (_, next) {
      if (next case AsyncData(value: UpdateAvailable(:final release))) {
        unawaited(_offer(release));
      }
    });
    return widget.child;
  }

  Future<void> _offer(AppRelease release) async {
    if (_busy) return;
    _busy = true;
    try {
      final store = UpdatePromptStore(ref.read(localStoreProvider));
      final offered = await store.offeredCode();
      if (!UpdatePromptStore.shouldOffer(
        versionCode: release.versionCode,
        offered: offered,
      )) {
        return;
      }
      if (!mounted) return;
      // Marked BEFORE the sheet is awaited: the sheet only resolves when it is
      // dismissed, and a mark written after that would not exist for a phone
      // killed with the sheet open — which is the loop this guards.
      await store.markOffered(release.versionCode);
      if (!mounted) return;
      await showUpdateSheet(context, release);
    } finally {
      _busy = false;
    }
  }
}
