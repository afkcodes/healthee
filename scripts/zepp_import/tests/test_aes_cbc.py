"""AES-128-CBC is pinned to three answers produced OUTSIDE this codebase.

A cipher that is wrong does not fail loudly: Zepp receives a body it cannot decrypt and
answers as it would to a wrong password. These vectors are what stand between a typo in
`aes_cbc.py` and a sign-in that "just does not work".
"""

from __future__ import annotations

import unittest

from zepp_import import zepp_wire
from zepp_import.aes_cbc import (
    BLOCK_BYTES,
    encrypt_block,
    encrypt_cbc_pkcs7,
    expand_key,
    pkcs7_pad,
)

# NIST SP 800-38A, F.2.1 (CBC-AES128.Encrypt): the four-block known answer.
_F21_K = bytes.fromhex("2b7e151628aed2a6abf7158809cf4f3c")
_F21_IV = bytes.fromhex("000102030405060708090a0b0c0d0e0f")
_F21_PLAIN = bytes.fromhex(
    "6bc1bee22e409f96e93d7e117393172a"
    "ae2d8a571e03ac9c9eb76fac45af8e51"
    "30c81c46a35ce411e5fbc1191a0a52ef"
    "f69f2445df4f9b17ad2b417be66c3710"
)
_F21_CIPHER = bytes.fromhex(
    "7649abac8119b246cee98e9b12e9197d"
    "5086cb9b507219ee95db113a917678b2"
    "73bed6b8e3c1743b7116e69e22229516"
    "3ff1caa1681fac09120eca307586e1a7"
)

# The same pair `apps/mobile/test/pairing/zepp_crypto_test.dart` holds the Dart port to:
# `urllib.parse.urlencode(..., doseq=True)` of the step-1 form, and `openssl enc
# -aes-128-cbc` over those bytes with the Zepp constants.
_FORM = (
    "emailOrPhone=owner%2Btest%40example.com&state=REDIRECTION&client_id=HuaMi"
    "&password=p+a%21s%2As%27w%28o%29rd~_.-%C3%A9"
    "&redirect_uri=https%3A%2F%2Fs3-us-west-2.amazonaws.com"
    "%2Fhm-registration%2Fsuccesssignin.html"
    "&region=us-west-2&token=access&token=refresh&country_code=US"
)
_OPENSSL_OUTPUT = (
    "815932a2f5d6cd860efe3cef4a004fda1c59eee58fce5a6ef1722ec410eb032f"
    "0bb23d6c552f0f5d52c89b775bef7718a51b68bd4b0dfd84c6b14237622a6dca"
    "c969c6620e9fcbee7d14d3a49daf82a0735ace3d97b6dc70811b273c3ac46410"
    "2a3f85981022335a3ffd41fca81d3ef860e9257bdd8ea01d3023d1d1c7745053"
    "818a2a09cbe95e267bb2a7c5f7f31a2cd5f78a1b7cb73208955359fed6c691e3"
    "3f28efe171b0508a7c528219da81740d738a16636cd52196712e4603d336b1bd"
    "9f34eb07bb4f5dc9772693820baac1c1ac4c668fadd29e83027d4a903808542b"
    "5a3d74dd75b3a622641014ba172ce4b8f3f34fbd3941a9482e3d170e63f71a41"
    "45c1a9386f8611f9e679330052ad91f8"
)


class KnownAnswers(unittest.TestCase):
    def test_fips_197_appendix_c1_single_block(self) -> None:
        round_keys = expand_key(bytes.fromhex("000102030405060708090a0b0c0d0e0f"))
        block = encrypt_block(bytes.fromhex("00112233445566778899aabbccddeeff"), round_keys)
        self.assertEqual(block.hex(), "69c4e0d86a7b0430d8cdb78070b4c55a")

    def test_sp800_38a_f21_cbc_chain(self) -> None:
        # The standard's vector has no padding; ours always pads, so compare the four
        # blocks the standard defines and expect exactly one more after them.
        ciphertext = encrypt_cbc_pkcs7(_F21_PLAIN, key=_F21_K, iv=_F21_IV)
        self.assertEqual(ciphertext[:64], _F21_CIPHER)
        self.assertEqual(len(ciphertext), 80)

    def test_the_zepp_sign_in_body_matches_openssl(self) -> None:
        ciphertext = encrypt_cbc_pkcs7(
            _FORM.encode("ascii"),
            key=zepp_wire.AES_KEY,
            iv=zepp_wire.AES_IV,
        )
        self.assertEqual(ciphertext.hex(), _OPENSSL_OUTPUT)
        self.assertEqual(len(ciphertext), 272)  # 270 bytes of form, padded


class Padding(unittest.TestCase):
    def test_a_whole_block_still_gains_a_full_block(self) -> None:
        self.assertEqual(pkcs7_pad(b"0123456789abcdef")[16:], bytes([16]) * 16)

    def test_a_short_block_is_filled_with_its_own_shortfall(self) -> None:
        self.assertEqual(pkcs7_pad(b"abc"), b"abc" + bytes([13]) * 13)

    def test_empty_input_is_one_block_of_padding(self) -> None:
        self.assertEqual(pkcs7_pad(b""), bytes([BLOCK_BYTES]) * BLOCK_BYTES)


class WrongSizes(unittest.TestCase):
    def test_a_wrong_length_key_is_refused_not_misused(self) -> None:
        with self.assertRaises(ValueError):
            encrypt_cbc_pkcs7(b"x", key=b"short", iv=zepp_wire.AES_IV)

    def test_a_wrong_length_iv_is_refused(self) -> None:
        with self.assertRaises(ValueError):
            encrypt_cbc_pkcs7(b"x", key=zepp_wire.AES_KEY, iv=b"short")

    def test_a_block_that_is_not_sixteen_bytes_is_refused(self) -> None:
        with self.assertRaises(ValueError):
            encrypt_block(b"too short", expand_key(zepp_wire.AES_KEY))

    def test_the_zepp_constants_are_sixteen_bytes(self) -> None:
        self.assertEqual((len(zepp_wire.AES_KEY), len(zepp_wire.AES_IV)), (16, 16))


if __name__ == "__main__":
    unittest.main()
