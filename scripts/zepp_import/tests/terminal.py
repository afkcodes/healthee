"""A person at a terminal, scripted, and a way to run the real command for them."""

from __future__ import annotations

import tempfile
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass, field
from pathlib import Path

from zepp_import import cli
from zepp_import.deps import Deps
from zepp_import.prompts import Terminal
from zepp_import.tests.support import NOW_S, Net
from zepp_import.zepp_wire import ZeppEndpoints


@dataclass
class Script:
    """A terminal that answers by matching the prompt, and records what it was asked."""

    answers: Mapping[str, str] = field(default_factory=dict)
    interactive: bool = True
    asked: list[str] = field(default_factory=list)

    def _answer(self, prompt: str) -> str:
        self.asked.append(prompt)
        for needle, answer in self.answers.items():
            if needle in prompt:
                return answer
        return ""

    def terminal(self) -> Terminal:
        return Terminal(self.interactive, self._answer, self._answer)


@dataclass
class CliResult:
    status: int
    lines: list[str]
    script: Script

    @property
    def text(self) -> str:
        return "\n".join(self.lines)


def run_cli(
    argv: Sequence[str],
    net: Net,
    *,
    script: Script | None = None,
    env: Mapping[str, str] | None = None,
    state_file: Path | None = None,
    now: Callable[[], float] = lambda: float(NOW_S),
    endpoints: ZeppEndpoints | None = None,
) -> CliResult:
    """Run the real `cli.main` against `net`. The state file is a fresh temp file by default."""
    script = script or Script(interactive=False)
    lines: list[str] = []
    state = state_file or Path(tempfile.mkdtemp(prefix="zepp-import-test-")) / "ledger.json"
    deps = Deps(
        send=net.send,
        endpoints=endpoints or ZeppEndpoints(),
        env=dict(env or {}),
        now=now,
        out=lines.append,
        terminal=script.terminal(),
        pause=lambda _seconds: None,
    )
    status = cli.main([*argv, "--state-file", str(state)], deps)
    return CliResult(status, lines, script)
