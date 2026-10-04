"""The bearer check: no token, a bad token, a revoked token, a JWT, and the off switch.

The check is one middleware in front of the SDK, so every refusal here happens before a
tool could run. `mcp_enabled=False` is a different answer entirely: the mount is absent
and the path is a plain 404, not a 401 that would confirm something is listening.
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient
from tests._auth import SECRET, auth_header
from tests.mcp_server.conftest import McpBed

from healthee.api.app import create_app
from healthee.core.config import get_settings
from healthee.core.db import transaction
from healthee.core.device_token import list_device_tokens, revoke_device_token

pytestmark = pytest.mark.integration

INITIALIZE = {
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": {
        "protocolVersion": "2025-06-18",
        "capabilities": {},
        "clientInfo": {"name": "t", "version": "0"},
    },
}
HEADERS = {"Accept": "application/json, text/event-stream", "Content-Type": "application/json"}


def _post(bed: McpBed, authorization: str | None, path: str = "/mcp"):
    headers = dict(HEADERS)
    if authorization is not None:
        headers["Authorization"] = authorization
    with TestClient(bed.app) as client:
        return client.post(path, json=INITIALIZE, headers=headers)


def test_no_token_is_401(bed: McpBed) -> None:
    response = _post(bed, None)
    assert response.status_code == 401
    assert response.json() == {"detail": "Missing or malformed Bearer token"}


def test_unknown_token_is_401_invalid_token(bed: McpBed) -> None:
    response = _post(bed, "Bearer not-a-minted-token")
    assert response.status_code == 401
    assert response.json() == {"detail": "Invalid token"}


def test_a_revoked_token_is_401(bed: McpBed) -> None:
    headers = {**HEADERS, "Authorization": f"Bearer {bed.token_a}"}
    # One client for both calls: the SDK's session manager runs once per app lifespan.
    with TestClient(bed.app) as client:
        assert client.post("/mcp", json=INITIALIZE, headers=headers).status_code == 200
        (row,) = [r for r in list_device_tokens(bed.owner_a) if r.label == "claude-code"]
        assert revoke_device_token(bed.owner_a, row.id)
        response = client.post("/mcp", json=INITIALIZE, headers=headers)
    assert response.status_code == 401
    assert response.json() == {"detail": "Invalid token"}


def test_a_supabase_jwt_is_not_accepted(bed: McpBed, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("SUPABASE_JWT_SECRET", SECRET)
    get_settings.cache_clear()
    header = auth_header(bed.owner_a, SECRET)["Authorization"]
    assert _post(bed, header).status_code == 401


def test_a_suspended_owner_is_refused(bed: McpBed) -> None:
    with transaction() as cur:
        cur.execute("UPDATE app_user SET status = 'suspended' WHERE id = %s", (str(bed.owner_a),))
    try:
        assert _post(bed, f"Bearer {bed.token_a}").status_code == 403
    finally:
        with transaction() as cur:
            cur.execute("UPDATE app_user SET status = 'active' WHERE id = %s", (str(bed.owner_a),))


@pytest.mark.parametrize("path", ["/mcp", "/mcp/"])
def test_a_valid_token_reaches_the_server_with_and_without_the_slash(
    bed: McpBed, path: str
) -> None:
    response = _post(bed, f"Bearer {bed.token_a}", path)
    assert response.status_code == 200
    assert response.json()["result"]["serverInfo"]["name"] == "healthee"


def test_server_instructions_are_served(bed: McpBed) -> None:
    result = _post(bed, f"Bearer {bed.token_a}").json()["result"]
    assert "evidence grade" in result["instructions"]
    assert "medical advice" in result["instructions"]


def test_mcp_disabled_is_a_plain_404(bed: McpBed, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("MCP_ENABLED", "false")
    get_settings.cache_clear()
    app = create_app()
    with TestClient(app) as client:
        for path in ("/mcp", "/mcp/"):
            response = client.post(
                path, json=INITIALIZE, headers={**HEADERS, "Authorization": f"Bearer {bed.token_a}"}
            )
            assert response.status_code == 404


def test_owner_of_refuses_a_request_that_carries_no_owner() -> None:
    """The one door every tool goes through never acts as nobody.

    Unreachable behind the middleware, which is exactly why it is pinned: a future
    mount that forgets the middleware must fail loudly rather than serve a tenant
    the request never named.
    """
    from types import SimpleNamespace

    from healthee.mcp.auth import owner_of

    request = SimpleNamespace(state=SimpleNamespace())
    bare = SimpleNamespace(request_context=SimpleNamespace(request=request))
    with pytest.raises(PermissionError, match="no authenticated owner"):
        owner_of(bare)  # type: ignore[arg-type]
