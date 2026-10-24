"""The import rules: each test is one rule from `plan.py`, with the defect it prevents."""

from __future__ import annotations

import json
import unittest

from zepp_import import plan
from zepp_import.healthee_rows import ExistingWorkout, existing_workout
from zepp_import.localtime import utc_iso
from zepp_import.plan import Step, StoredTracks, Verdict
from zepp_import.tests import fixtures
from zepp_import.zepp_parse import ZeppWorkout, parse_summary

START = 1_790_000_000
OWNER = "0b1e6f0e-58d5-4b2f-9b56-1f1f6e2f8a11"
NO_TRACKS = StoredTracks()
EVERY_MEASUREMENT = ("distance_m", "calories", "avg_hr", "max_hr", "min_hr")
HEART_RATE = ("avg_hr", "max_hr", "min_hr")


def workout(
    start: int = START, *, cloud_type: int = 1, minutes: float = 31, **over: object
) -> ZeppWorkout:
    parsed = parse_summary(fixtures.summary(start, cloud_type=cloud_type, minutes=minutes, **over))
    assert parsed is not None
    return parsed


def stored(
    start_s: int, minutes: int = 30, sport: int | None = 1, lacks: tuple[str, ...] = ()
) -> ExistingWorkout:
    """A row Healthee holds. `lacks` are the measurements the server reported as null."""
    return ExistingWorkout(start_s * 1000, minutes * 60, sport, frozenset(lacks))


class VerdictWords(unittest.TestCase):
    def test_a_verdict_reads_as_its_words_on_every_python(self) -> None:
        # A `str`-mixin enum formats as its value before Python 3.11 and as its name
        # after; the plan a person reads must not depend on which one is installed.
        self.assertEqual(str(Verdict.PRESENT), "already there")
        self.assertEqual(f"{Verdict.SKIP}", "skip")
        self.assertEqual(json.dumps([Verdict.IMPORT]), '["import"]')
        self.assertEqual(Verdict("update"), Verdict.UPDATE)


class NewSession(unittest.TestCase):
    def test_a_session_healthee_lacks_is_imported_whole(self) -> None:
        step = plan.plan_summary(workout(), [])
        self.assertEqual(step.verdict, Verdict.IMPORT)
        self.assertEqual(
            step.payload,
            {
                "start_ts": START * 1000,
                "sport": 1,
                "duration_s": 1860,
                "calories": 296,
                "distance_m": 2701.0,
                "avg_hr": 133,
                "max_hr": 158,
                "min_hr": 97,
            },
        )

    def test_the_stored_duration_is_wall_clock_so_the_window_covers_the_session(self) -> None:
        step = plan.plan_summary(workout(minutes=30, run_time="1500"), [])
        assert step.payload is not None
        self.assertEqual(step.payload["duration_s"], 1800)

    def test_what_zepp_did_not_measure_is_sent_as_absent_not_zero(self) -> None:
        step = plan.plan_summary(workout(cloud_type=52, dis="-1", calorie="-1"), [])
        assert step.payload is not None
        self.assertIsNone(step.payload["distance_m"])
        self.assertIsNone(step.payload["calories"])
        self.assertEqual(step.payload["sport"], 14)


class NeverImported(unittest.TestCase):
    def assert_skipped(self, step: Step, reason: str) -> None:
        self.assertEqual((step.verdict, step.payload), (Verdict.SKIP, None))
        self.assertIn(reason, step.reason)

    def test_an_auto_detected_bout_would_count_the_same_minutes_twice(self) -> None:
        self.assert_skipped(plan.plan_summary(workout(cloud_type=223), []), "auto-detected")
        self.assert_skipped(plan.plan_summary(workout(auto_recognition=True), []), "auto-detected")

    def test_an_unknown_sport_would_be_filed_under_another_sports_name(self) -> None:
        self.assert_skipped(plan.plan_summary(workout(cloud_type=999), []), "Zepp type 999")

    def test_under_ten_minutes_would_change_calories_and_be_listed_nowhere(self) -> None:
        self.assert_skipped(plan.plan_summary(workout(minutes=9.98), []), "under 10 min")
        self.assertEqual(plan.plan_summary(workout(minutes=10), []).verdict, Verdict.IMPORT)

    def test_a_leg_of_a_multi_sport_session_is_already_inside_its_parent(self) -> None:
        self.assert_skipped(plan.plan_summary(workout(parent_trackid=START - 5), []), "one leg")


