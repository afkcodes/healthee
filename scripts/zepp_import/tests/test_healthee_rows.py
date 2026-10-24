"""Healthee's read replies, and the address rules that keep a password on https."""

from __future__ import annotations

import unittest

from zepp_import.failures import ZeppImportError
from zepp_import.healthee_rows import (
    existing_track,
    existing_workout,
    next_page_day,
    normalise_url,
    read_all,
)


class Address(unittest.TestCase):
    def test_a_bare_name_becomes_an_https_origin(self) -> None:
        for typed in (
            "healthee.example.com",
            " https://healthee.example.com/ ",
            "HTTPS://healthee.example.com",
        ):
            with self.subTest(typed=typed):
                self.assertEqual(normalise_url(typed).lower(), "https://healthee.example.com")

    def test_a_port_is_kept(self) -> None:
        self.assertEqual(
            normalise_url("healthee.example.com:8443"), "https://healthee.example.com:8443"
        )

    def test_plain_http_is_refused_because_it_would_carry_a_password(self) -> None:
        with self.assertRaises(ZeppImportError) as raised:
            normalise_url("http://healthee.example.com")
        self.assertIn("https", raised.exception.headline)

    def test_plain_http_is_allowed_to_this_machine_only(self) -> None:
        self.assertEqual(normalise_url("http://127.0.0.1:8000"), "http://127.0.0.1:8000")
        self.assertEqual(normalise_url("http://localhost:8000"), "http://localhost:8000")
        with self.assertRaises(ZeppImportError):
            normalise_url("http://192.168.1.10:8000")

    def test_a_path_query_or_credentials_are_refused(self) -> None:
        for typed in (
            "https://healthee.example.com/api",
            "https://healthee.example.com/?a=b",
            "https://user:pw@healthee.example.com",
            "https://",
            "",
        ):
            with self.subTest(typed=typed), self.assertRaises(ZeppImportError):
                normalise_url(typed)

    def test_the_sign_in_service_may_live_under_a_path(self) -> None:
        url = normalise_url("https://example.com/auth/", what="sign-in", allow_path=True)
        self.assertEqual(url, "https://example.com/auth")


class WorkoutRow(unittest.TestCase):
    ROW = {
        "start_iso": "2026-09-26T04:27:00+00:00",
        "sport": 44,
        "duration_min": 25,
        "distance_m": None,
        "calories": 180,
        "avg_hr": 140,
        "max_hr": None,
        "min_hr": None,
    }

    def test_the_start_is_the_exact_key_and_minutes_become_seconds(self) -> None:
        row = existing_workout(self.ROW)
        assert row is not None
        self.assertEqual(row.start_ms, 1_790_396_820_000)
        self.assertEqual((row.duration_s, row.end_s - row.start_s), (1500, 1500))
        self.assertEqual(row.sport, 44)

    def test_a_measurement_is_lacking_only_when_the_server_says_null(self) -> None:
        row = existing_workout(self.ROW)
        assert row is not None
        self.assertEqual(row.lacks, {"distance_m", "max_hr", "min_hr"})

    def test_a_column_the_reply_leaves_out_is_not_called_lacking(self) -> None:
        silent = {k: v for k, v in self.ROW.items() if k not in ("max_hr", "calories", "sport")}
        row = existing_workout(silent)
        assert row is not None
        self.assertEqual(row.lacks, {"distance_m", "min_hr"})
        self.assertIsNone(row.sport)

    def test_an_offset_other_than_utc_is_the_same_instant(self) -> None:
        row = existing_workout({**self.ROW, "start_iso": "2026-09-26T09:57:00+05:30"})
        assert row is not None
        self.assertEqual(row.start_ms, 1_790_396_820_000)

    def test_utc_written_as_z_is_read_on_every_python(self) -> None:
        # Python 3.10 reads `isoformat()` output and little else. A "Z" it could not read
        # would make a stored session look absent, and absent sessions get imported.
        for spelling in ("2026-09-26T04:27:00Z", "2026-09-26T04:27:00z"):
            with self.subTest(spelling=spelling):
                row = existing_workout({**self.ROW, "start_iso": spelling})
                assert row is not None
                self.assertEqual(row.start_ms, 1_790_396_820_000)

    def test_the_servers_own_spelling_with_microseconds_is_read(self) -> None:
        row = existing_workout({**self.ROW, "start_iso": "2026-09-26T04:27:00.250000+00:00"})
        assert row is not None
        self.assertEqual(row.start_ms, 1_790_396_820_250)

    def test_a_row_without_a_usable_start_is_not_a_row(self) -> None:
        for start in (None, "yesterday", "2026-09-26T04:27:00", 5):
            with self.subTest(start=start):
                self.assertIsNone(existing_workout({**self.ROW, "start_iso": start}))
        self.assertIsNone(existing_workout("not a row"))

    def test_a_missing_duration_is_zero_seconds_not_a_crash(self) -> None:
        row = existing_workout({**self.ROW, "duration_min": None})
        assert row is not None
        self.assertEqual(row.duration_s, 0)


