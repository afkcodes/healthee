/// Where to support this, on the screens that are about the app rather than you.
///
/// ## Settings and About, and nowhere else
///
/// Not Today, not Sleep, not Activity, not Actions. A donation prompt on the
/// screen somebody opened to read their recovery score makes a health app feel
/// like it wants something from them — which is exactly the posture this product
/// is built against. Settings and About are where "which build is this, who made
/// it, how do I support it" already belongs, and somebody on those screens is
/// already asking.
///
/// ## It is the app's own card, not a coloured one
///
/// An accent-gradient panel with its own glass pills was tried here and taken
/// out. Nothing else in this product shouts — Settings is a column of quiet
/// surfaces with one accent glyph per row — and the loudest thing on the screen
/// being the ask reads as a pitch. So this is `PlainCard`, `HButton` and the same
/// ink the rows beside it use: one accent heart, one line, two buttons.
///
/// It sits directly UNDER the owner's own profile card rather than above it. The
/// screen is theirs first; visibility comes from being above the fold, which it
/// still is, and not from going in front of the thing they came for.
///
/// The head is `rowTitle` over `rowSubtitle` — the same pair every `ListRow`
/// below it uses, so the card reads at the size of its neighbours rather than
/// announcing itself.
///
/// ## Three things `oss/sunoh` learned the hard way about UPI, kept verbatim
///
///   * **The link is built as a STRING.** `Uri(scheme:, host:, queryParameters:)`
///     percent-encodes the `@` in a VPA to `%40`, and several Indian UPI apps
///     refuse to parse that. The raw `upi://pay?…` form is the canonical deep
///     link.
///   * **`canLaunchUrl` is not consulted.** It is unreliable for non-HTTP schemes
///     on Android even with the manifest `<queries>` entry, and a false from it
///     forced the copy fallback on phones that *did* have a UPI app.
///   * **`externalNonBrowserApplication`** is the documented mode for a
///     non-browser deep link; `externalApplication` can hand `upi://` to a
///     browser, which cannot pay.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:healthee/core/logging.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_scale_forms.dart';
import 'package:healthee/shared/v02/buttons.dart';
import 'package:healthee/shared/v02/surfaces.dart';
import 'package:solar_icons/solar_icons.dart';
import 'package:url_launcher/url_launcher.dart';

/// Where one-off and recurring support goes, from anywhere.
const String kKofiUrl = 'https://ko-fi.com/afkcodes';

/// The project's own page, on a domain it controls.
const String kSponsorUrl = 'https://afk.codes/sponsor';

/// The UPI address money actually lands in.
///
/// ⛔ **A wrong value here sends a stranger money and there is no undo.** It is
/// never guessed, never defaulted and never derived from anything — it is typed
/// in by the person it pays.
const String kUpiVpa = 'afkcodes@axl';

/// The name the UPI app shows as the payee.
const String kUpiPayee = 'Healthee';

/// The `upi://pay` deep link. **No amount — the payer decides.**
///
/// An `am=` would open the app with a number already in the field, which reads
/// as a price however editable it is.
///
/// **A string, on purpose.** See the library doc: `Uri`'s own query encoding
/// turns `afkcodes@axl` into `afkcodes%40axl` and several UPI apps reject it.
const String kUpiLink = 'upi://pay?pa=$kUpiVpa&pn=$kUpiPayee&cu=INR';

/// The line under the heading. Public so a test can pin it.
///
/// It names what the money is for and stops. It does NOT describe what the
/// product costs, what it does not cost, or what nothing unlocks — a donation
/// card is not the place to litigate pricing.
///
/// **Development and research, not hosting.** Hosting is the owner's own server
/// bill on a self-hosted product — naming it as the thing donations cover reads
/// as a running cost somebody else is carrying for you. The work is the
/// development and the research behind the corpus, and those are what this pays
/// for.
const String kSupportBody = 'Support pays for development and research time.';

/// The heading the card carries. Public so a test can pin it.
const String kSupportHeading = 'Support Healthee';

