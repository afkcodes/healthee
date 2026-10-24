/// The server address, an email and a password — signing in, or signing up.
///
/// ## One form, two modes, and why it is not two screens
///
/// The fields are identical and the flow after them is identical: prove an
/// identity, ask the server, mint this device, store. What differs is one call
/// and the words on the button — so a second screen would be this file copied,
/// with the copy free to drift on the promises it makes about where a password
/// goes. The mode is a toggle, and the toggle is a link rather than a tab
/// because signing in is what almost everyone is here to do.
///
/// ⚠ **Creating an account here does not mean this server will serve it.** The
/// identity provider and the deployment are separate gates; an email that is not
/// on the invite list gets a real account and a 403, which the screen reports as
/// `ServerRefusedThisAccount`. The form says so before the button is pressed,
/// because finding out afterwards is a worse way to learn it.
///
/// ## What the form says, in the form
///
/// The same discipline `zepp_sign_in_form.dart` uses: the promise about where a
/// secret goes is on screen next to the field that collects it, because that is
/// where the question gets asked. Here there are two promises and they are
/// different, so both are made: the password goes to the identity provider and
/// never to the Healthee server, and the credential this phone ends up holding
/// is one the server minted for this phone alone.
///
/// ## Why the address is still a field
///
/// This product is self-hostable, and the owner's server is wherever they put
/// it. The identity provider is fixed at build time (`core/env.dart`) and the
/// server is not, so the address stays and the provider does not appear.
///
/// ## The reveal toggle
///
/// Obscured by default, with an eye. Being able to look at what is in the field
/// is a correctness feature rather than a convenience — a mistyped password and
/// a wrong password are the same 400 from the provider, and only one of them is
/// worth resetting an account over.
///
/// **The password is never rendered anywhere but this field.** Not in the
/// semantics label, not in a log line, and not in the state object — see
/// `server_signin_state.dart`, and `test/signin/signin_secrecy_test.dart`,
/// which executes the claim.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_scale_forms.dart';
import 'package:healthee/shared/v02/buttons.dart';
import 'package:healthee/shared/v02/fields.dart';
import 'package:healthee/shared/v02/settings_page.dart';
import 'package:healthee/shared/v02/surfaces.dart';
import 'package:solar_icons/solar_icons.dart';

/// Collects the server address and the API token.
class ServerSignInForm extends StatefulWidget {
  /// [initialUrl] prefills the address and [initialEmail] the email, when this
  /// phone already knows one. [onSubmit] receives the fields as typed plus
  /// whether to create the account. [onUseToken] opens the transitional
  /// pasted-token path, or is null where that path should not be offered.
  const ServerSignInForm({
    required this.initialUrl,
    this.initialEmail,
    required this.onSubmit,
    this.onUseToken,
    required this.onEdited,
    required this.enabled,
    super.key,
  });

  /// What the address field starts with — the stored server, or the build's.
  final String initialUrl;

  /// What the email field starts with. Null leaves it empty.
  ///
  /// The Zepp account's email, when the strap has been paired: the owner has
  /// already typed it on this phone and it is almost always the same address.
  ///
  /// ⛔ **The email only.** The Zepp PASSWORD is never offered here and never
  /// reused. It belongs to Amazfit, and making it the key to the health record
  /// as well would mean one breach opens both — the exact amplification that
  /// makes credential stuffing work. Two services, two passwords, and the owner
  /// chooses this one.
  final String? initialEmail;

  /// Runs the check. Trimming is the data layer's job, in one place.
  ///
  /// The `bool` is whether to CREATE the account rather than sign in.
  final void Function(
    String url,
    String email,
    String password, {
    required bool create,
  })
  onSubmit;

  /// Opens the ⛔ transitional token form. Null hides the way in entirely.
  final VoidCallback? onUseToken;

  /// Called on the first edit after a failure, so stale copy can be cleared.
  final VoidCallback onEdited;

  /// False while a check is in flight.
  final bool enabled;

  @override
  State<ServerSignInForm> createState() => _ServerSignInFormState();
}

class _ServerSignInFormState extends State<ServerSignInForm> {
  late final TextEditingController _url = TextEditingController(
    text: widget.initialUrl,
  );
  late final TextEditingController _email = TextEditingController(
    text: widget.initialEmail ?? '',
  );
  final TextEditingController _password = TextEditingController();
  bool _revealed = false;
  bool _creating = false;

