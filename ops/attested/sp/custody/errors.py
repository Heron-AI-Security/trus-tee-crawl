"""Exception hierarchy, following the source POC's split.

"This evidence is bad" and "we cannot check this" must stay distinguishable
at the call site; the second must never be reported as the first, and
neither may be reported as a pass.
"""


class CustodyError(Exception):
    """Base class for every error raised on purpose."""


class MalformedEvidenceError(CustodyError):
    """Evidence does not parse as the structure it claims to be."""


class InputCommitmentError(CustodyError):
    """The worker was handed bytes that do not match the committed input.

    Raised inside the worker, before the transformation runs. A worker that
    transformed mismatched input and recorded the mismatch would produce a
    receipt that is honest and useless; refusing is the only safe outcome.
    """


class PolicyError(CustodyError):
    """The policy file is not one this cleaner can execute."""


class AttestationUnavailable(CustodyError):
    """No TDX quote could be obtained on this machine."""
