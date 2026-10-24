"""Signing in to Healthee: the handshake, and each way it is told apart when it fails."""

from __future__ import annotations

import unittest

from zepp_import.failures import ZeppImportError
from zepp_import.healthee_session import HealtheeSession, detail
from zepp_import.tests.fake_healthee import (
    ANON_KEY,
    AUTH_ORIGIN,
    JWT,
    ORIGIN,
    USER_ID,
    FakeHealthee,
)
from zepp_import.tests.support import Net, json_reply, sentinel
from zepp_import.transport import Response

EMAIL = "owner@example.com"
PASSWORD = sentinel("healthee-password")


class SignIn(unittest.TestCase):
    def setUp(self) -> None:
        self.healthee = FakeHealthee(EMAIL, PASSWORD)
        self.net = Net([self.healthee])
        self.session = HealtheeSession(ORIGIN, self.net.send)

    def failure(self, password: str = PASSWORD) -> ZeppImportError:
        with self.assertRaises(ZeppImportError) as raised:
            self.session.sign_in(EMAIL, password)
        return raised.exception

    def test_the_owner_is_told_where_the_password_goes_before_it_is_sent(self) -> None:
        self.assertEqual(self.session.sign_in_host(), "auth.healthee.test")
        self.assertEqual([r.path for r in self.net.requests], ["/api/auth-config"])

    def test_sign_in_returns_the_account_and_its_timezone(self) -> None:
        account = self.session.sign_in(EMAIL, PASSWORD)
        self.assertEqual((account.user_id, account.timezone), (USER_ID, "Asia/Kolkata"))

    def test_the_password_goes_to_the_sign_in_service_and_nowhere_else(self) -> None:
        self.session.sign_in(EMAIL, PASSWORD)
        holders = [r.origin for r in self.net.requests if PASSWORD in r.everything()]
        self.assertEqual(holders, [AUTH_ORIGIN])
        grant = self.net.to("auth.healthee.test")[0]
        self.assertEqual(grant.headers["apikey"], ANON_KEY)
        self.assertEqual(grant.query, {"grant_type": "password"})

    def test_later_calls_carry_the_owners_token(self) -> None:
        self.session.sign_in(EMAIL, PASSWORD)
        self.assertEqual(self.net.requests[-1].headers["authorization"], f"Bearer {JWT}")

    def test_a_wrong_password_is_named_with_the_services_own_reason(self) -> None:
        failure = self.failure("not-it")
        self.assertEqual(failure.code, "healthee_wrong_credentials")
        self.assertIn("Invalid login", failure.headline)

    def test_a_server_too_old_to_have_the_handshake_is_refused_before_any_write(self) -> None:
        self.healthee.forced[("GET", "/api/auth-config")] = json_reply(404, {"detail": "Not Found"})
        self.assertEqual(self.failure().code, "healthee_too_old")
        self.assertEqual(len(self.net.requests), 1)

    def test_a_server_with_no_sign_in_configured_says_so(self) -> None:
        self.healthee.auth_config = {"supabase_url": None, "supabase_anon_key": None}
        self.assertEqual(self.failure().code, "healthee_no_sign_in")

    def test_something_that_is_not_healthee(self) -> None:
        for forced in (
            json_reply(200, {"hello": "world"}),
            Response(200, {}, b"<html>"),
            json_reply(500, {}),
        ):
            self.healthee.forced[("GET", "/api/auth-config")] = forced
            self.assertEqual(self.failure().code, "healthee_not_healthee")

    def test_a_sign_in_service_that_is_not_https_never_gets_the_password(self) -> None:
        self.healthee.auth_config = {
            "supabase_url": "http://auth.example.com",
            "supabase_anon_key": "k",
        }
        failure = self.failure()
        self.assertEqual(failure.code, "bad_setting")
        self.assertFalse(any(PASSWORD in r.everything() for r in self.net.requests))

    def test_an_unreachable_server_is_a_network_failure(self) -> None:
        self.net.down.add(ORIGIN)
        failure = self.failure()
        self.assertEqual(failure.code, "no_network")
        self.assertIn("healthee.test", failure.headline)

    def test_an_account_reply_without_an_id_is_refused(self) -> None:
        self.healthee.forced[("GET", "/api/me")] = json_reply(200, {"timezone": "UTC"})
        self.assertEqual(self.failure().code, "healthee_refused")


class Replies(unittest.TestCase):
    def setUp(self) -> None:
        self.session = HealtheeSession(ORIGIN, Net([]).send)

    def test_a_gateway_timeout_says_the_write_may_have_landed(self) -> None:
        for status in (502, 503, 504):
            with self.assertRaises(ZeppImportError) as raised:
                self.session.object("a route", json_reply(status, {}))
            self.assertEqual(raised.exception.code, "healthee_slow")
            self.assertIn("nothing is imported twice", raised.exception.remedy)

    def test_a_refusal_carries_the_servers_reason_and_only_that(self) -> None:
        reply = json_reply(
            422, {"detail": [{"loc": ["body", "workouts", 0, "duration_s"], "msg": "too long"}]}
        )
        with self.assertRaises(ZeppImportError) as raised:
            self.session.object("the workout summaries", reply)
        self.assertIn("HTTP 422", raised.exception.headline)
        self.assertIn("'duration_s']: too long", raised.exception.headline)

    def test_a_reason_is_cut_short_and_a_body_is_never_quoted_whole(self) -> None:
        self.assertEqual(len(detail(json_reply(400, {"detail": "x" * 5000}))), 160)
        self.assertEqual(detail(Response(500, {}, b"<html>stack trace</html>")), "no reason given")
        self.assertEqual(
            detail(json_reply(400, {"unexpected": sentinel("body")})), "no reason given"
        )

    def test_a_200_that_is_not_json_is_refused(self) -> None:
        with self.assertRaises(ZeppImportError):
            self.session.object("the route list", Response(200, {}, b"<html>"))
        with self.assertRaises(ZeppImportError):
            self.session.object("the route list", json_reply(200, [1, 2]))


if __name__ == "__main__":
    unittest.main()
