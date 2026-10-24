"""What the owner reads: the plan before anything is written, and the outcome after.

Written for a phone terminal, which is where this tool is most likely run: no line is
wider than `WIDTH`, nothing depends on colour, the tool's own words are plain ASCII, and
every skipped session says why it was skipped — a session that silently does not appear
is the failure this tool exists to fix.
"""

from __future__ import annotations

import textwrap
from collections.abc import Callable, Sequence
from datetime import tzinfo

from zepp_import import sports
from zepp_import.failures import SIGN_IN_SCREEN
from zepp_import.localtime import local
from zepp_import.plan import Decision, Step

WIDTH = 56
_ITEM = "  "
_DETAIL = "    "
Out = Callable[[str], None]

ROUTE_NOTE = (
    "Routes: Healthee tries to measure your fitness (VO2max) from each route. A measured "
    "value replaces the estimate for 14 days and can move biological age up or down. "
    "This tool cannot remove a route once it is stored."
)


HEALTHEE_LOGIN_NOTE = (
    "This is the email and password you typed into the Healthee app on "
    f'"{SIGN_IN_SCREEN}". The app stays signed in, so it is easy to forget you have '
    "one. It is not your Zepp login; that is asked for next."
)


NO_TRACKS_NOTE = (
    "Zepp returned no usable GPS track for any session asked about. If the Zepp app shows "
    "maps for them, run again with --verbose and share what it prints: field names and "
    "types only."
)


def when(epoch_s: float, zone: tzinfo) -> str:
    return local(epoch_s, zone).strftime("%d %b %H:%M")


def day(epoch_s: float, zone: tzinfo) -> str:
    return local(epoch_s, zone).strftime("%d %b %Y")


def duration(seconds: int) -> str:
    hours, rest = divmod(max(0, seconds), 3600)
    minutes, secs = divmod(rest, 60)
    return f"{hours}:{minutes:02d}:{secs:02d}" if hours else f"{minutes}:{secs:02d}"


def wrapped(text: str, indent: str = _DETAIL, hang: str = "") -> str:
    """`text` folded to the phone's width. `hang` further indents continuation lines."""
    return textwrap.fill(
        text,
        width=WIDTH,
        initial_indent=indent,
        subsequent_indent=indent + hang,
        break_on_hyphens=False,  # `--env-file` and a host name stay in one piece
        break_long_words=False,  # and so does a shape somebody will copy
    )


def counted(count: int, noun: str) -> str:
    """`1 route`, `2 routes`."""
    return f"{count} {noun}{'' if count == 1 else 's'}"


def _facts(decision: Decision) -> str:
    workout = decision.workout
    facts = [duration(workout.elapsed_s)]
    if workout.distance_m is not None:
        facts.append(f"{workout.distance_m / 1000:.2f} km")
    if workout.calories_kcal is not None:
        facts.append(f"{workout.calories_kcal} kcal")
    if workout.avg_hr is not None:
        facts.append(f"avg HR {workout.avg_hr}")
    return ", ".join(facts)


def _step_line(label: str, step: Step, extra: str = "") -> str:
    text = f"{label}: {step.verdict.value}{extra}"
    return f"{text} ({step.reason})" if step.reason else text


def sport_name(decision: Decision) -> str:
    """The name Healthee will show, or what Zepp called it when there is none."""
    if decision.sport is not None:
        return decision.sport.name
    cloud_type = decision.workout.cloud_type
    if sports.is_auto_detected(cloud_type):
        return "Auto-detected activity"
    return f"Zepp type {cloud_type}"


def describe(decision: Decision, zone: tzinfo) -> list[str]:
    """The lines for one workout: what it was, then what happens to each half of it."""
    lines = [
        f"{_ITEM}{when(decision.workout.start_s, zone)}  {sport_name(decision)}",
        wrapped(_facts(decision)),
        wrapped(_step_line("workout", decision.summary), hang="  "),
    ]
    if decision.route.shown:
        points = f", {decision.route_points:,} points" if decision.route.writes else ""
        lines.append(wrapped(_step_line("route", decision.route, points), hang="  "))
    return lines


def writes(decisions: Sequence[Decision]) -> tuple[int, int]:
    """(summaries, routes) the plan would write."""
    return (
        sum(1 for d in decisions if d.summary.writes),
        sum(1 for d in decisions if d.route.writes),
    )


def to_write(summaries: int, routes: int) -> str:
    return f"{counted(summaries, 'workout')}, {counted(routes, 'route')}"


def plan(decisions: Sequence[Decision], zone: tzinfo, out: Out) -> None:
    for decision in decisions:
        for line in describe(decision, zone):
            out(line)


def fitness_note(scoring: object) -> str:
    """What the server made of a stored route, in the server's own short vocabulary."""
    if not isinstance(scoring, dict):
        return "fitness: the server did not score it on arrival"
    value = scoring.get("vo2max_submax")
    if scoring.get("ok") is True and isinstance(value, (int, float)):
        return f"fitness measured: VO2max {value:.1f} ({scoring.get('method') or 'method unnamed'})"
    reason = scoring.get("reserve_reason") or scoring.get("reason") or "no reason given"
    return f"fitness not measured: {str(reason).replace('_', ' ')}"


def failure(headline: str, remedy: str, out: Out) -> None:
    out("")
    out(wrapped(headline, indent=""))
    out(wrapped(remedy, indent="  "))
