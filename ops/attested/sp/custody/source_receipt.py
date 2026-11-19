"""The SourceReceipt: what the collection stage says about one fetch.

FIELDS
------
Each field: meaning / property / authenticated how / needed Sunday / future.
"Bound" below means covered by the quote's REPORTDATA, which authenticates
that *some* process in the TD emitted these bytes -- not which process.

  version               decoding.                     bound; needed.
  document_id           the dataset object this fetch becomes. Stops a
                        receipt being reassigned to another object.
                        bound; needed; the N>1 key.
  source_url            what was fetched. The hostname in it is checked
                        against the certificate IN THE TD.
                        bound; needed.
  raw_content_hash      H(A), A = HTTP body after transfer decoding, the
                        exact bytes handed to Task 2. THE custody field.
                        bound; needed.
  raw_content_length    length of A. Redundant with the hash; kept so a
                        reader can sanity-check without the bytes.
                        bound; optional.
  collection_policy_hash
                        H(canonical collection policy): TLS parameters,
                        request shape, artifact definition, trust store.
                        Lets a verifier say which collection rules were
                        CLAIMED to apply. bound; needed.
  server                {hostname, leaf_sha256, chain_sha256[],
                        signature_scheme, chain_valid, finished_verified,
                        transcript_sha256}: results of the TLS verifier
                        run INSIDE the TD. Workload claims -- a verifier
                        outside cannot re-check them without the handshake
                        plaintext, which Sunday does not export.
                        bound; needed (it is the source-identity claim).
  http_status           200 required by policy. bound; needed.
  code_hash             self-computed digest of collector + TLS POC source.
                        A CLAIM (see Test G). bound; kept to show the gap.
  nonce                 verifier challenge; freshness. bound; needed.
  binding               which construction ties this to hardware.

Deliberately absent:

  ecdhe_private, traffic secrets, the .att artifact
                        the whole point of the new architecture. Their
                        absence is also why the TLS checks become CLAIMS:
                        the verifier can no longer redo them. That is a
                        trade, not a free win.
  fetch time            the TD has no trusted clock. The OCSP producedAt
                        lower bound exists in the POC but is not signature-
                        checked there either; omitted rather than overstated.
  HTTP headers          not part of A. A future policy could commit to them.
"""
from typing import Any, Dict, NamedTuple, Optional

from . import canonical
from .errors import MalformedEvidenceError

VERSION = "tc-source-receipt/2"
#: v1: issued only for an authenticated server (fail closed).
#: v2: issued whatever the certificate's state; server.validation records it.
VERSIONS = ("tc-source-receipt/1", VERSION)
DOMAIN = "tc/source-receipt/v1"

FIELDS = ("version", "document_id", "source_url", "raw_content_hash",
          "raw_content_length", "collection_policy_hash", "server",
          "http_status", "code_hash", "nonce", "binding")


class SourceReceipt(NamedTuple):
    version: str
    document_id: str
    source_url: str
    raw_content_hash: str
    raw_content_length: int
    collection_policy_hash: str
    server: Dict[str, Any]
    http_status: int
    code_hash: str
    nonce: Optional[str]
    binding: Dict[str, Any]

    def to_bytes(self) -> bytes:
        return canonical.encode(self._asdict())

    def hash(self) -> str:
        return canonical.sha256_hex(self.to_bytes())


def from_bytes(data: bytes) -> SourceReceipt:
    value = canonical.decode(data)
    if set(value) != set(FIELDS):
        raise MalformedEvidenceError("source receipt fields {} != {}".format(
            sorted(value), sorted(FIELDS)))
    if value["version"] not in VERSIONS:
        raise MalformedEvidenceError("unknown version {!r}".format(value["version"]))
    return SourceReceipt(**value)


def authentication(rec: SourceReceipt):
    """(label, detail) for the source, as the emitter recorded it.

    authenticated    chain valid under the pinned anchors and hostname matches
    unauthenticated  anything else: an expired or not-yet-valid chain proves
                     nothing about who answered (its key may have leaked or
                     been retired), no more than an untrusted chain or a
                     hostname mismatch does. The detail says which.
    A v1 receipt was only issued for an authenticated server.
    """
    if rec.version == "tc-source-receipt/1":
        return "authenticated", ""
    v = rec.server.get("validation") or {}
    if v.get("authenticated") is True:
        return "authenticated", ""
    return "unauthenticated", "chain {}, hostname {}".format(v.get("chain"), v.get("hostname"))


def reportdata(receipt_bytes: bytes) -> bytes:
    return canonical.domain_hash(DOMAIN, receipt_bytes)
