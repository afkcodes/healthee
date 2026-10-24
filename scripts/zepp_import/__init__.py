"""Import workouts recorded in the Zepp app into a Healthee server.

## Why this exists

Healthee's only workout source is the strap's own summary list over BLE, and its only
route source is its own recorder. A run the owner starts in the ZEPP app — phone GPS,
strap heart rate — is stored by Zepp with its distance and its route, and Healthee has
neither: at best it holds a session with no distance, and for at least one owner it held
no session at all. Why the strap's list lacks those sessions has not been established;
what is known is that the Zepp app shows them in full.

This tool closes that gap from the outside. It signs in to Zepp the same way the app's
pairing screen does (`apps/mobile/lib/data/pairing/zepp_client.dart`), reads the account's
workout history, and writes it to Healthee through the two public endpoints the mobile app
already uses: `POST /ingest/helio` for the session summary and `POST /api/workout/gps` for
the route. No server code changes, no schema changes, no new APK.

## What it is not

It is not part of the server and must not become one: the server never sees a Zepp
password (`zepp_client.dart` says why). It runs where the owner runs it, with credentials
the owner types, and keeps none of them.

Standard library only, by the same reasoning as `scripts/check_file_length.py`: it has to
run on a bare server or a phone terminal with no environment to set up.
"""

from __future__ import annotations

__all__ = ["__version__"]

__version__ = "0.2.0"
