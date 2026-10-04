"""The catalogue table: complete against the registry, honest about its notes."""

from __future__ import annotations

from healthee.analytics.metrics import EVENT_KINDS, FLAG_DERIVED_METRICS, KNOWN_METRICS
from healthee.insights import manifest
from healthee.mcp.catalogue import BY_KEY, CATALOGUE, catalogue_payload


def test_every_registry_key_is_in_the_catalogue() -> None:
    missing = (KNOWN_METRICS | EVENT_KINDS.keys()) - BY_KEY.keys()
    assert not missing, f"keys in analytics.metrics with no catalogue entry: {sorted(missing)}"


def test_the_catalogue_names_nothing_the_registry_does_not() -> None:
    extra = BY_KEY.keys() - (KNOWN_METRICS | EVENT_KINDS.keys())
    assert not extra, f"catalogue entries for keys the server does not serve: {sorted(extra)}"


def test_keys_are_unique() -> None:
    assert len(BY_KEY) == len(CATALOGUE)


def test_every_note_id_exists_in_the_manifest() -> None:
    for entry in CATALOGUE:
        if entry.note_id is not None:
            assert manifest.by_id(entry.note_id) is not None, (entry.key, entry.note_id)


def test_kinds_follow_the_registry() -> None:
    for entry in CATALOGUE:
        if entry.key in EVENT_KINDS:
            assert entry.kind == "event"
        elif entry.key in FLAG_DERIVED_METRICS:
            assert entry.kind == "derived"
        else:
            assert entry.kind == "series"


def test_every_entry_has_a_unit_and_a_definition() -> None:
    for entry in CATALOGUE:
        assert entry.unit.strip() and entry.definition.strip(), entry.key


def test_payload_carries_every_field() -> None:
    payload = catalogue_payload()
    assert len(payload["metrics"]) == len(CATALOGUE)
    assert set(payload["metrics"][0]) == {"key", "kind", "unit", "definition", "note_id"}
