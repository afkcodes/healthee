# zepp-import

Bring workouts you recorded in the Zepp app into your own Healthee server: the session,
its distance and heart rate, and the GPS route.

Healthee reads the strap over Bluetooth. A run you start in the Zepp app is stored by
Zepp with its distance and route, and Healthee has neither. This tool reads your Zepp
workout history and writes it to Healthee through the same two endpoints the mobile app
uses. Nothing on the server changes and no new app build is needed.

It is a standalone script. Python 3.10 or newer, standard library only, nothing to
install. It runs on the server, on a laptop, or in Termux on a phone.

## Run it

```sh
python3 scripts/zepp-import
```

It signs in, lists every Zepp workout it found with what it would do to each, and asks
before it writes anything. Answer `n` and nothing is written. `--dry-run` shows the same
list and never asks.

The first run asks for five things:

| Asked for          | What to type                                                |
|--------------------|-------------------------------------------------------------|
| Healthee address   | the server name you typed into the Healthee app             |
| Healthee email     | the email you typed into the Healthee app (see below)       |
| Healthee password  | the password you typed there; hidden while you type         |
| Zepp email         | the email on your Zepp account                              |
| Zepp password      | hidden while you type                                       |

The address and the two emails are remembered. Later runs ask for the two passwords and
let you press Enter for the rest. Passwords are never stored.

Run it as often as you like. A session already in Healthee is recognised and nothing is
imported twice.

## Your Healthee login

The app's first screen says "Healthee has no account of its own". That is true: nobody
runs a central Healthee account. Your own server still has a login, and this tool needs
it. It is the email and password you typed into the app on its "Sign in to your server"
screen. The app stays signed in afterwards, so it is easy to forget you have one. It is
not your Zepp login.

If you host the server yourself and do not remember which email you used, the server
has it. On the machine that runs it:

```sh
docker exec healthee-db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "select email from app_user where email is not null"'
```

The password is not on your server, so nothing there can show it. It is held by the
sign-in provider the server names (the Supabase project from `docs/SELF_HOSTING.md`,
Part 4), and a forgotten one can only be replaced there. Signing out of the app does not
help: signing back in needs the same password.

## What the plan means

Every Zepp session in the window is listed with two lines. `workout:` is the session
itself: its time, distance, heart rate and calories. `route:` is its GPS track, shown
where there is one.

| Verdict                         | Meaning                                                |
|---------------------------------|--------------------------------------------------------|
| `import`                        | Healthee does not have it. It will be written.         |
| `update (adds ...)`             | Healthee has this session. Only what it lacks is added. |
| `update (sport was filed as X)` | The stored sport label was wrong and is corrected.     |
| `already there`                 | Nothing to do.                                         |
| `skip (...)`                    | Not imported. The reason is in the brackets.           |

What is skipped, and why:

* **Auto-detected activity.** The strap already reports these to Healthee. Importing
  Zepp's copy would count the same minutes and calories twice.
* **Under 10 minutes.** Healthee lists no session that short, so it would change a day's
  calories and appear nowhere.
* **A sport with no Healthee equivalent.** Zepp and Healthee number sports differently.
  A type this tool cannot translate is left out rather than filed under the wrong name.
* **One leg of a multi-sport session.** It is already inside its parent.

Two rules protect what Healthee already holds:

* A stored value is never replaced. `update` fills only fields the server reports as
  empty.
* A session that overlaps one already stored is imported without its calories, because
  Healthee adds workout calories together.

## What changes in Healthee

**Workouts** change the workout list, the weekly training and strength minutes, and the
calories of the days they fall on.

**Routes** add the map, and they also feed fitness. Healthee tries to measure VO2max from
each route using your strap's heart rate. A measured value replaces the estimated one for
14 days, and biological age moves with it. It can go up or down. Walking is not scored.

There is no endpoint that deletes a workout or a route, so this tool cannot undo an
import. If you are unsure about the fitness effect, import the workouts first with
`--no-routes` and add the routes in a later run.

## Body weight

After the workouts, the tool compares the weigh-ins in Zepp's weight log with
Healthee's, one per day (the last reading of each day), and makes Healthee match Zepp:

| Line                       | Meaning                                                  |
|----------------------------|----------------------------------------------------------|
| `add`                      | Healthee has no reading that day, or an earlier one. Zepp's is written at its own time. |
| `correct (Healthee has X)` | Healthee's newest reading is that day and differs. It is changed to Zepp's number. |
| `already there`            | Same number. Nothing to do.                              |
| `sent before`              | Written by an earlier run, but Healthee keeps a later reading that day. |

A weight typed into the Healthee app on a day after Zepp's newest weigh-in is left
alone, so it stays the current one. Weight feeds BMI, and through it the fitness estimate
when no recent route measures it. It is written through `POST /api/log`, the app's own
path for a weigh-in. Every Zepp weigh-in is checked on every run, whatever `--days` says.

