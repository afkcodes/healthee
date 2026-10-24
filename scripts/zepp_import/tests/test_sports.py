"""Zepp cloud types → Healthee device sport codes, and the mislabels this prevents."""

from __future__ import annotations

import unittest

from zepp_import import sports


class Mapping(unittest.TestCase):
    def test_the_two_enums_disagree_which_is_why_there_is_a_table(self) -> None:
        # Cloud 8 is a treadmill; device 8 is a pool swim. Cloud 52 is strength; device
        # 52 is boxing. Written through unchanged, both would be filed under the wrong name.
        self.assertEqual(sports.healthee_sport(8), sports.HealtheeSport(4, "Treadmill"))
        self.assertEqual(sports.healthee_sport(52), sports.HealtheeSport(14, "Strength"))
        self.assertEqual(sports.healthee_sport(14), sports.HealtheeSport(8, "Pool swim"))

    def test_running_walking_and_cycling(self) -> None:
        self.assertEqual(sports.healthee_sport(1), sports.HealtheeSport(1, "Outdoor run"))
        self.assertEqual(sports.healthee_sport(6), sports.HealtheeSport(2, "Walking"))
        self.assertEqual(sports.healthee_sport(9), sports.HealtheeSport(3, "Outdoor cycling"))
        self.assertEqual(sports.healthee_sport(7), sports.HealtheeSport(1, "Outdoor run"))  # trail

    def test_every_mapped_type_names_a_sport_healthee_can_show(self) -> None:
        for cloud_type in (1, 6, 7, 8, 9, 10, 12, 14, 15, 16, 21, 23, 49, 50, 52, 53, 60, 211):
            sport = sports.healthee_sport(cloud_type)
            with self.subTest(cloud_type=cloud_type):
                assert sport is not None
                self.assertEqual(sports.DEVICE_SPORT_NAMES[sport.code], sport.name)

    def test_a_stored_code_is_named_the_way_the_app_names_it(self) -> None:
        self.assertEqual(sports.device_sport_name(8), "Pool swim")
        self.assertEqual(sports.device_sport_name(52), "Boxing")
        self.assertEqual(sports.device_sport_name(999), "Activity")

    def test_an_unknown_type_has_no_mapping_rather_than_a_guess(self) -> None:
        for cloud_type in (0, 2, 44, 999, -1):
            with self.subTest(cloud_type=cloud_type):
                self.assertIsNone(sports.healthee_sport(cloud_type))

    def test_the_auto_detected_bout_is_recognised_and_never_mapped(self) -> None:
        self.assertTrue(sports.is_auto_detected(223))
        self.assertFalse(sports.is_auto_detected(1))
        self.assertIsNone(sports.healthee_sport(223))


class Routes(unittest.TestCase):
    def test_outdoor_sessions_can_carry_a_route(self) -> None:
        for cloud_type in (1, 6, 7, 9, 15, 211):  # run, walk, trail run, ride, hike, road ride
            with self.subTest(cloud_type=cloud_type):
                self.assertTrue(sports.can_have_route(cloud_type))

    def test_indoor_and_unknown_sessions_are_not_asked_for_one(self) -> None:
        for cloud_type in (8, 10, 12, 14, 16, 21, 23, 49, 50, 52, 53, 60, 223, 999):
            with self.subTest(cloud_type=cloud_type):
                self.assertFalse(sports.can_have_route(cloud_type))


if __name__ == "__main__":
    unittest.main()