class ReadAll(unittest.TestCase):
    GOOD = {"start_iso": "2026-09-26T04:27:00+00:00", "sport": 1, "duration_min": 30}

    def failure(self, listed: object) -> ZeppImportError:
        with self.assertRaises(ZeppImportError) as raised:
            read_all("the workout list", listed, existing_workout, ("start_iso",))
        return raised.exception

    def test_every_row_that_reads_is_returned_in_order(self) -> None:
        later = {**self.GOOD, "start_iso": "2026-09-27T04:27:00+00:00"}
        rows = read_all("the workout list", [later, self.GOOD], existing_workout, ("start_iso",))
        self.assertEqual([r.start_ms for r in rows], [1_790_483_220_000, 1_790_396_820_000])
        self.assertEqual(read_all("the workout list", [], existing_workout, ("start_iso",)), [])

    def test_one_unreadable_row_fails_the_read_and_shows_only_how_it_was_written(self) -> None:
        failure = self.failure([self.GOOD, {**self.GOOD, "start_iso": "26/09/2026 04:27"}])
        self.assertEqual(failure.code, "healthee_unreadable")
        self.assertIn("the workout list, and 1 of its 2 rows could not be read", failure.headline)
        self.assertIn("(start_iso:99?99?9999 99:99)", failure.headline)
        self.assertNotIn("2026", failure.headline)
        self.assertIn("Nothing was written", failure.remedy)

    def test_a_reply_with_no_list_is_a_failure_not_an_empty_history(self) -> None:
        for listed in (None, {"rows": []}, "none"):
            with self.subTest(listed=listed):
                failure = self.failure(listed)
                self.assertEqual(failure.code, "healthee_unreadable")
                self.assertIn("the reply could not be read", failure.headline)

    def test_a_route_row_shows_its_times_as_layout_and_its_id_as_a_type(self) -> None:
        row = {
            "track_id": 5,
            "start_ts": "2026-09-26T04:27:00+00:00",
            "end_ts": "2026-09-26T04:58:00+00:00",
        }
        with self.assertRaises(ZeppImportError) as raised:
            read_all("the route list", [row], existing_track, ("start_ts", "end_ts"), ("track_id",))
        when = "9999-99-99a99:99:99+99:99"
        self.assertIn(f"(start_ts:{when},end_ts:{when},track_id:int)", raised.exception.headline)


class TrackRow(unittest.TestCase):
    def test_a_listed_track(self) -> None:
        track = existing_track(
            {
                "track_id": "t-1",
                "start_ts": "2026-09-26T04:27:00+00:00",
                "end_ts": "2026-09-26T04:58:00+00:00",
            }
        )
        assert track is not None
        self.assertEqual((track.track_id, track.end_s - track.start_s), ("t-1", 1860))

    def test_a_track_missing_a_bound_or_an_id_is_not_a_track(self) -> None:
        good = {
            "track_id": "t",
            "start_ts": "2026-09-26T04:27:00+00:00",
            "end_ts": "2026-09-26T04:58:00+00:00",
        }
        for broken in (
            {**good, "end_ts": None},
            {**good, "track_id": 5},
            {**good, "start_ts": "x"},
            [],
        ):
            with self.subTest(broken=broken):
                self.assertIsNone(existing_track(broken))


class NextPage(unittest.TestCase):
    OLDEST_S = 1_790_396_820  # 2026-09-26T04:27:00Z, which is 09:57 on the 26th in Kolkata

    def test_the_day_asked_for_can_never_be_before_the_rows_local_day(self) -> None:
        # One UTC day later covers every timezone, at the cost of re-reading a few rows.
        self.assertEqual(next_page_day(self.OLDEST_S, "2026-10-11"), "2026-09-27")

    def test_it_is_capped_at_the_servers_today_because_the_future_is_refused(self) -> None:
        self.assertEqual(next_page_day(self.OLDEST_S, "2026-09-26"), "2026-09-26")

    def test_without_the_servers_date_there_is_no_safe_day_to_ask_for(self) -> None:
        for today in (None, "soon", 20261011):
            with self.subTest(today=today):
                self.assertIsNone(next_page_day(self.OLDEST_S, today))


if __name__ == "__main__":
    unittest.main()
