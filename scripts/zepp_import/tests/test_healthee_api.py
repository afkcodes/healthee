"""Reading what Healthee holds, and writing under a credential that does not outlive the call."""

from __future__ import annotations

import unittest

from zepp_import.failures import ZeppImportError
from zepp_import.healthee_api import TOKEN_LEFT, HealtheeApi
from zepp_import.healthee_session import HealtheeSession
from zepp_import.tests.fake_healthee import ORIGIN, FakeHealthee
from zepp_import.tests.support import DAY_S, NOW_S, Net, json_reply, sentinel

EMAIL = "owner@example.com"
PASSWORD = sentinel("healthee-password")
START = NOW_S - 5 * DAY_S
ROUTE = {
    "client_id": "6281ebe0-319f-545b-a819-b03243014df3",
    "start_iso": "2026-10-06T06:26:40+00:00",
    "end_iso": "2026-10-06T06:57:40+00:00",
    "points": [[START + i * 5, 10.0 + i * 1e-5, 20.0, None] for i in range(12)],
}


class Base(unittest.TestCase):
    def setUp(self) -> None:
        self.healthee = FakeHealthee(EMAIL, PASSWORD)
        self.net = Net([self.healthee])
        session = HealtheeSession(ORIGIN, self.net.send)
        session.sign_in(EMAIL, PASSWORD)
        self.api = HealtheeApi(session)

    def failure(self, call: object, *args: object) -> ZeppImportError:
        with self.assertRaises(ZeppImportError) as raised:
            call(*args)  # type: ignore[operator]
        return raised.exception


class Reads(Base):
    def test_only_sessions_of_ten_minutes_or_more_are_listed(self) -> None:
        self.healthee.store_workout(START, sport=1, duration_s=1800, distance_m=5000.0)
        self.healthee.store_workout(START + 7200, sport=44, duration_s=599)
        rows = self.api.existing_workouts(NOW_S - 30 * DAY_S)
        self.assertEqual([(r.start_ms, r.sport) for r in rows], [(START * 1000, 1)])
        self.assertEqual(rows[0].lacks, {"calories", "avg_hr", "max_hr", "min_hr"})

    def test_more_than_one_page_of_history_is_read_without_a_gap(self) -> None:
        starts = [NOW_S - index * 6 * 3600 for index in range(1, 261)]  # 65 days, four a day
        for start in starts:
            self.healthee.store_workout(start, sport=1, duration_s=900)
        rows = self.api.existing_workouts(NOW_S - 60 * DAY_S)
        wanted = {s * 1000 for s in starts if s >= NOW_S - 60 * DAY_S}
        self.assertTrue(wanted <= {r.start_ms for r in rows})
        pages = [r for r in self.net.requests if r.path == "/api/activity"]
        self.assertGreaterEqual(len(pages), 3)
        self.assertTrue(all("day" in r.query for r in pages[1:]))

    def test_paging_never_asks_for_a_day_the_server_calls_the_future(self) -> None:
        for index in range(1, 261):
            self.healthee.store_workout(NOW_S - index * 6 * 3600, sport=1, duration_s=900)
        self.api.existing_workouts(NOW_S - 60 * DAY_S)  # a 422 would raise

    def test_paging_that_stops_making_progress_is_a_failure_not_a_short_list(self) -> None:
        page = {
            "date": "2026-10-11",
            "workouts": [
                {
                    "start_iso": f"2026-10-10T{h:02d}:{m:02d}:00+00:00",
                    "sport": 1,
                    "duration_min": 10,
                }
                for h in range(10)
                for m in range(0, 60, 6)
            ],
        }
        self.healthee.forced[("GET", "/api/activity")] = json_reply(200, page)
        failure = self.failure(self.api.existing_workouts, NOW_S - 60 * DAY_S)
        self.assertIn("paging made no progress", failure.headline)
        asked = [r for r in self.net.requests if r.path == "/api/activity"]
        self.assertEqual(len(asked), 2)  # the page, then the same page again: stop there

    def test_a_stored_workout_that_cannot_be_read_stops_the_run(self) -> None:
        row = {"start_iso": "11.10.2026 06:00", "sport": 1, "duration_min": 30}
        page = {"date": "2026-10-11", "workouts": [row]}
        self.healthee.forced[("GET", "/api/activity")] = json_reply(200, page)
        failure = self.failure(self.api.existing_workouts, NOW_S - 30 * DAY_S)
        self.assertEqual(failure.code, "healthee_unreadable")
        self.assertIn("the workout list", failure.headline)

    def test_a_workout_reply_with_no_list_is_not_read_as_an_empty_history(self) -> None:
        self.healthee.forced[("GET", "/api/activity")] = json_reply(200, {"date": "2026-10-11"})
        failure = self.failure(self.api.existing_workouts, NOW_S - 30 * DAY_S)
        self.assertEqual(failure.code, "healthee_unreadable")

    def test_a_stored_route_that_cannot_be_read_stops_the_run(self) -> None:
        listed = {"tracks": [{"track_id": "t", "start_ts": "x", "end_ts": "y"}]}
        self.healthee.forced[("GET", "/api/workout/gps")] = json_reply(200, listed)
        failure = self.failure(self.api.existing_tracks)
        self.assertEqual(failure.code, "healthee_unreadable")
        self.assertIn("the route list, and 1 of its 1 rows", failure.headline)

    def test_stored_routes_are_listed_with_their_window(self) -> None:
        track_id = self.healthee.store_track(START, START + 1860)
        tracks = self.api.existing_tracks()
        self.assertEqual(
            [(t.track_id, t.start_s, t.end_s) for t in tracks], [(track_id, START, START + 1860)]
        )
        self.assertEqual(self.net.requests[-1].query, {"limit": "100"})


