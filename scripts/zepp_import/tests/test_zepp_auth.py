"""Zepp sign-in and sign-out, against a fake that only accepts the exact encrypted body."""

from __future__ import annotations

import unittest

from zepp_import import zepp_auth, zepp_wire
from zepp_import.failures import ZeppImportError
from zepp_import.tests.fake_zepp import APP_TOKEN, LOGIN_TOKEN, USER_ID, FakeZepp
from zepp_import.tests.support import Net, json_reply, sentinel
from zepp_import.transport import Response
from zepp_import.zepp_wire import ZeppEndpoints

EMAIL = "runner@example.com"
PASSWORD = sentinel("zepp-password")
ENDPOINTS = ZeppEndpoints()
_TOKENS_PATH = "/v2/registrations/tokens"
_LOGIN_PATH = "/v2/client/login"
_LOGOUT_PATH = "/v1/client/logout"


class SignIn(unittest.TestCase):
    def setUp(self) -> None:
        self.zepp = FakeZepp(EMAIL, PASSWORD)
        self.net = Net([self.zepp])

    def sign_in(self, password: str = PASSWORD) -> zepp_auth.ZeppSession:
        return zepp_auth.sign_in(EMAIL, password, ENDPOINTS, self.net.send)

    def failure(self, password: str = PASSWORD) -> ZeppImportError:
        with self.assertRaises(ZeppImportError) as raised:
            self.sign_in(password)
        return raised.exception

    def test_email_and_password_become_a_session(self) -> None:
        session = self.sign_in()
        self.assertEqual((session.user_id, session.app_token), (USER_ID, APP_TOKEN))
        self.assertEqual(session.login_token, LOGIN_TOKEN)
        self.assertEqual(
            [r.url for r in self.net.requests], [zepp_wire.TOKENS_URL, zepp_wire.LOGIN_URL]
        )

    def test_the_password_travels_only_inside_the_encrypted_body(self) -> None:
        self.sign_in()
        for request in self.net.requests:
            self.assertNotIn(PASSWORD, request.everything())
        self.assertEqual(self.net.requests[0].headers["x-hm-ekv"], "1")

    def test_a_session_does_not_print_its_tokens(self) -> None:
        printed = repr(self.sign_in())
        self.assertIn(USER_ID, printed)
        self.assertNotIn(APP_TOKEN, printed)
        self.assertNotIn(LOGIN_TOKEN, printed)

    def test_a_wrong_password_is_named_as_one_with_zepps_own_error_number(self) -> None:
        failure = self.failure("not-it")
        self.assertEqual(failure.code, "zepp_wrong_credentials")
        self.assertIn("(Zepp error 401)", failure.headline)
        self.assertEqual(self.zepp.sign_ins, 0)

    def test_an_error_number_is_cut_down_to_a_number(self) -> None:
        page = "https://s3-us-west-2.amazonaws.com/x.html"
        hostile = Response(303, {"location": f"{page}?error=0117%3Cscript%3E%20{PASSWORD}"}, b"")
        self.zepp.forced[_TOKENS_PATH] = hostile
        failure = self.failure()
        self.assertIn("(Zepp error 0117scriptSE)", failure.headline)
        self.assertNotIn(PASSWORD, failure.headline)
        self.zepp.forced[_TOKENS_PATH] = Response(303, {"location": f"{page}?error="}, b"")
        self.assertIn("(Zepp error unnumbered)", self.failure().headline)
        self.zepp.forced[_TOKENS_PATH] = Response(303, {"location": f"{page}?error=%C3%A9401"}, b"")
        self.assertIn("(Zepp error 401)", self.failure().headline)

    def test_an_http_refusal_of_the_credentials(self) -> None:
        for status in (400, 401):
            self.zepp.forced[_TOKENS_PATH] = json_reply(status, {})
            failure = self.failure()
            with self.subTest(status=status):
                self.assertEqual(failure.code, "zepp_wrong_credentials")
                self.assertIn(f"(HTTP {status})", failure.headline)

    def test_a_rate_limit_or_block_points_at_the_network_not_the_password(self) -> None:
        for status in (403, 429):
            self.zepp.forced[_TOKENS_PATH] = json_reply(status, {})
            failure = self.failure()
            with self.subTest(status=status):
                self.assertEqual(failure.code, "zepp_sign_in_refused")
                self.assertIn(str(status), failure.headline)
                self.assertIn("Termux", failure.remedy)

    def test_anything_but_a_redirect_means_the_api_changed(self) -> None:
        self.zepp.forced[_TOKENS_PATH] = json_reply(200, {"ok": True})
        self.assertEqual(self.failure().code, "zepp_api_changed")
        self.zepp.forced[_TOKENS_PATH] = Response(303, {}, b"")
        self.assertIn("no Location", self.failure().headline)
        self.zepp.forced[_TOKENS_PATH] = Response(
            303, {"location": "https://x.example/?other=1"}, b""
        )
        self.assertIn("no access token", self.failure().headline)

    def test_a_login_reply_without_tokens_is_reported_without_quoting_it(self) -> None:
        secret_body = {"token_info": {"login_token": LOGIN_TOKEN}, "note": sentinel("body")}
        self.zepp.forced[_LOGIN_PATH] = json_reply(200, secret_body)
        failure = self.failure()
        self.assertEqual(failure.code, "zepp_api_changed")
        self.assertNotIn("SENTINEL", failure.headline + failure.remedy)
        for forced in (
            json_reply(200, []),
            json_reply(200, {}),
            json_reply(500, {}),
            Response(200, {}, b"<html>"),
        ):
            self.zepp.forced[_LOGIN_PATH] = forced
            self.assertEqual(self.failure().code, "zepp_api_changed")

    def test_a_region_host_named_by_the_reply_is_tried_first(self) -> None:
        self.zepp.login_extra = {"domain": {"id-dns": "API-MIFIT-IN.huami.com"}}
        self.assertEqual(self.sign_in().host_hints, ("https://api-mifit-in.huami.com",))

    def test_a_hint_can_only_ever_be_a_zepp_origin(self) -> None:
        # Whatever a reply mentions, the token goes to Zepp's own hosts and nowhere else.
        self.zepp.login_extra = {"partner": "https://evil.example/api-mifit.zepp.com.evil.example"}
        self.assertEqual(self.sign_in().host_hints, ("https://api-mifit.zepp.com",))

    def test_the_token_block_is_not_scanned_for_hosts(self) -> None:
        self.zepp.login_extra = {
            "token_info": {
                "app_token": APP_TOKEN,
                "login_token": LOGIN_TOKEN,
                "user_id": USER_ID,
                "issuer": "api-mifit-ru.huami.com",
            }
        }
        self.assertEqual(self.sign_in().host_hints, ())

    def test_an_unreachable_zepp_is_a_network_failure(self) -> None:
        self.net.down.add("https://api-user-us2.zepp.com")
        failure = self.failure()
        self.assertEqual(failure.code, "no_network")
        self.assertIn("api-user-us2.zepp.com", failure.headline)


