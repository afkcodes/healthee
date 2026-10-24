"""The on-disk record: what it keeps, who can read it, and that it is never quietly reset."""

from __future__ import annotations

import json
import stat
import tempfile
import unittest
from pathlib import Path

from zepp_import.failures import ZeppImportError
from zepp_import.ledger import Ledger, default_path

SERVER = "https://healthee.test"
OWNER = "owner-1"


class LedgerFile(unittest.TestCase):
    def setUp(self) -> None:
        self.path = Path(tempfile.mkdtemp(prefix="zepp-ledger-")) / "state" / "ledger.json"

    def test_a_missing_file_is_an_empty_ledger(self) -> None:
        ledger = Ledger.load(self.path)
        self.assertEqual(ledger.setting("healthee_url"), "")
        self.assertEqual(ledger.imported(SERVER, OWNER), {})
        self.assertFalse(self.path.exists())

    def test_what_is_saved_is_read_back(self) -> None:
        ledger = Ledger.load(self.path)
        ledger.remember({"healthee_url": SERVER, "healthee_email": "a@b.c", "zepp_email": "z@b.c"})
        ledger.remember_zepp_host("77", "https://api-mifit-in.huami.com")
        ledger.record(SERVER, OWNER, 1_790_000_000, {"start_ts": 1_790_000_000_000})
        ledger.save()
        again = Ledger.load(self.path)
        self.assertEqual(again.setting("healthee_email"), "a@b.c")
        self.assertEqual(again.zepp_host("77"), "https://api-mifit-in.huami.com")
        self.assertEqual(
            again.imported(SERVER, OWNER), {"1790000000": {"start_ts": 1_790_000_000_000}}
        )

    def test_the_file_and_its_directory_are_the_owners_alone(self) -> None:
        ledger = Ledger.load(self.path)
        ledger.save()
        self.assertEqual(stat.S_IMODE(self.path.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(self.path.parent.stat().st_mode), 0o700)

    def test_a_later_write_for_the_same_workout_adds_to_its_entry(self) -> None:
        ledger = Ledger.load(self.path)
        ledger.record(SERVER, OWNER, 5, {"summary": "import"})
        ledger.record(SERVER, OWNER, 5, {"route_id": "r"})
        self.assertEqual(
            ledger.imported(SERVER, OWNER)["5"], {"summary": "import", "route_id": "r"}
        )

    def test_two_accounts_and_two_servers_do_not_share_a_record(self) -> None:
        ledger = Ledger.load(self.path)
        ledger.record(SERVER, OWNER, 5, {"summary": "import"})
        self.assertEqual(ledger.imported(SERVER, "someone-else"), {})
        self.assertEqual(ledger.imported("https://other.test", OWNER), {})

    def test_only_the_three_non_secret_settings_are_remembered(self) -> None:
        ledger = Ledger.load(self.path)
        ledger.remember({"zepp_email": "z@b.c", "zepp_password": "nope", "healthee_password": "no"})
        ledger.save()
        saved = json.loads(self.path.read_text())
        self.assertEqual(saved["settings"], {"zepp_email": "z@b.c"})

    def test_a_host_is_not_remembered_for_a_session_with_no_user_id(self) -> None:
        ledger = Ledger.load(self.path)
        ledger.remember_zepp_host("", "https://api-mifit.zepp.com")
        self.assertIsNone(ledger.zepp_host(""))

    def test_a_damaged_file_is_a_named_failure_and_is_left_as_it_was(self) -> None:
        self.path.parent.mkdir(parents=True)
        for damaged in ("{not json", "[]", '{"version": 99}', '{"version": 1, "imports": []}'):
            self.path.write_text(damaged)
            with self.subTest(damaged=damaged), self.assertRaises(ZeppImportError) as raised:
                Ledger.load(self.path)
            self.assertEqual(raised.exception.code, "bad_setting")
            self.assertEqual(self.path.read_text(), damaged)


class DefaultPath(unittest.TestCase):
    def test_xdg_state_home_wins(self) -> None:
        path = default_path({"XDG_STATE_HOME": "/state", "HOME": "/home/me"})
        self.assertEqual(path, Path("/state/healthee-zepp-import/ledger.json"))

    def test_otherwise_it_is_under_the_home_directory(self) -> None:
        path = default_path({"HOME": "/home/me"})
        self.assertEqual(path, Path("/home/me/.local/state/healthee-zepp-import/ledger.json"))


if __name__ == "__main__":
    unittest.main()
