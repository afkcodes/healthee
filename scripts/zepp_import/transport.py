"""One HTTP request, standard library only, with the three properties this tool needs.

 * **No redirects.** Step 1 of the Zepp sign-in ANSWERS with a redirect whose `Location`
   carries the tokens; following it would send them to an S3 page. And every other call
   here carries a bearer credential that a 3xx would re-send to wherever `Location` names.
 * **No status raises.** Every status is a value the caller inspects, so each one maps to
   a named failure rather than to a generic exception.
 * **Nothing is logged.** Not the URL (query strings carry account ids), not headers, not
   bodies. A transport failure surfaces as a host and an error class name, both ours.

`Send` is the seam the tests use: every client in this package takes one.
"""

from __future__ import annotations

import http.client
import json
import urllib.error
import urllib.parse
import urllib.request
import zlib
from collections.abc import Callable, Mapping
from dataclasses import dataclass

DEFAULT_TIMEOUT_S = 30.0
# A workout detail is a few hundred kilobytes; this is a ceiling, not an expectation.
MAX_BODY_BYTES = 32 * 1024 * 1024
_TOO_LARGE = "response larger than expected"


# The failures a person can act on, in words. Anything else keeps its class name, which is
# ours to print: no part of a URL, header or body is ever in a `TransportError`.
_PLAIN_KINDS = {
    "gaierror": "the name does not resolve",
    "ConnectionRefusedError": "connection refused",
    "ConnectionResetError": "connection reset",
    "TimeoutError": "no answer in time",
    "timeout": "no answer in time",
    "SSLCertVerificationError": "its certificate could not be verified",
}


class TransportError(Exception):
    """The request never produced an HTTP status. Carries only the host and error class."""

    def __init__(self, host: str, kind: str) -> None:
        super().__init__(f"{host}: {kind}")
        self.host = host
        self.kind = kind


@dataclass(frozen=True)
class Response:
    """An HTTP reply. Header names are lower-cased."""

    status: int
    headers: Mapping[str, str]
    body: bytes

    def json(self) -> object:
        """The body as JSON. Raises `ValueError` when it is not."""
        return json.loads(self.body.decode("utf-8"))


Send = Callable[..., Response]


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *_args: object, **_kwargs: object) -> None:
        return None  # urllib then raises HTTPError, which `send` returns as a Response


def _opener() -> urllib.request.OpenerDirector:
    return urllib.request.build_opener(_NoRedirect())


def host_of(url: str) -> str:
    return urllib.parse.urlsplit(url).hostname or "?"


def _inflated(body: bytes, url: str) -> bytes:
    """A gzip body, decoded — to the same ceiling as a plain one, so it cannot be a bomb."""
    try:
        inflated = zlib.decompressobj(16 + zlib.MAX_WBITS).decompress(body, MAX_BODY_BYTES + 1)
    except zlib.error:
        raise TransportError(host_of(url), "a gzip body that does not decode") from None
    if len(inflated) > MAX_BODY_BYTES:
        raise TransportError(host_of(url), _TOO_LARGE)
    return inflated


def _read(raw: http.client.HTTPResponse | urllib.error.HTTPError, url: str) -> Response:
    body = raw.read(MAX_BODY_BYTES + 1)
    if len(body) > MAX_BODY_BYTES:
        raise TransportError(host_of(url), _TOO_LARGE)
    headers = {name.lower(): value for name, value in raw.headers.items()}
    if headers.get("content-encoding", "").lower() == "gzip":
        body = _inflated(body, url)
    status = raw.code if isinstance(raw, urllib.error.HTTPError) else raw.status
    return Response(status=status, headers=headers, body=body)


def send(
    method: str,
    url: str,
    *,
    headers: Mapping[str, str] | None = None,
    body: bytes | None = None,
    timeout_s: float = DEFAULT_TIMEOUT_S,
) -> Response:
    """Send one request and return whatever status came back. Raises `TransportError`."""
    request = urllib.request.Request(url, data=body, method=method, headers=dict(headers or {}))
    try:
        with _opener().open(request, timeout=timeout_s) as raw:
            return _read(raw, url)
    except urllib.error.HTTPError as reply:  # any non-2xx, including the 3xx we do not follow
        with reply:
            return _read(reply, url)
    except OSError as error:  # URLError, a timeout, a TLS failure, a reset: all are OSError
        reason = getattr(error, "reason", error)
        kind = type(reason).__name__
        raise TransportError(host_of(url), _PLAIN_KINDS.get(kind, kind)) from None
    except http.client.HTTPException as error:
        raise TransportError(host_of(url), type(error).__name__) from None


def get_json(send_: Send, url: str, headers: Mapping[str, str], timeout_s: float) -> Response:
    """GET expecting JSON. A convenience so callers do not repeat the Accept header."""
    return send_("GET", url, headers={"accept": "application/json", **headers}, timeout_s=timeout_s)


def post_json(
    send_: Send, url: str, payload: object, headers: Mapping[str, str], timeout_s: float
) -> Response:
    """POST a JSON body. `allow_nan=False`: a NaN is not a measurement (`ingest/models.py`)."""
    body = json.dumps(payload, allow_nan=False, separators=(",", ":")).encode("utf-8")
    merged = {"accept": "application/json", "content-type": "application/json", **headers}
    return send_("POST", url, headers=merged, body=body, timeout_s=timeout_s)
