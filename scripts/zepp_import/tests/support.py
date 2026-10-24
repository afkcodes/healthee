"""Shared test plumbing: a network made of fakes, behind the `transport.Send` seam."""

from __future__ import annotations

import json
import urllib.parse
from collections.abc import Mapping, Sequence
from dataclasses import dataclass, field
from typing import Protocol

from zepp_import.transport import Response, TransportError, host_of

# 2026-10-11T06:26:40Z. Every test clock starts here.
NOW_S = 1_791_700_000
DAY_S = 86_400


def sentinel(name: str) -> str:
    """A recognisable stand-in for a secret, so a leak is findable by searching for it."""
    return f"SENTINEL-{name}-9f3c"


@dataclass(frozen=True)
class Request:
    method: str
    url: str
    headers: Mapping[str, str]
    body: bytes | None

    @property
    def origin(self) -> str:
        parts = urllib.parse.urlsplit(self.url)
        return f"{parts.scheme}://{parts.netloc}"

    @property
    def path(self) -> str:
        return urllib.parse.urlsplit(self.url).path

    @property
    def query(self) -> dict[str, str]:
        return dict(urllib.parse.parse_qsl(urllib.parse.urlsplit(self.url).query, True))

    def everything(self) -> str:
        """All of the request as text: what a secrecy test searches."""
        body = (self.body or b"").decode("utf-8", "replace")
        return f"{self.method} {self.url} {dict(self.headers)} {body}"


class Service(Protocol):
    def owns(self, origin: str) -> bool: ...

    def handle(self, request: Request) -> Response: ...


@dataclass
class Net:
    """The `Send` the tests hand out: routes by origin, and remembers every request."""

    services: Sequence[Service]
    requests: list[Request] = field(default_factory=list)
    down: set[str] = field(default_factory=set)

    def send(
        self,
        method: str,
        url: str,
        *,
        headers: Mapping[str, str] | None = None,
        body: bytes | None = None,
        timeout_s: float = 30.0,
    ) -> Response:
        del timeout_s
        request = Request(method, url, {k.lower(): v for k, v in (headers or {}).items()}, body)
        self.requests.append(request)
        if request.origin in self.down:
            raise TransportError(host_of(url), "ConnectionRefusedError")
        for service in self.services:
            if service.owns(request.origin):
                return service.handle(request)
        raise TransportError(host_of(url), "gaierror")

    def to(self, origin_part: str) -> list[Request]:
        return [request for request in self.requests if origin_part in request.origin]


def json_reply(status: int, payload: object) -> Response:
    return Response(status, {"content-type": "application/json"}, json.dumps(payload).encode())
