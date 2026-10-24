"""The Zepp wire format: what is sent, in what order, and where a token may go."""

from __future__ import annotations

import unittest

from zepp_import import zepp_wire


class Forms(unittest.TestCase):
    def test_step_one_matches_the_reference_byte_for_byte(self) -> None:
        form = zepp_wire.tokens_form("owner+test@example.com", "p a!s*s'w(o)rd~_.-é")
        self.assertEqual(
            zepp_wire.encode_form(form).decode("ascii"),
            "emailOrPhone=owner%2Btest%40example.com&state=REDIRECTION&client_id=HuaMi"
            "&password=p+a%21s%2As%27w%28o%29rd~_.-%C3%A9"
            "&redirect_uri=https%3A%2F%2Fs3-us-west-2.amazonaws.com"
            "%2Fhm-registration%2Fsuccesssignin.html"
            "&region=us-west-2&token=access&token=refresh&country_code=US",
        )

    def test_field_order_is_part_of_the_format(self) -> None:
        names = [name for name, _value in zepp_wire.tokens_form("e", "p")]
        self.assertEqual(
            names,
            [
                "emailOrPhone",
                "state",
                "client_id",
                "password",
                "redirect_uri",
                "region",
                "token",
                "token",
                "country_code",
            ],
        )

    def test_the_login_form_carries_the_access_token_as_code(self) -> None:
        form = dict(zepp_wire.login_form("ACCESS", "device-1"))
        self.assertEqual(form["code"], "ACCESS")
        self.assertEqual(form["device_id"], "device-1")
        self.assertEqual(form["grant_type"], "access_token")


class Headers(unittest.TestCase):
    def test_step_one_declares_its_body_encrypted(self) -> None:
        self.assertEqual(zepp_wire.tokens_headers()["x-hm-ekv"], "1")

    def test_data_calls_carry_the_token_and_opt_out_of_telemetry(self) -> None:
        headers = zepp_wire.api_headers("TOKEN", "request-1")
        self.assertEqual(headers["apptoken"], "TOKEN")
        self.assertEqual(headers["hm-privacy-ceip"], "false")
        self.assertEqual(headers["x-request-id"], "request-1")


class Hosts(unittest.TestCase):
    def test_only_zepp_api_hosts_are_found_in_a_reply(self) -> None:
        text = (
            '{"a":"https://API-MIFIT-IN.huami.com/x","b":"auth.zepp.com",'
            '"c":"api-mifit-de2.zepp.com","d":"evil.example","e":"api-mifit-in.huami.com"}'
        )
        self.assertEqual(
            zepp_wire.api_hosts_in(text),
            ["https://api-mifit-in.huami.com", "https://api-mifit-de2.zepp.com"],
        )

    def test_a_named_host_gets_https_and_must_be_zepps(self) -> None:
        self.assertEqual(
            zepp_wire.checked_api_host(" api-mifit-in.huami.com/ "),
            "https://api-mifit-in.huami.com",
        )
        self.assertEqual(
            zepp_wire.checked_api_host("https://API-MIFIT.zepp.com"), "https://api-mifit.zepp.com"
        )

    def test_a_host_that_only_resembles_zepp_is_refused(self) -> None:
        for value in (
            "evil.example",
            "api-mifit.zepp.com.evil.example",
            "evil.example/api-mifit.zepp.com",
            "http://api-mifit.zepp.com",
            "api-mifit.zepp.com:8443",
            "api-mifit.zepp.com/v1",
            "",
        ):
            with self.subTest(value=value), self.assertRaises(ValueError):
                zepp_wire.checked_api_host(value)

    def test_is_api_host_wants_exactly_an_https_zepp_origin(self) -> None:
        self.assertTrue(zepp_wire.is_api_host("https://api-mifit-sg2.huami.com"))
        for value in (
            "http://api-mifit.zepp.com",
            "https://api-mifit.zepp.com.evil.example",
            "https://evil.example",
            "api-mifit.zepp.com",
        ):
            with self.subTest(value=value):
                self.assertFalse(zepp_wire.is_api_host(value))

    def test_every_shipped_host_passes_its_own_rule(self) -> None:
        for origin in (*zepp_wire.PRIMARY_API_HOSTS, *zepp_wire.REGION_API_HOSTS):
            with self.subTest(origin=origin):
                self.assertTrue(zepp_wire.is_api_host(origin))


if __name__ == "__main__":
    unittest.main()