## Options

| Option                 | Effect                                                       |
|------------------------|--------------------------------------------------------------|
| `--dry-run`            | Show the plan and write nothing.                             |
| `--days N`             | Look back N days. The default is 30.                         |
| `--since YYYY-MM-DD`   | Look back to this date, in your Healthee timezone.           |
| `--no-routes`          | Import workouts without their routes.                        |
| `--no-weight`          | Leave body weight out.                                       |
| `--yes`                | Import without asking, routes included.                      |
| `--healthee-url HOST`  | Your Healthee server.                                        |
| `--zepp-host HOST`     | Ask only this Zepp region host.                              |
| `--env-file FILE`      | Read settings from a file only you can read (`chmod 600`).   |
| `--state-file FILE`    | Where the import record is kept.                             |
| `--verbose`            | Also print the shape of each Zepp reply.                     |

Exit status: 0 when everything asked for was done, 1 for a failure or a refused route,
130 when interrupted.

## Running it unattended

Every setting can come from the environment or from an `--env-file`:

```sh
HEALTHEE_URL=healthee.example.com
HEALTHEE_EMAIL=you@example.com
HEALTHEE_PASSWORD=...
ZEPP_EMAIL=you@example.com
ZEPP_PASSWORD=...
```

With no terminal the tool refuses to import unless `--yes` is given. A variable already
in the environment wins over the same name in the file.

`ZEPP_APP_TOKEN` (with `ZEPP_USER_ID` if you have it) replaces the Zepp email and
password, for an account that has no password. The tool then neither signs in nor signs
out.

## Privacy

* The Zepp password goes to Zepp's sign-in endpoint and nowhere else. It is never sent to
  Healthee and never written to disk.
* The Healthee password goes to the sign-in service your Healthee server names. The tool
  prints that host before asking for the password.
* The Zepp session is signed out before anything is written to Healthee.
* Writing workouts needs a device token. One is created for the run and revoked when
  the run ends. If a run is killed in between, the next run revokes it first.
* Nothing is printed or stored that identifies where you ran. `--verbose` prints field
  names and types only, never a value.
* The record file (`~/.local/state/healthee-zepp-import/ledger.json`, mode 600) holds the
  server address, the two emails, which Zepp host has your data, and one line per
  imported session. No password and no token.

## Limits

* **Zepp's API is unofficial.** It can change without notice. When it does, the tool
  stops with a message that names the step, and `--verbose` prints what the reply looked
  like so it can be fixed.
* **Not tested with a real Zepp account.** Two things were checked against live Zepp
  on 2026-10-11: it accepts this sign-in request (it answers an account that does not
  exist with its usual error), and every host in the list answers the workout path,
  refusing a bad token in the expected shape. A successful sign-in and real workout
  replies were not, because that needs somebody's password. The workout calls follow
  what open-source clients do against real accounts, and the parser was run over real
  payloads from one of them. The Healthee half is checked against the real server.
* **Sign-in needs a Zepp email and password.** An account created with Google, Apple or a
  phone number needs a password set first.
* **Zepp may refuse a cloud server's address.** If sign-in is refused from a server, run
  the same command from Termux on your phone.
* **Your data lives on one regional Zepp host**, and a wrong host answers with an empty
  list. The tool tries the known hosts in turn and remembers the one that worked. If it
  finds nothing, pass yours with `--zepp-host`.
* **Sport codes.** The table in `sports.py` marks which types have been seen in real
  histories and which rest on a firmware catalogue. The plan shows the sport name before
  anything is written.
* **Duration is start to end**, pauses included, so pace can read a little slower than
  Zepp's moving pace.
* **Healthee does not record where a row came from.** Imported sessions look like any
  other. The record file is the only note of which ones came from Zepp.
* **Routes older than Healthee's newest 100** cannot be checked for duplicates and are
  not imported.

## Tests

```sh
python3 -m unittest discover -s scripts/zepp_import/tests -t scripts
```

Zepp and Healthee are in-process fakes. `tests/test_server_contract.py` reads the server
source and fails when a constant this tool copies (sport names, limits, the upsert's
behaviour) has changed.

## Sources

The sign-in is a port of `apps/mobile/lib/data/pairing/zepp_client.dart`, which follows
[huami-token](https://github.com/argrento/huami-token).

The workout history and detail formats, and the workout type numbers, were read from:

* [Mi-Fit-and-Zepp-workout-exporter](https://github.com/rolandsz/Mi-Fit-and-Zepp-workout-exporter)
* [zepp-fit-extractor](https://github.com/H3llK33p3r/zepp-fit-extractor)
* [ZeppBridge](https://github.com/lingcang728/ZeppBridge)
* [MiFitDataExport](https://github.com/mireq/MiFitDataExport)

No code was copied from them. The test fixtures are synthetic.
