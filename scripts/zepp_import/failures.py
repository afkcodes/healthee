"""Every way an import can fail, named — and what to do about each one.

The mobile app's pairing flow sets the rule this file follows
(`apps/mobile/lib/data/pairing/pairing_failure.dart`): "something went wrong" is banned.
A failure carries a `headline` that says WHICH failure it is and a `remedy` that says what
to do next, and nothing else reaches the screen.

## What is deliberately not in here

No failure carries a password, a token or a response body. The nearest thing to raw
detail is a step name, an HTTP status and a short field name, all of which are ours.
`tests/test_secrecy.py` runs the whole flow with sentinel secrets and fails if one of them
reaches the output.
"""

from __future__ import annotations

# The Healthee app's own heading for the screen an owner signed in on
# (`apps/mobile/lib/features/signin/widgets/server_signin_form.dart`). It is quoted to
# them, so `tests/test_server_contract.py` fails when the app renames it.
SIGN_IN_SCREEN = "Sign in to your server"


class ZeppImportError(Exception):
    """A named failure. `code` is a stable, secret-free id for logs and tests."""

    def __init__(self, code: str, headline: str, remedy: str) -> None:
        super().__init__(headline)
        self.code = code
        self.headline = headline
        self.remedy = remedy


def no_network(what: str, host: str, kind: str) -> ZeppImportError:
    return ZeppImportError(
        "no_network",
        f"Could not reach {what} ({host}): {kind}.",
        "Check the connection and run the same command again. Nothing was changed.",
    )


def bad_setting(name: str, problem: str) -> ZeppImportError:
    return ZeppImportError("bad_setting", f"{name}: {problem}", "Fix that value and run it again.")


def missing_setting(name: str, env: str) -> ZeppImportError:
    return ZeppImportError(
        "missing_setting",
        f"No {name} was given, and there is no terminal to ask on.",
        f"Set {env} in the environment or in the --env-file.",
    )


def unconfirmed() -> ZeppImportError:
    return ZeppImportError(
        "unconfirmed",
        "Nothing was written: there is no terminal to confirm the import on.",
        "Run it in a terminal, or add --yes to import without being asked.",
    )


# ── Zepp ─────────────────────────────────────────────────────────────────────


def zepp_sign_in_refused(status: int) -> ZeppImportError:
    return ZeppImportError(
        "zepp_sign_in_refused",
        f"Zepp did not accept the sign-in (HTTP {status}).",
        "Check the email and password in the Zepp app itself. If you sign in to Zepp with "
        "Google, Apple or a phone number, set a Zepp password first. If they are right, "
        "Zepp may be refusing this network, which happens on cloud servers: run the same "
        "command from Termux on your phone instead.",
    )


def zepp_wrong_credentials(said: str) -> ZeppImportError:
    """`said` is Zepp's own short answer: an HTTP status, or the error number it redirects with."""
    return ZeppImportError(
        "zepp_wrong_credentials",
        f"Zepp did not accept that email and password ({said}).",
        "Check them in the Zepp app itself, then type them again. If you sign in to Zepp "
        "with Google, Apple or a phone number, set a Zepp password first.",
    )


def zepp_api_changed(step: str, detail: str) -> ZeppImportError:
    return ZeppImportError(
        "zepp_api_changed",
        f"Zepp answered {step} in a way this tool does not understand ({detail}).",
        "Zepp's API is unofficial and has probably changed. Nothing was written. Run it "
        "again with --verbose and share what that prints: it is field names and types "
        "only, never a value, a place or a token.",
    )


def zepp_no_workouts(tried: list[str]) -> ZeppImportError:
    return ZeppImportError(
        "zepp_no_workouts",
        "Zepp returned no workouts for this account.",
        "Tried: " + "; ".join(tried) + ". Check that the Zepp app shows workouts under "
        "this same account. If it does, your data lives on a region host this tool did "
        "not find: pass it with --zepp-host.",
    )