class SummaryPush(Base):
    ROW = {
        "start_ts": START * 1000,
        "sport": 1,
        "duration_s": 1860,
        "calories": 296,
        "distance_m": 2701.0,
    }

    def test_summaries_are_pushed_under_a_token_minted_for_the_push_and_revoked_after(self) -> None:
        result = self.api.push_workouts([self.ROW])
        self.assertEqual((result.workouts, result.days_derived, result.token_revoked), (1, 1, True))
        self.assertEqual(self.healthee.workouts[START * 1000]["distance_m"], 2701.0)
        self.assertEqual(self.healthee.live_tokens(), [])
        token = next(iter(self.healthee.tokens.values()))
        self.assertEqual(token["label"], "zepp-import (temporary)")
        push = next(r for r in self.net.requests if r.path == "/ingest/helio")
        self.assertEqual(push.headers["authorization"], f"Bearer {token['token']}")

    def test_the_push_carries_workouts_and_nothing_that_could_reset_the_account(self) -> None:
        self.api.push_workouts([self.ROW])
        self.assertEqual(list(self.healthee.pushes[0]), ["workouts"])  # no timezone, no profile

    def test_a_large_import_goes_in_chunks_and_each_stored_chunk_is_reported(self) -> None:
        rows = [{**self.ROW, "start_ts": (START + i * 3600) * 1000} for i in range(60)]
        seen: list[int] = []
        result = self.api.push_workouts(rows, stored=lambda chunk: seen.append(len(chunk)))
        self.assertEqual((seen, result.workouts), ([25, 25, 10], 60))
        self.assertEqual(len(self.healthee.tokens), 1)

    def test_the_token_is_revoked_even_when_the_push_is_refused(self) -> None:
        failure = self.failure(self.api.push_workouts, [{**self.ROW, "duration_s": 10**9}])
        self.assertEqual(failure.code, "healthee_refused")
        self.assertIn("duration_s", failure.headline)
        self.assertEqual(self.healthee.live_tokens(), [])
        self.assertNotIn("could not be revoked", failure.remedy)

    def test_a_token_that_could_not_be_revoked_is_reported_not_hidden(self) -> None:
        real = self.healthee.handle

        def no_delete(request: object) -> object:
            if request.method == "DELETE":  # type: ignore[attr-defined]
                return json_reply(500, {"detail": "boom"})
            return real(request)  # type: ignore[arg-type]

        self.healthee.handle = no_delete  # type: ignore[method-assign]
        self.assertFalse(self.api.push_workouts([self.ROW]).token_revoked)
        failure = self.failure(self.api.push_workouts, [{**self.ROW, "duration_s": 10**9}])
        self.assertIn(TOKEN_LEFT, failure.remedy)

    def test_a_token_left_by_an_interrupted_run_is_revoked_by_the_next(self) -> None:
        self.net.send(
            "POST",
            f"{ORIGIN}/api/device",
            headers=self.net.requests[-1].headers,
            body=b'{"label":"zepp-import (temporary)"}',
        )
        self.net.send(
            "POST",
            f"{ORIGIN}/api/device",
            headers=self.net.requests[-1].headers,
            body=b'{"label":"My phone"}',
        )
        self.assertEqual(self.api.revoke_leftovers(), 1)
        self.assertEqual([t["label"] for t in self.healthee.live_tokens()], ["My phone"])

    def test_an_account_at_its_token_cap_is_told_what_to_do(self) -> None:
        for _ in range(10):
            self.net.send(
                "POST", f"{ORIGIN}/api/device", headers=self.net.requests[-1].headers, body=b"{}"
            )
        self.assertEqual(
            self.failure(self.api.push_workouts, [self.ROW]).code, "healthee_too_many_tokens"
        )
        self.assertNotIn(START * 1000, self.healthee.workouts)


class RoutePush(Base):
    def test_a_stored_route_comes_back_with_the_servers_fitness_verdict(self) -> None:
        self.healthee.scoring = {"ok": True, "vo2max_submax": 41.2, "method": "gps_graded"}
        verdict = self.api.push_track(ROUTE)
        self.assertEqual((verdict["ok"], verdict["points"]), (True, 12))
        self.assertEqual(verdict["vo2max"]["vo2max_submax"], 41.2)
        self.assertIn(ROUTE["client_id"], self.healthee.tracks)

    def test_sending_the_same_route_again_stores_nothing_new(self) -> None:
        self.api.push_track(ROUTE)
        again = self.api.push_track(ROUTE)
        self.assertEqual((again["ok"], again["vo2max"]), (True, None))
        self.assertEqual(len(self.healthee.tracks), 1)

    def test_a_route_the_server_refuses_is_a_verdict_so_the_run_goes_on(self) -> None:
        backwards = {**ROUTE, "points": list(reversed(ROUTE["points"]))}
        verdict = self.api.push_track(backwards)
        self.assertEqual(verdict["ok"], False)
        self.assertIn("HTTP 422", verdict["reason"])
        self.assertIn("timestamps must increase", verdict["reason"])

    def test_a_server_error_on_a_route_is_a_failure_because_the_next_would_fail_too(self) -> None:
        self.healthee.forced[("POST", "/api/workout/gps")] = json_reply(500, {"detail": "boom"})
        self.assertEqual(self.failure(self.api.push_track, ROUTE).code, "healthee_refused")
        self.healthee.forced[("POST", "/api/workout/gps")] = json_reply(504, {})
        self.assertEqual(self.failure(self.api.push_track, ROUTE).code, "healthee_slow")


if __name__ == "__main__":
    unittest.main()
