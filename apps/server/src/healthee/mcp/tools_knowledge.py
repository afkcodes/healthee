"""Knowledge tools and resources: the graded research corpus, never the owner's data.

Search returns passages with the grade of the note they sit in, because a client that
quotes a passage must calibrate to that grade (Established plainly, Emerging flagged,
Contested as debated). Nothing here is owner-scoped; the surface is still behind the
bearer check.
"""

from __future__ import annotations

import json
from typing import Any

from mcp.server.mcpserver import MCPServer
from mcp.server.mcpserver.exceptions import ToolError

from healthee.core.logging import get_logger
from healthee.insights import coach_tools, embedding_index, manifest, passages
from healthee.insights.retrieval import rank_notes
from healthee.mcp.catalogue import catalogue_payload

log = get_logger(__name__)

MAX_PASSAGES = 20


def search_passages(query: str, k: int) -> dict:
    """Top `k` passages for `query`: ref, note id, grade, section, text."""
    if not query.strip():
        raise ToolError("give a non-empty query")
    wanted = max(1, min(int(k), MAX_PASSAGES))
    try:
        hits = embedding_index.search(query, wanted)
    except embedding_index.EmbeddingIndexUnavailableError as exc:
        # Different from "nothing matched": say the semantic index is down and answer from
        # the note-level lexical ranking instead of an empty list.
        log.warning("knowledge_search: embedding index unavailable (%s)", exc)
        notes = rank_notes(query)[:wanted]
        return {
            "mode": "notes_only",
            "results": [
                {"note_id": n.id, "grade": n.grade, "name": n.name, "summary": n.summary}
                for n in notes
            ],
        }
    results = []
    for ref, score in hits:
        found = passages.passage(ref)
        if found is None:
            continue
        results.append(
            {
                "ref": ref,
                "note_id": found.note_id,
                "grade": manifest.grade_of(found.note_id),
                "section": found.section,
                "text": found.text,
                "score": round(float(score), 3),
            }
        )
    return {"mode": "passages", "results": results}


def register(server: MCPServer) -> None:
    """Attach the knowledge tools and the two resources to `server`."""

    @server.tool()
    def knowledge_search(query: str, k: int = 8) -> dict[str, Any]:
        """Search the graded research corpus. Each passage carries its note's evidence
        grade; cite it as `[note_id]` and word the claim to that grade."""
        return search_passages(query, k)

    @server.tool()
    def knowledge_note(note_id: str) -> dict[str, Any]:
        """One research note by exact id: body (truncated), evidence grade, citation form."""
        return coach_tools.get_knowledge(None, note_id)

    @server.resource("healthee://metrics", mime_type="application/json")
    def metrics_resource() -> str:
        """The metric catalogue as JSON."""
        return json.dumps(catalogue_payload())

    @server.resource("healthee://knowledge/{note_id}", mime_type="text/markdown")
    def knowledge_resource(note_id: str) -> str:
        """A research note's prompt body (the text a citation resolves against)."""
        if manifest.by_id(note_id) is None:
            raise ValueError(f"no note with id {note_id}")
        return manifest.prompt_body(note_id)
