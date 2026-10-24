"""A stand-in for the Zepp account API, as far as this tool uses it.

It answers on the REAL production URLs — the tests never reach them, because `support.Net`
intercepts every request — so the tool under test runs with its shipped endpoints.

The behaviours modelled are the ones the tool's design depends on:

 * step 1 answers with a 303 whose `Location` carries the tokens, and only when the body
   is exactly the AES-encrypted form for the right email and password;
 * a host for the wrong region accepts the token and returns a well-formed EMPTY list
   (or, with `redirect_strangers`, points at the right one);
 * the feed is newest-first, paged by a cursor, in two parameter styles, and the
   windowed style is bounded below by `startTrackId`.

`forced` replaces the reply for a path: with one `Response` for every call, or with a list
that is used up one call at a time and then gets out of the way.
"""

from __future__ import annotations

import urllib.parse
from dataclasses import dataclass, field

from zepp_import import zepp_wire
from zepp_import.aes_cbc import encrypt_cbc_pkcs7
from zepp_import.tests.support import Request, json_reply, sentinel
from zepp_import.transport import Response

ACCESS = sentinel("zepp-access")
APP_TOKEN = sentinel("zepp-app-token")
LOGIN_TOKEN = sentinel("zepp-login-token")
USER_ID = "7700112233"
HOME = "https://api-mifit-in.huami.com"
_ZEPP_ORIGINS = ("https://api-user-us2.zepp.com", "https://api-mifit")
_EMPTY_FEED = {"code": 1, "message": "success", "data": {"next": -1, "summary": []}}


@dataclass
class FakeZepp:
    email: str
    password: str
    home: str = HOME
    page_size: int = 3
    styles: tuple[str, ...] = ("windowed", "bare")
    inclusive_cursor: bool = False
    workouts: dict[int, dict] = field(default_factory=dict)
    details: dict[int, object] = field(default_factory=dict)
    login_extra: dict = field(default_factory=dict)
    forced: dict[str, Response | list[Response]] = field(default_factory=dict)
    redirect_strangers: bool = False
    # `weightRecords` items, any order; served newest first, `toTime` inclusive.
    weights: list[dict] = field(default_factory=list)
    weight_page: int = 200
    signed_out: int = 0
    sign_ins: int = 0

    def add(self, summary: dict, detail: object = None) -> None:
        track_id = int(str(summary["trackid"]))
        self.workouts[track_id] = summary
        if detail is not None:
            self.details[track_id] = detail

    def owns(self, origin: str) -> bool:
        return origin.startswith(_ZEPP_ORIGINS)

    def handle(self, request: Request) -> Response:
        forced = self.forced.get(request.path)
        if isinstance(forced, list) and forced:
            return forced.pop(0)
        if isinstance(forced, Response):
            return forced
        if request.url == zepp_wire.TOKENS_URL:
            return self._tokens(request)
        if request.url == zepp_wire.LOGIN_URL:
            return self._login(request)
        if request.url == zepp_wire.LOGOUT_URL:
            return self._logout(request)
        if request.headers.get("apptoken") != APP_TOKEN:
            return json_reply(401, {"code": 0, "message": "invalid token"})
        if request.path == zepp_wire.HISTORY_PATH:
            return self._history(request)
        if request.path == zepp_wire.DETAIL_PATH:
            return self._detail(request)
        if request.path == f"/users/{USER_ID}/members/-1/weightRecords":
            return self._weights(request)
        return json_reply(404, {"code": 0, "message": "not found"})

    def _tokens(self, request: Request) -> Response:
        expected = encrypt_cbc_pkcs7(
            zepp_wire.encode_form(zepp_wire.tokens_form(self.email, self.password)),
            key=zepp_wire.AES_KEY,
            iv=zepp_wire.AES_IV,
        )
        page = "https://s3-us-west-2.amazonaws.com/hm-registration/successsignin.html"
        if request.body != expected or request.headers.get("x-hm-ekv") != "1":
            return Response(303, {"location": f"{page}?error=401"}, b"")
        self.sign_ins += 1
        query = urllib.parse.urlencode({"access": ACCESS, "country_code": "US", "refresh": "r"})
        return Response(303, {"location": f"{page}?{query}"}, b"")

    def _login(self, request: Request) -> Response:
        form = dict(urllib.parse.parse_qsl((request.body or b"").decode()))
        if form.get("code") != ACCESS:
            return json_reply(401, {"error_code": "0102"})
        token_info = {"app_token": APP_TOKEN, "login_token": LOGIN_TOKEN, "user_id": USER_ID}
        return json_reply(200, {"result": "ok", "token_info": token_info, **self.login_extra})

    def _logout(self, request: Request) -> Response:
        form = dict(urllib.parse.parse_qsl((request.body or b"").decode()))
        if form.get("login_token") != LOGIN_TOKEN:
            return json_reply(401, {"result": "error"})
        self.signed_out += 1
        return json_reply(200, {"result": "ok"})

    def _history(self, request: Request) -> Response:
        query = request.query
        style = "windowed" if "userid" in query else "bare"
        if request.origin != self.home and self.redirect_strangers:
            return Response(302, {"location": request.url.replace(request.origin, self.home)}, b"")
        if request.origin != self.home or style not in self.styles:
            return json_reply(200, _EMPTY_FEED)
        raw_cursor = query.get("stopTrackId") if style == "windowed" else query.get("trackid")
        cursor = int(raw_cursor) if raw_cursor else None
        floor = int(query.get("startTrackId") or 0) if style == "windowed" else 0
        newest_first = [t for t in sorted(self.workouts, reverse=True) if t >= floor]
        if cursor is not None:
            newest_first = [
                t for t in newest_first if t < cursor or (self.inclusive_cursor and t == cursor)
            ]
        page = newest_first[: self.page_size]
        more = len(newest_first) > len(page)
        data = {"next": page[-1] if more else -1, "summary": [self.workouts[t] for t in page]}
        return json_reply(200, {"code": 1, "message": "success", "data": data})

    def _detail(self, request: Request) -> Response:
        if request.origin != self.home:
            return json_reply(200, {"code": 0, "message": "no data"})
        found = self.details.get(int(request.query.get("trackid", "0")))
        if isinstance(found, Response):
            return found
        if found is None:
            return json_reply(404, {"code": 0, "message": "not found"})
        return json_reply(200, {"code": 1, "message": "success", "data": found})

    def _weights(self, request: Request) -> Response:
        if request.origin != self.home:
            return json_reply(200, {"items": []})
        limit = min(int(request.query.get("limit", "20")), self.weight_page)
        to_time = request.query.get("toTime")
        newest_first = sorted(self.weights, key=lambda item: -item["generatedTime"])
        if to_time is not None:
            newest_first = [i for i in newest_first if i["generatedTime"] <= int(to_time)]
        page = newest_first[:limit]
        body: dict = {"items": page}
        if len(newest_first) > len(page):
            body["next"] = page[-1]["generatedTime"]
        return json_reply(200, body)
