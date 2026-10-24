"""From a Zepp feed to a plan: what is fetched, in what order, and what is said when it fails."""

from __future__ import annotations

import unittest

from zepp_import.failures import ZeppImportError
from zepp_import.gather import Gatherer, Stored, plan_summaries, read_workouts
from zepp_import.healthee_rows import ExistingWorkout
from zepp_import.plan import StoredTracks, Verdict
from zepp_import.tests import fixtures
from zepp_import.tests.fake_zepp import APP_TOKEN, HOME, USER_ID, FakeZepp
from zepp_import.tests.support import DAY_S, NOW_S, Net, json_reply
from zepp_import.zepp_auth import ZeppSession
from zepp_import.zepp_history import Feed, ZeppHistory
from zepp_import.zepp_parse import parse_summary
from zepp_import.zepp_wire import DETAIL_PATH, ZeppEndpoints

OWNER = "0b1e6f0e-58d5-4b2f-9b56-1f1f6e2f8a11"
OLD, MID, NEW = NOW_S - 9 * DAY_S, NOW_S - 5 * DAY_S, NOW_S - 2 * DAY_S


def feed_of(*records: dict) -> Feed:
    return Feed(HOME, tuple(records), ())


class ReadWorkouts(unittest.TestCase):
    def test_unreadable_records_are_counted_not_dropped_in_silence(self) -> None:
        workouts, unreadable = read_workouts(
            feed_of(fixtures.summary(NEW), {"trackid": "?"}, fixtures.summary(OLD))
        )
        self.assertEqual(([w.start_s for w in workouts], unreadable), ([OLD, NEW], 1))

    def test_a_feed_of_nothing_but_unreadable_records_is_an_api_change(self) -> None:
        with self.assertRaises(ZeppImportError) as raised:
            read_workouts(feed_of({"id": "1", "kind": "run"}, {"id": "2", "kind": "run"}))
        failure = raised.exception
        self.assertEqual(failure.code, "zepp_api_changed")
        self.assertIn("2 records, none readable: trackid:missing,type:missing", failure.headline)

    def test_the_same_workout_listed_twice_is_one_workout(self) -> None:
        twin = fixtures.summary(NEW, source="run.other.huami.com")
        workouts, _ = read_workouts(feed_of(fixtures.summary(NEW), twin))
        self.assertEqual(len(workouts), 1)
        self.assertEqual(workouts[0].source, fixtures.SOURCE)

    def test_an_empty_feed_is_simply_empty(self) -> None:
        self.assertEqual(read_workouts(feed_of()), ([], 0))


class SummariesInOrder(unittest.TestCase):
    def test_two_zepp_sessions_over_the_same_minutes_do_not_both_bring_calories(self) -> None:
        first = parse_summary(fixtures.summary(MID, minutes=40))
        second = parse_summary(fixtures.summary(MID + 600, minutes=20, cloud_type=6))
        assert first and second
        (_, earlier), (_, later) = plan_summaries([first, second], [])
        assert earlier.payload and later.payload
        self.assertEqual(earlier.payload["calories"], 296)
        self.assertIsNone(later.payload["calories"])

    def test_a_session_this_run_skips_does_not_shadow_a_later_one(self) -> None:
        auto = parse_summary(fixtures.summary(MID, minutes=40, cloud_type=223))
        run = parse_summary(fixtures.summary(MID + 600, minutes=20))
        assert auto and run
        (_, _skipped), (_, imported) = plan_summaries([auto, run], [])
        assert imported.payload
        self.assertEqual(imported.payload["calories"], 296)

    def test_what_healthee_already_holds_is_still_respected(self) -> None:
        run = parse_summary(fixtures.summary(MID))
        assert run
        held = ExistingWorkout(MID * 1000, 1860, 1)
        ((_, step),) = plan_summaries([run], [held])
        self.assertEqual(step.verdict, Verdict.PRESENT)


