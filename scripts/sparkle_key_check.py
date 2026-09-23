#!/usr/bin/env python3
"""Verify that a Sparkle EdDSA signing key actually matches the app's
SUPublicEDKey, and verify signatures against that public key.

Why this exists
---------------
Sparkle verifies every downloaded update against the EdDSA public key baked
into the app (``SUPublicEDKey`` in Info.plist). If the private key used to sign
the appcast is not the counterpart of that public key, then:

  * ``sign_update`` still succeeds and prints a perfectly well-formed signature,
  * the appcast still validates as XML,
  * the release still uploads fine,

...and every single client silently refuses to install the update. There is no
error anywhere. That is the worst possible failure mode for a release pipeline,
so it is checked explicitly instead of assumed.

Why not use ``sign_update --verify``
------------------------------------
``sign_update --verify`` derives the public key from the *private* key you hand
it, so it only proves the signature is self-consistent - it says nothing about
whether that private key is the one the shipped app trusts. This script does the
comparison against the key that is actually in the bundle.

Key file format
---------------
Per ``generate_keys --help``: for keys in the modern format the exported file is
"the base64 encoding of the private seed" (32 bytes after decoding). Older keys
export the keychain password instead; those cannot be used for this check and the
script reports that with exit code 2 rather than pretending the key is wrong.

Only the Python standard library is used, so this runs anywhere, including on a
GitHub runner without pip installs.

Usage
-----
    # CI gate: does the signing key match the key compiled into the app?
    scripts/sparkle_key_check.py check --key-file "$KEY" \\
        --info-plist Release/DynamicNotch.app/Contents/Info.plist

    # Post-release smoke test: does the published DMG carry a signature that the
    # shipped public key accepts?
    scripts/sparkle_key_check.py verify --public-key "$SUPublicEDKey" \\
        --signature "$ED_SIGNATURE" path/to/DynamicNotch-1.2.dmg

    scripts/sparkle_key_check.py derive --key-file "$KEY"   # print the public key
    scripts/sparkle_key_check.py selftest                   # RFC 8032 test vector

Exit codes: 0 = ok, 1 = mismatch/invalid, 2 = unsupported key format.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import plistlib
import sys

# --------------------------------------------------------------------------
# Ed25519 (RFC 8032) - reference implementation, stdlib only.
# --------------------------------------------------------------------------

P = 2**255 - 19
_D = -121665 * pow(121666, P - 2, P) % P
_Q = 2**252 + 27742317777372353535851937790883648493
_I = pow(2, (P - 1) // 4, P)


def _inv(x: int) -> int:
    return pow(x, P - 2, P)


def _x_recover(y: int) -> int:
    xx = (y * y - 1) * _inv(_D * y * y + 1)
    x = pow(xx, (P + 3) // 8, P)
    if (x * x - xx) % P != 0:
        x = (x * _I) % P
    if x % 2 != 0:
        x = P - x
    return x


_BY = 4 * _inv(5) % P
_B = (_x_recover(_BY), _BY)


def _edwards(p1, p2):
    x1, y1 = p1
    x2, y2 = p2
    k = _D * x1 * x2 * y1 * y2
    x3 = (x1 * y2 + x2 * y1) * _inv(1 + k)
    y3 = (y1 * y2 + x1 * x2) * _inv(1 - k)
    return (x3 % P, y3 % P)


def _scalarmult(point, scalar: int):
    """Iterative double-and-add. Iterative on purpose: the classic recursive
    reference implementation needs ~255 stack frames and trips recursion limits
    under some embeddings."""
    result = (0, 1)  # identity
    addend = point
    while scalar > 0:
        if scalar & 1:
            result = _edwards(result, addend)
        addend = _edwards(addend, addend)
        scalar >>= 1
    return result


def _encode_point(point) -> bytes:
    x, y = point
    bits = [(y >> i) & 1 for i in range(255)] + [x & 1]
    return bytes(
        sum(bits[i * 8 + j] << j for j in range(8)) for i in range(32)
    )


def _decode_point(data: bytes):
    if len(data) != 32:
        raise ValueError("point must be 32 bytes")
    y = sum(((data[i // 8] >> (i % 8)) & 1) << i for i in range(255))
    x = _x_recover(y)
    if x & 1 != (data[31] >> 7) & 1:
        x = P - x
    if (-x * x + y * y - 1 - _D * x * x * y * y) % P != 0:
        raise ValueError("point is not on the curve")
    return (x, y)


def _decode_int(data: bytes) -> int:
    return sum(data[i] << (8 * i) for i in range(len(data)))


def public_key_from_seed(seed: bytes) -> bytes:
    """Ed25519 public key = (clamped SHA-512(seed)[:32]) * B."""
    if len(seed) != 32:
        raise ValueError(f"seed must be 32 bytes, got {len(seed)}")
    h = hashlib.sha512(seed).digest()
    scalar = 2**254 + sum(
        (1 << i) * ((h[i // 8] >> (i % 8)) & 1) for i in range(3, 254)
    )
    return _encode_point(_scalarmult(_B, scalar))


def verify(public_key: bytes, message: bytes, signature: bytes) -> bool:
    """RFC 8032 signature verification."""
    if len(signature) != 64 or len(public_key) != 32:
        return False
    try:
        r_point = _decode_point(signature[:32])
        a_point = _decode_point(public_key)
    except ValueError:
        return False
    s = _decode_int(signature[32:])
    if s >= _Q:
        return False
    h = _decode_int(
        hashlib.sha512(signature[:32] + public_key + message).digest()
    ) % _Q
    return _scalarmult(_B, s) == _edwards(r_point, _scalarmult(a_point, h))


# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------

# RFC 8032, section 7.1, TEST 1.
_RFC8032_SEED = "nWGxne/9WmC6hEr0kuwsxERJxWl7MmkZcDusAxyuf2A="
_RFC8032_PUBLIC = "11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo="


def die(message: str, code: int = 1) -> "NoReturn":  # noqa: F821
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(code)


def read_key_file(path: str) -> bytes:
    """Return the 32-byte Ed25519 seed from a Sparkle exported key file."""
    if path == "-":
        raw = sys.stdin.read()
    else:
        try:
            with open(path, encoding="utf-8") as fh:
                raw = fh.read()
        except OSError as exc:
            die(f"cannot read key file {path}: {exc}")
    raw = raw.strip()
    if not raw:
        die(f"key file {path} is empty")
    try:
        seed = base64.b64decode(raw, validate=True)
    except Exception:
        die(f"key file {path} is not valid base64")
    if len(seed) != 32:
        die(
            f"key file {path} decodes to {len(seed)} bytes, not 32. This is the "
            "legacy Sparkle key format (the keychain password rather than a raw "
            "seed), which cannot be used to derive the public key. Generate a "
            "modern key with: generate_keys --account <name>",
            code=2,
        )
    return seed


def read_public_key_from_plist(path: str) -> str:
    try:
        with open(path, "rb") as fh:
            plist = plistlib.load(fh)
    except OSError as exc:
        die(f"cannot read Info.plist {path}: {exc}")
    key = plist.get("SUPublicEDKey")
    if not key:
        die(f"{path} has no SUPublicEDKey - the app cannot verify updates at all")
    return key


def b64_to_point(value: str, label: str) -> bytes:
    try:
        raw = base64.b64decode(value.strip(), validate=True)
    except Exception:
        die(f"{label} is not valid base64")
    if len(raw) != 32:
        die(f"{label} decodes to {len(raw)} bytes, expected 32")
    return raw


# --------------------------------------------------------------------------
# commands
# --------------------------------------------------------------------------

def cmd_derive(args) -> int:
    seed = read_key_file(args.key_file)
    print(base64.b64encode(public_key_from_seed(seed)).decode())
    return 0


def cmd_check(args) -> int:
    seed = read_key_file(args.key_file)
    derived = public_key_from_seed(seed)

    if args.info_plist:
        expected_b64 = read_public_key_from_plist(args.info_plist)
        source = f"SUPublicEDKey in {args.info_plist}"
    elif args.public_key:
        expected_b64 = args.public_key
        source = "--public-key"
    else:
        die("pass --info-plist or --public-key")

    expected = b64_to_point(expected_b64, source)

    print(f"  signing key   -> {base64.b64encode(derived).decode()}")
    print(f"  app trusts    -> {expected_b64.strip()}  ({source})")

    if derived != expected:
        print(
            "\nMISMATCH: the key you sign releases with is not the key this app "
            "trusts.\nEvery update would be downloaded and then silently "
            "rejected.\nFix by either re-signing the app with the matching "
            "public key in Info.plist,\nor by rotating SUPublicEDKey and "
            "shipping that build before any update.",
            file=sys.stderr,
        )
        return 1

    print("\nOK - the signing key matches the public key the app verifies against.")
    return 0


def cmd_verify(args) -> int:
    pub = b64_to_point(args.public_key, "--public-key")
    sig = base64.b64decode(args.signature.strip(), validate=True)
    if len(sig) != 64:
        die(f"--signature decodes to {len(sig)} bytes, expected 64")
    try:
        with open(args.file, "rb") as fh:
            message = fh.read()
    except OSError as exc:
        die(f"cannot read {args.file}: {exc}")

    if not verify(pub, message, sig):
        print(
            f"INVALID: {args.file} does not carry a valid signature for the "
            "given public key.",
            file=sys.stderr,
        )
        return 1

    print(f"OK - {args.file} ({len(message)} bytes) verifies against {args.public_key.strip()}")
    return 0


def cmd_selftest(args) -> int:
    """Validate the implementation against the RFC 8032 test vector."""
    seed = base64.b64decode(_RFC8032_SEED)
    derived = base64.b64encode(public_key_from_seed(seed)).decode()
    ok = derived == _RFC8032_PUBLIC
    print(f"  RFC 8032 TEST 1 public key: {derived}")
    print(f"  expected:                   {_RFC8032_PUBLIC}")
    if not ok:
        print("SELFTEST FAILED - the Ed25519 implementation is wrong.", file=sys.stderr)
        return 1

    # RFC 8032 TEST 1 signature over the empty message.
    sig = bytes.fromhex(
        "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155"
        "5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"
    )
    pub = base64.b64decode(_RFC8032_PUBLIC)
    if not verify(pub, b"", sig):
        print("SELFTEST FAILED - signature verification is wrong.", file=sys.stderr)
        return 1
    # ...and must reject a tampered message.
    if verify(pub, b"x", sig):
        print("SELFTEST FAILED - accepted a signature for the wrong message.", file=sys.stderr)
        return 1

    print("  signature over empty message: verified")
    print("  tampered message rejected:    yes")
    print("\nSELFTEST PASSED")
    return 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    sub = p.add_subparsers(dest="command", required=True)

    d = sub.add_parser("derive", help="print the public key for a private key file")
    d.add_argument("--key-file", required=True, help="Sparkle exported key file, or - for stdin")
    d.set_defaults(func=cmd_derive)

    c = sub.add_parser("check", help="check a private key against the app's SUPublicEDKey")
    c.add_argument("--key-file", required=True, help="Sparkle exported key file, or - for stdin")
    c.add_argument("--info-plist", help="app Info.plist to read SUPublicEDKey from")
    c.add_argument("--public-key", help="expected public key, base64")
    c.set_defaults(func=cmd_check)

    v = sub.add_parser("verify", help="verify a signature over a file")
    v.add_argument("--public-key", required=True)
    v.add_argument("--signature", required=True, help="base64 EdDSA signature")
    v.add_argument("file", help="the file the signature was made over")
    v.set_defaults(func=cmd_verify)

    s = sub.add_parser("selftest", help="run the RFC 8032 test vector")
    s.set_defaults(func=cmd_selftest)

    args = p.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
