"""The whole command, start to finish, against a fake Zepp and a fake Healthee.

The ordinary paths: a dry run, an import, and running it again. What happens when
something is wrong, or when nobody is at the keyboard, is in `test_cli_edges.py`.
"""

from __future__ import annotations

import json
import unittest

from zepp_import import plan
from zepp_import.report import WIDTH
from zepp_import.tests.fake_healthee import USER_ID
from zepp_import.tests.fake_zepp import HOME
from zepp_import.tests.world import JOG, JOG_STORED, RUN, SHORT, STRENGTH, World
from zepp_import.zepp_wire import DETAIL_PATH, LOGOUT_URL

YES = {"Import": "y"}

# What the plan prints for each session of `world.World`, newest first. The trailing
# element of a block is the start of the NEXT session, which pins that no route line
# follows a session that has no route to speak of.
EXPECTED_PLAN = (
    (
        "  26 Sep 11:56  Outdoor run",
        "    31:00, 2.70 km, 296 kcal, avg HR 133",
        "    workout: import",
        "    route: import, 120 points",
    ),
    (
        "  02 Oct 11:56  Outdoor run",
        "    24:00, 4.01 km, 296 kcal, avg HR 133",
        "    workout: update (adds distance, heart rate, sport)",
        "    route: import, 300 points",
    ),
    (
        "  03 Oct 11:56  Auto-detected activity",
        "    14:00, 0.90 km, 296 kcal, avg HR 133",
        "    workout: skip (auto-detected; the strap reports it)",
        "  02 Oct",
    ),
    (
        "  04 Oct 11:56  Outdoor run",
        "    6:00, 2.70 km, 296 kcal, avg HR 133",
        "    workout: skip (under 10 min; Healthee lists none)",
        "  03 Oct",
    ),
    (
        "  06 Oct 11:56  Strength",
        "    45:00, 296 kcal, avg HR 133",
        "    workout: import",
        "  04 Oct",
    ),
    (
        "  08 Oct 11:56  Zepp type 999",
        "    20:00, 2.70 km, 296 kcal, avg HR 133",
        "    workout: skip (Zepp type 999 has no Healthee sport)",
        "  06 Oct",
    ),
)


class DryRun(unittest.TestCase):
    def setUp(self) -> None:
        self.world = World()
        self.result = self.world.run("--dry-run")

    def test_it_shows_the_plan_and_writes_nothing(self) -> None:
        self.assertEqual(self.result.status, 0)
        self.assertIn("To write: 3 workouts, 2 routes.", self.result.lines)
        self.assertIn("Dry run: nothing was written.", self.result.lines)
        self.assertEqual(self.world.writes(), [])
        self.assertEqual(self.world.healthee.tokens, {})
        self.assertEqual(self.world.healthee.tracks, {})

    def test_every_session_is_listed_with_what_would_happen_to_it(self) -> None:
        for block in EXPECTED_PLAN:
            with self.subTest(block=block[0]):
                self.assertIn("\n".join(block), self.result.text)

    def test_it_is_not_asked_whether_to_import(self) -> None:
        self.assertFalse(any("Import" in prompt for prompt in self.result.script.asked))

    def test_the_route_consequence_is_stated_before_anything_could_be_written(self) -> None:
        self.assertIn("can move biological age up or down", self.result.text.replace("\n", " "))

    def test_the_zepp_session_is_ended_even_though_nothing_was_imported(self) -> None:
        self.assertEqual(self.world.zepp.signed_out, 1)
        self.assertIn("  Zepp: signed out", self.result.lines)

    def test_times_are_the_owners_not_the_machines(self) -> None:
        self.assertIn("(Asia/Kolkata)", self.result.text)
        self.assertIn("26 Sep 11:56  Outdoor run", self.result.text)  # 06:26 UTC

    def test_no_line_is_wider_than_a_phone(self) -> None:
        for line in self.result.text.split("\n"):
            with self.subTest(line=line):
                self.assertLessEqual(len(line), WIDTH)

    def test_everything_printed_is_plain_ascii(self) -> None:
        self.assertTrue(self.result.text.isascii())


