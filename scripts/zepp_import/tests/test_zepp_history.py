"""Reading the workout feed: finding the account's host, paging, and saying what went wrong."""

from __future__ import annotations

import unittest

from zepp_import.failures import ZeppImportError
from zepp_import.tests import fixtures
from zepp_import.tests.fake_zepp import APP_TOKEN, HOME, USER_ID, FakeZepp
from zepp_import.tests.support import DAY_S, NOW_S, Net, json_reply, sentinel
from zepp_import.zepp_auth import ZeppSession
from zepp_import.zepp_history import ZeppHistory
from zepp_import.zepp_wire import DETAIL_PATH, HISTORY_PATH, ZeppEndpoints

SINCE_S = NOW_S - 30 * DAY_S
STARTS = [NOW_S - day * DAY_S for day in (1, 3, 5, 8, 13, 21, 29, 34, 55)]  # two are too old


def _host(origin: str) -> str:
    return origin.removeprefix("https://")


class Feed(unittest.TestCase):
    def setUp(self) -> None:
        self.zepp = FakeZepp("e", "p", page_size=3)
        for start in STARTS:
            self.zepp.add(fixtures.summary(start))
        self.net = Net([self.zepp])
        self.notes: list[str] = []
        self.traces: list[str] = []

    def history(self, session: ZeppSession | None = None) -> ZeppHistory:
        session = session or ZeppSession(user_id=USER_ID, app_token=APP_TOKEN)
        return ZeppHistory(
            session, ZeppEndpoints(), self.net.send, self.notes.append, self.traces.append
        )

    def failure(self, first_host: str | None = None, named: bool = False) -> ZeppImportError:
        with self.assertRaises(ZeppImportError) as raised:
            self.history().feed(SINCE_S, NOW_S, first_host, named=named)
        return raised.exception

    def starts(self, feed: object) -> list[int]:
        return [int(record["trackid"]) for record in feed.records]  # type: ignore[attr-defined]

    def test_every_workout_in_the_window_newest_first_and_none_outside_it(self) -> None:
        feed = self.history().feed(SINCE_S, NOW_S)
        self.assertEqual(self.starts(feed), STARTS[:7])
        self.assertEqual(feed.host, HOME)

    def test_an_empty_answer_from_the_wrong_region_is_not_believed(self) -> None:
        feed = self.history().feed(SINCE_S, NOW_S)
        self.assertEqual(len(feed.records), 7)
        self.assertEqual([line.split(": ")[1] for line in feed.tried], ["no workouts"] * 3)
        asked = [note.removeprefix("asking ") for note in self.notes]
        self.assertEqual(asked[-1], _host(HOME))
        self.assertEqual(asked[:2], ["api-mifit.zepp.com", "api-mifit.huami.com"])

    def test_the_token_stops_at_the_first_host_that_has_the_workouts(self) -> None:
        self.history().feed(SINCE_S, NOW_S)
        asked = {request.origin for request in self.net.requests}
        self.assertIn(HOME, asked)
        self.assertNotIn("https://api-mifit-sg2.huami.com", asked)
        self.assertNotIn("https://api-mifit-ru.huami.com", asked)

    def test_a_remembered_host_is_asked_first_and_alone_when_it_answers(self) -> None:
        self.history().feed(SINCE_S, NOW_S, HOME)
        self.assertEqual({request.origin for request in self.net.requests}, {HOME})

    def test_a_remembered_host_that_has_gone_empty_does_not_end_the_search(self) -> None:
        self.zepp.home = "https://api-mifit-de2.huami.com"
        feed = self.history().feed(SINCE_S, NOW_S, HOME)
        self.assertEqual(feed.host, "https://api-mifit-de2.huami.com")

    def test_a_host_the_owner_named_is_the_only_one_asked_and_its_empty_answer_is_final(
        self,
    ) -> None:
        feed = self.history().feed(SINCE_S, NOW_S, "https://api-mifit-sg2.huami.com", named=True)
        self.assertEqual(feed.records, ())
        self.assertEqual({r.origin for r in self.net.requests}, {"https://api-mifit-sg2.huami.com"})

    def test_a_named_host_that_fails_does_not_send_the_token_anywhere_else(self) -> None:
        named = "https://api-mifit-sg2.huami.com"
        self.net.down.add(named)
        failure = self.failure(first_host=named, named=True)
        self.assertEqual(failure.code, "no_network")
        self.assertEqual({request.origin for request in self.net.requests}, {named})

    def test_a_hint_from_the_login_reply_is_tried_before_the_defaults(self) -> None:
        session = ZeppSession(user_id=USER_ID, app_token=APP_TOKEN, host_hints=(HOME,))
        self.history(session).feed(SINCE_S, NOW_S)
        self.assertEqual({request.origin for request in self.net.requests}, {HOME})

    def test_either_parameter_style_works(self) -> None:
        for styles in (("windowed",), ("bare",)):
            self.zepp.styles = styles
            with self.subTest(styles=styles):
                self.assertEqual(self.starts(self.history().feed(SINCE_S, NOW_S, HOME)), STARTS[:7])

    def test_a_session_without_a_user_id_uses_the_bare_style_only(self) -> None:
        pasted = ZeppSession(user_id="", app_token=APP_TOKEN)
        self.assertEqual(self.starts(self.history(pasted).feed(SINCE_S, NOW_S, HOME)), STARTS[:7])
        self.assertTrue(all("userid" not in request.query for request in self.net.requests))

    def test_paging_survives_a_cursor_that_repeats_its_last_record(self) -> None:
        self.zepp.inclusive_cursor = True
        self.assertEqual(self.starts(self.history().feed(SINCE_S, NOW_S, HOME)), STARTS[:7])

    def test_paging_stops_once_the_window_is_covered(self) -> None:
        for start in range(NOW_S - 400 * DAY_S, NOW_S - 300 * DAY_S, DAY_S):
            self.zepp.add(fixtures.summary(start))
        self.history().feed(SINCE_S, NOW_S, HOME)
        pages = [r for r in self.net.requests if r.path == HISTORY_PATH]
        self.assertEqual(len(pages), 3)  # 7 in the window, in pages of 3

    def test_the_account_wide_style_is_stopped_here_because_zepp_will_not_stop_it(self) -> None:
        # The bare style has no lower bound, so a hundred sessions from last year are all
        # on offer. The window is covered by the third page; nothing older is asked for.
        self.zepp.styles = ("bare",)
        for start in range(NOW_S - 400 * DAY_S, NOW_S - 300 * DAY_S, DAY_S):
            self.zepp.add(fixtures.summary(start))
        feed = self.history().feed(SINCE_S, NOW_S, HOME)
        self.assertEqual(self.starts(feed), STARTS[:7])
        bare = [r for r in self.net.requests if r.path == HISTORY_PATH and "userid" not in r.query]
        self.assertEqual(len(bare), 3)

    def test_the_windowed_style_asks_zepp_for_the_window_itself(self) -> None:
        self.history().feed(SINCE_S, NOW_S, HOME)
        first = next(r for r in self.net.requests if r.path == HISTORY_PATH)
        self.assertEqual(
            first.query,
            {
                "userid": USER_ID,
                "startTrackId": str(SINCE_S),
                "stopTrackId": str(NOW_S),
                "need_sub_data": "1",
                "type": "",
            },
        )

    def test_no_workouts_anywhere_says_which_hosts_were_asked(self) -> None:
        self.zepp.workouts.clear()
        failure = self.failure()
        self.assertEqual(failure.code, "zepp_no_workouts")
        self.assertIn("api-mifit-in.huami.com: no workouts", failure.remedy)
        self.assertIn("--zepp-host", failure.remedy)

    def test_a_token_refused_everywhere_is_not_reported_as_no_workouts(self) -> None:
        stale = ZeppSession(user_id=USER_ID, app_token=sentinel("stale-token"))
        with self.assertRaises(ZeppImportError) as raised:
            self.history(stale).feed(SINCE_S, NOW_S)
        self.assertEqual(raised.exception.code, "zepp_token_refused")
        self.assertNotIn("SENTINEL", raised.exception.headline + raised.exception.remedy)

    def test_a_refusing_host_is_asked_once_not_once_per_style(self) -> None:
        stale = ZeppSession(user_id=USER_ID, app_token="stale")
        with self.assertRaises(ZeppImportError):
            self.history(stale).feed(SINCE_S, NOW_S)
        per_host = [r.origin for r in self.net.requests].count(HOME)
        self.assertEqual(per_host, 1)

    def test_zepp_unreachable_everywhere_is_a_network_failure(self) -> None:
        endpoints = ZeppEndpoints()
        self.net.down.update((*endpoints.primary_hosts, *endpoints.region_hosts))
        self.assertEqual(self.failure().code, "no_network")

    def test_a_reply_this_cannot_read_names_its_shape_and_no_value(self) -> None:
        odd = {"code": 1, "message": "ok", "data": {"items": [fixtures.summary(STARTS[0])]}}
        self.zepp.forced[HISTORY_PATH] = json_reply(200, odd)
        failure = self.failure()
        self.assertEqual(failure.code, "zepp_api_changed")
        self.assertIn("no data.summary list in {items:[{", failure.headline)
        self.assertNotIn(str(STARTS[0]), failure.headline)
        self.assertIn("--verbose", failure.remedy)

    def test_an_error_code_is_reported_as_a_code(self) -> None:
        self.zepp.forced[HISTORY_PATH] = json_reply(200, {"code": -1, "message": sentinel("msg")})
        failure = self.failure()
        self.assertIn("code -1", failure.headline)
        self.assertNotIn("SENTINEL", failure.headline + failure.remedy)

    def test_a_failure_on_an_older_page_is_not_a_short_history(self) -> None:
        self.zepp.page_size = 2
        calls = {"n": 0}
        real = self.zepp._history

        def flaky(request: object) -> object:
            calls["n"] += 1
            return json_reply(500, {}) if calls["n"] > 2 else real(request)  # type: ignore[arg-type]

        self.zepp._history = flaky  # type: ignore[method-assign]
        failure = self.failure(first_host=HOME)
        self.assertEqual(failure.code, "zepp_busy")

    def test_an_older_page_that_makes_no_sense_is_an_api_change(self) -> None:
        self.zepp.page_size = 2
        self.zepp.forced[HISTORY_PATH] = [
            json_reply(
                200,
                {
                    "code": 1,
                    "data": {
                        "next": STARTS[1],
                        "summary": [fixtures.summary(s) for s in STARTS[:2]],
                    },
                },
            ),
            json_reply(200, {"code": 1, "data": {"next": 5, "rows": []}}),
        ]
        failure = self.failure(first_host=HOME)
        self.assertEqual(failure.code, "zepp_api_changed")
        self.assertIn("an older page", failure.headline)


