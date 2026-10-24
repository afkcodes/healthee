"""Zepp sign-in and sign-out — the only place a Zepp password is handled.

A port of `apps/mobile/lib/data/pairing/zepp_client.dart`, step for step, and bound by the
same rule: the password goes into an AES block, into one HTTPS request to Zepp's own login
endpoint, and nowhere else. It is not written to disk, not sent to Healthee, and not
logged — nor is anything from this host beyond a status code.

Unlike the app, this signs OUT when it is done (`sign_out`). The app drops its session by
letting it go out of scope and the token lives out its thirty days unused; a command-line
run has a definite end, so it ends the session there. That is what the `huami_token`
reference does by default.
"""

from __future__ import annotations

import json
import urllib.parse
import uuid
from dataclasses import dataclass, field

from zepp_import import failures, zepp_wire
from zepp_import.aes_cbc import encrypt_cbc_pkcs7
from zepp_import.transport import Response, Send, TransportError
from zepp_import.zepp_wire import ZeppEndpoints

_TIMEOUT_S = 30.0
_REFUSED_STATUSES = (403, 429)
_WRONG_CREDENTIAL_STATUSES = (400, 401)
_ERROR_CHARS = 12


@dataclass(frozen=True)
class ZeppSession:
    """A signed-in Zepp session, held in memory for the length of one run.

    `app_token` and `login_token` are bearer credentials: never stored, never logged,
    never sent to Healthee. `repr` omits them and the secrecy test proves nothing else
    prints them.
    """

    user_id: str
    app_token: str = field(repr=False)
    login_token: str | None = field(default=None, repr=False)
    host_hints: tuple[str, ...] = ()


def sign_in(email: str, password: str, endpoints: ZeppEndpoints, send: Send) -> ZeppSession:
    """Steps 1 and 2: email + password in, an app token and user id out."""
    access_token = _request_access_token(email, password, endpoints, send)
    return _exchange_for_app_token(access_token, endpoints, send)


def sign_out(session: ZeppSession, endpoints: ZeppEndpoints, send: Send) -> bool:
    """End the session this run opened. False when Zepp did not confirm it.

    A failure here is reported by the caller and is not fatal: the import has already
    happened, and an unconfirmed sign-out leaves a token that expires on its own.
    """
    if not session.login_token:
        return False
    form = [("login_token", session.login_token), ("os_verison", "vnull")]  # sic: reference
    try:
        reply = send(
            "POST",
            endpoints.logout_url,
            headers=zepp_wire.logout_headers(),
            body=zepp_wire.encode_form(form),
            timeout_s=_TIMEOUT_S,
        )
    except TransportError:
        return False
    if reply.status != 200:
        return False
    try:
        return _object(reply).get("result") == "ok"
    except ValueError:
        return False


def _send(step: str, send: Send, url: str, headers: dict[str, str], body: bytes) -> Response:
    try:
        return send("POST", url, headers=headers, body=body, timeout_s=_TIMEOUT_S)
    except TransportError as error:
        raise failures.no_network(f"Zepp for {step}", error.host, error.kind) from None


def _request_access_token(email: str, password: str, endpoints: ZeppEndpoints, send: Send) -> str:
    """Step 1 — the encrypted credential exchange. Returns the `access` token."""
    payload = encrypt_cbc_pkcs7(
        zepp_wire.encode_form(zepp_wire.tokens_form(email, password)),
        key=zepp_wire.AES_KEY,
        iv=zepp_wire.AES_IV,
    )
    reply = _send("the sign-in", send, endpoints.tokens_url, zepp_wire.tokens_headers(), payload)
    if reply.status in _WRONG_CREDENTIAL_STATUSES:
        raise failures.zepp_wrong_credentials(f"HTTP {reply.status}")
    if reply.status in _REFUSED_STATUSES:
        raise failures.zepp_sign_in_refused(reply.status)
    if not 300 <= reply.status < 400:
        raise failures.zepp_api_changed("the sign-in", f"HTTP {reply.status}, not a redirect")
    location = reply.headers.get("location", "")
    if not location:
        raise failures.zepp_api_changed("the sign-in", "a redirect with no Location header")
    query = urllib.parse.parse_qs(urllib.parse.urlsplit(location).query, keep_blank_values=True)
    access = query.get("access", [""])[0]
    if access:
        return access
    # A redirect that carries an error number instead of tokens is Zepp saying no. Live
    # Zepp answers a wrong email or password with `error=401` (checked 2026-10-11).
    said = (query.get("error") or query.get("error_code") or [""])[0]
    if said or "error" in query or "error_code" in query:
        kept = "".join(ch for ch in said if ch.isascii() and ch.isalnum())
        number = kept[:_ERROR_CHARS] or "unnumbered"
        raise failures.zepp_wrong_credentials(f"Zepp error {number}")
    raise failures.zepp_api_changed("the sign-in", "no access token in the redirect")


def _exchange_for_app_token(access_token: str, endpoints: ZeppEndpoints, send: Send) -> ZeppSession:
    """Step 2 — access token in, app token and user id out."""
    form = zepp_wire.login_form(access_token, str(uuid.uuid4()))
    reply = _send(
        "the login",
        send,
        endpoints.login_url,
        zepp_wire.login_headers(),
        zepp_wire.encode_form(form),
    )
    if reply.status != 200:
        raise failures.zepp_api_changed("the login", f"HTTP {reply.status}")
    try:
        body = _object(reply)
    except ValueError:
        # The body is not quoted into the failure: on this host it is what holds the tokens.
        raise failures.zepp_api_changed("the login", "a reply that is not a JSON object") from None
    token_info = body.get("token_info")
    if not isinstance(token_info, dict):
        raise failures.zepp_api_changed("the login", "no token_info in the reply")
    app_token = token_info.get("app_token")
    user_id = token_info.get("user_id")
    if not isinstance(app_token, str) or not app_token:
        raise failures.zepp_api_changed("the login", "no app_token in the reply")
    if not isinstance(user_id, (str, int)) or isinstance(user_id, bool) or not str(user_id):
        raise failures.zepp_api_changed("the login", "no user_id in the reply")
    login_token = token_info.get("login_token")
    return ZeppSession(
        user_id=str(user_id),
        app_token=app_token,
        login_token=login_token if isinstance(login_token, str) and login_token else None,
        host_hints=tuple(_host_hints(body)),
    )


def _host_hints(body: dict) -> list[str]:
    """Region hosts the login reply names, with every token removed before scanning."""
    visible = {key: value for key, value in body.items() if key != "token_info"}
    return zepp_wire.api_hosts_in(json.dumps(visible))


def _object(reply: Response) -> dict:
    decoded = reply.json()
    if not isinstance(decoded, dict):
        raise ValueError("not an object")
    return decoded