class Import(unittest.TestCase):
    def setUp(self) -> None:
        self.world = World()
        self.world.healthee.scoring = {"ok": True, "vo2max_submax": 41.23, "method": "gps_graded"}

    def test_yes_to_both_stores_routes_first_then_summaries(self) -> None:
        result = self.world.run(answers=YES)
        self.assertEqual(result.status, 0)
        self.assertEqual(
            self.world.writes(), ["POST /api/workout/gps"] * 2 + ["POST /ingest/helio"]
        )
        self.assertIn("Done: 3 workouts, 2 routes stored.", result.lines)
        self.assertIn("    fitness measured: VO2max 41.2 (gps_graded)", result.lines)
        self.assertIn("  3 workouts stored, 3 days recalculated", result.lines)

    def test_what_lands_in_healthee(self) -> None:
        self.world.run(answers=YES)
        stored = self.world.healthee.workouts
        self.assertEqual(
            stored[RUN * 1000],
            {
                "sport": 1,
                "duration_s": 1860,
                "calories": 296,
                "distance_m": 2701.0,
                "avg_hr": 133,
                "max_hr": 158,
                "min_hr": 97,
            },
        )
        self.assertEqual(stored[STRENGTH * 1000]["sport"], 14)
        self.assertIsNone(stored[STRENGTH * 1000]["distance_m"])
        self.assertNotIn(SHORT * 1000, stored)
        self.assertNotIn(JOG * 1000, stored)  # the jog was completed under its stored key
        self.assertEqual(len(stored), 3)
        self.assertEqual(
            set(self.world.healthee.tracks),
            {plan.route_id(USER_ID, RUN), plan.route_id(USER_ID, JOG)},
        )

    def test_a_completed_row_keeps_everything_it_had(self) -> None:
        self.world.run(answers=YES)
        jog = self.world.healthee.workouts[JOG_STORED * 1000]
        self.assertEqual((jog["duration_s"], jog["calories"], jog["avg_hr"]), (1500, 180, 140))
        self.assertEqual((jog["sport"], jog["distance_m"]), (1, 4010.0))
        self.assertEqual((jog["max_hr"], jog["min_hr"]), (158, 97))

    def test_the_two_questions_are_asked_separately(self) -> None:
        result = self.world.run(answers=YES)
        questions = [prompt for prompt in result.script.asked if "Import" in prompt]
        self.assertEqual(questions, ["Import 3 workouts? [y/N]: ", "Import 2 routes too? [y/N]: "])

    def test_summaries_without_routes(self) -> None:
        result = self.world.run(answers={"workouts?": "y", "routes": "n"})
        self.assertEqual(self.world.writes(), ["POST /ingest/helio"])
        self.assertEqual(self.world.healthee.tracks, {})
        self.assertIn("Done: 3 workouts, 0 routes stored.", result.lines)

    def test_declining_the_summaries_ends_it_without_a_second_question(self) -> None:
        result = self.world.run(answers={"Import": "n"})
        self.assertEqual((result.status, self.world.writes()), (0, []))
        self.assertIn("Nothing was written.", result.lines)
        self.assertEqual(len([p for p in result.script.asked if "Import" in p]), 1)

    def test_no_routes_fetches_no_track_and_stores_none(self) -> None:
        result = self.world.run("--no-routes", answers=YES)
        self.assertEqual(self.world.writes(), ["POST /ingest/helio"])
        self.assertNotIn(DETAIL_PATH, self.world.paths_to("api-mifit"))
        self.assertNotIn("/api/workout/gps", self.world.paths_to("healthee.test"))
        self.assertNotIn("biological age", result.text)

    def test_the_temporary_ingest_token_does_not_outlive_the_run(self) -> None:
        self.world.run(answers=YES)
        self.assertEqual(len(self.world.healthee.tokens), 1)
        self.assertEqual(self.world.healthee.live_tokens(), [])

    def test_the_zepp_session_is_over_before_healthee_is_written_to(self) -> None:
        self.world.run(answers=YES)
        urls = [r.url for r in self.world.net.requests]
        first_write = next(
            i
            for i, r in enumerate(self.world.net.requests)
            if r.path == "/api/workout/gps" and r.method == "POST"
        )
        self.assertLess(urls.index(LOGOUT_URL), first_write)


class RunningItAgain(unittest.TestCase):
    def setUp(self) -> None:
        self.world = World()
        self.first = self.world.run(answers=YES)
        self.before = json.dumps(
            [self.world.healthee.workouts, sorted(self.world.healthee.tracks)], sort_keys=True
        )
        self.world.net.requests.clear()
        self.second = self.world.run(answers=YES)

    def test_a_second_run_finds_nothing_to_do(self) -> None:
        self.assertEqual(self.second.status, 0)
        self.assertIn("Nothing to import.", self.second.lines)
        self.assertEqual(self.world.writes(), [])
        after = json.dumps(
            [self.world.healthee.workouts, sorted(self.world.healthee.tracks)], sort_keys=True
        )
        self.assertEqual(after, self.before)

    def test_it_asks_for_nothing_but_the_two_passwords_and_enter(self) -> None:
        self.assertEqual(
            self.second.script.asked,
            [
                "Healthee address [https://healthee.test]: ",
                "Healthee email [owner@healthee.example]: ",
                "Healthee password (hidden): ",
                "Zepp email [runner@zepp.example]: ",
                "Zepp password (hidden): ",
            ],
        )

    def test_what_the_healthee_login_is_gets_said_only_when_it_is_asked_from_nothing(self) -> None:
        said = 'the Healthee app on "Sign in to your server"'
        self.assertIn(said, " ".join(self.first.text.split()))
        self.assertNotIn("Sign in to your server", self.second.text)

    def test_it_goes_straight_to_the_host_that_had_the_workouts(self) -> None:
        asked = [line for line in self.second.lines if "asking" in line]
        self.assertEqual(asked, ["  Zepp: asking api-mifit-in.huami.com"])
        self.assertGreater(len([line for line in self.first.lines if "asking" in line]), 1)

    def test_the_record_says_what_came_from_zepp(self) -> None:
        ledger = json.loads(self.world.state.read_text())
        imports = ledger["imports"][f"https://healthee.test|{USER_ID}"]
        self.assertEqual(sorted(imports), sorted(str(t) for t in (RUN, JOG, STRENGTH)))
        self.assertEqual(imports[str(RUN)]["start_ts"], RUN * 1000)
        self.assertEqual(imports[str(RUN)]["route_id"], plan.route_id(USER_ID, RUN))
        self.assertEqual(imports[str(JOG)]["summary"], "update")
        self.assertEqual(imports[str(JOG)]["start_ts"], JOG_STORED * 1000)
        self.assertNotIn("route_id", imports[str(STRENGTH)])
        self.assertEqual(ledger["hosts"], {"7700112233": HOME})


if __name__ == "__main__":
    unittest.main()
