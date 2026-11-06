"""Canonical encoding and commitments.

Every commitment in this package is a hash over bytes, and every structured
object is turned into bytes exactly one way. If two honest parties can
serialise the same receipt differently, a mismatch stops meaning "tampered"
and starts meaning "investigate by hand", and the verifier becomes useless.

THE ENCODING
------------
A deliberately small subset of JSON (``tc-canonical-json/1``):

  * objects with ASCII string keys, sorted by key
  * strings, integers in [-(2^53-1), 2^53-1], booleans, null, lists
  * no floats (their textual form is not canonical across languages)
  * no unpaired surrogates in strings (they have no UTF-8 encoding)
  * separators "," and ":" with no whitespace
  * UTF-8, non-ASCII characters emitted literally

For accepted values this coincides with RFC 8785 (JCS), which is the
property that lets a verifier written in another language reproduce the
bytes; the integer range is the one in which JCS's number serialisation is
plain decimal digits. Anything outside the subset is refused at encode time
rather than silently encoded some other way.

The Java emitter (``org.commoncrawl.util.TcCanonical`` in the CC-Bot patch)
must produce the same bytes and refuse the same values. The fixed vectors in
``custody/testdata/canonical-vectors.json`` and the randomized differential
test ``verify/test_canonical.py`` check both. Changing any rule here changes
receipt hashes, so it needs a new canonicalization version, not an edit.

Parsing is strict in the other direction: :func:`decode` re-encodes what it
parsed and refuses input that is not already in canonical form. A receipt
that differs from its own canonical encoding is either corrupted or was
produced by something other than this encoder, and either way is not what
the quote committed to.
"""
import hashlib
import json
from typing import Any

from .errors import MalformedEvidenceError

HASH_PREFIX = "sha256:"
VERSION = "tc-canonical-json/1"
MAX_SAFE_INTEGER = 2 ** 53 - 1


def _check(value: Any, path: str = "$") -> None:
    if value is None or isinstance(value, bool):
        return
    if isinstance(value, str):
        if any(0xD800 <= ord(c) <= 0xDFFF for c in value):
            raise TypeError("{}: unpaired surrogate".format(path))
        return
    if isinstance(value, int):
        if abs(value) > MAX_SAFE_INTEGER:
            raise TypeError("{}: integer outside +-(2^53-1)".format(path))
        return
    if isinstance(value, float):
        raise TypeError("{}: floats are not canonical".format(path))
    if isinstance(value, list):
        for index, item in enumerate(value):
            _check(item, "{}[{}]".format(path, index))
        return
    if isinstance(value, dict):
        for key, item in value.items():
            if not isinstance(key, str) or not key.isascii():
                raise TypeError("{}: keys must be ASCII strings".format(path))
            _check(item, "{}.{}".format(path, key))
        return
    raise TypeError("{}: {} is not encodable".format(path, type(value).__name__))


def encode(value: Any) -> bytes:
    """The one byte representation of ``value``."""
    _check(value)
    return json.dumps(value, sort_keys=True, separators=(",", ":"),
                      ensure_ascii=False, allow_nan=False).encode("utf-8")


def decode(data: bytes) -> Any:
    """Parse canonical bytes, refusing anything not in canonical form."""
    try:
        value = json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, ValueError) as exc:
        raise MalformedEvidenceError("not valid UTF-8 JSON: {}".format(exc))
    try:
        again = encode(value)
    except TypeError as exc:
        raise MalformedEvidenceError("outside the canonical subset: {}".format(exc))
    if again != data:
        raise MalformedEvidenceError(
            "not in canonical form ({} bytes given, canonical form is {} "
            "bytes)".format(len(data), len(again)))
    return value


def sha256_hex(data: bytes) -> str:
    """``sha256:<hex>``. The prefix names the algorithm so a digest is never
    compared against one computed with something else."""
    return HASH_PREFIX + hashlib.sha256(data).hexdigest()


def domain_hash(domain: str, data: bytes, length: int = 64) -> bytes:
    """SHA-512 over a domain tag and the data.

    The domain tag stops bytes committed for one purpose (a receipt) from
    being reinterpreted as a commitment for another (a worker key), which
    matters as soon as both constructions put their commitments into the
    same 64-byte REPORTDATA field.
    """
    if length != 64:
        raise ValueError("only 64-byte (SHA-512) commitments are defined")
    return hashlib.sha512(domain.encode("ascii") + b"\x00" + data).digest()
