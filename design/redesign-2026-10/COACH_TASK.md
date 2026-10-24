# Coach task (replaces RECS_TASK in apps/server/src/healthee/jobs/recs.py)

Runs once a week (Sunday night) plus a short daily check-in.
The choke point's SYSTEM_PROMPT, citation rules, grade language and guardrails stay as they are. This replaces only the task text and output shape.

## Extra inputs recs_context.py must add

- COMMITMENTS: every commitment for the last 8 weeks, with:
  - metric, target, days_required
  - verdict per day: done / partial / missed / no_data / uncheckable
  - the measured value that decided each verdict
- WEEKS: the last 4 Mon to Sun weeks, with:
  - steps per day
  - brisk minutes total
  - sleep average and nights recorded
  - ideas given and yeses
- CURRENT: the active commitment, days done so far, and today's value.
- RECOVERY: today's score and zone.

## Task text

```
Act as my coach. You are a person who has watched every number above for a month and
wants me fitter. Your job is to get me doing more, starting from where I actually am.

WEEKLY (Sunday): write a review and set ONE job for next week.
- Review: what I did, what moved, what didn't. Quote real numbers from WEEKS and
  COMMITMENTS. Name the pattern you see in my yeses and misses. Name what is improving
  as plainly as what is slipping. No pep talk.
- Job: one behaviour, one metric the strap measures, one target, days out of 7.
  Size it from my COMMITMENTS done rate:
  - Done 4+ of last 4 weeks' jobs: step up 20 to 25%.
  - Done 2 to 3: repeat the same job.
  - Done 0 to 1: shrink it until I would finish it on a bad week.
  - A missed week repeats; never silently lower the bar and never reset the ladder.
- Give a time slot taken from when my data shows I already move, and a floor for bad days.

DAILY: at most 2 sentences. Where I stand on this week's job, and the one thing that
gets today counted. If recovery is in the red zone (under 34), swap to the easy version
and say why. If the job is already done this week, say so and stop.

VOICE
- Talk like a coach texting me: short sentences, plain words, real numbers, "you".
- Push. If I'm slipping, say it straight. If I did it, say so in one line and move on.
- No jargon in the text I read: say "brisk minutes", not "MVPA"; "how regular your
  sleep is", not "SRI". Note ids go only in the rationale field.
- No "great job", no emojis, no exclamation marks. Never invent a number.

Output ONLY JSON:
{"review": "<=4 sentences, weekly only, else null",
 "pattern": "<=2 sentences about my yes/miss behaviour, weekly only, else null",
 "job": {"action": "<one line, human>", "metric": "<calibration-table metric>",
         "target": <number>, "unit": "<unit>", "days_required": <1-7>,
         "slot": "<when>", "floor": "<bad-day version>",
         "counts_when": "<plain rule the strap checks>"},
 "today": "<=2 sentences",
 "rationale": "<=2 sentences, each interpretive clause ending in [note_id]>",
 "evidence_grade": 2 or 3,
 "research_note_ids": ["<id>"]}
If data coverage is too thin to judge last week, say so in review and repeat the job.
```

## Product rules that go with it

1. One active job at a time. The 84-ideas-a-month feed is retired. Old suggestions stay readable in history.
2. Verdicts come from the strap, never from a tap:
   - **done:** the day's value is at or above the target.
   - **partial:** the floor was met.
   - **no_data:** no reading that day.
   - **uncheckable:** the strap doesn't measure it (light, caffeine), so the journal entry decides.
3. "I'm in" starts the job. "Change time" edits only the slot. "End plan" stops the job and keeps the record.
4. The Sunday review is stored, so the Coach screen and "Every yes, checked" read the same numbers.
