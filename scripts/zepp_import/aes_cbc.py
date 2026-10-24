"""AES-128-CBC with PKCS#7 padding — encryption only.

The standard library has no AES and this tool takes no dependencies, so the cipher is
here. It is used for exactly one thing: step 1 of the Zepp sign-in wraps its form body in
AES-CBC under a key and IV that are public constants of the Zepp Android client
(`zepp_wire.py`). That is obfuscation in transit, not secrecy, so what matters about this
file is that it is CORRECT, not that it is constant-time.

Correctness is pinned three ways in `tests/test_aes_cbc.py`: the FIPS-197 Appendix C.1
single-block vector, the NIST SP 800-38A F.2.1 CBC vectors, and the same OpenSSL-produced
ciphertext `apps/mobile/test/pairing/zepp_crypto_test.dart` holds the Dart port to.

Layout (FIPS-197): the state is 16 bytes in COLUMN-major order, `state[row + 4*col]`.
"""

from __future__ import annotations

BLOCK_BYTES = 16
_KEY_BYTES = 16
_ROUNDS = 10  # AES-128
_REDUCTION = 0x1B  # x^8 + x^4 + x^3 + x + 1, low byte


def _rotl8(value: int, shift: int) -> int:
    return ((value << shift) | (value >> (8 - shift))) & 0xFF


def _build_sbox() -> bytes:
    """The FIPS-197 S-box: GF(2^8) inverse, then the affine transform.

    Generated rather than typed in as a 256-entry table, so there is no table to mistype;
    the known-answer tests are what prove the generator.
    """
    sbox = [0] * 256
    p = q = 1
    while True:
        p = p ^ ((p << 1) & 0xFF) ^ (_REDUCTION if p & 0x80 else 0)  # p *= 3
        q ^= q << 1  # q /= 3
        q ^= q << 2
        q ^= q << 4
        q &= 0xFF
        if q & 0x80:
            q ^= 0x09
        sbox[p] = q ^ _rotl8(q, 1) ^ _rotl8(q, 2) ^ _rotl8(q, 3) ^ _rotl8(q, 4) ^ 0x63
        if p == 1:
            break
    sbox[0] = 0x63
    return bytes(sbox)


_SBOX = _build_sbox()


def _xtime(value: int) -> int:
    """Multiply by x (i.e. by 2) in GF(2^8)."""
    doubled = value << 1
    return (doubled ^ _REDUCTION) & 0xFF if value & 0x80 else doubled


def expand_key(key: bytes) -> list[bytes]:
    """The 11 round keys for a 16-byte key (FIPS-197 section 5.2)."""
    if len(key) != _KEY_BYTES:
        raise ValueError(f"AES-128 needs a 16-byte key, got {len(key)}")
    words = [key[i : i + 4] for i in range(0, _KEY_BYTES, 4)]
    rcon = 1
    for index in range(4, 4 * (_ROUNDS + 1)):
        word = words[index - 1]
        if index % 4 == 0:
            rotated = word[1:] + word[:1]
            word = bytes(_SBOX[b] for b in rotated)
            word = bytes([word[0] ^ rcon]) + word[1:]
            rcon = _xtime(rcon)
        words.append(bytes(a ^ b for a, b in zip(words[index - 4], word, strict=True)))
    return [b"".join(words[r * 4 : r * 4 + 4]) for r in range(_ROUNDS + 1)]


def _shift_rows(state: bytes) -> bytes:
    # Row r moves left by r columns: new[r + 4c] = old[r + 4((c + r) mod 4)].
    return bytes(state[(i % 4) + 4 * (((i // 4) + (i % 4)) % 4)] for i in range(BLOCK_BYTES))


def _mix_columns(state: bytes) -> bytes:
    mixed = bytearray(BLOCK_BYTES)
    for col in range(0, BLOCK_BYTES, 4):
        a0, a1, a2, a3 = state[col : col + 4]
        total = a0 ^ a1 ^ a2 ^ a3
        mixed[col] = a0 ^ total ^ _xtime(a0 ^ a1)
        mixed[col + 1] = a1 ^ total ^ _xtime(a1 ^ a2)
        mixed[col + 2] = a2 ^ total ^ _xtime(a2 ^ a3)
        mixed[col + 3] = a3 ^ total ^ _xtime(a3 ^ a0)
    return bytes(mixed)


def _xor(left: bytes, right: bytes) -> bytes:
    return bytes(a ^ b for a, b in zip(left, right, strict=True))


def encrypt_block(block: bytes, round_keys: list[bytes]) -> bytes:
    """Encrypt one 16-byte block (FIPS-197 section 5.1)."""
    if len(block) != BLOCK_BYTES:
        raise ValueError(f"a block is 16 bytes, got {len(block)}")
    state = _xor(block, round_keys[0])
    for round_index in range(1, _ROUNDS):
        state = bytes(_SBOX[b] for b in state)
        state = _mix_columns(_shift_rows(state))
        state = _xor(state, round_keys[round_index])
    state = _shift_rows(bytes(_SBOX[b] for b in state))
    return _xor(state, round_keys[_ROUNDS])


def pkcs7_pad(data: bytes) -> bytes:
    """PKCS#7: always pads, so a whole-block input gains a full block."""
    fill = BLOCK_BYTES - len(data) % BLOCK_BYTES
    return data + bytes([fill]) * fill


def encrypt_cbc_pkcs7(plaintext: bytes, *, key: bytes, iv: bytes) -> bytes:
    """AES-128-CBC over PKCS#7-padded `plaintext`. A wrong-length key or IV is refused."""
    if len(iv) != BLOCK_BYTES:
        raise ValueError(f"CBC needs a 16-byte IV, got {len(iv)}")
    round_keys = expand_key(key)
    padded = pkcs7_pad(plaintext)
    previous = iv
    out = bytearray()
    for offset in range(0, len(padded), BLOCK_BYTES):
        previous = encrypt_block(_xor(padded[offset : offset + BLOCK_BYTES], previous), round_keys)
        out += previous
    return bytes(out)
