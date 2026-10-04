"""Who is asking — the ONE place an MCP request becomes an owner.

## The credential

`Authorization: Bearer <device token>`: the same hashed, labelled, revocable token
`core.device_token` mints for a phone. The owner mints one for an AI tool the same way the
phone does (`POST /api/device` with a label such as "claude-code") and revokes it the same
way; there is no MCP-specific minting.

**A Supabase JWT is NOT accepted here.** It lives about an hour and says who is using the
app right now; a standing connection from Claude Code or Codex needs a credential that
outlives a session and can be cut without signing the owner out of everything. A JWT
presented here is simply an unknown device token, so it is a 401.

## Where the check lives, and how a tool learns the owner

`DeviceTokenAuth` wraps the MCP ASGI app, so the token is resolved BEFORE the SDK sees a
request and a bad one never reaches a tool. It reuses `request_auth.ingest_user` (device
token -> owner + timezone, 401 for unknown/revoked, 403 for a suspended owner), so this
surface cannot disagree with `/ingest/*` about which token is live.

The resolved `RequestUser` goes on `scope["state"]`. A tool never trusts a header for
identity: `owner_of(ctx)` reads the user the middleware stored on the SDK's own request
object (`ctx.request_context.request`, a Starlette `Request` whose `.state` IS
`scope["state"]`). It does NOT re-resolve the token itself and it does not cache — one
resolution per HTTP request, in one place. If the request object or the stored user is
missing, `owner_of` raises rather than guessing: failing closed is the only safe answer
when identity is unknown.

Security note: never log a raw token; only the status and the owner id.
"""

from __future__ import annotations

import json
from collections.abc import Callable
from typing import Any

import anyio.to_thread
from fastapi import HTTPException
from mcp.server.mcpserver import Context
from starlette.types import ASGIApp, Receive, Scope, Send

from healthee.core.logging import get_logger
from healthee.core.request_auth import ingest_user
from healthee.core.supabase_auth import RequestUser

log = get_logger(__name__)

# The key on `scope["state"]` the middleware writes and `owner_of` reads.
OWNER_STATE_KEY = "mcp_owner"


class DeviceTokenAuth:
    """ASGI middleware: resolve the bearer device token to its owner or answer 401/403."""

    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        authorization = _header(scope, b"authorization")
        try:
            # Blocking DB lookup (`resolve_device_token`) — off the event loop.
            user = await anyio.to_thread.run_sync(ingest_user, authorization)
        except HTTPException as exc:
            log.info("mcp request refused: %s", exc.status_code)
            await _refuse(send, exc)
            return
        scope.setdefault("state", {})[OWNER_STATE_KEY] = user
        await self.app(scope, receive, send)


def _header(scope: Scope, name: bytes) -> str | None:
    for key, value in scope["headers"]:
        if key.lower() == name:
            return value.decode("latin-1")
    return None


async def _refuse(send: Send, exc: HTTPException) -> None:
    body = json.dumps({"detail": exc.detail}).encode()
    await send(
        {
            "type": "http.response.start",
            "status": exc.status_code,
            "headers": [
                (b"content-type", b"application/json"),
                (b"content-length", str(len(body)).encode()),
                (b"www-authenticate", b"Bearer"),
            ],
        }
    )
    await send({"type": "http.response.body", "body": body})


def owner_of(ctx: Context[Any, Any]) -> RequestUser:
    """The authenticated owner of this tool call, as `DeviceTokenAuth` resolved it."""
    request = ctx.request_context.request
    state = getattr(request, "state", None)
    user = getattr(state, OWNER_STATE_KEY, None)
    if not isinstance(user, RequestUser):
        # Unreachable behind the middleware; refuse rather than act as nobody.
        raise PermissionError("no authenticated owner on this MCP request")
    return user


async def as_owner[T](ctx: Context[Any, Any], read: Callable[[RequestUser], T]) -> T:
    """Run a blocking read as the authenticated owner, off the event loop.

    The ONE door every tool goes through: the owner comes from `owner_of`, never from a
    tool argument, so no tool can name another tenant.
    """
    user = owner_of(ctx)
    return await anyio.to_thread.run_sync(read, user)