class Detail(unittest.TestCase):
    def setUp(self) -> None:
        self.zepp = FakeZepp("e", "p")
        self.zepp.add(fixtures.summary(STARTS[0]), fixtures.detail(STARTS[0]))
        self.net = Net([self.zepp])
        self.traces: list[str] = []
        session = ZeppSession(user_id=USER_ID, app_token=APP_TOKEN)
        self.history = ZeppHistory(
            session, ZeppEndpoints(), self.net.send, trace=self.traces.append
        )

    def test_a_detail_is_asked_for_by_track_id_and_source(self) -> None:
        detail = self.history.detail(HOME, STARTS[0], fixtures.SOURCE)
        assert isinstance(detail, dict)
        self.assertIn("longitude_latitude", detail)
        query = self.net.requests[-1].query
        self.assertEqual((query["trackid"], query["source"]), (str(STARTS[0]), fixtures.SOURCE))

    def test_a_detail_zepp_does_not_have_is_a_note_not_a_failure(self) -> None:
        self.assertEqual(self.history.detail(HOME, 123, fixtures.SOURCE), "HTTP 404")
        self.zepp.forced[DETAIL_PATH] = json_reply(200, {"code": 0, "message": "no"})
        self.assertEqual(self.history.detail(HOME, STARTS[0], fixtures.SOURCE), "code 0")

    def test_a_source_that_is_not_an_id_is_never_sent(self) -> None:
        before = len(self.net.requests)
        note = self.history.detail(HOME, STARTS[0], "x&trackid=1 or 1=1")
        self.assertEqual(note, "its record has no usable source id")
        self.assertEqual(len(self.net.requests), before)

    def test_a_trace_is_a_shape_with_no_coordinate_in_it(self) -> None:
        self.history.detail(HOME, STARTS[0], fixtures.SOURCE)
        self.assertEqual(len(self.traces), 1)
        self.assertIn("longitude_latitude:str[;x121 like 9,9]", self.traces[0])
        self.assertNotIn(str(fixtures.START_LAT_E8), self.traces[0])
        self.assertNotIn(APP_TOKEN, self.traces[0])


if __name__ == "__main__":
    unittest.main()
