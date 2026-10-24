"""A shape may be pasted into a bug report. These tests are why that is safe."""

from __future__ import annotations

import json
import unittest

from zepp_import.shapes import MAX_CHARS, fields, layout, shape
from zepp_import.tests import fixtures

START = 1_790_000_000


class NoValueSurvives(unittest.TestCase):
    def test_a_workout_reply_is_described_without_one_digit_of_it(self) -> None:
        reply = {
            "code": 1,
            "message": "success",
            "data": {"next": START, "summary": [fixtures.summary(START)] * 3},
        }
        described = shape(reply)
        self.assertIn("summary:[{", described)
        self.assertIn("trackid:numstr", described)
        self.assertIn("}x3]", described)
        for value in (str(START), "2701", "296", "133", "158", fixtures.SOURCE, "success"):
            self.assertNotIn(value, described)

    def test_a_track_is_a_count_and_a_pattern_never_a_coordinate(self) -> None:
        described = shape(fixtures.detail(START, points=40))
        self.assertIn("longitude_latitude:str[;x41 like 9,9]", described)
        self.assertIn("time:str[;x41 like 9]", described)
        for digits in ("1000000000", "2000000000", "1500", "2300", "41200"):
            self.assertNotIn(digits, described)

    def test_free_text_is_only_ever_called_str(self) -> None:
        self.assertEqual(shape("my password is hunter2"), "str")
        self.assertEqual(shape({"note": "meet at 5 Rue X"}), "{note:str}")
        self.assertEqual(shape("a;b c"), "str[;x2 like a]")
        self.assertEqual(shape(""), "str(empty)")

    def test_a_pattern_keeps_punctuation_and_nothing_else(self) -> None:
        self.assertEqual(shape("-12,40;3,4"), "str[;x2 like -9,9]")
        self.assertEqual(shape("me@example.com;x"), "str[;x2 like a?a.a]")

    def test_a_key_that_is_data_is_masked(self) -> None:
        described = shape(
            {"2026-09-26": 1, "1790000000": 2, "user7700112233": 3, "a b": 4, "spo2_max": 5}
        )
        self.assertEqual(described, "{<key>:int,spo2_max:int}")

    def test_scalars_are_named_by_type(self) -> None:
        self.assertEqual(shape([1, 2.5, None, True]), "[intx4]")
        self.assertEqual(
            shape({"a": None, "b": True, "c": 1.5, "d": 7, "e": "7"}),
            "{a:null,b:bool,c:float,d:int,e:numstr}",
        )
        self.assertEqual(shape([]), "[]")


class Bounded(unittest.TestCase):
    def test_depth_is_capped(self) -> None:
        self.assertEqual(shape({"a": [[[[[1]]]]]}), "{a:[[[...x1]x1]x1]}")

    def test_length_is_capped_so_a_reply_cannot_ride_out_in_its_shape(self) -> None:
        huge = {f"field_{chr(97 + i % 26)}{chr(97 + i // 26)}": {"x": "y"} for i in range(600)}
        self.assertLessEqual(len(shape(huge)), MAX_CHARS)
        self.assertEqual(len(shape(huge, 50)), 50)
        self.assertTrue(shape(huge, 50).endswith("..."))

    def test_the_shape_of_a_shape_is_not_json(self) -> None:
        with self.assertRaises(json.JSONDecodeError):
            json.loads(shape({"a": 1}))


class Fields(unittest.TestCase):
    def test_only_the_named_fields_and_whether_each_is_there(self) -> None:
        record = fixtures.summary(START, end_time=None)
        self.assertEqual(
            fields(record, ("trackid", "type", "end_time", "run_time", "source")),
            "trackid:numstr,type:int,end_time:missing,run_time:numstr,source:str",
        )

    def test_something_that_is_not_an_object_is_described_whole(self) -> None:
        self.assertEqual(fields("oops", ("trackid",)), "str")


class Layout(unittest.TestCase):
    def test_a_timestamp_keeps_its_format_and_loses_every_digit(self) -> None:
        row = {"start_iso": "2026-09-26T04:27:13.5Z", "end": "26/09/2026 04:27"}
        self.assertEqual(
            layout(row, ("start_iso", "end")),
            "start_iso:9999-99-99a99:99:99.9a,end:99?99?9999 99:99",
        )

    def test_letters_of_any_script_are_masked_one_for_one(self) -> None:
        self.assertEqual(layout({"t": "Сб 26 sept"}, ("t",)), "t:aa 99 aaaa")

    def test_a_long_string_is_cut_so_free_text_cannot_ride_out(self) -> None:
        self.assertEqual(layout({"t": "x" * 500}, ("t",)), "t:" + "a" * 40)

    def test_what_is_not_a_string_is_named_by_type(self) -> None:
        self.assertEqual(
            layout({"a": None, "b": 5, "d": ""}, ("a", "b", "c", "d")),
            "a:null,b:int,c:missing,d:str(empty)",
        )
        self.assertEqual(layout(["x"], ("a",)), "[strx1]")


if __name__ == "__main__":
    unittest.main()
