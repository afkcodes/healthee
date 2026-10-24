"""One Zepp data call: what is retried, what is followed, and where the token may not go."""

from __future__ import annotations

import unittest

from zepp_import.failures import ZeppImportError
from zepp_import.tests import fixtures
from zepp_import.tests.fake_zepp import APP_TOKEN, HOME, USER_ID, FakeZepp
from zepp_import.tests.support import DAY_S, NOW_S, Net, json_reply
from zepp_import.transport import Response
from zepp_import.zepp_api import ZeppApi
from zepp_import.zepp_auth import ZeppSession
from zepp_import.zepp_history import ZeppHistory
from zepp_import.zepp_wire import HISTORY_PATH, ZeppEndpoints

SINCE_S = NOW_S - 30 * DAY_S
START = NOW_S - 3 * DAY_S


def busy(status: int = 429, retry_after: str | None = None) -> Response:
    headers = {"retry-after": retry_after} if retry_after else {}
    return Response(status, headers, b"{}")


class Base(unittest.TestCase):
    def setUp(self) -> None:
        self.zepp = FakeZepp("e", "p")
        self.zepp.add(fixtures.summary(START))
        self.net = Net([self.zepp])
        self.pauses: list[float] = []
        self.session = ZeppSession(user_id=USER_ID, app_token=APP_TOKEN)
        self.api = ZeppApi(self.session, self.net.send, pause=self.pauses.append)

    def history(self) -> ZeppHistory:
        return ZeppHistory(self.session, ZeppEndpoints(), self.net.send, pause=self.pauses.append)

    def get(self) -> dict | str:
        return self.api.get(HOME, HISTORY_PATH, {})


class Envelope(Base):
    def test_code_one_is_success_and_its_data_is_the_answer(self) -> None:
        data = self.get()
        assert isinstance(data, dict)
        self.assertEqual(len(data["summary"]), 1)

    def test_anything_else_is_a_note_in_this_tools_own_words(self) -> None:
        for forced, note in (
            (json_reply(200, {"code": 0, "message": "nope"}), "code 0"),
            (json_reply(200, {"code": "1", "data": {}}), "code str"),
            (json_reply(200, {"data": {}}), "code NoneType"),
            (json_reply(200, [1, 2]), "a reply that is not an object"),
            (Response(200, {}, b"<html>"), "a reply that is not JSON"),
            (
                json_reply(200, {"code": 1, "data": [1]}),
                "no data object in {code:int,data:[intx1]}",
            ),
            (json_reply(404, {}), "HTTP 404"),
            (json_reply(401, {}), "refused (HTTP 401)"),
        ):
            self.zepp.forced[HISTORY_PATH] = forced
            with self.subTest(note=note):
                self.assertEqual(self.get(), note)

    def test_every_request_carries_the_token_and_a_fresh_request_id(self) -> None:
        self.get()
        self.get()
        first, second = self.net.requests
        self.assertEqual(first.headers["apptoken"], APP_TOKEN)
        self.assertNotEqual(first.headers["x-request-id"], second.headers["x-request-id"])


class Retries(Base):
    def test_a_rate_limit_is_waited_out_for_as_long_as_zepp_asks(self) -> None:
        self.zepp.forced[HISTORY_PATH] = [busy(429, "7"), busy(503)]
        self.assertIsInstance(self.get(), dict)
        self.assertEqual(self.pauses, [7.0, 3.0])
        self.assertEqual(len(self.net.requests), 3)

    def test_a_wait_zepp_asks_for_is_capped(self) -> None:
        self.zepp.forced[HISTORY_PATH] = [busy(429, "3600")]
        self.get()
        self.assertEqual(self.pauses, [20.0])

    def test_it_gives_up_after_three_tries_and_says_busy(self) -> None:
        self.zepp.forced[HISTORY_PATH] = busy(429)
        self.assertEqual(self.get(), "busy (HTTP 429)")
        self.assertEqual((len(self.net.requests), self.pauses), (3, [1.0, 3.0]))

    def test_a_refused_token_is_not_retried(self) -> None:
        self.zepp.forced[HISTORY_PATH] = json_reply(403, {})
        self.get()
        self.assertEqual((len(self.net.requests), self.pauses), (1, []))

    def test_a_busy_zepp_is_named_as_busy_not_as_an_api_change(self) -> None:
        self.zepp.forced[HISTORY_PATH] = busy(429)
        with self.assertRaises(ZeppImportError) as raised:
            self.history().feed(SINCE_S, NOW_S)
        self.assertEqual(raised.exception.code, "zepp_busy")
        self.assertIn("Wait a few minutes", raised.exception.remedy)

    def test_a_busy_host_is_not_asked_again_in_the_other_style(self) -> None:
        self.zepp.forced[HISTORY_PATH] = busy(429)
        with self.assertRaises(ZeppImportError):
            self.history().feed(SINCE_S, NOW_S, HOME, named=True)
        self.assertEqual(len(self.net.requests), 3)  # three tries of one request


