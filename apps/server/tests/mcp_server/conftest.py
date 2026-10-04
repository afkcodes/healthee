"""The MCP bed: two seeded owners, a live device token each, and a real MCP client.

Owner A is the sentinel (`seed_all`); owner B is layered on with the SAME natural keys and
impossible values (`seed_owner_b`), so only `user_id` separates their series and a read
that forgot its owner returns an absurd number. Each owner holds a device token minted the
way the phone's is (`mint_device_token`). Requests go through the SDK's own client over an
ASGI transport against the real app, lifespan included, so what is exercised is what a
Claude Code or Codex connection would exercise.
"""

from __future__ import annotations

from collections.abc import Awaitable, Callable, Iterator
from dataclasses import dataclass
from datetime import timedelta
from typing import Any
from uuid import UUID

import anyio
import httpx2
import pytest
from fastapi import FastAPI
from mcp import Client
from mcp.client.streamable_http import streamable_http_client
from tests.contracts.seed import seed_all, today_local
from tests.contracts.seed_owner_b import OWNER_B, seed_owner_b

from healthee.api.app import create_app
from healthee.core.config import get_settings
from healthee.core.db import admin_connection, close_pool, tenant_transaction
from healthee.core.device_token import mint_device_token
from healthee.core.tenancy import SENTINEL_USER_ID

BASE = "http://testserver"
URL = f"{BASE}/mcp"

# The shared seed writes a full month of this metric for owner A; the bed replaces it with
# exactly these days, so a coverage figure can be asserted to the digit.
SPARSE_METRIC = "basal_calories"
SPARSE_DAYS_AGO = (1, 2, 4, 7)
SPARSE_VALUE = 1500.0


@dataclass(frozen=True)
class McpBed:
    token_a: str
    token_b: str
    owner_a: UUID = SENTINEL_USER_ID
    owner_b: UUID = OWNER_B

    @property
    def app(self) -> FastAPI:
        """A NEW app per access: the SDK's session manager runs once per instance, and
        every client run enters the app's lifespan."""
        return create_app()


def run_client[T](app: FastAPI, token: str | None, work: Callable[[Client], Awaitable[T]]) -> T:
    """Open a real MCP client against `app` with `token` and run `work` on it."""

    async def go() -> T:
        headers = {"Authorization": f"Bearer {token}"} if token else {}
        async with app.router.lifespan_context(app):
            transport = httpx2.ASGITransport(app=app)
            async with httpx2.AsyncClient(
                transport=transport, base_url=BASE, headers=headers
            ) as http:
                streams = streamable_http_client(URL, http_client=http, terminate_on_close=False)
                async with Client(streams) as client:
                    return await work(client)

    return anyio.run(go)


def call(app: FastAPI, token: str | None, tool: str, **arguments: Any) -> Any:
    """Call one tool and return its structured result (raises on an error result)."""

    async def work(client: Client) -> Any:
        result = await client.call_tool(tool, arguments)
        assert not result.is_error, result.content
        return result.structured_content

    return run_client(app, token, work)


def call_raw(app: FastAPI, token: str | None, tool: str, **arguments: Any) -> Any:
    """Call one tool and return the whole result, error or not."""

    async def work(client: Client) -> Any:
        return await client.call_tool(tool, arguments)

    return run_client(app, token, work)


def _seed_sparse(owner: UUID) -> None:
    today = today_local()
    with admin_connection() as conn, conn.cursor() as cur:
        cur.execute(
            "DELETE FROM derived_daily WHERE user_id = %s AND metric = %s", (owner, SPARSE_METRIC)
        )
    with tenant_transaction(owner) as cur:
        for ago in SPARSE_DAYS_AGO:
            cur.execute(
                "INSERT INTO derived_daily (user_id, day, metric, value, flags) "
                "VALUES (%s, %s, %s, %s, '{}'::jsonb) "
                "ON CONFLICT (user_id, day, metric) DO UPDATE SET value = EXCLUDED.value",
                (owner, today - timedelta(days=ago), SPARSE_METRIC, SPARSE_VALUE),
            )


def _drop_tokens() -> None:
    """The sentinel outlives a test, so its device tokens must not (or they pile up)."""
    with admin_connection() as conn, conn.cursor() as cur:
        cur.execute(
            "DELETE FROM device_token WHERE user_id = ANY(%s)", ([SENTINEL_USER_ID, OWNER_B],)
        )


@pytest.fixture
def bed(db: None, owner_sweep: None, monkeypatch: pytest.MonkeyPatch) -> Iterator[McpBed]:  # noqa: ARG001
    """Both owners seeded, each with a live device token, on a fresh app."""
    monkeypatch.delenv("SUPABASE_PROJECT_REF", raising=False)
    get_settings.cache_clear()
    close_pool()
    seed_all()
    seed_owner_b()
    _seed_sparse(SENTINEL_USER_ID)
    _drop_tokens()
    token_a, _ = mint_device_token(SENTINEL_USER_ID, "claude-code")
    token_b, _ = mint_device_token(OWNER_B, "codex")
    yield McpBed(token_a, token_b)
    _drop_tokens()
    close_pool()
    get_settings.cache_clear()
