"""Build the MCP server and mount it inside the FastAPI app at `/mcp`.

Streamable HTTP, **stateless with plain JSON replies** (`stateless_http=True`,
`json_response=True`): every request carries its own bearer token and is answered in one
JSON body, so a restart or deploy never strands a client's session, nothing depends on
which worker answers, and nginx buffering is irrelevant (no SSE stream to hold open).

DNS-rebinding protection is switched off: the SDK enables it only for a loopback `host`
and would then 421 every request behind nginx (Host is the public name). The bearer token
is the access control; a rebinding page cannot supply it.

`mcp_enabled=False` makes `/mcp` a plain 404 (see `_enabled_only`), and the session manager
is not started.
"""

from __future__ import annotations

from collections.abc import AsyncIterator
from contextlib import AsyncExitStack, asynccontextmanager

from fastapi import FastAPI
from mcp.server.mcpserver import MCPServer
from mcp.server.transport_security import TransportSecuritySettings
from starlette.responses import JSONResponse
from starlette.routing import Mount, Route
from starlette.types import ASGIApp, Receive, Scope, Send

from healthee.core.config import get_settings
from healthee.mcp import tools_knowledge, tools_metrics, tools_reads
from healthee.mcp.auth import DeviceTokenAuth

MOUNT_PATH = "/mcp"

INSTRUCTIONS = (
    "Every number here is the owner's own measurement from their strap, returned with its "
    "coverage and data confidence; when coverage is thin or a value is withheld, say so "
    "instead of filling the gap. Research passages carry an evidence grade (Established, "
    "Probable, Emerging, Contested, Myth): cite them by note id and word the claim to "
    "that grade. Nothing here is medical advice."
)


def build_server() -> MCPServer:
    """A fresh server with every tool and resource registered."""
    server = MCPServer("healthee", instructions=INSTRUCTIONS)
    tools_metrics.register(server)
    tools_reads.register(server)
    tools_knowledge.register(server)
    return server


class _ExactPath:
    """Serve `/mcp` (no trailing slash) without a redirect, as the inner app's `/`.

    A class, not a function: Starlette's `Route` treats a plain function as a
    request/response endpoint, and this is a raw ASGI app.
    """

    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        await self.app({**scope, "path": "/", "raw_path": b"/"}, receive, send)


def _enabled_only(app: ASGIApp) -> ASGIApp:
    """Answer exactly what an unmounted path answers (404) while `mcp_enabled` is false.

    Decided per request, not at construction: `create_app()` runs at import (`app = ...`)
    and settings must not be read at import time. The effect is the one the setting
    promises: no token check, no 401 that would confirm something is listening.
    """

    async def gate(scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] == "http" and not get_settings().mcp_enabled:
            await JSONResponse({"detail": "Not Found"}, status_code=404)(scope, receive, send)
            return
        await app(scope, receive, send)

    return gate


def mount_mcp(app: FastAPI) -> None:
    """Mount the gated, authenticated MCP app on `app` at `/mcp` and `/mcp/`."""
    server = build_server()
    inner = server.streamable_http_app(
        streamable_http_path="/",
        stateless_http=True,
        json_response=True,
        transport_security=TransportSecuritySettings(enable_dns_rebinding_protection=False),
    )
    guarded = _enabled_only(DeviceTokenAuth(inner))
    app.router.routes.append(
        Route(MOUNT_PATH, _ExactPath(guarded), methods=["GET", "POST", "DELETE"])
    )
    app.router.routes.append(Mount(MOUNT_PATH, app=guarded))
    app.state.mcp_server = server


@asynccontextmanager
async def mcp_lifespan(app: FastAPI) -> AsyncIterator[None]:
    """Run the SDK's session manager for the life of the host app (when enabled).

    Mounting disables the SDK's own lifespan, so without this the first request fails.
    """
    server: MCPServer = app.state.mcp_server
    async with AsyncExitStack() as stack:
        if get_settings().mcp_enabled:
            await stack.enter_async_context(server.session_manager.run())
        yield
