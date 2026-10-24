# Redesign 2026-10 status

Complete. Branch `design/redesign-2026-10`. Spec: the PNGs + COACH_TASK.md in this folder.

| Phase | State | Commits |
|---|---|---|
| P0-P4 spec, tokens, charts, signals, insights | done | 3e2fa61 76e095c aa23063 2482c6a 50bcbde b25da34 |
| P5 coach server | done | aec60e5 ledger, 3d338e3 review + weekly job |
| P6 coach mobile | done | 5989188 ledger + plan screens, e4ca94f slot/undo API, acac887 Coach home |
| P7 water + breathing | done | 2b1dc00 data layer, a5764f7 water, e773be9 breathing UI |

Final gates: analyze clean, flutter test 2810 (2 fixed), pytest 3375 pass + 2 env-only (SUPABASE_* set), ruff/pyright clean.
Open issues:
- Review prose (review, pattern, today) is not grounded per sentence (spec: note ids only in rationale); rationale is grounded and grade-checked.
- Server tests need SELF_HOST_UNLOCKED and PREMIUM_COACH_QUESTIONS unset. Mobile does not compile at 23ed000 and e4ca94f (staged deck deletions); acac887 fixes it.