/// The label on the UPI action.
///
/// It names the rail. "Send a tip" beside "Buy a coffee" said what the gesture
/// was but not what happens when you press it, and the two are not alike: one
/// opens a payment app that is already signed in, the other opens a browser.
/// Somebody deciding between them is deciding exactly that.
const String kUpiLabel = 'Tip via UPI';

/// The label on the Ko-fi action.
const String kKofiLabel = 'Buy a coffee';

/// Opens [url] in whatever the phone uses for the web.
Future<void> _openWeb(BuildContext context, String url) async {
  try {
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      _say(context, 'Nothing on this phone would open that link');
    }
  } on Object catch (error) {
    AppLog.info('settings', 'could not open $url: $error');
    if (context.mounted) {
      _say(context, 'Nothing on this phone would open that link');
    }
  }
}

/// Fires the UPI intent, and falls back to the clipboard when nothing takes it.
///
/// The fallback is the point: somebody who taps this has already decided to
/// give, and "nothing happened" is the worst possible answer to that. Copying
/// the VPA leaves them able to finish by hand.
Future<void> _payUpi(BuildContext context) async {
  try {
    final opened = await launchUrl(
      Uri.parse(kUpiLink),
      mode: LaunchMode.externalNonBrowserApplication,
    );
    if (opened) return;
  } on Object catch (error) {
    AppLog.info('settings', 'no UPI app took the intent: $error');
  }
  await Clipboard.setData(const ClipboardData(text: kUpiVpa));
  if (context.mounted) _say(context, 'No UPI app — copied $kUpiVpa');
}

/// One line of feedback, on the surface the app already has for it.
void _say(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text(message)));
}

/// The card at the top of settings: an accent heart, a line, two buttons.
class SupportCard extends StatelessWidget {
  /// Const constructor.
  const SupportCard({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return PlainCard(
      inset: 12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // `rowTitle`/`rowSubtitle` rather than a heading pair: this sits
              // directly above a column of `ListRow`s and now reads at the same
              // size as they do, which is both quieter and shorter.
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  SolarIconsBold.heart,
                  size: 16,
                  color: colors.accent,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      kSupportHeading,
                      style: FormType.rowTitle.copyWith(color: colors.ink),
                    ),
                    Text(
                      kSupportBody,
                      style: FormType.rowSubtitle.copyWith(color: colors.ink2),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              // Both secondary. A filled accent button made the ask the loudest
              // thing on a screen of quiet rows — brighter than the header and
              // every value under it. Supporting is an offer, not this screen's
              // primary action, and the two ways to give are equals besides.
              Expanded(
                child: HButton(
                  label: kUpiLabel,
                  icon: SolarIconsBold.heartAngle,
                  kind: HButtonKind.secondary,
                  full: false,
                  onPressed: () => unawaited(_payUpi(context)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: HButton(
                  label: kKofiLabel,
                  icon: SolarIconsOutline.cupHot,
                  kind: HButtonKind.secondary,
                  full: false,
                  onPressed: () => unawaited(_openWeb(context, kKofiUrl)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The quiet form, for About: the line, then the ways to give.
class SupportNotice extends StatelessWidget {
  /// Const constructor.
  const SupportNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          kSupportBody,
          style: FormType.fieldHint.copyWith(color: colors.ink2),
        ),
        const SizedBox(height: 12),
        HButton(
          label: kUpiLabel,
          icon: SolarIconsBold.heartAngle,
          kind: HButtonKind.secondary,
          onPressed: () => unawaited(_payUpi(context)),
        ),
        const SizedBox(height: 8),
        HButton(
          label: kKofiLabel,
          icon: SolarIconsOutline.cupHot,
          kind: HButtonKind.secondary,
          onPressed: () => unawaited(_openWeb(context, kKofiUrl)),
        ),
        const SizedBox(height: 8),
        HLinkButton(
          label: 'Other ways to support',
          onPressed: () => unawaited(_openWeb(context, kSponsorUrl)),
        ),
      ],
    );
  }
}
