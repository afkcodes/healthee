"""Where a setting comes from, and the one rule about passwords."""

from __future__ import annotations

import os
import tempfile
import unittest
from collections.abc import Callable
from pathlib import Path

from zepp_import.failures import ZeppImportError
from zepp_import.prompts import Settings, load_env_file
from zepp_import.tests.terminal import Script


def _remembered(values: dict[str, str]) -> Callable[[str], str]:
    return lambda name: values.get(name, "")


class Text(unittest.TestCase):
    def test_a_flag_beats_the_environment(self) -> None:
        script = Script()
        chosen = Settings({"HEALTHEE_URL": "from-env"}, _remembered({}), script.terminal())
        self.assertEqual(chosen.text("healthee_url", "Healthee address", "from-flag"), "from-flag")
        self.assertEqual(script.asked, [])

    def test_the_environment_beats_what_was_remembered(self) -> None:
        script = Script()
        chosen = Settings(
            {"HEALTHEE_URL": " from-env "}, _remembered({"healthee_url": "old"}), script.terminal()
        )
        self.assertEqual(chosen.text("healthee_url", "Healthee address"), "from-env")
        self.assertEqual(script.asked, [])

    def test_a_setting_is_known_when_the_environment_or_an_earlier_run_holds_it(self) -> None:
        terminal = Script().terminal()
        in_env = Settings({"ZEPP_EMAIL": "me@zepp.test"}, _remembered({}), terminal)
        remembered = Settings({}, _remembered({"zepp_email": "me@zepp.test"}), terminal)
        blank = Settings({"ZEPP_EMAIL": "  "}, _remembered({}), terminal)
        self.assertEqual(
            [s.known("zepp_email") for s in (in_env, remembered, blank)], [True, True, False]
        )

    def test_the_remembered_value_is_offered_and_enter_accepts_it(self) -> None:
        script = Script()
        chosen = Settings({}, _remembered({"zepp_email": "me@zepp.test"}), script.terminal())
        self.assertEqual(chosen.text("zepp_email", "Zepp email"), "me@zepp.test")
        self.assertEqual(script.asked, ["Zepp email [me@zepp.test]: "])

    def test_a_typed_answer_replaces_the_remembered_one(self) -> None:
        script = Script({"Zepp email": " new@zepp.test "})
        chosen = Settings({}, _remembered({"zepp_email": "old@zepp.test"}), script.terminal())
        self.assertEqual(chosen.text("zepp_email", "Zepp email"), "new@zepp.test")

    def test_with_nobody_to_ask_the_remembered_value_is_used(self) -> None:
        script = Script(interactive=False)
        chosen = Settings({}, _remembered({"zepp_email": "me@zepp.test"}), script.terminal())
        self.assertEqual(chosen.text("zepp_email", "Zepp email"), "me@zepp.test")
        self.assertEqual(script.asked, [])

    def test_with_nobody_to_ask_and_nothing_known_it_is_a_named_failure(self) -> None:
        chosen = Settings({}, _remembered({}), Script(interactive=False).terminal())
        with self.assertRaises(ZeppImportError) as raised:
            chosen.text("zepp_email", "Zepp email")
        self.assertEqual(raised.exception.code, "missing_setting")
        self.assertIn("ZEPP_EMAIL", raised.exception.remedy)

    def test_an_empty_answer_is_refused(self) -> None:
        chosen = Settings({}, _remembered({}), Script().terminal())
        with self.assertRaises(ZeppImportError) as raised:
            chosen.text("zepp_email", "Zepp email")
        self.assertEqual(raised.exception.code, "bad_setting")


class Secret(unittest.TestCase):
    def test_a_password_comes_from_the_environment(self) -> None:
        script = Script()
        chosen = Settings({"ZEPP_PASSWORD": " kept exactly "}, _remembered({}), script.terminal())
        self.assertEqual(chosen.secret("zepp_password", "Zepp password"), " kept exactly ")
        self.assertEqual(script.asked, [])

    def test_or_from_a_hidden_prompt(self) -> None:
        script = Script({"Zepp password": "typed"})
        chosen = Settings({}, _remembered({}), script.terminal())
        self.assertEqual(chosen.secret("zepp_password", "Zepp password"), "typed")
        self.assertEqual(script.asked, ["Zepp password (hidden): "])

    def test_and_never_from_what_was_remembered(self) -> None:
        script = Script(interactive=False)
        chosen = Settings(
            {}, _remembered({"zepp_password": "should-not-be-here"}), script.terminal()
        )
        with self.assertRaises(ZeppImportError) as raised:
            chosen.secret("zepp_password", "Zepp password")
        self.assertEqual(raised.exception.code, "missing_setting")

    def test_an_empty_password_is_refused(self) -> None:
        chosen = Settings({}, _remembered({}), Script().terminal())
        with self.assertRaises(ZeppImportError):
            chosen.secret("zepp_password", "Zepp password")


class Confirm(unittest.TestCase):
    def test_only_a_yes_is_a_yes(self) -> None:
        for answer, expected in (
            ("y", True),
            ("YES", True),
            ("", False),
            ("n", False),
            ("yep", False),
        ):
            chosen = Settings({}, _remembered({}), Script({"Import": answer}).terminal())
            with self.subTest(answer=answer):
                self.assertEqual(chosen.confirm("Import 3 summaries?"), expected)

    def test_no_terminal_means_no(self) -> None:
        chosen = Settings(
            {}, _remembered({}), Script({"Import": "y"}, interactive=False).terminal()
        )
        self.assertFalse(chosen.confirm("Import 3 summaries?"))


class EnvFile(unittest.TestCase):
    def setUp(self) -> None:
        self.path = Path(tempfile.mkdtemp(prefix="zepp-env-")) / "zepp.env"

    def write(self, text: str, mode: int = 0o600) -> None:
        self.path.write_text(text)
        os.chmod(self.path, mode)

    def test_lines_quotes_comments_and_export_are_read(self) -> None:
        self.write(
            "# a comment\n\nHEALTHEE_URL=healthee.test\nexport ZEPP_EMAIL='me@zepp.test'\n"
            'ZEPP_PASSWORD="a=b c"\nnot a setting\nEMPTY=\n'
        )
        self.assertEqual(
            load_env_file(self.path),
            {
                "HEALTHEE_URL": "healthee.test",
                "ZEPP_EMAIL": "me@zepp.test",
                "ZEPP_PASSWORD": "a=b c",
                "EMPTY": "",
            },
        )

    def test_a_file_others_can_read_is_refused_because_it_holds_passwords(self) -> None:
        for mode in (0o644, 0o640, 0o604):
            self.write("ZEPP_PASSWORD=x\n", mode)
            with self.subTest(mode=oct(mode)), self.assertRaises(ZeppImportError) as raised:
                load_env_file(self.path)
            self.assertIn("chmod 600", raised.exception.headline)

    def test_a_missing_file_is_a_named_failure(self) -> None:
        with self.assertRaises(ZeppImportError) as raised:
            load_env_file(self.path)
        self.assertEqual(raised.exception.code, "bad_setting")


if __name__ == "__main__":
    unittest.main()