class SignOut(unittest.TestCase):
    def setUp(self) -> None:
        self.zepp = FakeZepp(EMAIL, PASSWORD)
        self.net = Net([self.zepp])
        self.session = zepp_auth.sign_in(EMAIL, PASSWORD, ENDPOINTS, self.net.send)

    def test_the_session_is_ended_with_its_login_token(self) -> None:
        self.assertTrue(zepp_auth.sign_out(self.session, ENDPOINTS, self.net.send))
        self.assertEqual(self.zepp.signed_out, 1)

    def test_an_unconfirmed_sign_out_is_false_never_an_exception(self) -> None:
        for forced in (
            json_reply(500, {}),
            json_reply(200, {"result": "no"}),
            Response(200, {}, b"<html>"),
        ):
            self.zepp.forced[_LOGOUT_PATH] = forced
            self.assertFalse(zepp_auth.sign_out(self.session, ENDPOINTS, self.net.send))
        self.zepp.forced.clear()
        self.net.down.add("https://api-mifit-us2.zepp.com")
        self.assertFalse(zepp_auth.sign_out(self.session, ENDPOINTS, self.net.send))

    def test_a_session_from_a_pasted_token_has_nothing_to_sign_out(self) -> None:
        pasted = zepp_auth.ZeppSession(user_id="", app_token=APP_TOKEN)
        before = len(self.net.requests)
        self.assertFalse(zepp_auth.sign_out(pasted, ENDPOINTS, self.net.send))
        self.assertEqual(len(self.net.requests), before)


if __name__ == "__main__":
    unittest.main()
