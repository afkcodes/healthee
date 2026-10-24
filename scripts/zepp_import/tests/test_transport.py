"""The one place that opens a socket, against a server this test starts on loopback."""

from __future__ import annotations

import gzip
import http.server
import threading
import unittest

from zepp_import import transport
from zepp_import.transport import TransportError


class _Handler(http.server.BaseHTTPRequestHandler):
    def _reply(self, status: int, body: bytes = b"", **headers: str) -> None:
        self.send_response(status)
        for name, value in headers.items():
            self.send_header(name.replace("_", "-"), value)
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802 - the name http.server requires
        if self.path == "/redirect":
            self._reply(303, location="http://127.0.0.1:1/elsewhere?access=TOKEN")
        elif self.path == "/elsewhere":
            self.server.followed = True  # type: ignore[attr-defined]
            self._reply(200, b"followed")
        elif self.path == "/missing":
            self._reply(404, b'{"detail":"Not Found"}', content_type="application/json")
        elif self.path == "/gzip":
            self._reply(200, gzip.compress(b'{"ok":true}'), content_encoding="gzip")
        elif self.path == "/huge":
            self._reply(200, b"x" * 2048)
        elif self.path == "/bomb":
            self._reply(200, gzip.compress(b"\0" * 200_000), content_encoding="gzip")
        elif self.path == "/not-gzip":
            self._reply(200, b"plainly not gzip", content_encoding="gzip")
        else:
            self._reply(200, self.headers.get("x-echo", "").encode())

    def do_POST(self) -> None:  # noqa: N802
        length = int(self.headers.get("content-length", "0"))
        self._reply(200, self.rfile.read(length), content_type=self.headers.get("content-type", ""))

    def do_DELETE(self) -> None:  # noqa: N802
        self._reply(204)

    def log_message(self, *_args: object) -> None:
        return None


class Transport(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), _Handler)
        cls.server.followed = False  # type: ignore[attr-defined]
        cls.base = f"http://127.0.0.1:{cls.server.server_address[1]}"
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls) -> None:
        cls.server.shutdown()
        cls.server.server_close()

    def test_a_redirect_is_returned_not_followed(self) -> None:
        # Zepp's sign-in answers with a 303 whose Location carries the tokens; following
        # it would hand them to the page it names.
        reply = transport.send("GET", f"{self.base}/redirect")
        self.assertEqual(reply.status, 303)
        self.assertIn("access=TOKEN", reply.headers["location"])
        self.assertFalse(self.server.followed)  # type: ignore[attr-defined]

    def test_an_error_status_is_a_value_with_its_body(self) -> None:
        reply = transport.send("GET", f"{self.base}/missing")
        self.assertEqual((reply.status, reply.json()), (404, {"detail": "Not Found"}))

    def test_a_gzipped_body_is_decoded(self) -> None:
        self.assertEqual(transport.send("GET", f"{self.base}/gzip").json(), {"ok": True})

    def test_headers_and_bodies_are_sent(self) -> None:
        echoed = transport.send("GET", f"{self.base}/echo", headers={"x-echo": "hello"})
        self.assertEqual(echoed.body, b"hello")
        posted = transport.post_json(transport.send, f"{self.base}/post", {"a": [1, None]}, {}, 5.0)
        self.assertEqual(posted.body, b'{"a":[1,null]}')
        self.assertEqual(posted.headers["content-type"], "application/json")

    def test_delete_with_no_content(self) -> None:
        self.assertEqual(transport.send("DELETE", f"{self.base}/thing").status, 204)

    def test_a_nan_is_refused_before_it_is_sent(self) -> None:
        with self.assertRaises(ValueError):
            transport.post_json(transport.send, f"{self.base}/post", {"a": float("nan")}, {}, 5.0)

    def test_an_unreachable_host_is_a_transport_error_naming_only_the_host(self) -> None:
        with self.assertRaises(TransportError) as raised:
            transport.send("GET", "http://127.0.0.1:1/secret-path?token=abc", timeout_s=2.0)
        self.assertEqual(raised.exception.host, "127.0.0.1")
        self.assertEqual(raised.exception.kind, "connection refused")
        self.assertNotIn("secret-path", str(raised.exception))
        self.assertNotIn("abc", str(raised.exception))

    def test_a_body_over_the_ceiling_is_refused(self) -> None:
        ceiling = transport.MAX_BODY_BYTES
        transport.MAX_BODY_BYTES = 1024
        try:
            with self.assertRaises(TransportError) as raised:
                transport.send("GET", f"{self.base}/huge")
        finally:
            transport.MAX_BODY_BYTES = ceiling
        self.assertEqual(raised.exception.kind, "response larger than expected")

    def test_a_small_gzip_body_cannot_inflate_past_the_ceiling(self) -> None:
        ceiling = transport.MAX_BODY_BYTES
        transport.MAX_BODY_BYTES = 4096
        try:
            with self.assertRaises(TransportError) as raised:
                transport.send("GET", f"{self.base}/bomb")
        finally:
            transport.MAX_BODY_BYTES = ceiling
        self.assertEqual(raised.exception.kind, "response larger than expected")

    def test_a_body_that_claims_gzip_and_is_not_is_a_transport_error(self) -> None:
        with self.assertRaises(TransportError) as raised:
            transport.send("GET", f"{self.base}/not-gzip")
        self.assertEqual(raised.exception.kind, "a gzip body that does not decode")

    def test_host_of(self) -> None:
        self.assertEqual(
            transport.host_of("https://api-mifit.zepp.com/v1/x?y=1"), "api-mifit.zepp.com"
        )


if __name__ == "__main__":
    unittest.main()
