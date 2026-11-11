"""A read-only file over HTTP range requests, for pyarrow: only the bytes pyarrow asks for are downloaded. Counts requests and bytes.
Backs off politely on 429/503 (never retries a 403: that would be working around a block)."""
import io, time, urllib.error, urllib.request
UA = {"User-Agent": "training-custody-benchmark"}
class RangeFile(io.RawIOBase):
    def __init__(self, url, size=None):
        self.url, self.pos, self.requests, self.bytes = url, 0, 0, 0
        if size is None:
            r = self._open(urllib.request.Request(url, method="HEAD", headers=UA), 60); size = int(r.headers["Content-Length"])
        self.size = size
    @staticmethod
    def _open(req, timeout):
        """One request, with polite backoff on 429/5xx (30 s, doubling, up to ~15 min in all); a 403 stops at once, never retried."""
        wait = 30
        while True:
            try:
                return urllib.request.urlopen(req, timeout=timeout)
            except urllib.error.HTTPError as e:
                if e.code == 403: raise SystemExit("HTTP 403 from the server: stopping (no retry)")
                if e.code not in (429, 500, 502, 503, 504) or wait > 900: raise
            except (urllib.error.URLError, TimeoutError, ConnectionError):
                if wait > 900: raise
            time.sleep(wait); wait *= 2
    def readable(self): return True
    def seekable(self): return True
    def tell(self): return self.pos
    def seek(self, off, whence=0):
        self.pos = off if whence == 0 else self.pos + off if whence == 1 else self.size + off; return self.pos
    def read(self, n=-1):
        if n is None or n < 0: n = self.size - self.pos
        n = min(n, self.size - self.pos)
        if n <= 0: return b""
        req = urllib.request.Request(self.url, headers=dict(UA, Range="bytes=%d-%d" % (self.pos, self.pos + n - 1)))
        data = self._open(req, 120).read()
        self.requests += 1; self.bytes += len(data); self.pos += len(data); return data
    def readinto(self, b):
        d = self.read(len(b)); b[:len(d)] = d; return len(d)
