"""What this tool has imported, written down — because the database cannot say.

## Why a file

`workout` has no `source` column and `gps_track.source` is always `'phone'`
(`read/gps.py::ingest_gps_track`). So once a Zepp session is in Healthee, nothing in
Healthee records that it came from Zepp. On a product whose premise is that every number
names its instrument (`tests/derive/test_session_source.py`), that provenance has to live
somewhere until the schema can hold it. It lives here: one entry per imported session,
keyed by the exact `start_ts` it was stored under, which is what a future migration would
need to backfill a `source` column truthfully.

It is NOT what makes a re-run safe. That is the server: `workout` upserts on its primary
key and a route carries a derived id (`plan.py`). Deleting this file loses the record of
where rows came from; it cannot cause a duplicate.

## What else it remembers

The Healthee address, the two account emails, and which Zepp host answered — so the next
run asks for two passwords and nothing else. No password and no token is ever written
here; `tests/test_secrecy.py` checks the file itself.
"""

from __future__ import annotations

import json
import os
from collections.abc import Mapping
from pathlib import Path

from zepp_import import failures

_VERSION = 1
_DIR_NAME = "healthee-zepp-import"
_FILE_NAME = "ledger.json"
REMEMBERED_SETTINGS = ("healthee_url", "healthee_email", "zepp_email")


def default_path(env: Mapping[str, str]) -> Path:
    """`$XDG_STATE_HOME/healthee-zepp-import/ledger.json`, defaulting under `~/.local/state`."""
    base = env.get("XDG_STATE_HOME") or str(Path(env.get("HOME") or Path.home()) / ".local/state")
    return Path(base) / _DIR_NAME / _FILE_NAME


class Ledger:
    """The on-disk record. Load it, change it, `save` it."""

    def __init__(self, path: Path, data: dict | None = None) -> None:
        self.path = path
        self._data: dict = data or {"version": _VERSION, "settings": {}, "hosts": {}, "imports": {}}

    @classmethod
    def load(cls, path: Path) -> Ledger:
        """Read the ledger, or start an empty one. A damaged file is a named failure.

        Never quietly replaced: an unreadable ledger still holds the only record of which
        rows came from Zepp, and starting over would discard it.
        """
        if not path.exists():
            return cls(path)
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError) as error:
            raise failures.bad_setting(
                f"The import record at {path}", f"cannot be read ({type(error).__name__})"
            ) from None
        if not isinstance(data, dict) or data.get("version") != _VERSION:
            raise failures.bad_setting(
                f"The import record at {path}", "is not one this version wrote"
            )
        for section in ("settings", "hosts", "imports"):
            if not isinstance(data.setdefault(section, {}), dict):
                raise failures.bad_setting(
                    f"The import record at {path}", f"has a damaged {section}"
                )
        return cls(path, data)

    def save(self) -> None:
        """Write atomically, readable by the owner only."""
        self.path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        scratch = self.path.with_suffix(".tmp")
        descriptor = os.open(scratch, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(self._data, handle, indent=1, sort_keys=True)
            handle.write("\n")
        os.replace(scratch, self.path)

    # ── remembered, non-secret settings ──────────────────────────────────────

    def setting(self, name: str) -> str:
        value = self._data["settings"].get(name)
        return value if isinstance(value, str) else ""

    def remember(self, settings: Mapping[str, str]) -> None:
        for name in REMEMBERED_SETTINGS:
            if settings.get(name):
                self._data["settings"][name] = settings[name]

    def zepp_host(self, zepp_user_id: str) -> str | None:
        """The Zepp host that last produced this Zepp account's workouts, if any."""
        value = self._data["hosts"].get(zepp_user_id)
        return value if isinstance(value, str) and value else None

    def remember_zepp_host(self, zepp_user_id: str, host: str) -> None:
        if zepp_user_id:
            self._data["hosts"][zepp_user_id] = host

    # ── provenance ───────────────────────────────────────────────────────────

    def record(self, server: str, healthee_user_id: str, track_id: int, entry: Mapping) -> None:
        """Note what was written for one Zepp workout. Later runs add to the same entry."""
        account = self._data["imports"].setdefault(f"{server}|{healthee_user_id}", {})
        account.setdefault(str(track_id), {}).update(entry)

    def imported(self, server: str, healthee_user_id: str) -> Mapping[str, Mapping]:
        account = self._data["imports"].get(f"{server}|{healthee_user_id}")
        return account if isinstance(account, dict) else {}

    def record_weight(self, server: str, healthee_user_id: str, ts_s: int, kg: float) -> None:
        """Note a weight this tool wrote, by its instant."""
        weights = self._data.setdefault("weights", {})
        weights.setdefault(f"{server}|{healthee_user_id}", {})[str(ts_s)] = kg

    def weights_sent(self, server: str, healthee_user_id: str) -> dict[int, float]:
        account = self._data.get("weights", {}).get(f"{server}|{healthee_user_id}")
        if not isinstance(account, dict):
            return {}
        sent: dict[int, float] = {}
        for stamp, kg in account.items():
            if stamp.isdigit() and isinstance(kg, (int, float)) and not isinstance(kg, bool):
                sent[int(stamp)] = float(kg)
        return sent
