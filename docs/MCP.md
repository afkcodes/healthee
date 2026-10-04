# Healthee over MCP

Healthee can answer an AI tool (Claude Code, Codex, or any client that speaks the
Model Context Protocol) from your own data. The server exposes a read-only MCP
endpoint at `/mcp`; you point the tool at it with a token you mint yourself.

Nothing is written. There is no tool that logs, adopts, deletes or changes anything.

## What it exposes

Every number is your own measurement with the coverage and confidence the app
shows. Research passages carry the evidence grade of the note they come from.

| Tool | Returns |
|---|---|
| `list_metrics` | the catalogue: every series, derived series and logged event kind, with unit, one-line definition and the research note that defines it |
| `metric_series(metric, days=30)` | daily `{date: value}`, plus `n`, `coverage` (days with a reading over days asked) and the unit |
| `metric_stats(metric, days=30, stat)` | `avg`, `min`, `max`, `sum`, `latest`, `trend` or `series` |
| `compare_event(event, metric, days=60)` | the metric on days you logged an event versus days you did not (observational, single-subject) |
| `today`, `sleep`, `activity` (optional `day`) | the same payloads as `/api/today`, `/api/sleep`, `/api/activity` |
| `sleep_health`, `workouts`, `recovery`, `recent_logs` (`days`) | the sleep-health checks, recent workouts, recovery score with its markers, and manual logs |
| `workout(id)` | one workout in detail, by the `start_iso` that `workouts` lists |
| `history(metric, days=90)` | the `/api/history` payload |
| `findings` | your personal correlations with their n and effect size. Patterns in your own data, never research |
| `recommendations` | recent recommendations (premium owners; a free owner gets the same `locked` marker the API returns) |
| `knowledge_search(query, k=8)` | passages from the graded corpus: ref, note id, grade, section, text |
| `knowledge_note(note_id)` | one note's body and grade |

Resources: `healthee://metrics` (the catalogue) and `healthee://knowledge/{note_id}`
(a note's text).

Free and premium gating is the API's: a field the API withholds from a free owner is
withheld here too, and no tool spends any of your coach allowance.

## 1. Mint a token

An AI tool uses a device token, the same kind your phone holds: stored hashed,
labelled, revocable, shown once. A Supabase sign-in token is not accepted at `/mcp`
(it lives about an hour; a standing tool connection needs a credential you can cut
without signing yourself out).

With a signed-in session's access token:

```bash
curl -sX POST https://<host>/api/device \
  -H "Authorization: Bearer <your sign-in access token>" \
  -H "Content-Type: application/json" \
  -d '{"label": "claude-code"}'
```

The response holds `device_token`. It is returned once and cannot be recovered; copy
it now. An account can hold ten live tokens.

## 2. Connect a tool

Claude Code:

```bash
claude mcp add --transport http healthee https://<host>/mcp \
  --header "Authorization: Bearer <token>"
```

Codex, in `~/.codex/config.toml`:

```toml
[mcp_servers.healthee]
url = "https://<host>/mcp"
http_headers = { Authorization = "Bearer <token>" }
```

If your Codex version reads the header from the environment instead, use
`bearer_token_env_var = "HEALTHEE_MCP_TOKEN"` and export that variable.

Then ask, for example: *"Using healthee, how did my resting heart rate and HRV move
over the last 30 days, and how much of that is measured?"*

## 3. Revoke it

List your tokens, then delete the one you want gone:

```bash
curl -s https://<host>/api/device -H "Authorization: Bearer <sign-in access token>"
curl -sX DELETE https://<host>/api/device/<token id> \
  -H "Authorization: Bearer <sign-in access token>"
```

The next request with that token is a 401. `last_seen` on the listing tells you
whether a token was used after you stopped expecting it to be.

## Privacy

A token reads only its owner's data: the owner is resolved from the token on every
request, in one place, and no tool takes an owner argument. Row-level security is
underneath, as for every other read. Revoke the token to cut access. What your AI
tool does with the numbers it reads is up to that tool and its provider; the data
leaves this server in the answer to the call.

## Operating it

- `MCP_ENABLED=false` removes the endpoint: `/mcp` is a plain 404.
- Transport is Streamable HTTP in stateless mode with plain JSON replies. Each
  request carries its own token and gets one JSON body, so a deploy never strands a
  session and nothing needs sticky routing.
- nginx: the existing `location /` proxies `/mcp` correctly and needs no change. It
  uses HTTP/1.1 with the `Connection` header cleared and a 180 s read timeout.
  Proxy buffering is on, which does not matter here because no reply is streamed (the
  coach stream is the one route that disables it, with an `X-Accel-Buffering` header).
  Requests share the API's per-IP rate limit.
- The SDK's DNS-rebinding host check is off (it only knows loopback names, so it would
  reject the public host). The bearer token is the access control.
