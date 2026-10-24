"""The outside world, as a run sees it — and the one place the real one is assembled.

Every effect a run has goes through a field of `Deps`: HTTP (`send`), the clock, the
terminal, the environment, standard output, and the pause between Zepp requests. The
tests replace all of them, which is how the whole command gets run against a fake Zepp
and a fake Healthee with no network and nobody at the keyboard.
"""

from __future__ import annotations

import getpass
import os
import sys
import time
from collections.abc import Callable, Mapping
from dataclasses import dataclass

from zepp_import import transport
from zepp_import.prompts import Terminal
from zepp_import.transport import Send
from zepp_import.zepp_wire import ZeppEndpoints


@dataclass(frozen=True)
class Deps:
    send: Send
    endpoints: ZeppEndpoints
    env: Mapping[str, str]
    now: Callable[[], float]
    out: Callable[[str], None]
    terminal: Terminal
    pause: Callable[[float], None]


def _quiet_eof(ask: Callable[[str], str]) -> Callable[[str], str]:
    """`ask`, with a closed stdin read as an empty answer rather than a traceback."""

    def asked(prompt: str) -> str:
        try:
            return ask(prompt)
        except EOFError:
            return ""

    return asked


def _say(line: str) -> None:
    print(line, flush=True)


def real_deps() -> Deps:
    for stream in (sys.stdout, sys.stderr):
        # A server's reason can hold a character this terminal's encoding lacks, and a
        # report that crashes on one is worse than a report that prints "?" for it.
        reconfigure = getattr(stream, "reconfigure", None)
        if reconfigure is not None:
            reconfigure(errors="replace")
    return Deps(
        send=transport.send,
        endpoints=ZeppEndpoints(),
        env=os.environ,
        now=time.time,
        out=_say,
        terminal=Terminal(sys.stdin.isatty(), _quiet_eof(input), _quiet_eof(getpass.getpass)),
        pause=time.sleep,
    )
