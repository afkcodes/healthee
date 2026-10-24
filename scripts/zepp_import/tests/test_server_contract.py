"""The server facts this tool restates, checked against the server's own source.

The tool cannot import the server (it has to run with nothing installed), so it carries
copies: sport names, the ten-minute listing floor, the route point cap, the upsert's
COALESCE. A copy that drifts is a silent wrong answer — a session filed under the wrong
sport, a route refused for a limit the tool thought was higher. These tests read the
server files as text and fail when a copy no longer matches.

Skipped when the tool has been copied out of the repository, where there is nothing to
read.
"""

from __future__ import annotations

import ast
import re
import unittest
from pathlib import Path

from zepp_import import failures, healthee_api, plan, sports, zepp_parse

_SERVER = Path(__file__).resolve().parents[3] / "apps" / "server" / "src" / "healthee"


def _source(relative: str) -> str:
    return (_SERVER / relative).read_text(encoding="utf-8")


def _assigned(source: str, name: str) -> object:
    """The literal a module-level `name = ...` (or `name: T = ...`) is assigned."""
    for node in ast.parse(source).body:
        if isinstance(node, ast.Assign):
            targets, value = node.targets, node.value
        elif isinstance(node, ast.AnnAssign) and node.value is not None:
            targets, value = [node.target], node.value
        else:
            continue
        if any(isinstance(target, ast.Name) and target.id == name for target in targets):
            return ast.literal_eval(value)
    raise AssertionError(f"{name} is no longer assigned at module level")


@unittest.skipUnless(_SERVER.is_dir(), "the server source is not next to this tool")
class ServerContract(unittest.TestCase):
    def test_the_sport_name_table_is_the_servers_table(self) -> None:
        names = _assigned(_source("read/common.py"), "_SPORT_NAMES")
        self.assertEqual(sports.DEVICE_SPORT_NAMES, names)

    def test_an_unnamed_code_reads_the_way_the_server_reads_it(self) -> None:
        self.assertIn('_SPORT_NAMES.get(code, "Activity")', _source("read/common.py"))
        self.assertEqual(sports.device_sport_name(223), "Activity")
        self.assertEqual(sports.device_sport_name(None), "Activity")

    def test_the_generic_codes_are_the_ones_the_server_calls_activity(self) -> None:
        self.assertEqual(sports.device_sport_name(44), "Activity")
        self.assertEqual(sports.device_sport_name(0), "Activity")
        self.assertEqual(plan._GENERIC_SPORT_CODES, (0, 44))

    def test_the_skipped_fix_accuracy_is_the_apps_own(self) -> None:
        recorder = _SERVER.parents[3] / "apps/mobile/lib/data/gps/gps_run.dart"
        expected = f"static const maxAccuracyM = {float(zepp_parse.MAX_ACCURACY_M)};"
        self.assertIn(expected, recorder.read_text(encoding="utf-8"))

    def test_the_sign_in_screen_this_tool_names_is_still_called_that(self) -> None:
        widgets = _SERVER.parents[3] / "apps/mobile/lib/features/signin/widgets"
        form = (widgets / "server_signin_form.dart").read_text(encoding="utf-8")
        self.assertIn(f"'{failures.SIGN_IN_SCREEN}'", form)

    def test_what_the_readme_says_about_the_healthee_login_is_still_true(self) -> None:
        repo = _SERVER.parents[3]
        readme = (Path(__file__).resolve().parents[1] / "README.md").read_text(encoding="utf-8")
        welcome = repo / "apps/mobile/lib/features/welcome/welcome_screen.dart"
        quoted = "Healthee has no account of its own"
        self.assertIn(quoted, readme)
        self.assertIn(quoted, welcome.read_text(encoding="utf-8"))
        # The email lookup it gives: that container, that table, that column.
        self.assertIn("docker exec healthee-db ", readme)
        compose = repo / "infra/docker/docker-compose.prod.yml"
        self.assertIn("container_name: healthee-db", compose.read_text(encoding="utf-8"))
        table = _source("db/schema.sql").split("CREATE TABLE IF NOT EXISTS app_user (")[1]
        self.assertIn("email ", table.split(");")[0])

    def test_strength_sessions_map_to_codes_the_weekly_target_counts(self) -> None:
        strength = _assigned(_source("read/fitness.py"), "_STRENGTH_SPORTS")
        assert isinstance(strength, dict)
        for cloud_type in (49, 50, 52):  # HIIT, core, strength
            sport = sports.healthee_sport(cloud_type)
            assert sport is not None
            self.assertIn(sport.code, strength)

    def test_the_listing_floor_is_still_ten_minutes(self) -> None:
        self.assertEqual(_assigned(_source("read/fitness.py"), "_MIN_WORKOUT_S"), plan.MIN_LISTED_S)

    def test_the_route_point_cap_and_floor(self) -> None:
        request = _source("read/gps_request.py")
        self.assertIn(f"max_length={zepp_parse.MAX_TRACK_POINTS}", request)
        self.assertIn(f"if len(pts) < {plan.MIN_ROUTE_POINTS}:", _source("read/gps.py"))

    def test_the_route_list_is_still_capped_where_the_duplicate_check_assumes(self) -> None:
        limit = healthee_api.TRACK_LIST_LIMIT
        self.assertIn(f"max(1, min(limit, {limit}))", _source("read/gps.py"))

    def test_a_partial_push_still_preserves_what_it_does_not_send(self) -> None:
        upsert = re.sub(r"\s+", " ", _source("ingest/upsert.py"))
        for column in ("sport", "duration_s"):
            self.assertIn(f"{column} = COALESCE(%s::int, workout.{column})", upsert)
        for column in ("calories", "distance_m", "avg_hr", "max_hr", "min_hr"):
            self.assertIn(f"{column} = COALESCE(EXCLUDED.{column}, workout.{column})", upsert)

    def test_a_push_may_carry_more_workouts_than_one_chunk(self) -> None:
        cap = _assigned(_source("ingest/models.py"), "_MAX_WORKOUTS")
        assert isinstance(cap, int)
        self.assertGreaterEqual(cap, healthee_api._PUSH_CHUNK)

    def test_stored_instants_are_still_written_the_way_python_3_10_reads_them(self) -> None:
        # `datetime.fromisoformat` on 3.10 reads `isoformat()` output and little else, and
        # a start this tool cannot read ends the run (`healthee_rows.read_all`).
        listed = _source("read/fitness.py")
        self.assertIn('"start_iso": start_ts.isoformat() if start_ts else None', listed)
        tracks = _source("read/gps.py")
        self.assertIn('"start_ts": r[1].isoformat()', tracks)
        self.assertIn('"end_ts": r[2].isoformat()', tracks)

    def test_the_endpoints_this_tool_calls_still_exist(self) -> None:
        routers = "".join(
            _source(f"api/routers/{name}.py") for name in ("auth", "gps", "ingest", "activity")
        )
        for route in (
            '@router.get("/auth-config"',
            '@router.get("/me"',
            '@router.post("/device"',
            '@router.get("/device"',
            '@router.delete("/device/{token_id}"',
            '@router.post("/api/workout/gps")',
            '@router.get("/api/workout/gps")',
            '@router.post("/ingest/helio"',
            '@router.get("/api/activity")',
        ):
            with self.subTest(route=route):
                self.assertIn(route, routers)


if __name__ == "__main__":
    unittest.main()
