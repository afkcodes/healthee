"""The command when something is wrong, or when nobody is at the keyboard.

Bad arguments, wrong passwords, a server that refuses, a run that is interrupted, a record
file somebody edited: each must end in a named failure or a clean exit, with nothing
half-written that a second run cannot finish.
"""

from __future__ import annotations

import json
import unittest

from zepp_import.tests.fake_healthee import USER_ID
from zepp_import.tests.fake_zepp import APP_TOKEN, HOME
from zepp_import.tests.support import json_reply
from zepp_import.tests.world import HEALTHEE_EMAIL, JOG, RUN, STRENGTH, World
from zepp_import.zepp_wire import LOGIN_URL, LOGOUT_URL, TOKENS_URL

YES = {"Import": "y"}


class Unattended(unittest.TestCase):
    def setUp(self) -> None:
        self.world = World()

    def test_with_yes_and_the_environment_it_asks_nothing(self) -> None:
        result = self.world.run_unattended("--yes")
        self.assertEqual((result.status, result.script.asked), (0, []))
        self.assertEqual(len(self.world.healthee.tracks), 2)

    def test_without_yes_it_refuses_rather_than_assume(self) -> None:
        result = self.world.run_unattended()
        self.assertEqual((result.status, self.world.writes()), (1, []))
        self.assertIn("--yes", result.text)

    def test_a_dry_run_needs_no_confirmation(self) -> None:
        self.assertEqual(self.world.run_unattended("--dry-run").status, 0)

    def test_a_missing_password_names_the_variable_to_set(self) -> None:
        result = self.world.run_unattended("--yes", env={"ZEPP_PASSWORD": ""})
        self.assertEqual(result.status, 1)
        self.assertIn("ZEPP_PASSWORD", result.text)
        self.assertEqual(self.world.writes(), [])


class Arguments(unittest.TestCase):
    def setUp(self) -> None:
        self.world = World()

    def refused(self, *argv: str) -> str:
        result = self.world.run(*argv, answers=YES)
        self.assertEqual(result.status, 1)
        self.assertEqual(self.world.net.requests, [], "a bad argument must cost no request")
        self.assertEqual(result.script.asked, [], "and no question")
        return result.text

    def test_a_bad_argument_is_refused_before_anything_is_asked_or_sent(self) -> None:
        self.assertIn("--days", self.refused("--days", "0"))
        self.assertIn("--since", self.refused("--since", "last-week"))
        self.assertIn("in the past", self.refused("--since", "2030-01-01"))
        self.assertIn("--zepp-host", self.refused("--zepp-host", "evil.example"))

    def test_days_narrows_the_window(self) -> None:
        result = self.world.run("--days", "6", "--dry-run")
        self.assertIn("2 Zepp workouts", result.text)
        self.assertIn("Since 05 Oct 2026", result.text)

    def test_since_is_the_owners_local_midnight(self) -> None:
        # The run starts 26 Sep 11:56 in Kolkata: inside a window from the 26th, and
        # outside one from the 27th.
        self.assertIn("6 Zepp workouts", self.world.run("--since", "2026-09-26", "--dry-run").text)
        self.assertIn("5 Zepp workouts", self.world.run("--since", "2026-09-27", "--dry-run").text)

    def test_the_address_can_be_given_as_a_flag(self) -> None:
        result = self.world.run("--healthee-url", "https://healthee.test/", "--dry-run")
        self.assertEqual(result.status, 0)
        self.assertFalse(any("address" in prompt for prompt in result.script.asked))

    def test_a_named_zepp_host_is_the_only_one_asked(self) -> None:
        self.world.run("--zepp-host", "api-mifit-in.huami.com", "--dry-run")
        data_hosts = {r.origin for r in self.world.net.requests if r.path.startswith("/v1/sport")}
        self.assertEqual(data_hosts, {HOME})


