"""The owner's timezone, with an honest fallback when this machine has no zone database.

Healthee stores the owner's IANA zone on the account (`/api/me`). Every time this tool
shows, and every local day it asks the server for, is in that zone — not this machine's,
which on a cloud server is UTC and would file a morning run under the wrong day.

A phone terminal can lack the zone database altogether. Then the times are shown in UTC
and LABELLED as UTC (`label`), rather than shown in the server's zone under no label.
"""

from __future__ import annotations

from datetime import datetime, timezone, tzinfo
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

# `datetime.UTC` arrived in Python 3.11 and this tool runs on 3.10, the Python that
# Ubuntu 22.04 ships. Every module takes UTC from here, so the reason is written once.
UTC = timezone.utc


def zone_for(name: str) -> tzinfo:
    """The named zone, or UTC when it cannot be loaded here."""
    try:
        return ZoneInfo(name)
    except (ZoneInfoNotFoundError, ValueError, OSError):
        return UTC


def label(zone: tzinfo) -> str:
    """How to name `zone` beside a time: its IANA key, or "UTC" for the fallback."""
    return getattr(zone, "key", None) or "UTC"


def local(epoch_s: float, zone: tzinfo) -> datetime:
    return datetime.fromtimestamp(epoch_s, tz=zone)


def local_day(epoch_s: float, zone: tzinfo) -> str:
    """The `YYYY-MM-DD` local day an instant falls on."""
    return local(epoch_s, zone).date().isoformat()


def utc_iso(epoch_s: float) -> str:
    """An instant as ISO 8601 with an explicit UTC offset, as the server's models require."""
    return datetime.fromtimestamp(epoch_s, tz=UTC).isoformat()
