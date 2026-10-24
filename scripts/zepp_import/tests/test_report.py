"""What the owner reads. Small functions, but they are the whole interface."""

from __future__ import annotations

import unittest
from zoneinfo import ZoneInfo

from zepp_import import report
from zepp_import.localtime import UTC, label, local_day, utc_iso, zone_for

START = 1_790_396_820  # 2026-09-26T04:27:00Z


class Times(unittest.TestCase):
    def test_a_time_is_shown_in_the_owners_zone(self) -> None:
        self.assertEqual(report.when(START, ZoneInfo("Asia/Kolkata")), "26 Sep 09:57")
        self.assertEqual(report.when(START, UTC), "26 Sep 04:27")
        self.assertEqual(report.day(START, UTC), "26 Sep 2026")

    def test_the_local_day_is_the_owners_not_utcs(self) -> None:
        late = START + 15 * 3600  # 19:27 UTC is already the 27th in Kolkata
        self.assertEqual(local_day(late, ZoneInfo("Asia/Kolkata")), "2026-09-27")
        self.assertEqual(local_day(late, UTC), "2026-09-26")

    def test_a_zone_that_cannot_be_loaded_falls_back_to_utc_and_says_so(self) -> None:
        self.assertEqual(label(zone_for("Mars/Olympus_Mons")), "UTC")
        self.assertEqual(label(zone_for("")), "UTC")
        self.assertEqual(label(zone_for("Asia/Kolkata")), "Asia/Kolkata")

    def test_an_instant_for_the_server_always_carries_its_offset(self) -> None:
        self.assertEqual(utc_iso(START), "2026-09-26T04:27:00+00:00")

    def test_durations(self) -> None:
        self.assertEqual(report.duration(1860), "31:00")
        self.assertEqual(report.duration(59), "0:59")
        self.assertEqual(report.duration(3 * 3600 + 5 * 60 + 9), "3:05:09")
        self.assertEqual(report.duration(-5), "0:00")


class Wording(unittest.TestCase):
    def test_counts_agree_with_their_nouns(self) -> None:
        self.assertEqual(report.to_write(1, 1), "1 workout, 1 route")
        self.assertEqual(report.to_write(3, 0), "3 workouts, 0 routes")
        self.assertEqual(report.counted(1, "Zepp workout"), "1 Zepp workout")
        self.assertEqual(report.counted(2, "Zepp workout"), "2 Zepp workouts")

    def test_text_is_folded_to_a_phone_and_hangs_under_itself(self) -> None:
        folded = report.wrapped("word " * 30, indent="  ", hang="  ")
        lines = folded.split("\n")
        self.assertTrue(all(len(line) <= report.WIDTH for line in lines))
        self.assertTrue(lines[0].startswith("  word"))
        self.assertTrue(all(line.startswith("    word") for line in lines[1:]))

    def test_a_flag_or_a_long_token_is_never_split_across_lines(self) -> None:
        text = "Set HEALTHEE_URL in the environment or in the abcdef --env-file, then go on."
        for line in report.wrapped(text, indent="  ").split("\n"):
            self.assertFalse(line.rstrip().endswith("-"), line)
        long_word = "x" * 90
        self.assertIn(long_word, report.wrapped(f"shape: {long_word} end", indent=""))

    def test_the_route_note_says_the_three_things_that_matter(self) -> None:
        for phrase in ("VO2max", "14 days", "up or down", "cannot remove a route"):
            self.assertIn(phrase, report.ROUTE_NOTE)


class Fitness(unittest.TestCase):
    def test_a_measured_value_names_its_method(self) -> None:
        scoring = {"ok": True, "vo2max_submax": 41.234, "method": "hr_reserve"}
        self.assertEqual(report.fitness_note(scoring), "fitness measured: VO2max 41.2 (hr_reserve)")

    def test_a_withheld_value_gives_the_servers_short_reason_not_its_essay(self) -> None:
        scoring = {
            "ok": False,
            "reason": "no usable intervals",
            "reserve_reason": "walking_intensity_only",
            "message": "This session was walking, and walking can't measure your VO2max. " * 3,
        }
        self.assertEqual(
            report.fitness_note(scoring), "fitness not measured: walking intensity only"
        )

    def test_a_refusal_with_only_a_reason(self) -> None:
        scoring = {"ok": False, "reason": "no HR for this window (was the strap worn?)"}
        self.assertEqual(
            report.fitness_note(scoring),
            "fitness not measured: no HR for this window (was the strap worn?)",
        )

    def test_no_verdict_is_said_plainly(self) -> None:
        self.assertEqual(
            report.fitness_note(None), "fitness: the server did not score it on arrival"
        )
        self.assertIn("no reason given", report.fitness_note({"ok": False}))
        self.assertIn("not measured", report.fitness_note({"ok": True, "vo2max_submax": None}))


if __name__ == "__main__":
    unittest.main()