class WhenThingsGoWrong(unittest.TestCase):
    def setUp(self) -> None:
        self.world = World()

    def test_a_wrong_healthee_password_stops_it_before_zepp_is_contacted(self) -> None:
        result = self.world.run(answers={"Healthee password": "wrong"})
        self.assertEqual(result.status, 1)
        said = " ".join(result.text.split())
        self.assertIn("Healthee's sign-in refused that email and password", said)
        self.assertIn("This is your Healthee login, not your Zepp one", said)
        self.assertEqual(self.world.paths_to("zepp.com"), [])
        self.assertFalse(any("Zepp" in prompt for prompt in result.script.asked))

    def test_a_wrong_zepp_password_writes_nothing(self) -> None:
        result = self.world.run(answers={"Zepp password": "wrong", **YES})
        self.assertEqual((result.status, self.world.writes()), (1, []))
        self.assertIn("Zepp did not accept that email and password (Zepp", result.text)

    def test_a_zepp_failure_after_sign_in_still_ends_the_session(self) -> None:
        self.world.zepp.workouts.clear()
        result = self.world.run(answers=YES)
        self.assertEqual(result.status, 1)
        self.assertIn("Zepp returned no workouts for this account.", result.lines)
        self.assertEqual(self.world.zepp.signed_out, 1)

    def test_a_route_healthee_refuses_does_not_cost_the_rest(self) -> None:
        refusal = json_reply(422, {"detail": "nope"})
        self.world.healthee.forced[("POST", "/api/workout/gps")] = refusal
        result = self.world.run(answers=YES)
        self.assertEqual(result.status, 1)
        self.assertIn("route refused: HTTP 422: nope", result.text)
        self.assertIn("Done: 3 workouts, 0 routes stored.", result.lines)
        self.assertIn("2 routes refused by Healthee; see above.", result.lines)
        self.assertEqual(len(self.world.healthee.workouts), 3)

    def test_a_failure_halfway_says_what_was_already_stored_and_a_rerun_finishes(self) -> None:
        self.world.healthee.forced[("POST", "/ingest/helio")] = json_reply(500, {"detail": "boom"})
        result = self.world.run(answers=YES)
        self.assertEqual(result.status, 1)
        flat = result.text.replace("\n", " ")
        self.assertIn("Stored before the failure below: 0 workouts, 2 routes.", flat)
        self.assertIn("Healthee refused the workouts (HTTP 500: boom).", flat)
        self.assertEqual(self.world.healthee.live_tokens(), [])
        ledger = json.loads(self.world.state.read_text())
        self.assertIn("route_id", ledger["imports"][f"https://healthee.test|{USER_ID}"][str(RUN)])

        self.world.healthee.forced.clear()
        again = self.world.run(answers=YES)
        self.assertEqual(again.status, 0)
        self.assertIn("Done: 3 workouts, 0 routes stored.", again.lines)
        self.assertEqual(len(self.world.healthee.tracks), 2)

    def test_a_token_left_behind_is_swept_by_the_next_run(self) -> None:
        real = self.world.healthee.handle

        def no_delete(request: object) -> object:
            if request.method == "DELETE":  # type: ignore[attr-defined]
                return json_reply(500, {"detail": "boom"})
            return real(request)  # type: ignore[arg-type]

        self.world.healthee.handle = no_delete  # type: ignore[method-assign]
        first = self.world.run(answers=YES)
        self.assertIn("could not be revoked", first.text.replace("\n", " "))
        self.assertEqual(len(self.world.healthee.live_tokens()), 1)

        self.world.healthee.handle = real  # type: ignore[method-assign]
        second = self.world.run("--dry-run")
        self.assertIn("  revoked 1 temporary token left by an earlier run", second.lines)
        self.assertEqual(self.world.healthee.live_tokens(), [])

    def test_an_interrupt_is_an_exit_status_not_a_traceback(self) -> None:
        def interrupted(request: object) -> object:
            raise KeyboardInterrupt

        self.world.zepp.handle = interrupted  # type: ignore[method-assign]
        result = self.world.run(answers=YES)
        self.assertEqual(result.status, 130)
        self.assertIn("nothing is imported twice", result.text)

    def test_a_damaged_record_file_stops_the_run_before_anything_else(self) -> None:
        self.world.state.write_text("{not json")
        result = self.world.run(answers=YES)
        self.assertEqual((result.status, self.world.net.requests), (1, []))