class Gather(unittest.TestCase):
    def setUp(self) -> None:
        self.zepp = FakeZepp("e", "p")
        self.net = Net([self.zepp])
        self.notes: list[str] = []
        self.pauses: list[float] = []
        session = ZeppSession(user_id=USER_ID, app_token=APP_TOKEN)
        self.history = ZeppHistory(session, ZeppEndpoints(), self.net.send)

    def gather(self, *records: dict, want_routes: bool = True, tracks: StoredTracks | None = None):
        stored = Stored(OWNER, [], tracks or StoredTracks())
        gatherer = Gatherer(
            self.history,
            stored,
            want_routes=want_routes,
            notify=self.notes.append,
            pause=self.pauses.append,
        )
        return gatherer.gather(feed_of(*records))

    def detail_requests(self) -> list[str]:
        return [r.query["trackid"] for r in self.net.requests if r.path == DETAIL_PATH]

    def test_decisions_come_back_newest_first_each_with_its_route(self) -> None:
        for start in (OLD, NEW):
            self.zepp.add(fixtures.summary(start), fixtures.detail(start, points=50))
        gathered = self.gather(fixtures.summary(NEW), fixtures.summary(OLD))
        self.assertEqual([d.workout.start_s for d in gathered.decisions], [NEW, OLD])
        self.assertEqual([d.route.verdict for d in gathered.decisions], [Verdict.IMPORT] * 2)
        self.assertEqual([d.route_points for d in gathered.decisions], [50, 50])
        self.assertEqual((gathered.tracks_asked, gathered.tracks_found), (2, 2))
        self.assertEqual(self.notes, ["reading 2 routes"])

    def test_a_detail_is_fetched_only_where_a_route_can_still_be_imported(self) -> None:
        self.zepp.add(fixtures.summary(NEW), fixtures.detail(NEW))
        records = [
            fixtures.summary(NEW),
            fixtures.summary(MID, cloud_type=223),  # auto-detected
            fixtures.summary(MID + 9000, cloud_type=52, dis="-1"),  # strength, no distance
            fixtures.summary(OLD, minutes=5),  # too short to import
        ]
        self.gather(*records)
        self.assertEqual(self.detail_requests(), [str(NEW)])
        self.assertEqual(self.notes, ["reading 1 route"])

    def test_there_is_a_pause_before_every_detail_request(self) -> None:
        for start in (OLD, MID, NEW):
            self.zepp.add(fixtures.summary(start), fixtures.detail(start))
        self.gather(*(fixtures.summary(start) for start in (NEW, MID, OLD)))
        self.assertEqual(len(self.pauses), 3)
        self.assertTrue(all(seconds > 0 for seconds in self.pauses))

    def test_no_routes_means_no_detail_request_at_all(self) -> None:
        self.zepp.add(fixtures.summary(NEW), fixtures.detail(NEW))
        gathered = self.gather(fixtures.summary(NEW), want_routes=False)
        self.assertEqual(self.detail_requests(), [])
        self.assertEqual(gathered.decisions[0].route.verdict, Verdict.SKIP)
        self.assertEqual(gathered.decisions[0].summary.verdict, Verdict.IMPORT)

    def test_a_track_zepp_will_not_return_costs_that_workout_its_route_only(self) -> None:
        self.zepp.add(fixtures.summary(NEW), json_reply(500, {}))
        self.zepp.add(fixtures.summary(OLD), fixtures.detail(OLD))
        gathered = self.gather(fixtures.summary(NEW), fixtures.summary(OLD))
        newest, oldest = gathered.decisions
        self.assertEqual(newest.summary.verdict, Verdict.IMPORT)
        self.assertEqual(newest.route.verdict, Verdict.SKIP)
        self.assertEqual(newest.route.reason, "Zepp returned no track: busy (HTTP 500)")
        self.assertEqual(oldest.route.verdict, Verdict.IMPORT)
        self.assertEqual((gathered.tracks_asked, gathered.tracks_found), (2, 1))

    def test_a_detail_with_no_track_is_counted_so_an_api_change_can_be_noticed(self) -> None:
        self.zepp.add(
            fixtures.summary(NEW), {"trackid": NEW, "source": fixtures.SOURCE, "gps": "?"}
        )
        gathered = self.gather(fixtures.summary(NEW))
        self.assertEqual(gathered.decisions[0].route.reason, "no GPS track")
        self.assertEqual((gathered.tracks_asked, gathered.tracks_found), (1, 0))


if __name__ == "__main__":
    unittest.main()