def zepp_elsewhere(host: str) -> ZeppImportError:
    return ZeppImportError(
        "zepp_elsewhere",
        f"Zepp says this account's data is on {host}, not on the host that was asked.",
        f"Run it again with --zepp-host {host}. Nothing was written.",
    )


def zepp_busy() -> ZeppImportError:
    return ZeppImportError(
        "zepp_busy",
        "Zepp is limiting or failing requests right now.",
        "Wait a few minutes and run the same command again. Nothing was written.",
    )


def zepp_token_refused(tried: list[str]) -> ZeppImportError:
    return ZeppImportError(
        "zepp_token_refused",
        "Zepp signed you in but refused the workout request.",
        "Tried: " + "; ".join(tried) + ". Run it again. If it keeps happening Zepp has "
        "changed how its workout API is authorised.",
    )


# ── Healthee ─────────────────────────────────────────────────────────────────


def healthee_no_sign_in(host: str) -> ZeppImportError:
    return ZeppImportError(
        "healthee_no_sign_in",
        f"{host} has no sign-in configured, so this tool cannot write to it.",
        "The server needs SUPABASE_URL (or SUPABASE_PROJECT_REF) and SUPABASE_ANON_KEY. "
        "See docs/SELF_HOSTING.md.",
    )


def healthee_not_healthee(host: str, detail: str) -> ZeppImportError:
    return ZeppImportError(
        "healthee_not_healthee",
        f"{host} did not answer like a Healthee server ({detail}).",
        "Check the address. It is the one you typed into the Healthee app.",
    )


def healthee_too_old(host: str) -> ZeppImportError:
    return ZeppImportError(
        "healthee_too_old",
        f"{host} has no /api/auth-config, so it is not a Healthee server this tool can use.",
        "Check the address. If it is right, the server predates the sign-in this tool "
        "needs: update it, then run again. Nothing was written.",
    )


def healthee_slow(step: str, status: int) -> ZeppImportError:
    return ZeppImportError(
        "healthee_slow",
        f"Healthee did not answer {step} in time (HTTP {status}).",
        "The write may still have gone through. Run the same command again: what is "
        "already stored is recognised and nothing is imported twice.",
    )


def healthee_wrong_credentials(detail: str) -> ZeppImportError:
    return ZeppImportError(
        "healthee_wrong_credentials",
        f"Healthee's sign-in refused that email and password ({detail}).",
        "This is your Healthee login, not your Zepp one: the email and password you "
        f'typed into the Healthee app on "{SIGN_IN_SCREEN}". The README says how to '
        "look the email up on your own server.",
    )


def healthee_refused(step: str, status: int, detail: str) -> ZeppImportError:
    return ZeppImportError(
        "healthee_refused",
        f"Healthee refused {step} (HTTP {status}: {detail}).",
        "Nothing after this step was written. Run it again; if it repeats, the server's "
        "API differs from the one this tool was written against.",
    )


def healthee_unreadable(what: str, unread: int, total: int, looked_like: str) -> ZeppImportError:
    """A list of what Healthee holds that this tool could not fully read."""
    count = f"{unread} of its {total} rows" if total else "the reply"
    return ZeppImportError(
        "healthee_unreadable",
        f"Healthee sent {what}, and {count} could not be read ({looked_like}).",
        "Nothing was written. A stored session this tool cannot read would look absent "
        "and be imported a second time, and nothing here can delete one. The server's "
        "reply differs from the one this tool was written against.",
    )


def healthee_too_many_tokens() -> ZeppImportError:
    return ZeppImportError(
        "healthee_too_many_tokens",
        "Your Healthee account already holds the maximum number of device tokens.",
        "One must be revoked first, and the app has no screen for that yet: list them "
        "with GET /api/device and revoke an old one with DELETE /api/device/{id}, "
        "signed in as yourself. Nothing was written.",
    )
