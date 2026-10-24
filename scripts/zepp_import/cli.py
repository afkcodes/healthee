"""The command: arguments in, one import run out, an exit status back.

    python3 scripts/zepp-import --dry-run        # show the plan, write nothing
    python3 scripts/zepp-import                  # show the plan, ask, then import

Exit status: 0 when everything asked for was done (a dry run, and "nothing to import",
count), 1 for a named failure or a route the server refused, 130 when interrupted.

Everything that touches the outside world arrives through `deps.Deps`, so the tests run
this same `main` against a fake Zepp and a fake Healthee.
"""

from __future__ import annotations

import argparse
from collections.abc import Sequence
from pathlib import Path

from zepp_import import __version__, failures, report
from zepp_import.deps import Deps, real_deps
from zepp_import.run import Run

_EPILOG = (
    "Passwords are asked for on the terminal, or read from HEALTHEE_PASSWORD and "
    "ZEPP_PASSWORD. They are never accepted as arguments and never stored. "
    "See scripts/zepp_import/README.md."
)


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="zepp-import",
        description="Import workouts recorded in the Zepp app into your Healthee server.",
        epilog=_EPILOG,
    )
    window = parser.add_mutually_exclusive_group()
    window.add_argument("--days", type=int, metavar="N", help="how far back to look (default 30)")
    window.add_argument("--since", metavar="YYYY-MM-DD", help="look back to this date instead")
    parser.add_argument("--dry-run", action="store_true", help="show the plan and write nothing")
    parser.add_argument("--yes", action="store_true", help="import without asking, routes included")
    parser.add_argument(
        "--no-routes", action="store_true", help="import workouts without their routes"
    )
    parser.add_argument(
        "--no-weight", action="store_true", help="leave body weight out of the sync"
    )
    parser.add_argument("--healthee-url", metavar="HOST", help="your Healthee server")
    parser.add_argument(
        "--zepp-host", metavar="HOST", help="ask only this Zepp region host for your workouts"
    )
    parser.add_argument(
        "--env-file", metavar="FILE", type=Path, help="read settings from a chmod-600 file"
    )
    parser.add_argument(
        "--state-file", metavar="FILE", type=Path, help="where the import record is kept"
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="also print the shape of each Zepp reply: field names and types, never values",
    )
    parser.add_argument("--version", action="version", version=f"zepp-import {__version__}")
    return parser


def main(argv: Sequence[str] | None = None, deps: Deps | None = None) -> int:
    """Run one import. Returns the process exit status."""
    args = _parser().parse_args(argv)
    deps = deps or real_deps()
    try:
        return Run(args, deps).go()
    except failures.ZeppImportError as failure:
        report.failure(failure.headline, failure.remedy, deps.out)
        return 1
    except KeyboardInterrupt:
        deps.out("")
        deps.out("Stopped. Run it again when ready: nothing is imported twice.")
        return 130