class TamperedRecord(unittest.TestCase):
    def test_a_host_written_into_the_record_gets_the_token_only_if_it_is_zepps(self) -> None:
        world = World()
        world.state.parent.mkdir(parents=True, exist_ok=True)
        record = {"version": 1, "settings": {}, "imports": {}, "hosts": {}}
        for planted in (
            "https://evil.example",
            "http://api-mifit.zepp.com",
            "https://api-mifit.zepp.com.evil.example",
        ):
            record["hosts"] = {"7700112233": planted}
            world.state.write_text(json.dumps(record))
            world.net.requests.clear()
            result = world.run("--dry-run")
            with self.subTest(planted=planted):
                self.assertEqual(result.status, 0)
                origins = {request.origin for request in world.net.requests}
                self.assertNotIn(planted, origins)
                self.assertFalse(any("evil" in origin for origin in origins))

    def test_a_zepp_host_in_the_record_is_asked_first(self) -> None:
        world = World()
        world.state.parent.mkdir(parents=True, exist_ok=True)
        record = {"version": 1, "settings": {}, "imports": {}, "hosts": {"7700112233": HOME}}
        world.state.write_text(json.dumps(record))
        result = world.run("--dry-run")
        asked = [line for line in result.lines if "asking" in line]
        self.assertEqual(asked, ["  Zepp: asking api-mifit-in.huami.com"])


class AppToken(unittest.TestCase):
    def test_a_token_in_the_environment_skips_the_password_and_the_sign_out(self) -> None:
        world = World()
        result = world.run("--dry-run", env={"ZEPP_APP_TOKEN": APP_TOKEN})
        self.assertEqual(result.status, 0)
        self.assertIn("To write: 3 workouts, 2 routes.", result.lines)
        self.assertFalse(any("Zepp" in prompt for prompt in result.script.asked))
        urls = {r.url for r in world.net.requests}
        self.assertTrue(urls.isdisjoint({TOKENS_URL, LOGIN_URL, LOGOUT_URL}))


class Hints(unittest.TestCase):
    def test_the_login_note_is_for_a_person_who_has_to_type_the_email(self) -> None:
        said = "It is not your Zepp login"
        asked = World().run("--dry-run")
        given = World().run("--dry-run", env={"HEALTHEE_EMAIL": HEALTHEE_EMAIL})
        nobody = World().run_unattended("--dry-run")
        self.assertIn(said, " ".join(asked.text.split()))
        self.assertLess(asked.lines.index("  its sign-in goes to auth.healthee.test"), 3)
        for result in (given, nobody):
            self.assertEqual(result.status, 0)
            self.assertNotIn("Zepp login", result.text)

    def test_no_track_for_any_session_is_called_out_as_a_possible_api_change(self) -> None:
        world = World()
        for track_id in (RUN, JOG):
            world.zepp.details[track_id] = {"trackid": track_id, "gps_points": "?"}
        result = world.run("--dry-run")
        self.assertIn("Zepp returned no usable GPS track", result.text)
        self.assertIn("--verbose", result.text)
        self.assertIn("To write: 3 workouts, 0 routes.", result.lines)

    def test_records_that_could_not_be_read_are_counted_out_loud(self) -> None:
        world = World()
        world.zepp.workouts[STRENGTH] = {"trackid": str(STRENGTH), "kind": "strength"}
        result = world.run("--dry-run")
        self.assertIn("1 Zepp record could not be read", result.text)
        self.assertIn("5 Zepp workouts", result.text)

    def test_a_timezone_this_machine_cannot_load_is_said_not_silently_replaced(self) -> None:
        world = World()
        world.healthee.timezone = "Mars/Olympus_Mons"
        result = world.run("--dry-run")
        flat = result.text.replace("\n", " ").replace("   ", " ")
        self.assertIn("times below are in UTC", flat)
        self.assertIn("(UTC)", result.text)
        self.assertIn("26 Sep 06:26  Outdoor run", result.text)


class Verbose(unittest.TestCase):
    def test_shapes_are_printed_and_hold_no_value(self) -> None:
        world = World()
        result = world.run("--dry-run", "--verbose")
        shapes = [line for line in result.lines if "[shape]" in line]
        self.assertGreater(len(shapes), 3)
        self.assertTrue(any("longitude_latitude:str[;x" in line for line in shapes))
        for line in shapes:
            for value in (str(RUN), str(JOG), "1000000000", "2000000000", "2701", APP_TOKEN):
                self.assertNotIn(value, line)

    def test_without_the_flag_no_shape_is_printed(self) -> None:
        self.assertNotIn("[shape]", World().run("--dry-run").text)


if __name__ == "__main__":
    unittest.main()
