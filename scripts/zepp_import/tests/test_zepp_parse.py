"""Zepp's workout JSON → a summary and a track. Each test states one fact of the format."""

from __future__ import annotations

import unittest

from zepp_import.tests import fixtures
from zepp_import.zepp_parse import (
    MAX_ACCURACY_M,
    MAX_TRACK_POINTS,
    parse_summary,
    parse_track,
)

START = 1_790_000_000


class Summary(unittest.TestCase):
    def test_numbers_arrive_as_strings_and_are_read(self) -> None:
        workout = parse_summary(fixtures.summary(START))
        assert workout is not None
        self.assertEqual(
            (workout.track_id, workout.start_s, workout.end_s), (START,) * 2 + (START + 1860,)
        )
        self.assertEqual((workout.distance_m, workout.calories_kcal), (2701.0, 296))
        self.assertEqual((workout.avg_hr, workout.max_hr, workout.min_hr), (133, 158, 97))
        self.assertEqual((workout.cloud_type, workout.source), (1, fixtures.SOURCE))

    def test_minus_one_means_not_measured(self) -> None:
        record = fixtures.summary(
            START, dis="-1", calorie=-1, avg_heart_rate="-1", max_heart_rate=-1, min_heart_rate=0
        )
        workout = parse_summary(record)
        assert workout is not None
        self.assertIsNone(workout.distance_m)
        self.assertIsNone(workout.calories_kcal)
        self.assertEqual((workout.avg_hr, workout.max_hr, workout.min_hr), (None, None, None))

    def test_elapsed_time_includes_pauses_and_active_time_does_not(self) -> None:
        workout = parse_summary(fixtures.summary(START, minutes=30, run_time="1500"))
        assert workout is not None
        self.assertEqual((workout.elapsed_s, workout.active_s), (1800, 1500))

    def test_a_missing_end_falls_back_to_the_active_time(self) -> None:
        workout = parse_summary(fixtures.summary(START, end_time=None, run_time="900"))
        assert workout is not None
        self.assertEqual(workout.end_s, START + 900)

    def test_no_usable_start_end_or_type_is_no_workout(self) -> None:
        for record in (
            fixtures.summary(START, trackid="abc"),
            fixtures.summary(START, trackid="0"),
            fixtures.summary(START, type=None),
            fixtures.summary(START, end_time=None, run_time="-1"),
            fixtures.summary(START, end_time=str(START + 8 * 24 * 3600)),
            fixtures.summary(START, trackid="nan"),
        ):
            with self.subTest(record=record):
                self.assertIsNone(parse_summary(record))

    def test_a_heart_rate_outside_the_possible_is_dropped(self) -> None:
        workout = parse_summary(fixtures.summary(START, max_heart_rate=400, min_heart_rate=3))
        assert workout is not None
        self.assertEqual((workout.max_hr, workout.min_hr), (None, None))

    def test_auto_recognition_and_parentage_are_carried(self) -> None:
        workout = parse_summary(fixtures.summary(START, auto_recognition=True, parent_trackid=7))
        assert workout is not None
        self.assertTrue(workout.auto_detected)
        self.assertTrue(workout.is_child)
        plain = parse_summary(fixtures.summary(START, auto_recognition=None, parent_trackid=-1))
        assert plain is not None
        self.assertFalse(plain.auto_detected or plain.is_child)


