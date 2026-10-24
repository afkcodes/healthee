"""One authenticated GET against a Zepp data host, and what its reply means.

Every data call goes through `ZeppApi.get`, which answers with the reply's `data` object
or with a short NOTE saying why there is none. A note is made of words this tool chose —
a status, a code, a shape — and never of anything Zepp sent, so it can be printed.

## What a reply can be

 * **`{code: 1, message, data}`** is success. That envelope and that code are what a
   store of over a thousand real workout replies held without exception (README,
   "Sources"). Any other code is reported as a code, never read as "no data".
 * **401 / 403**: the token is not accepted here. Not retried.
 * **429 / 5xx**: Zepp is limiting or failing. Retried a little, waiting as long as
   `Retry-After` asks (to a ceiling), because hammering a rate limiter extends it.
 * **3xx**: followed only within the same host. A redirect to ANOTHER Zepp API host is
   not followed with the token; the host is remembered (`redirected_to`) so the caller
   can decide to ask it. A redirect anywhere else is refused: the token is a bearer
   credential and `Location` is whatever the reply says it is.
"""

from __future__ import annotations

import urllib.parse
import uuid
from collections.abc import Callable

from zepp_import import zepp_wire
from zepp_import.shapes import shape
from zepp_import.transport import Response, Send, TransportError, get_json, host_of
from zepp_import.zepp_auth import ZeppSession

TIMEOUT_S = 30.0
_SUCCESS_CODE = 1
_NOTE_SHAPE_CHARS = 200
_MAX_ATTEMPTS = 3
_MAX_REDIRECTS = 3
_BACKOFF_S = (1.0, 3.0)
_MAX_RETRY_AFTER_S = 20.0
_RETRY_STATUSES = frozenset({429, 500, 502, 503, 504})
UNREACHABLE, REFUSED, BUSY, REDIRECTED = "unreachable", "refused", "busy", "redirected to "
Notify = Callable[[str], None]


def _origin(url: str) -> str:
    parts = urllib.parse.urlsplit(url)
    return f"{parts.scheme}://{parts.netloc}"


def _code(value: object) -> str:
    """Zepp's reply code for a note: a number as itself, anything else as its type."""
    if isinstance(value, int) and not isinstance(value, bool):
        return str(value)
    return type(value).__name__


def _wait_s(reply: Response, attempt: int) -> float:
    """How long to wait before trying again: what Zepp asked for, within a ceiling."""
    asked = reply.headers.get("retry-after", "").strip()
    if asked.isdigit():
        return min(float(asked), _MAX_RETRY_AFTER_S)
    return _BACKOFF_S[min(attempt, len(_BACKOFF_S) - 1)]


class ZeppApi:
    """The data calls of one signed-in session. Holds the token; prints none of it."""

    def __init__(
        self,
        session: ZeppSession,
        send: Send,
        *,
        pause: Callable[[float], None],
        trace: Notify = lambda _line: None,
    ) -> None:
        self._session = session
        self._send = send
        self._pause = pause
        self._trace = trace
        self.redirected_to: list[str] = []

    def get(
        self, host: str, path: str, params: dict[str, object], timeout_s: float = TIMEOUT_S
    ) -> dict | str:
        """The `data` object of a successful reply, or a note on why there is none."""
        body = self.get_body(host, path, params, timeout_s)
        if isinstance(body, str):
            return body
        if body.get("code") != _SUCCESS_CODE:
            return f"code {_code(body.get('code'))}"
        data = body.get("data")
        if isinstance(data, dict):
            return data
        return f"no data object in {shape(body, _NOTE_SHAPE_CHARS)}"

    def get_body(
        self, host: str, path: str, params: dict[str, object], timeout_s: float = TIMEOUT_S
    ) -> dict | str:
        """The whole JSON object of a 200 reply, or a note. For the few endpoints that
        answer without the `{code, data}` envelope (the weight log is one)."""
        query = urllib.parse.urlencode(params)
        reply = self._fetch(f"{host}{path}{'?' + query if query else ''}", timeout_s)
        if isinstance(reply, str):
            return reply
        try:
            body = reply.json()
        except ValueError:
            return "a reply that is not JSON"
        self._trace(f"{host_of(host)}{path}: {shape(body)}")
        if not isinstance(body, dict):
            return "a reply that is not an object"
        return body

    def _fetch(self, url: str, timeout_s: float) -> Response | str:
        """A 200 reply, or a note. Retries what is worth retrying; follows what is safe."""
        attempt = redirects = 0
        while True:
            headers = zepp_wire.api_headers(self._session.app_token, str(uuid.uuid4()))
            try:
                reply = get_json(self._send, url, headers, timeout_s)
            except TransportError as error:
                return f"{UNREACHABLE} ({error.kind})"
            if reply.status == 200:
                return reply
            if reply.status in (401, 403):
                return f"{REFUSED} (HTTP {reply.status})"
            if 300 <= reply.status < 400 and redirects < _MAX_REDIRECTS:
                moved = self._same_host_target(url, reply)
                if isinstance(moved, tuple):
                    return moved[0]
                url, redirects = moved, redirects + 1
                continue
            if reply.status not in _RETRY_STATUSES:
                return f"HTTP {reply.status}"
            attempt += 1
            if attempt >= _MAX_ATTEMPTS:
                return f"{BUSY} (HTTP {reply.status})"
            self._pause(_wait_s(reply, attempt - 1))

    def _same_host_target(self, url: str, reply: Response) -> str | tuple[str]:
        """Where a redirect may be followed to, or a one-tuple holding the note that ends it."""
        location = reply.headers.get("location", "")
        target = urllib.parse.urljoin(url, location) if location else ""
        if target and _origin(target) == _origin(url):
            return target
        if target and zepp_wire.is_api_host(_origin(target)):
            if _origin(target) not in self.redirected_to:
                self.redirected_to.append(_origin(target))
            return (f"{REDIRECTED}{host_of(target)}",)
        return (f"a redirect off Zepp's API (HTTP {reply.status})",)
