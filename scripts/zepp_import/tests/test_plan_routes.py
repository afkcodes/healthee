"""The route rules from `plan.py`: when a route is fetched, sent, or left alone."""

from __future__ import annotations

import unittest
import uuid
from datetime import datetime

from zepp_import import plan
from zepp_import.healthee_rows import ExistingTrack
from zepp_import.plan import StoredTracks, Verdict
from zepp_import.tests import fixtures
from zepp_import.zepp_parse import ZeppWorkout, parse_summary, parse_track

START = 1_790_000_000
OWNER = "0b1e6f0e-58d5-4b2f-9b56-1f1f6e2f8a11"
NO_TRACKS = StoredTracks()


def workout(
    start: int = START, *, cloud_type: int = 1, minutes: float = 31, **over: object
) -> ZeppWorkout:
    parsed = parse_summary(fixtures.summary(start, cloud_type=cloud_type, minutes=minutes, **over))
    assert parsed is not None
    return parsed


class Routes(unittest.TestCase):
    def setUp(self) -> None:
        self.session = workout()
        self.imported = plan.plan_summary(self.session, [])
        self.track = parse_track(fixtures.detail(START, points=120), START)

    def test_a_route_is_asked_for_only_when_nothing_rules_it_out(self) -> None:
        self.assertIsNone(plan.route_precheck(self.session, self.imported, NO_TRACKS, OWNER))

    def test_a_session_with_no_distance_has_no_route_to_fetch(self) -> None:
        strength = workout(cloud_type=52, dis="-1")
        step = plan.route_precheck(strength, plan.plan_summary(strength, []), NO_TRACKS, OWNER)
        assert step is not None
        self.assertEqual((step.verdict, step.shown), (Verdict.SKIP, False))

    def test_an_indoor_session_has_a_distance_and_still_no_route(self) -> None:
        treadmill = workout(cloud_type=8)
        step = plan.route_precheck(treadmill, plan.plan_summary(treadmill, []), NO_TRACKS, OWNER)
        assert step is not None
        self.assertEqual((step.verdict, step.shown), (Verdict.SKIP, False))
        self.assertFalse(plan.wants_track(treadmill))
        self.assertTrue(plan.wants_track(workout(cloud_type=6)))  # a walk

    def test_a_route_follows_its_session(self) -> None:
        short = workout(minutes=6)
        step = plan.route_precheck(short, plan.plan_summary(short, []), NO_TRACKS, OWNER)
        assert step is not None
        self.assertEqual((step.verdict, step.reason), (Verdict.SKIP, "its session is not imported"))

    def test_a_route_already_imported_is_recognised_by_its_derived_id(self) -> None:
        mine = ExistingTrack(plan.route_id(OWNER, START), START, START + 1860)
        step = plan.route_precheck(self.session, self.imported, StoredTracks((mine,)), OWNER)
        assert step is not None
        self.assertEqual((step.verdict, step.reason), (Verdict.PRESENT, ""))

    def test_one_route_per_run_even_when_healthee_recorded_its_own(self) -> None:
        theirs = ExistingTrack(str(uuid.uuid4()), START + 30, START + 1700)
        step = plan.route_precheck(self.session, self.imported, StoredTracks((theirs,)), OWNER)
        assert step is not None
        self.assertEqual(step.verdict, Verdict.PRESENT)
        self.assertIn("these minutes", step.reason)

    def test_a_full_route_list_cannot_vouch_for_anything_older_than_it(self) -> None:
        newer = [
            ExistingTrack(str(uuid.uuid4()), START + 10_000 + i, START + 10_500 + i)
            for i in range(100)
        ]
        full = StoredTracks.listed(newer, list_limit=100)
        partial = StoredTracks.listed(newer[:99], list_limit=100)
        self.assertEqual(full.horizon_s, START + 10_000)
        self.assertIsNone(partial.horizon_s)
        blocked = plan.route_precheck(self.session, self.imported, full, OWNER)
        assert blocked is not None
        self.assertEqual(blocked.verdict, Verdict.SKIP)
        self.assertIsNone(plan.route_precheck(self.session, self.imported, partial, OWNER))

    def test_the_route_body_is_what_the_server_validates(self) -> None:
        step = plan.plan_route(self.session, self.track, OWNER)
        assert step.payload is not None
        self.assertEqual(step.payload["client_id"], plan.route_id(OWNER, START))
        self.assertEqual(datetime.fromisoformat(step.payload["start_iso"]).timestamp(), START)
        self.assertEqual(datetime.fromisoformat(step.payload["end_iso"]).timestamp(), START + 1860)
        self.assertEqual(len(step.payload["points"]), 120)
        self.assertEqual(step.payload["points"][0], [START, 10.0, 20.0, 412.0])

    def test_the_window_stretches_to_a_fix_recorded_after_the_summarys_end(self) -> None:
        late = parse_track(fixtures.detail(START, points=400, step_s=5), START)
        step = plan.plan_route(self.session, late, OWNER)
        assert step.payload is not None
        self.assertEqual(datetime.fromisoformat(step.payload["end_iso"]).timestamp(), START + 1995)

    def test_a_refused_or_tiny_track_is_not_sent(self) -> None:
        tiny = parse_track(fixtures.detail(START, points=plan.MIN_ROUTE_POINTS - 1), START)
        self.assertEqual(
            plan.plan_route(self.session, tiny, OWNER).reason, "only 9 usable GPS points"
        )
        none = parse_track({}, START)
        self.assertEqual(plan.plan_route(self.session, none, OWNER).reason, "no GPS track")
        enough = parse_track(fixtures.detail(START, points=plan.MIN_ROUTE_POINTS), START)
        self.assertEqual(plan.plan_route(self.session, enough, OWNER).verdict, Verdict.IMPORT)


class RouteIdentity(unittest.TestCase):
    def test_the_same_workout_always_gets_the_same_id(self) -> None:
        self.assertEqual(plan.route_id(OWNER, START), plan.route_id(OWNER, START))
        self.assertEqual(uuid.UUID(plan.route_id(OWNER, START)).version, 5)

    def test_two_accounts_importing_one_zepp_account_do_not_collide(self) -> None:
        other = "11111111-2222-3333-4444-555555555555"
        self.assertNotEqual(plan.route_id(OWNER, START), plan.route_id(other, START))
        self.assertNotEqual(plan.route_id(OWNER, START), plan.route_id(OWNER, START + 1))


if __name__ == "__main__":
    unittest.main()