class Redirects(Base):
    def test_a_redirect_within_the_same_host_is_followed(self) -> None:
        moved = Response(302, {"location": f"{HISTORY_PATH}?moved=1"}, b"")
        self.zepp.forced[HISTORY_PATH] = [moved]
        self.assertIsInstance(self.get(), dict)
        self.assertEqual([r.origin for r in self.net.requests], [HOME, HOME])
        self.assertEqual(self.net.requests[1].query, {"moved": "1"})

    def test_a_redirect_loop_ends(self) -> None:
        self.zepp.forced[HISTORY_PATH] = Response(302, {"location": HISTORY_PATH}, b"")
        self.assertEqual(self.get(), "HTTP 302")
        self.assertEqual(len(self.net.requests), 4)

    def test_a_redirect_off_zepp_is_never_followed_with_the_token(self) -> None:
        for location in (
            "https://evil.example/v1/sport/run/history.json",
            "http://api-mifit-in.huami.com/v1/sport/run/history.json",
            "https://api-mifit.zepp.com.evil.example/x",
            "//evil.example/x",
        ):
            self.net.requests.clear()
            self.zepp.forced[HISTORY_PATH] = Response(302, {"location": location}, b"")
            with self.subTest(location=location):
                self.assertEqual(self.get(), "a redirect off Zepp's API (HTTP 302)")
                self.assertEqual([r.origin for r in self.net.requests], [HOME])
                self.assertEqual(self.api.redirected_to, [])

    def test_a_redirect_with_no_location_is_not_followed(self) -> None:
        self.zepp.forced[HISTORY_PATH] = Response(302, {}, b"")
        self.assertEqual(self.get(), "a redirect off Zepp's API (HTTP 302)")

    def test_a_redirect_to_another_zepp_host_is_a_lead_not_a_hop(self) -> None:
        target = "https://api-mifit-xx9.zepp.com"
        self.zepp.forced[HISTORY_PATH] = Response(302, {"location": f"{target}{HISTORY_PATH}"}, b"")
        self.assertEqual(self.get(), "redirected to api-mifit-xx9.zepp.com")
        self.assertEqual(self.api.redirected_to, [target])
        self.assertEqual([r.origin for r in self.net.requests], [HOME])

    def test_the_feed_asks_a_host_zepp_pointed_at_next(self) -> None:
        # The account lives on a host this tool has never heard of; every other host
        # says so with a redirect.
        self.zepp.home = "https://api-mifit-xx9.zepp.com"
        self.zepp.redirect_strangers = True
        feed = self.history().feed(SINCE_S, NOW_S)
        self.assertEqual(feed.host, "https://api-mifit-xx9.zepp.com")
        self.assertEqual(len(feed.records), 1)
        asked = list(dict.fromkeys(r.origin for r in self.net.requests))
        self.assertEqual(asked, ["https://api-mifit.zepp.com", "https://api-mifit-xx9.zepp.com"])

    def test_a_named_host_that_redirects_is_reported_not_left(self) -> None:
        self.zepp.home = "https://api-mifit-xx9.zepp.com"
        self.zepp.redirect_strangers = True
        with self.assertRaises(ZeppImportError) as raised:
            self.history().feed(SINCE_S, NOW_S, "https://api-mifit-sg2.huami.com", named=True)
        self.assertEqual(raised.exception.code, "zepp_elsewhere")
        self.assertIn("--zepp-host api-mifit-xx9.zepp.com", raised.exception.remedy)
        self.assertEqual({r.origin for r in self.net.requests}, {"https://api-mifit-sg2.huami.com"})


if __name__ == "__main__":
    unittest.main()
