"""Signing in to a Healthee server as its owner, and the one way requests are made to it.

The sign-in is the app's own (`apps/mobile/lib/data/auth/identity_client.dart`): ask the
server which identity provider it uses (`GET /api/auth-config`), give that provider the
owner's email and password, and carry the token it returns as the bearer on `/api/*`.

## Why the sign-in is also the version check

A partial workout push — `{start_ts, distance_m}`, to complete a stored row — is only safe
on a server whose upsert COALESCEs `sport` and `duration_s` (`ingest/upsert.py`, audit
B4); before that change the same push zeroed the stored duration. `/api/auth-config`
landed after it, and this tool cannot sign in without it. A server old enough to be harmed
therefore answers 404 here and is refused before anything is written.

## Where the password goes

To the provider the SERVER names, which is the trust the app already places in it. The
run prints that host before the password is asked for (`sign_in_host`), and anything but
https is refused unless it is this machine's own loopback.

## The server's reason is the one piece of foreign text that gets printed

A refusal is reported with the server's own short reason (`HealtheeSession.reason`). That
is text this tool did not write, so before it reaches a failure message every credential
this session has sent is cut out of it. Healthee does not echo credentials today; the
guarantee should not depend on that staying true.
"""

from __future__ import annotations

from dataclasses import dataclass

from zepp_import import failures
from zepp_import.healthee_rows import normalise_url
from zepp_import.transport import Response, Send, TransportError, get_json, host_of, post_json

TIMEOUT_S = 30.0
_DETAIL_CHARS = 160
_NO_REASON = "no reason given"
_REDACTED = "[redacted]"
# Shorter than this and "redacting" it would shred ordinary words in the server's reason.
_MIN_SECRET_CHARS = 6
_GATEWAY_STATUSES = (502, 503, 504)
_WRONG_CREDENTIAL_STATUSES = (400, 401, 403, 422)


@dataclass(frozen=True)
class Account:
    user_id: str
    timezone: str


def detail(reply: Response) -> str:
    """The server's own short reason, unredacted. Never the whole body.

    Callers print `HealtheeSession.reason`, not this: see the module docstring.
    """
    try:
        body = reply.json()
    except ValueError:
        return _NO_REASON
    if not isinstance(body, dict):
        return _NO_REASON
    for key in ("detail", "msg", "error_description", "message", "error_code", "error"):
        value = body.get(key)
        if isinstance(value, list) and value and isinstance(value[0], dict):
            value = f"{value[0].get('loc')}: {value[0].get('msg')}"
        if isinstance(value, str) and value:
            return value[:_DETAIL_CHARS]
    return _NO_REASON


class HealtheeSession:
    """One conversation with one Healthee server: unauthenticated until `sign_in`."""

    def __init__(self, base_url: str, send: Send) -> None:
        self.base_url = base_url
        self._send = send
        self._jwt = ""
        self._provider: tuple[str, str] | None = None
        self._sent_secrets: set[str] = set()

    def reason(self, reply: Response) -> str:
        """The server's short reason for a refusal, with this session's credentials cut out."""
        text = detail(reply)
        for secret in sorted(self._sent_secrets, key=len, reverse=True):
            if len(secret) >= _MIN_SECRET_CHARS:
                text = text.replace(secret, _REDACTED)
        return text

    def call(
        self,
        step: str,
        method: str,
        path: str,
        payload: object = None,
        *,
        bearer: str = "",
        timeout_s: float = TIMEOUT_S,
    ) -> Response:
        """One request. `bearer` replaces the owner's token (the ingest path takes its own)."""
        token = bearer or self._jwt
        self._sent_secrets.add(token)
        headers = {"authorization": f"Bearer {token}"} if token else {}
        url = f"{self.base_url}{path}"
        try:
            if method == "GET":
                return get_json(self._send, url, headers, timeout_s)
            if method == "DELETE":
                return self._send("DELETE", url, headers=headers, timeout_s=timeout_s)
            return post_json(self._send, url, payload, headers, timeout_s)
        except TransportError as error:
            raise failures.no_network(f"Healthee for {step}", error.host, error.kind) from None

    def decoded(self, step: str, reply: Response) -> object:
        """The JSON of a 200 reply. Every other status is a named failure."""
        if reply.status in _GATEWAY_STATUSES:
            raise failures.healthee_slow(step, reply.status)
        if reply.status != 200:
            raise failures.healthee_refused(step, reply.status, self.reason(reply))
        try:
            return reply.json()
        except ValueError:
            raise failures.healthee_refused(step, 200, "a reply that is not JSON") from None

    def object(self, step: str, reply: Response) -> dict:
        body = self.decoded(step, reply)
        if not isinstance(body, dict):
            raise failures.healthee_refused(step, 200, "a reply that is not a JSON object")
        return body

    def sign_in_host(self) -> str:
        """The host the owner's Healthee password will be sent to. Asked before it is typed."""
        reply = self.call("its sign-in settings", "GET", "/api/auth-config")
        host = host_of(self.base_url)
        if reply.status == 404:
            raise failures.healthee_too_old(host)
        if reply.status != 200:
            raise failures.healthee_not_healthee(host, f"HTTP {reply.status} from /api/auth-config")
        try:
            body = reply.json()
        except ValueError:
            body = None
        if not isinstance(body, dict) or "supabase_url" not in body:
            raise failures.healthee_not_healthee(host, "no sign-in settings in the reply")
        url, key = body.get("supabase_url"), body.get("supabase_anon_key")
        if not isinstance(url, str) or not isinstance(key, str) or not url or not key:
            raise failures.healthee_no_sign_in(host)
        provider_url = normalise_url(url, what="Healthee's sign-in service", allow_path=True)
        self._provider = (provider_url, key)
        return host_of(provider_url)

    def sign_in(self, email: str, password: str) -> Account:
        """Sign in as the owner and return who the server says that is."""
        if self._provider is None:
            self.sign_in_host()
        assert self._provider is not None
        self._jwt = self._provider_token(*self._provider, email, password)
        me = self.object("your sign-in", self.call("your sign-in", "GET", "/api/me"))
        user_id = me.get("id")
        if not isinstance(user_id, str) or not user_id:
            raise failures.healthee_refused("your sign-in", 200, "no account id in the reply")
        return Account(user_id=user_id, timezone=str(me.get("timezone") or "UTC"))

    def _provider_token(self, provider_url: str, anon_key: str, email: str, password: str) -> str:
        url = f"{provider_url}/auth/v1/token?grant_type=password"
        credentials = {"email": email, "password": password}
        self._sent_secrets.add(password)
        try:
            reply = post_json(self._send, url, credentials, {"apikey": anon_key}, TIMEOUT_S)
        except TransportError as error:
            raise failures.no_network(
                "Healthee's sign-in service", error.host, error.kind
            ) from None
        if reply.status in _WRONG_CREDENTIAL_STATUSES:
            raise failures.healthee_wrong_credentials(self.reason(reply))
        token = self.object("the sign-in", reply).get("access_token")
        if not isinstance(token, str) or not token:
            raise failures.healthee_refused("the sign-in", 200, "no access token in the reply")
        self._sent_secrets.add(token)
        return token