class TrackDecoding(unittest.TestCase):
    def test_positions_are_deltas_and_latitude_comes_first(self) -> None:
        track = parse_track(fixtures.detail(START, points=3, step_s=5), START)
        self.assertIsNone(track.refused)
        self.assertEqual([p.ts_s for p in track.points], [START, START + 5, START + 10])
        self.assertEqual((track.points[0].lat, track.points[0].lng), (10.0, 20.0))
        self.assertAlmostEqual(track.points[2].lat, 10.00003)
        self.assertAlmostEqual(track.points[2].lng, 20.000046)

    def test_altitude_is_centimetres_and_has_a_no_reading_value(self) -> None:
        detail = fixtures.detail(START, points=2, altitude=f"41250;{fixtures.NO_ALTITUDE_CM};")
        track = parse_track(detail, START)
        self.assertEqual([p.ele_m for p in track.points], [412.5, None])

    def test_a_trailing_separator_is_optional(self) -> None:
        with_it = parse_track(fixtures.detail(START, points=12), START)
        without = parse_track(fixtures.detail(START, points=12, trailing=False), START)
        self.assertEqual(with_it.points, without.points)
        self.assertEqual(len(with_it.points), 12)

    def test_a_point_with_no_fix_still_moves_the_clock(self) -> None:
        detail = fixtures.detail(
            START, points=3, time="0;5;5", longitude_latitude="1000000000,2000000000;;10,20"
        )
        track = parse_track(detail, START)
        self.assertEqual([p.ts_s for p in track.points], [START, START + 10])
        self.assertEqual(track.dropped, {"no_fix": 1})
        self.assertAlmostEqual(track.points[1].lat, 10.0000001)

    def test_a_repeated_instant_is_dropped_because_the_server_refuses_it(self) -> None:
        detail = fixtures.detail(START, points=3, time="0;0;4")
        track = parse_track(detail, START)
        self.assertEqual([p.ts_s for p in track.points], [START, START + 4])
        self.assertEqual(track.dropped, {"not_later": 1})

    def test_a_dropped_point_still_moves_the_position(self) -> None:
        # The second fix is dropped (same instant), but the third is a delta FROM it.
        track = parse_track(fixtures.detail(START, points=3, time="0;0;4"), START)
        self.assertAlmostEqual(track.points[1].lat, 10.00003)

    def test_an_inaccurate_fix_is_dropped(self) -> None:
        detail = fixtures.detail(
            START, points=3, accuracy=f"5;{MAX_ACCURACY_M + 1};{MAX_ACCURACY_M}"
        )
        track = parse_track(detail, START)
        self.assertEqual(len(track.points), 2)
        self.assertEqual(track.dropped, {"inaccurate": 1})

    def test_a_fix_off_the_planet_is_dropped(self) -> None:
        detail = fixtures.detail(START, points=2, longitude_latitude="9100000000,0;-200000000,0")
        track = parse_track(detail, START)
        self.assertEqual(track.dropped, {"out_of_range": 1})
        self.assertEqual(track.points[0].lat, 89.0)


class TrackRefusal(unittest.TestCase):
    def test_no_track_at_all(self) -> None:
        for detail in (
            {},
            fixtures.detail(START, longitude_latitude=""),
            fixtures.detail(START, time=""),
        ):
            with self.subTest(detail=list(detail)):
                self.assertEqual(parse_track(detail, START).refused, "no GPS track")

    def test_lists_of_different_lengths_are_refused_not_repaired(self) -> None:
        track = parse_track(fixtures.detail(START, points=4, time="0;5;5"), START)
        self.assertEqual(track.refused, "track lists do not line up (3 vs 4)")
        self.assertEqual(track.points, ())

    def test_a_cell_that_is_not_a_number_refuses_the_whole_track(self) -> None:
        for change in (
            {"time": "0;x;5"},
            {"time": "0;-5;5"},
            {"longitude_latitude": "1,2;oops;3,4"},
            {"longitude_latitude": "1,2;3;4,5"},
        ):
            with self.subTest(change=change):
                track = parse_track({**fixtures.detail(START, points=3), **change}, START)
                self.assertIsNotNone(track.refused)
                self.assertEqual(track.points, ())


class Thinning(unittest.TestCase):
    def test_a_track_over_the_servers_cap_keeps_both_ends(self) -> None:
        count = MAX_TRACK_POINTS + 500
        track = parse_track(fixtures.detail(START, points=count, step_s=1), START)
        self.assertEqual(len(track.points), MAX_TRACK_POINTS)
        self.assertEqual(track.dropped, {"thinned": 500})
        self.assertEqual(track.points[0].ts_s, START)
        self.assertEqual(track.points[-1].ts_s, START + count - 1)
        stamps = [p.ts_s for p in track.points]
        self.assertEqual(stamps, sorted(set(stamps)))


if __name__ == "__main__":
    unittest.main()