class SameSession(unittest.TestCase):
    def test_a_complete_stored_row_is_left_alone(self) -> None:
        step = plan.plan_summary(workout(), [stored(START + 60)])
        self.assertEqual((step.verdict, step.payload), (Verdict.PRESENT, None))

    def test_only_what_is_missing_is_added_and_under_the_stored_key(self) -> None:
        row = stored(START - 90, sport=44, lacks=("distance_m",))
        step = plan.plan_summary(workout(), [row])
        self.assertEqual(step.verdict, Verdict.UPDATE)
        self.assertEqual(
            step.payload, {"start_ts": (START - 90) * 1000, "distance_m": 2701.0, "sport": 1}
        )
        self.assertEqual(step.reason, "adds distance, sport")

    def test_a_completion_never_carries_a_duration(self) -> None:
        # The list reports whole minutes; sending one back would overwrite stored seconds.
        step = plan.plan_summary(workout(), [stored(START, sport=0, lacks=EVERY_MEASUREMENT)])
        assert step.payload is not None
        self.assertNotIn("duration_s", step.payload)

    def test_missing_heart_rate_and_calories_are_filled(self) -> None:
        row = stored(START, lacks=("calories", *HEART_RATE))
        step = plan.plan_summary(workout(), [row])
        self.assertEqual(
            step.payload,
            {"start_ts": START * 1000, "avg_hr": 133, "max_hr": 158, "min_hr": 97, "calories": 296},
        )
        self.assertEqual(step.reason, "adds calories, heart rate")

    def test_only_the_one_missing_value_is_sent(self) -> None:
        step = plan.plan_summary(workout(), [stored(START, lacks=("max_hr",))])
        self.assertEqual(step.payload, {"start_ts": START * 1000, "max_hr": 158})

    def test_a_column_the_server_did_not_mention_is_unknown_not_empty(self) -> None:
        # The upsert lets a pushed value REPLACE a stored one, so "missing" has to be
        # something the server said. A reply that omits a column says nothing about it.
        unmentioned = existing_workout(
            {"start_iso": utc_iso(START), "sport": 1, "duration_min": 30, "distance_m": None}
        )
        assert unmentioned is not None
        step = plan.plan_summary(workout(), [unmentioned])
        self.assertEqual(step.payload, {"start_ts": START * 1000, "distance_m": 2701.0})

    def test_what_zepp_did_not_measure_cannot_fill_a_gap(self) -> None:
        gappy = workout(dis="-1", calorie="-1", max_heart_rate=-1)
        step = plan.plan_summary(gappy, [stored(START, lacks=EVERY_MEASUREMENT)])
        self.assertEqual(step.payload, {"start_ts": START * 1000, "avg_hr": 133, "min_hr": 97})

    def test_two_minutes_is_the_same_session_and_just_over_is_not(self) -> None:
        near = plan.plan_summary(workout(), [stored(START + 120, sport=44)])
        far = plan.plan_summary(workout(), [stored(START + 121, sport=44)])
        before = plan.plan_summary(workout(), [stored(START - 120, sport=44)])
        self.assertEqual(near.verdict, Verdict.UPDATE)
        self.assertEqual(before.verdict, Verdict.UPDATE)
        self.assertEqual(far.verdict, Verdict.IMPORT)

    def test_the_nearest_of_two_candidates_is_the_one_completed(self) -> None:
        rows = [stored(START - 100, sport=44), stored(START + 20, sport=44)]
        step = plan.plan_summary(workout(), rows)
        assert step.payload is not None
        self.assertEqual(step.payload["start_ts"], (START + 20) * 1000)


class SportLabel(unittest.TestCase):
    def test_a_generic_label_becomes_the_sport_zepp_recorded(self) -> None:
        for generic in (0, 44):
            step = plan.plan_summary(workout(cloud_type=6), [stored(START, sport=generic)])
            with self.subTest(generic=generic):
                self.assertEqual(step.payload, {"start_ts": START * 1000, "sport": 2})

    def test_a_specific_stored_sport_is_not_overwritten(self) -> None:
        self.assertEqual(
            plan.plan_summary(workout(), [stored(START, sport=12)]).verdict, Verdict.PRESENT
        )

    def test_a_stored_sport_the_server_did_not_report_is_not_overwritten(self) -> None:
        step = plan.plan_summary(workout(), [stored(START, sport=None)])
        self.assertEqual(step.verdict, Verdict.PRESENT)

    def test_a_cloud_code_stored_as_a_device_code_is_corrected(self) -> None:
        # Zepp says this session is cloud type 8, a treadmill run. The stored row says 8
        # too, which in Healthee's enum is "Pool swim": it was written in the wrong enum.
        step = plan.plan_summary(workout(cloud_type=8), [stored(START, sport=8)])
        self.assertEqual(step.verdict, Verdict.UPDATE)
        self.assertEqual(step.payload, {"start_ts": START * 1000, "sport": 4})
        self.assertEqual(step.reason, "sport was filed as Pool swim")

    def test_a_code_that_means_the_same_in_both_enums_is_not_a_correction(self) -> None:
        step = plan.plan_summary(workout(cloud_type=1), [stored(START, sport=1)])
        self.assertEqual(step.verdict, Verdict.PRESENT)

    def test_a_correction_and_a_fill_are_both_said(self) -> None:
        row = stored(START, sport=52, lacks=HEART_RATE)
        step = plan.plan_summary(workout(cloud_type=52, dis="-1"), [row])
        self.assertEqual(step.reason, "adds heart rate; sport was filed as Boxing")
        assert step.payload is not None
        self.assertEqual(step.payload["sport"], 14)


class Overlap(unittest.TestCase):
    def test_an_overlapping_import_brings_no_calories_to_count_twice(self) -> None:
        step = plan.plan_summary(workout(), [stored(START + 600, minutes=20, sport=44)])
        self.assertEqual(step.verdict, Verdict.IMPORT)
        assert step.payload is not None
        self.assertIsNone(step.payload["calories"])
        self.assertEqual(step.payload["avg_hr"], 133)
        self.assertIn("calories left out", step.reason)

    def test_a_session_that_only_touches_another_is_not_an_overlap(self) -> None:
        step = plan.plan_summary(workout(), [stored(START + 1860, minutes=20)])
        assert step.payload is not None
        self.assertEqual(step.payload["calories"], 296)

    def test_calories_left_out_for_an_overlap_are_not_added_back_on_the_next_run(self) -> None:
        mine = stored(START, minutes=31, lacks=("calories",))
        other = stored(START + 600, minutes=20, sport=44)
        self.assertEqual(plan.plan_summary(workout(), [mine, other]).verdict, Verdict.PRESENT)

    def test_calories_are_filled_when_the_row_shares_its_minutes_with_nothing(self) -> None:
        step = plan.plan_summary(workout(), [stored(START, minutes=31, lacks=("calories",))])
        self.assertEqual(step.payload, {"start_ts": START * 1000, "calories": 296})


if __name__ == "__main__":
    unittest.main()
