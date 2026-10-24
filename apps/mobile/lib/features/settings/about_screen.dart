/// About — `H.screens.about`, plus the notice this app is obliged to carry.
///
/// ```js
/// H.screens.about = () => `${H.header('Health, understood.','About Healthee',true)}
///   <div class="coach-symbol">${H.icon('leaf')}</div>
///   <h2>A little more clarity.<br>A little less guessing.</h2>
///   <p class="small section">…</p>
///   ${H.section('Built around your trust', …three blocks split by dividers…)}
///   ${H.footer()}`;
/// ```
///
/// ## The fourth block is a licence term, not a design choice
///
/// Figtree and Inter both ship vendored in `assets/fonts/` under the SIL OFL 1.1, and those
/// terms require the notice to travel **with the fonts** — inside the binary
/// somebody installs, not beside them in a repository. `core/licences.dart`
/// registers the bundled `OFL.txt` with `LicenseRegistry`, and this screen is
/// the only door to the page that renders it. *A registered licence nobody can
/// open satisfies the obligation on paper and not in fact.*
///
/// The prototype has no block for it because a design preview has no binary to
/// ship. So the trust card grows a fourth division, in the prototype's own
/// `h3` + `.small` + `.divider` rhythm, and the door is a `.button.secondary`.
///
/// The version is read rather than written down, and the read is bounded — see
/// `features/settings/app_version.dart`. A host that cannot answer gets the
/// sentence saying so, never a number.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_scale_forms.dart';
import 'package:healthee/features/settings/app_version.dart';
import 'package:healthee/features/settings/widgets/support_notice.dart';
import 'package:healthee/features/settings/widgets/update_notice.dart';
import 'package:healthee/features/today/v02/today_header.dart';
import 'package:healthee/shared/v02/buttons.dart';
import 'package:healthee/shared/v02/emblems.dart';
import 'package:healthee/shared/v02/section_head.dart';
import 'package:healthee/shared/v02/settings_page.dart';
import 'package:healthee/shared/v02/surfaces.dart';
import 'package:solar_icons/solar_icons.dart';

/// What this app is, and the notices it carries.
class AboutScreen extends ConsumerWidget {
  /// The about screen.
  const AboutScreen({super.key});

  /// The prototype's own h1.
  static const String title = 'About Healthee';

  /// Its eyebrow.
  static const String eyebrow = 'About Healthee';

  /// `.section { margin-top: 24px }` inside a card.
  static const double blockGap = 24;

  /// The prototype's own headline, its `<br>` kept as a newline.
  static const String headline =
      'A little more clarity.\nA little less guessing.';

  /// And the paragraph under it.
  static const String opening =
      'Healthee brings your strap readings and everyday context together. Its '
      'job is to help you understand patterns, while being clear about what it '
      'doesn’t know.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    return SettingsPage(
      title: title,
      eyebrow: eyebrow,
      children: <Widget>[
        const CoachSymbol(SolarIconsOutline.leaf),
        Text(headline, style: FormType.heading2.copyWith(color: colors.ink)),
        const SizedBox(height: blockGap),
        const SmallProse(opening),
        const SectionGap(),
        const SectionHead(title: 'Built around your trust'),
        PlainCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const _Block(
                title: 'Data with a source.',
                body:
                    'Measurements, estimates and missing values each have '
                    'their place. Research context is available when you want '
                    'to go deeper.',
              ),
              const CardDivider(),
              const _Block(
                title: 'Useful when you’re offline.',
                body:
                    'This phone keeps recent readings on its own. Longer '
                    'history and coach responses depend on your server.',
              ),
              const CardDivider(),
              const _Block(
                title: 'No diagnosis behind a score.',
                body:
                    'Patterns can prompt a question. They don’t replace how '
                    'you feel or appropriate care.',
              ),
              const CardDivider(),
              _Block(
                title: 'Built on work that is credited.',
                body:
                    'The typeface is Figtree, with Inter covering the characters it '
                    'has no glyph for. Both under the SIL Open Font License '
                    '1.1, bundled with this app rather than fetched. Its '
                    'notice and every package licence are below — that is a '
                    'licence term, not a nicety.',
                // Which build this is, then whether there is a newer one. Two
                // halves of one question, so they sit together rather than the
                // second becoming a notification somewhere else.
                footer: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      versionLine(ref.watch(appVersionProvider)),
                      style: FormType.fieldHint.copyWith(color: colors.ink2),
                    ),
                    const SizedBox(height: 8),
                    const UpdateNotice(),
                  ],
                ),
              ),
              const SizedBox(height: blockGap),
              // After the credit block and before the licences: somebody reading
              // who made this is already asking the question this answers. It is
              // deliberately not on Today — see `support_notice.dart`.
              const SupportNotice(),
              const SizedBox(height: blockGap),
              HButton(
                label: 'Licences and notices',
                kind: HButtonKind.secondary,
                onPressed: () => showLicensePage(
                  context: context,
                  applicationName: 'Healthee',
                ),
              ),
            ],
          ),
        ),
        const DataFooter(),
      ],
    );
  }
}

/// One `h3` + `.small` division of the trust card.
class _Block extends StatelessWidget {
  const _Block({required this.title, required this.body, this.footer});

  final String title;
  final String body;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(title, style: FormType.heading3.copyWith(color: colors.ink)),
        const SizedBox(height: AboutScreen.blockGap),
        SmallProse(body),
        if (footer case final Widget line) ...<Widget>[
          const SizedBox(height: AboutScreen.blockGap),
          line,
        ],
      ],
    );
  }
}
