"""Zepp's CLOUD workout types, translated to the sport codes Healthee stores.

## Two different enums, and why this file exists

Healthee's `workout.sport` holds the strap's DEVICE sport code, and
`apps/server/src/healthee/read/common.py::_SPORT_NAMES` names those. Zepp's cloud history
uses a different numbering for the same sports. Writing a cloud code straight into
`workout.sport` does not fail — it files the session under whatever the device enum calls
that number: cloud 8 (treadmill) reads back as "Pool swim", cloud 52 (strength) as
"Boxing". So every imported session is translated here, and a cloud type with no entry is
NOT imported rather than guessed at.

## Where the cloud side comes from, and how sure each entry is

There is no published table. `_OBSERVED` holds the types that open-source clients have
read out of real cloud histories; `_CATALOGUED` holds types that rest on a catalogue of
the watch firmware's sport ids or on user reports, and have not been seen in a cloud
history by anyone whose code can be read (README, "Sources"). Both are imported, because
the plan shows the owner the sport name before anything is written. The difference is
recorded so that whoever next sees a wrong label knows which half to doubt first.

`DEVICE_SPORT_NAMES` is the server's table, copied whole, so the plan can show the label
the app will show; `tests/test_server_contract.py` fails when the two drift apart.

Strength matters beyond the label: `read/fitness.py::_STRENGTH_SPORTS` counts codes
10, 14, 21 and 22 toward the weekly strength target.
"""

from __future__ import annotations

from dataclasses import dataclass

# Zepp's generic auto-recognised bout. The strap already reports these over BLE (device
# code 44), so importing the cloud copy would count the same minutes twice.
AUTO_DETECTED_CLOUD_TYPE = 223

# `read/common.py::_SPORT_NAMES`, verbatim.
DEVICE_SPORT_NAMES: dict[int, str] = {
    1: "Outdoor run",
    2: "Walking",
    3: "Outdoor cycling",
    4: "Treadmill",
    6: "Indoor cycling",
    7: "Open-water swim",
    8: "Pool swim",
    9: "Elliptical",
    10: "Climbing",
    12: "Hiking",
    14: "Strength",
    15: "Rowing",
    16: "Yoga",
    21: "HIIT",
    22: "Core training",
    23: "Stretching",
    24: "Cardio",
    44: "Activity",
    50: "Jump rope",
    52: "Boxing",
    60: "Free training",
    1000: "Outdoor run",
    1001: "Walking",
}
_UNNAMED = "Activity"  # `read/common.py::sport_name`'s fallback
_OUTDOOR_CODES = frozenset({1, 2, 3, 12})  # run, walk, ride, hike: recorded with GPS

# cloud type -> device code. Seen in real cloud histories.
_OBSERVED: dict[int, int] = {
    1: 1,  # outdoor run
    6: 2,  # walking
    7: 1,  # trail run: Healthee has one outdoor-run code
    8: 4,  # treadmill
    9: 3,  # outdoor cycling
    10: 6,  # indoor cycling
    14: 8,  # pool swim
    16: 60,  # free training
    23: 15,  # rowing machine
    52: 14,  # strength
}
# cloud type -> device code. From a firmware sport catalogue or user reports.
_CATALOGUED: dict[int, int] = {
    12: 9,  # elliptical
    15: 12,  # hiking
    21: 50,  # jump rope
    49: 21,  # HIIT
    50: 22,  # core training
    53: 23,  # stretching
    60: 16,  # yoga
    211: 3,  # road cycling
}


@dataclass(frozen=True)
class HealtheeSport:
    """A Healthee device sport code and the name the app shows for it."""

    code: int
    name: str


def device_sport_name(code: int | None) -> str:
    """The name the Healthee app shows for a stored sport code."""
    return DEVICE_SPORT_NAMES.get(code, _UNNAMED) if code is not None else _UNNAMED


def healthee_sport(cloud_type: int) -> HealtheeSport | None:
    """The Healthee sport for a Zepp cloud type, or None when there is no safe mapping."""
    code = _OBSERVED.get(cloud_type, _CATALOGUED.get(cloud_type))
    return None if code is None else HealtheeSport(code, DEVICE_SPORT_NAMES[code])


def is_auto_detected(cloud_type: int) -> bool:
    return cloud_type == AUTO_DETECTED_CLOUD_TYPE


def can_have_route(cloud_type: int) -> bool:
    """Whether a session of this Zepp type is the kind that carries a GPS track.

    A treadmill run has a distance and no route, and asking Zepp for one is a wasted
    request that ends in a 404.
    """
    sport = healthee_sport(cloud_type)
    return sport is not None and sport.code in _OUTDOOR_CODES
