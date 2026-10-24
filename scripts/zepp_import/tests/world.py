"""One small, complete world for the end-to-end tests: a Zepp account, a Healthee, a person.

Six Zepp sessions over the last fifteen days, one of each kind the plan treats differently:

| name     | what it is                         | what should happen                        |
|----------|------------------------------------|-------------------------------------------|
| RUN      | a 31-minute run with a route       | summary imported, route imported          |
| JOG      | a 24-minute run with a route, that | summary UPDATED (distance, sport), route   |
|          | Healthee holds as an "Activity"    | imported                                  |
| AUTO     | an auto-detected bout              | skipped                                   |
| SHORT    | a 6-minute run with a route        | skipped, and its route with it            |
| STRENGTH | 45 minutes of strength, no GPS     | summary imported, no route                |
| ODD      | a type nobody has catalogued       | skipped                                   |
"""

from __future__ import annotations

import tempfile
from collections.abc import Sequence
from dataclasses import dataclass, field
from pathlib import Path

from zepp_import.tests import fixtures
from zepp_import.tests.fake_healthee import FakeHealthee
from zepp_import.tests.fake_zepp import FakeZepp
from zepp_import.tests.support import DAY_S, NOW_S, Net, sentinel
from zepp_import.tests.terminal import CliResult, Script, run_cli

ZEPP_EMAIL = "runner@zepp.example"
ZEPP_PASSWORD = sentinel("zepp-password")
HEALTHEE_EMAIL = "owner@healthee.example"
HEALTHEE_PASSWORD = sentinel("healthee-password")

RUN = NOW_S - 15 * DAY_S
JOG = NOW_S - 9 * DAY_S
AUTO = NOW_S - 8 * DAY_S
SHORT = NOW_S - 7 * DAY_S
STRENGTH = NOW_S - 5 * DAY_S
ODD = NOW_S - 3 * DAY_S
JOG_STORED = JOG - 30  # Healthee's own row for the jog starts half a minute earlier

ANSWERS = {
    "Healthee address": "healthee.test",
    "Healthee email": HEALTHEE_EMAIL,
    "Healthee password": HEALTHEE_PASSWORD,
    "Zepp email": ZEPP_EMAIL,
    "Zepp password": ZEPP_PASSWORD,
}
ENV = {
    "HEALTHEE_URL": "healthee.test",
    "HEALTHEE_EMAIL": HEALTHEE_EMAIL,
    "HEALTHEE_PASSWORD": HEALTHEE_PASSWORD,
    "ZEPP_EMAIL": ZEPP_EMAIL,
    "ZEPP_PASSWORD": ZEPP_PASSWORD,
}


@dataclass
class World:
    zepp: FakeZepp = field(default_factory=lambda: FakeZepp(ZEPP_EMAIL, ZEPP_PASSWORD))
    healthee: FakeHealthee = field(
        default_factory=lambda: FakeHealthee(HEALTHEE_EMAIL, HEALTHEE_PASSWORD)
    )
    state: Path = field(
        default_factory=lambda: Path(tempfile.mkdtemp(prefix="zepp-world-")) / "ledger.json"
    )

    def __post_init__(self) -> None:
        self.net = Net([self.zepp, self.healthee])
        zepp = self.zepp
        zepp.add(fixtures.summary(RUN), fixtures.detail(RUN, points=120))
        zepp.add(fixtures.summary(JOG, minutes=24, dis="4010"), fixtures.detail(JOG, points=300))
        zepp.add(fixtures.summary(AUTO, cloud_type=223, minutes=14, dis="900"))
        zepp.add(fixtures.summary(SHORT, minutes=6), fixtures.detail(SHORT, points=40))
        zepp.add(fixtures.summary(STRENGTH, cloud_type=52, minutes=45, dis="-1"))
        zepp.add(fixtures.summary(ODD, cloud_type=999, minutes=20))
        self.healthee.store_workout(JOG_STORED, sport=44, duration_s=1500, calories=180, avg_hr=140)

    def run(
        self,
        *argv: str,
        answers: dict[str, str] | None = None,
        env: dict[str, str] | None = None,
        interactive: bool = True,
    ) -> CliResult:
        """Run the CLI as a person at a terminal who answers `answers` (plus the sign-ins)."""
        script = Script({**ANSWERS, **(answers or {})}, interactive=interactive)
        return run_cli(argv, self.net, script=script, env=env, state_file=self.state)

    def run_unattended(self, *argv: str, env: dict[str, str] | None = None) -> CliResult:
        """Run the CLI with no terminal and everything in the environment."""
        script = Script(interactive=False)
        return run_cli(
            argv, self.net, script=script, env={**ENV, **(env or {})}, state_file=self.state
        )

    def writes(self) -> list[str]:
        """Every request that changes Healthee's data, in order."""
        return [
            f"{r.method} {r.path}"
            for r in self.net.requests
            if r.method != "GET" and r.path in ("/ingest/helio", "/api/workout/gps")
        ]

    def paths_to(self, origin_part: str) -> Sequence[str]:
        return [r.path for r in self.net.to(origin_part)]
