"""Where each setting comes from — and the one rule about passwords.

Order, for every setting: the command line, then the environment (an `--env-file` is
merged into it first), then whatever the last run remembered, then a question on the
terminal. When there is no terminal the question becomes a named failure.

**Passwords are never remembered and never accepted on the command line.** A flag ends up
in shell history and in the process list; the ledger is a file. They come from the
environment or from a hidden prompt, and that is all.

An env file holds passwords, so it is refused unless only its owner can read it — the
same check `ssh` makes on a private key, for the same reason.
"""

from __future__ import annotations

import stat
from collections.abc import Callable, Mapping
from dataclasses import dataclass
from pathlib import Path

from zepp_import import failures

ENV_NAMES = {
    "healthee_url": "HEALTHEE_URL",
    "healthee_email": "HEALTHEE_EMAIL",
    "healthee_password": "HEALTHEE_PASSWORD",
    "zepp_email": "ZEPP_EMAIL",
    "zepp_password": "ZEPP_PASSWORD",
    "zepp_app_token": "ZEPP_APP_TOKEN",
    "zepp_user_id": "ZEPP_USER_ID",
}
_OTHERS_CAN_READ = stat.S_IRWXG | stat.S_IRWXO


def load_env_file(path: Path) -> dict[str, str]:
    """`KEY=value` lines from a file only its owner can read."""
    try:
        mode = path.stat().st_mode
        text = path.read_text(encoding="utf-8")
    except OSError as error:
        problem = f"cannot be read ({type(error).__name__})"
        raise failures.bad_setting(f"--env-file {path}", problem) from None
    if mode & _OTHERS_CAN_READ:
        raise failures.bad_setting(
            f"--env-file {path}", "is readable by other users; run: chmod 600 on it"
        )
    values: dict[str, str] = {}
    for raw_line in text.splitlines():
        line = raw_line.strip().removeprefix("export ").strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
            value = value[1:-1]
        values[key.strip()] = value
    return values


@dataclass(frozen=True)
class Terminal:
    """The person, if there is one. `interactive` False means nobody can be asked."""

    interactive: bool
    ask: Callable[[str], str]
    ask_hidden: Callable[[str], str]


class Settings:
    """Resolves one setting at a time, so nothing is asked for before it is needed."""

    def __init__(
        self, env: Mapping[str, str], remembered: Callable[[str], str], terminal: Terminal
    ) -> None:
        self._env = env
        self._remembered = remembered
        self._terminal = terminal

    def from_env(self, name: str) -> str:
        return (self._env.get(ENV_NAMES[name]) or "").strip()

    def known(self, name: str) -> bool:
        """True when the environment or an earlier run already holds this setting."""
        return bool(self.from_env(name) or self._remembered(name))

    def text(self, name: str, label: str, override: str | None = None) -> str:
        """A non-secret setting. The remembered value is offered as the default."""
        given = (override or "").strip() or self.from_env(name)
        if given:
            return given
        default = self._remembered(name)
        if not self._terminal.interactive:
            if default:
                return default
            raise failures.missing_setting(label, ENV_NAMES[name])
        answer = self._terminal.ask(f"{label}{f' [{default}]' if default else ''}: ").strip()
        if answer or default:
            return answer or default
        raise failures.bad_setting(label, "nothing was entered")

    def secret(self, name: str, label: str) -> str:
        """A password: the environment or a hidden prompt, and never anything else."""
        given = self._env.get(ENV_NAMES[name]) or ""
        if given:
            return given
        if not self._terminal.interactive:
            raise failures.missing_setting(label, ENV_NAMES[name])
        answer = self._terminal.ask_hidden(f"{label} (hidden): ")
        if not answer:
            raise failures.bad_setting(label, "nothing was entered")
        return answer

    def confirm(self, question: str) -> bool:
        """A yes/no the owner must answer. No terminal means no."""
        if not self._terminal.interactive:
            return False
        return self._terminal.ask(f"{question} [y/N]: ").strip().lower() in ("y", "yes")
