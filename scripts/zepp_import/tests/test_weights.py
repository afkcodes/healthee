"""Weight sync: the per-day rule, reading Zepp's log, and a whole run against the fakes."""

from __future__ import annotations

import unittest

from zepp_import.localtime import zone_for
from zepp_import.tests.support import DAY_S, NOW_S, json_reply
from zepp_import.tests.world import World
from zepp_import.weights import (
    ADD,
    CORRECT,
    SENT,
    THERE,
    HealtheeWeights,
    Weighing,
    describe,
    local_day,
    plan,
    read_weighing,
)

ZONE = zone_for("Asia/Kolkata")
D1, D2, D3 = NOW_S - 20 * DAY_S, NOW_S - 10 * DAY_S, NOW_S - 2 * DAY_S


def _healthee(points: dict[int, float]) -> HealtheeWeights:
    by_day = {local_day(ts, ZONE): points[ts] for ts in sorted(points)}
    newest = max(points) if points else None
    return HealtheeWeights(by_day, Weighing(newest, points[newest]) if newest else None)


def _item(ts_s: int, kg: object, *, ms: bool = False) -> dict:
    return {"generatedTime": ts_s * 1000 if ms else ts_s, "summary": {"weight": kg}}


class PlanTest(unittest.TestCase):
    def _verdicts(self, zepp: list[Weighing], stored: dict[int, float], sent=None) -> list:
        steps = plan(zepp, _healthee(stored), ZONE, sent or {})
        return [(step.verdict, step.write_ts_s, step.zepp.kg) for step in steps]

    def test_a_day_only_zepp_weighed_is_added_at_its_zepp_instant(self) -> None:
        self.assertEqual(self._verdicts([Weighing(D1, 80.5)], {}), [(ADD, D1, 80.5)])

    def test_the_same_number_on_the_same_day_is_already_there(self) -> None:
        self.assertEqual(
            self._verdicts([Weighing(D1, 80.5)], {D1 + 60: 80.52}), [(THERE, D1, 80.5)]
        )

    def test_a_different_number_on_healthees_newest_day_corrects_that_row(self) -> None:
        verdicts = self._verdicts([Weighing(D3, 80.5)], {D1: 81.0, D3 + 3600: 79.0})
        self.assertEqual(verdicts, [(CORRECT, D3 + 3600, 80.5)])

    def test_a_later_zepp_reading_on_the_same_day_is_added_and_becomes_the_days(self) -> None:
        verdicts = self._verdicts([Weighing(D3 + 3600, 80.5)], {D3: 79.0})
        self.assertEqual(verdicts, [(ADD, D3 + 3600, 80.5)])

    def test_a_newer_healthee_day_is_left_alone(self) -> None:
        verdicts = self._verdicts([Weighing(D1, 80.5)], {D1: 80.5, D3: 79.0})
        self.assertEqual(verdicts, [(THERE, D1, 80.5)])

    def test_only_the_last_reading_of_a_zepp_day_counts(self) -> None:
        verdicts = self._verdicts([Weighing(D1, 81.0), Weighing(D1 + 600, 80.0)], {})
        self.assertEqual(verdicts, [(ADD, D1 + 600, 80.0)])

    def test_a_reading_sent_before_is_not_sent_again(self) -> None:
        # Healthee kept a later same-day row this tool cannot address.
        verdicts = self._verdicts([Weighing(D1, 80.5)], {D1 + 60: 81.0, D3: 79.0}, {D1: 80.5})
        self.assertEqual(verdicts, [(SENT, D1, 80.5)])

    def test_newest_day_first_and_described_plainly(self) -> None:
        steps = plan([Weighing(D1, 80.5), Weighing(D2, 81.5)], _healthee({D2: 81.0}), ZONE, {})
        self.assertEqual([s.day for s in steps], [local_day(D2, ZONE), local_day(D1, ZONE)])
        self.assertTrue(describe(steps[0]).endswith("81.5 kg  add (Healthee has 81.0)"))


class ReadWeighingTest(unittest.TestCase):
    def test_seconds_and_milliseconds(self) -> None:
        self.assertEqual(read_weighing(_item(D1, 80.5)), Weighing(D1, 80.5))
        self.assertEqual(read_weighing(_item(D1, 80.5, ms=True)), Weighing(D1, 80.5))

    def test_what_is_not_a_body_weight_is_refused(self) -> None:
        for bad in (_item(D1, 0), _item(D1, 400), _item(D1, "80"), _item(D1, True), {}, []):
            with self.subTest(bad=bad):
                self.assertIsNone(read_weighing(bad))


class WeightRunTest(unittest.TestCase):
    def _world(self, page: int = 200) -> World:
        world = World()
        world.zepp.weight_page = page
        world.zepp.weights = [_item(D1, 80.8), _item(D2, 81.5), _item(D3, 80.5)]
        world.healthee.weights = {D1 + 30: 80.8}
        return world

    def test_dry_run_shows_the_plan_and_writes_nothing(self) -> None:
        world = self._world()
        result = world.run_unattended("--dry-run")
        self.assertEqual(result.status, 0)
        self.assertIn("Weight: 3 days weighed in Zepp", result.lines)
        self.assertIn("Weight: would write 2 weights. Dry run: nothing was written.", result.lines)
        self.assertEqual(world.healthee.weights, {D1 + 30: 80.8})

    def test_yes_writes_the_missing_days_and_a_second_run_writes_nothing(self) -> None:
        world = self._world(page=2)  # forces the inclusive paging
        self.assertEqual(world.run_unattended("--yes").status, 0)
        self.assertEqual(world.healthee.weights, {D1 + 30: 80.8, D2: 81.5, D3: 80.5})
        again = world.run_unattended("--yes")
        self.assertIn("Weight: nothing to change.", again.lines)

    def test_unattended_without_yes_writes_no_weight(self) -> None:
        world = self._world()
        world.zepp.workouts.clear()
        result = world.run_unattended()
        self.assertEqual(result.status, 1)
        self.assertEqual(world.healthee.weights, {D1 + 30: 80.8})

    def test_no_weight_leaves_it_out(self) -> None:
        world = self._world()
        result = world.run_unattended("--yes", "--no-weight")
        self.assertFalse(any(line.startswith("Weight") for line in result.lines))
        self.assertEqual(world.healthee.weights, {D1 + 30: 80.8})

    def test_an_unreadable_weight_log_fails_the_run_after_the_workouts(self) -> None:
        world = self._world()
        path = "/users/7700112233/members/-1/weightRecords"
        world.zepp.forced[path] = json_reply(200, {"surprise": True})
        result = world.run_unattended("--yes")
        self.assertEqual(result.status, 1)
        self.assertIn("/ingest/helio", " ".join(world.writes()))
        self.assertIn("  No weight was changed.", result.lines)


if __name__ == "__main__":
    unittest.main()
