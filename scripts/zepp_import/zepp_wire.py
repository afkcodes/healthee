"""The Zepp account API on the wire: URLs, forms, headers and the hosts a token may go to.

## Where every value comes from

The sign-in half is transcribed from `apps/mobile/lib/data/pairing/zepp_endpoints.dart`,
which is itself transcribed from the `huami_token` reference this project has been running
against a real account. Standards section 5's porting rule applies: proven protocol code
is copied faithfully, not tidied. A field that looks redundant (`app_name` AND `appname`;
`token` sent twice) is redundant in the reference too, and Zepp's gateway rejects requests
that drop them. If Zepp changes the flow, change it THERE first and bring it here.

The workout half has no in-repo reference. Its paths and parameters are the ones two
independent open-source clients use against real accounts (see README, "Sources").

## Nothing here is a secret

The AES key and IV are fixed constants of the Zepp Android client, published in every
open-source implementation of this flow. They obfuscate the login payload in transit; they
do not protect it. What IS secret is the password they wrap and the tokens that come back,
and neither appears in this file.
"""

from __future__ import annotations

import re
import urllib.parse
from dataclasses import dataclass

TOKENS_URL = "https://api-user-us2.zepp.com/v2/registrations/tokens"
LOGIN_URL = "https://api-mifit-us2.zepp.com/v2/client/login"
LOGOUT_URL = "https://api-mifit-us2.zepp.com/v1/client/logout"

# The host the pairing flow reads the device list from, then the legacy name for it.
PRIMARY_API_HOSTS = ("https://api-mifit.zepp.com", "https://api-mifit.huami.com")

# Zepp keeps an account's data in one region and a host for another region answers with
# a well-formed EMPTY list rather than an error. These are tried, in this order, only when
# the primary hosts hold nothing for the account. Every host here, and both above, was
# answering the workout path on 2026-10-11 (a 401 for a made-up token).
REGION_API_HOSTS = (
    "https://api-mifit-us2.zepp.com",
    "https://api-mifit-in.huami.com",
    "https://api-mifit-sg2.huami.com",
    "https://api-mifit-sg.huami.com",
    "https://api-mifit-us3.zepp.com",
    "https://api-mifit-us2.huami.com",
    "https://api-mifit-us.huami.com",
    "https://api-mifit-de2.huami.com",
    "https://api-mifit-de.zepp.com",
    "https://api-mifit-de.huami.com",
    "https://api-mifit-ru.huami.com",
)

HISTORY_PATH = "/v1/sport/run/history.json"  # the account-wide feed, despite "run"
DETAIL_PATH = "/v1/sport/run/detail.json"

AES_KEY = b"xeNtBVqzDc6tuNTh"
AES_IV = b"MAAAYAAAAAAAAABg"

_CHANNEL = "a100900101016"
_APP_VERSION = "9.12.5"
_CLIENT_VERSION = f"151689_{_APP_VERSION}"
_BUILD_STAMP = "202509151347"
_USER_AGENT = f"Zepp/{_APP_VERSION} (Pixel 4; Android 12; Density/2.75)"
_FORM_CONTENT_TYPE = "application/x-www-form-urlencoded; charset=UTF-8"

_API_HOST_RE = re.compile(r"api-mifit[a-z0-9-]*\.(?:zepp|huami)\.com")


@dataclass(frozen=True)
class ZeppEndpoints:
    """Where the Zepp calls go. The defaults are production; tests pass their own."""

    tokens_url: str = TOKENS_URL
    login_url: str = LOGIN_URL
    logout_url: str = LOGOUT_URL
    primary_hosts: tuple[str, ...] = PRIMARY_API_HOSTS
    region_hosts: tuple[str, ...] = REGION_API_HOSTS


def api_hosts_in(text: str) -> list[str]:
    """Every Zepp API origin named anywhere in `text`, first appearance first.

    The login reply names the account's region host in fields whose names have changed
    between app versions, so the reply is scanned for the one shape that has not: a
    hostname. Only `api-mifit*.zepp.com` / `api-mifit*.huami.com` can match, which is also
    what keeps a token from ever being sent to a host a response merely mentions.
    """
    seen: list[str] = []
    for match in _API_HOST_RE.finditer(text.lower()):
        origin = f"https://{match.group(0)}"
        if origin not in seen:
            seen.append(origin)
    return seen


def checked_api_host(value: str) -> str:
    """A user-supplied `--zepp-host` as an origin, or `ValueError`. Bare names get https."""
    host = value.strip().lower().removeprefix("https://").rstrip("/")
    if not _API_HOST_RE.fullmatch(host):
        raise ValueError("expected a host like api-mifit-in.huami.com")
    return f"https://{host}"


