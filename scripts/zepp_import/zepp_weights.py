"""Reading the account's weight log from Zepp: `weightRecords`, newest first, paged.

The reply has no `{code, data}` envelope: it is `{items: [...], next}`. `next` is the
instant of the oldest item on the page and is passed back as `toTime`, which Zepp treats
as INCLUSIVE, so the first item of the next page repeats the last of this one; readings
are kept by instant, which drops the repeat. No `next` means the last page. Checked
against the live API on 2026-10-11 with a page size of 3.
"""

from __future__ import annotations

from zepp_import.shapes import shape
from zepp_import.weights import WEIGHT_PATH, Weighing, read_weighing
from zepp_import.zepp_api import ZeppApi

_PAGE = 200
_MAX_PAGES = 50
_NOTE_SHAPE_CHARS = 200


def read_weights(api: ZeppApi, host: str, user_id: str) -> tuple[list[Weighing], int] | str:
    """(every readable weighing, how many items could not be read), or a note on why not."""
    path = WEIGHT_PATH.format(user_id=user_id)
    found: dict[int, Weighing] = {}
    unreadable = 0
    cursor: int | None = None
    for _ in range(_MAX_PAGES):
        params: dict[str, object] = {"limit": _PAGE}
        if cursor is not None:
            params["toTime"] = cursor
        body = api.get_body(host, path, params)
        if isinstance(body, str):
            return body
        items = body.get("items")
        if not isinstance(items, list):
            return f"no items list in {shape(body, _NOTE_SHAPE_CHARS)}"
        for item in items:
            weighing = read_weighing(item)
            if weighing is None:
                unreadable += 1
            else:
                found[weighing.ts_s] = weighing
        following = body.get("next")
        if not isinstance(following, int) or isinstance(following, bool) or following == cursor:
            return sorted(found.values(), key=lambda w: w.ts_s), unreadable
        cursor = following
    return f"more than {_MAX_PAGES} pages of weights"
