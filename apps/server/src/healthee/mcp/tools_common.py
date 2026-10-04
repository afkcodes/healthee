"""What every tool shares: the wire shape, the refusals, and the one read door.

**Same payload as the API, byte for byte.** Tools call the same read functions (and, where
a router is a thin shell over one, the router's own handler — it takes a plain
`RequestUser`, so the gate and the shaping it applies come with it) and pass the result
through `jsonable_encoder`, which is exactly what FastAPI does on the way out. A date is an
ISO string here for the same reason it is on the wire.

**A refusal is a tool error, never an empty answer.** "That is not a metric" and "you have
no readings" are different states (standards section 1); the first raises `ToolError`
naming `list_metrics`, the second is a payload whose `n` is 0.
"""

from __future__ import annotations

from collections.abc import Callable
from typing import Any

from fastapi import HTTPException
from fastapi.encoders import jsonable_encoder
from mcp.server.mcpserver import Context
from mcp.server.mcpserver.exceptions import ToolError

from healthee.analytics.metrics import is_known_metric
from healthee.core.supabase_auth import RequestUser
from healthee.mcp.auth import as_owner

MAX_DAYS = 365


def bounded(days: int, *, lo: int = 1, hi: int = MAX_DAYS) -> int:
    """`days` clamped into a window a tool will answer for (unbounded data is windowed)."""
    return max(lo, min(int(days), hi))


def require_metric(metric: str) -> str:
    """`metric` unchanged, or a `ToolError` pointing at the catalogue."""
    if not is_known_metric(metric):
        raise ToolError(f"unknown metric {metric!r}; call list_metrics for the valid keys")
    return metric


def wire(payload: Any) -> Any:
    """The payload as FastAPI would serialise it: dates, UUIDs and models made JSON-safe."""
    return jsonable_encoder(payload)


async def read_as_owner[T](ctx: Context[Any, Any], read: Callable[[RequestUser], T]) -> Any:
    """Run `read` as the authenticated owner and return its payload in wire shape.

    An `HTTPException` raised by a reused handler (a bad `day`, a 402 gate) becomes a
    `ToolError` carrying the same detail, so the model is told what the API would say.
    """
    try:
        return wire(await as_owner(ctx, read))
    except HTTPException as exc:
        raise ToolError(f"{exc.status_code}: {wire(exc.detail)}") from exc