def is_api_host(origin: str) -> bool:
    """Whether `origin` is exactly an https Zepp API origin: the only kind a token goes to."""
    return origin.startswith("https://") and bool(
        _API_HOST_RE.fullmatch(origin.removeprefix("https://"))
    )


def encode_form(fields: list[tuple[str, str]]) -> bytes:
    """Url-encode ordered pairs exactly as the reference does (`urlencode`, `quote_plus`).

    Pairs rather than a dict because `token` legitimately appears twice in step 1's body,
    and because the order is part of what Zepp is fed.
    """
    return urllib.parse.urlencode(fields).encode("ascii")


def tokens_form(email: str, password: str) -> list[tuple[str, str]]:
    """Step 1's body, before encryption. Built, encrypted and dropped by the caller."""
    return [
        ("emailOrPhone", email),
        ("state", "REDIRECTION"),
        ("client_id", "HuaMi"),
        ("password", password),
        ("redirect_uri", "https://s3-us-west-2.amazonaws.com/hm-registration/successsignin.html"),
        ("region", "us-west-2"),
        ("token", "access"),  # sent twice on purpose — the reference's `doseq=True`
        ("token", "refresh"),
        ("country_code", "US"),
    ]


def login_form(access_token: str, device_id: str) -> list[tuple[str, str]]:
    """Step 2's body. `device_id` is a fresh random UUID per sign-in, as the reference."""
    return [
        ("code", access_token),
        ("device_id", device_id),
        ("device_model", "android_phone"),
        ("app_version", _APP_VERSION),
        (
            "dn",
            "api-mifit.zepp.com,api-user.zepp.com,api-mifit.zepp.com,api-watch.zepp.com,"
            "app-analytics.zepp.com,auth.zepp.com,api-analytics.zepp.com",
        ),
        ("third_name", "huami"),
        ("source", f"com.huami.watch.hmwatchmanager:{_APP_VERSION}:151689"),
        ("app_name", "com.huami.midong"),
        ("country_code", "US"),
        ("grant_type", "access_token"),
        ("allow_registration", "false"),
        ("lang", "en"),
        ("countryState", "US-NY"),
    ]


def tokens_headers() -> dict[str, str]:
    """Step 1. `x-hm-ekv: 1` is what tells the gateway the body is encrypted."""
    return {
        "app_name": "com.huami.midong",
        "appname": "com.huami.midong",
        "cv": _CLIENT_VERSION,
        "v": "2.0",
        "appplatform": "android_phone",
        "vb": _BUILD_STAMP,
        "vn": _APP_VERSION,
        "user-agent": _USER_AGENT,
        "x-hm-ekv": "1",
        "content-type": _FORM_CONTENT_TYPE,
    }


def login_headers() -> dict[str, str]:
    """Step 2. The reference sends browser headers here, not Android ones."""
    return {
        "app_name": "com.huami.webapp",
        "appname": "com.huami.webapp",
        "origin": "https://user.zepp.com",
        "referer": "https://user.zepp.com/",
        "user-agent": "Mozilla/5.0 (X11; Linux x86_64; rv:133.0) Gecko/20100101 Firefox/133.0",
        "content-type": _FORM_CONTENT_TYPE,
        "accept": "application/json, text/plain, */*",
        "accept-language": "en-US,en;q=0.5",
    }


def logout_headers() -> dict[str, str]:
    return {
        "app_name": "com.huami.midong",
        "appname": "com.huami.midong",
        "hm-privacy-ceip": "false",
        "accept-language": "en-US",
        "cv": _CLIENT_VERSION,
        "v": "2.0",
        "appplatform": "android_phone",
        "vb": _BUILD_STAMP,
        "vn": _APP_VERSION,
        "user-agent": _USER_AGENT,
        "content-type": _FORM_CONTENT_TYPE,
    }


def api_headers(app_token: str, request_id: str) -> dict[str, str]:
    """Data calls. The same set the pairing flow's device-list read sends.

    `hm-privacy-ceip` is Zepp's telemetry opt-in. It is `false` here for the reason
    `zepp_endpoints.dart` gives: this exists so health data stays on the owner's hardware.
    """
    return {
        "hm-privacy-diagnostics": "false",
        "hm-privacy-ceip": "false",
        "country": "US",
        "appplatform": "android_phone",
        "x-request-id": request_id,
        "timezone": "UTC",
        "channel": _CHANNEL,
        "vb": _BUILD_STAMP,
        "cv": _CLIENT_VERSION,
        "appname": "com.huami.midong",
        "v": "2.0",
        "vn": _APP_VERSION,
        "apptoken": app_token,
        "lang": "en_US",
        "user-agent": _USER_AGENT,
    }
