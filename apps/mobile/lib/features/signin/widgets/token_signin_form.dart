/// ⛔ TRANSITIONAL — the server address and a pasted API token.
///
/// This is how signing in worked before there was an identity provider, and it
/// is kept for exactly two people: an owner mid-migration whose phone still
/// holds the old credential, and a self-hoster whose build was compiled without
/// a Supabase project.
///
/// ## What the token actually is, said plainly
///
/// The shared `REALTIME_INGEST_TOKEN`. One string, no identity attached, and a
/// key to one tenant's entire health record — the server maps it to a single
/// sentinel owner and asks nothing else. **Handing it to a second person hands
/// them the first person's data.** The server refuses to boot with it set beside
/// open signups (`core/config.py`), and `docs/MULTI_USER.md` section 4.4a names
/// its removal condition. This file goes when that secret does.
///
/// The form says so, in the form. A control whose danger is only documented in
/// a docstring is documented for the wrong reader.
///
/// ## The reveal toggle
///
/// Obscured by default, with an eye. A token is long, opaque and usually pasted,
/// and the single most common way to get it wrong is an invisible character at
/// one end — so being able to look at what is in the field is a correctness
/// feature, not a convenience. The whitespace that causes that is trimmed
/// anyway (`data/api/server_session.dart`), which is the belt to this brace.
///
/// **The token is never rendered anywhere but this field.** Not in the semantics
/// label, not in a log line, and not in the state object — see
/// `server_signin_state.dart`, and `test/signin/signin_secrecy_test.dart`.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_scale_forms.dart';
import 'package:healthee/shared/v02/buttons.dart';
import 'package:healthee/shared/v02/fields.dart';
import 'package:healthee/shared/v02/settings_page.dart';
import 'package:healthee/shared/v02/surfaces.dart';
import 'package:solar_icons/solar_icons.dart';

/// Collects the server address and a pasted API token.
class TokenSignInForm extends StatefulWidget {
  /// [initialUrl] prefills the address; [onSubmit] receives both as typed.
  const TokenSignInForm({
    required this.initialUrl,
    required this.onSubmit,
    required this.onEdited,
    required this.enabled,
    required this.configured,
    this.onUsePassword,
    super.key,
  });

  /// What the address field starts with.
  final String initialUrl;

  /// Receives both fields exactly as typed; trimming belongs downstream.
  final void Function(String url, String token) onSubmit;

  /// Called on every keystroke, so a stale failure can be cleared.
  final VoidCallback onEdited;

  /// False while a check is in flight.
  final bool enabled;

  /// Whether this build HAS an identity provider.
  ///
  /// It changes what this screen is: with one, this is a fallback the owner
  /// chose and the note explains why they should not stay on it. Without one,
  /// it is the only way in and saying "use a password instead" would be an
  /// instruction the build cannot carry out.
  final bool configured;

  /// Goes back to the email-and-password form. Null hides the way back.
  final VoidCallback? onUsePassword;

  @override
  State<TokenSignInForm> createState() => _TokenSignInFormState();
}

class _TokenSignInFormState extends State<TokenSignInForm> {
  late final TextEditingController _url = TextEditingController(
    text: widget.initialUrl,
  );
  final TextEditingController _token = TextEditingController();
  bool _revealed = false;

  @override
  void dispose() {
    // A controller holding a token is memory we can drop early, and must drop
    // at all: leaking it would keep the string alive for the life of the isolate.
    _token
      ..clear()
      ..dispose();
    _url.dispose();
    super.dispose();
  }

  void _submit() {
    if (_url.text.trim().isEmpty || _token.text.trim().isEmpty) {
      return;
    }
    widget.onSubmit(_url.text, _token.text);
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
            'Sign in with an API token',
            style: FormType.heading3.copyWith(color: colors.ink),
          ),
          const SizedBox(height: SectionGap.height),
          // The strap-only promise, on BOTH sign-in forms. Whichever way in an
          // owner is looking at, the screen has to say that not signing in is a
          // supported way to use this app rather than a broken one.
          const SmallProse(
            'Healthee reads what your strap measured with no server at all. '
            'Signing in adds the half that is worked out on it — recovery, '
            'sleep health, debt, VO₂max and biological age.',
          ),
          const SizedBox(height: SectionGap.height),
          SmallProse(
            widget.configured
                ? 'This is the older way in, and it is going away. The token is '
                      'shared rather than yours: it identifies a server, not a '
                      'person, so anyone holding it can read and write the same '
                      'account. Sign in with your email instead if you can.'
                : 'This build was compiled without an identity provider, so a '
                      'token is the only way to reach a server. The token is '
                      'shared rather than yours — it identifies a server, not a '
                      'person — so treat it the way you would a house key.',
          ),
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
            label: 'API token',
            hint: 'Checked against the server before it is saved',
            child: HTextField(
              controller: _token,
              enabled: widget.enabled,
              obscure: !_revealed,
              onSubmitted: (_) => _submit(),
              onChanged: (_) => widget.onEdited(),
              suffixIcon: IconButton(
                onPressed: () => setState(() => _revealed = !_revealed),
                tooltip: _revealed ? 'Hide the token' : 'Show the token',
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
            'The token is kept in this phone’s secure keystore — the same place '
            'a password manager uses — and is sent only to the address above, '
            'as an Authorization header. It is never written to a log and never '
            'put in a web address.',
          ),
          const SizedBox(height: SectionGap.height),
          HButton(
            label: 'Check and sign in',
            onPressed: widget.enabled ? _submit : null,
          ),
          if (widget.onUsePassword case final VoidCallback back) ...<Widget>[
            const SizedBox(height: SectionGap.height),
            HLinkButton(
              label: 'Sign in with your email instead',
              onPressed: widget.enabled ? back : null,
            ),
          ],
        ],
      ),
    );
  }
}