  /// Takes a prefill that arrived AFTER the first build.
  ///
  /// ⛔ The controller is `late final`, so it is built on first access — during
  /// the first build, when the keystore read that supplies the email has not
  /// returned yet. Without this the prefill silently never happens: the field is
  /// constructed empty, the value lands one frame later, and `initialEmail` is
  /// never consulted again. The same shape as a `static final` that will not
  /// re-run, and just as invisible.
  ///
  /// **Only into an untouched field.** If the owner has typed anything, that is
  /// their answer and a late-arriving convenience must not overwrite it.
  @override
  void didUpdateWidget(ServerSignInForm old) {
    super.didUpdateWidget(old);
    final arrived = widget.initialEmail;
    if (arrived == null || arrived == old.initialEmail) {
      return;
    }
    if (_email.text.isEmpty || _email.text == (old.initialEmail ?? '')) {
      _email.text = arrived;
    }
  }

  @override
  void dispose() {
    // A controller holding a password is memory we can drop early, and must
    // drop at all: leaking it would keep the string alive for the life of the
    // isolate. Cleared before disposal, so the characters go with the widget.
    _password
      ..clear()
      ..dispose();
    _email.dispose();
    _url.dispose();
    super.dispose();
  }

  void _submit() {
    if (_url.text.trim().isEmpty ||
        _email.text.trim().isEmpty ||
        _password.text.isEmpty) {
      return;
    }
    widget.onSubmit(
      _url.text,
      _email.text,
      _password.text,
      create: _creating,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return PlainCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            _creating ? 'Create your account' : 'Sign in to your server',
            style: FormType.heading3.copyWith(color: colors.ink),
          ),
          const SizedBox(height: SectionGap.height),
          const SmallProse(
            'Healthee reads what your strap measured with no server at all. '
            'Signing in adds the half that is worked out on it — recovery, '
            'sleep health, debt, VO₂max and biological age — and it is what '
            'keeps your readings yours: every request after this carries who '
            'you are, and the server answers with your rows and nobody else’s.',
          ),
          if (_creating) ...<Widget>[
            const SizedBox(height: SectionGap.height),
            // Said BEFORE the button, not after the 403. A server can be
            // invite-only and this one is: the account will be real and this
            // deployment can still decline to open for it.
            const SmallProse(
              'Servers can be invite-only. Making an account and being served '
              'by this address are two separate steps — the server above only '
              'opens for addresses its owner has invited. If yours is not one '
              'it will say so, and nothing you typed was wrong.',
            ),
          ],
          const SizedBox(height: SectionGap.height),
          HField(
            label: 'Server address',
            hint: 'https://healthee.example.com — or this phone itself',
            child: HTextField(
              controller: _url,
              enabled: widget.enabled,
              keyboardType: TextInputType.url,
              onChanged: (_) => widget.onEdited(),
            ),
          ),
          HField(
            label: 'Email',
            hint: 'The account you sign in to Healthee with',
            child: HTextField(
              controller: _email,
              enabled: widget.enabled,
              keyboardType: TextInputType.emailAddress,
              onChanged: (_) => widget.onEdited(),
            ),
          ),
          HField(
            label: 'Password',
            hint: 'Checked by your identity provider, never by this app',
            child: HTextField(
              controller: _password,
              enabled: widget.enabled,
              obscure: !_revealed,
              onSubmitted: (_) => _submit(),
              onChanged: (_) => widget.onEdited(),
              suffixIcon: IconButton(
                onPressed: () => setState(() => _revealed = !_revealed),
                tooltip: _revealed ? 'Hide the password' : 'Show the password',
                icon: Icon(
                  _revealed
                      ? SolarIconsOutline.eyeClosed
                      : SolarIconsOutline.eye,
                  size: 18,
                  color: colors.ink2,
                ),
              ),
            ),
          ),
          const SmallProse(
            'Your password goes to the identity provider and never to the '
            'Healthee server. What this phone keeps afterwards is a key the '
            'server made for this phone alone — held in the secure keystore, '
            'sent only to the address above, never written to a log, and '
            'revocable from your account if you lose the device.',
          ),
          const SizedBox(height: SectionGap.height),
          HButton(
            label: _creating ? 'Create account' : 'Sign in',
            onPressed: widget.enabled ? _submit : null,
          ),
          const SizedBox(height: SectionGap.height),
          HLinkButton(
            label: _creating
                ? 'I already have an account'
                : 'Create an account',
            onPressed: widget.enabled
                ? () => setState(() {
                    _creating = !_creating;
                    // The failure on screen was about the OTHER mode, and a
                    // stale "no account for that email" under a form that now
                    // creates one reads as a refusal of what you are about to do.
                    widget.onEdited();
                  })
                : null,
          ),
          if (widget.onUseToken case final VoidCallback open) ...<Widget>[
            const SizedBox(height: SectionGap.height),
            HLinkButton(
              label: 'Sign in with an API token instead',
              onPressed: widget.enabled ? open : null,
            ),
          ],
        ],
      ),
    );
  }
}
