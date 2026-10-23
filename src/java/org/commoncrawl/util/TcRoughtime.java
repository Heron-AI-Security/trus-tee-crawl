package org.commoncrawl.util;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetSocketAddress;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.util.Map;
import java.util.TreeMap;

/**
 * Training Custody: a minimal Roughtime client (IETF draft protocol).
 *
 * Sends one request carrying a caller-chosen 32-byte nonce and returns the
 * server's signed response, unverified. The response is kept as evidence and
 * verified offline by the verifier against the server's pinned public key
 * (verify/time-servers.json): the time server signs the time together with a
 * Merkle tree containing our nonce, so the signed time was produced after the
 * nonce existed. Verification needs Ed25519, which Java 11 lacks, and is not
 * needed here: the crawler only records.
 */
public final class TcRoughtime {

  private static final byte[] MAGIC = "ROUGHTIM".getBytes(StandardCharsets.US_ASCII);
  /** IETF version 1 and the draft versions 0x80000008..0x80000012. */
  private static final int[] VERSIONS;
  static {
    VERSIONS = new int[12];
    VERSIONS[0] = 1;
    for (int i = 1; i < VERSIONS.length; i++) {
      VERSIONS[i] = 0x80000000 + (0x12 - (i - 1));
    }
  }

  private TcRoughtime() {
  }

  /** The signed response packet for this nonce, or an IOException. */
  public static byte[] query(String host, int port, byte[] nonce, int timeoutMs,
      int attempts) throws IOException {
    if (nonce.length != 32) {
      throw new IllegalArgumentException("Roughtime nonce must be 32 bytes");
    }
    byte[] request = request(nonce);
    IOException last = null;
    for (int a = 0; a < attempts; a++) {
      try (DatagramSocket s = new DatagramSocket()) {
        s.setSoTimeout(timeoutMs);
        s.send(new DatagramPacket(request, request.length,
            new InetSocketAddress(host, port)));
        byte[] buf = new byte[4096];
        DatagramPacket p = new DatagramPacket(buf, buf.length);
        s.receive(p);
        byte[] out = new byte[p.getLength()];
        System.arraycopy(buf, 0, out, 0, out.length);
        if (out.length < 12 || !startsWith(out, MAGIC)) {
          throw new IOException("not a Roughtime response");
        }
        return out;
      } catch (IOException e) {
        last = e;
      }
    }
    throw last;
  }

  /** The server's midpoint time, read without verification (for logging). */
  public static long midpointUnverified(byte[] packet) {
    Map<String, byte[]> r = decode(slice(packet, 12, packet.length));
    Map<String, byte[]> srep = decode(r.get("SREP"));
    return ByteBuffer.wrap(srep.get("MIDP")).order(ByteOrder.LITTLE_ENDIAN).getLong();
  }

  static byte[] request(byte[] nonce) {
    ByteBuffer ver = ByteBuffer.allocate(4 * VERSIONS.length).order(ByteOrder.LITTLE_ENDIAN);
    for (int v : VERSIONS) {
      ver.putInt(v);
    }
    Map<String, byte[]> m = new TreeMap<>();
    m.put("VER", ver.array());
    m.put("NONC", nonce);
    m.put("ZZZZ", new byte[0]);
    int pad = 1024 - 12 - encode(m).length;
    m.put("ZZZZ", new byte[Math.max(0, pad) & ~3]);
    byte[] msg = encode(m);
    ByteBuffer pkt = ByteBuffer.allocate(12 + msg.length).order(ByteOrder.LITTLE_ENDIAN);
    pkt.put(MAGIC).putInt(msg.length).put(msg);
    return pkt.array();
  }

  private static int tag(String t) {
    byte[] b = new byte[4];
    byte[] a = t.getBytes(StandardCharsets.US_ASCII);
    System.arraycopy(a, 0, b, 0, a.length);
    return ByteBuffer.wrap(b).order(ByteOrder.LITTLE_ENDIAN).getInt();
  }

  /** Tag-value message: count, offsets, tags (ascending as uint32), values. */
  static byte[] encode(Map<String, byte[]> m) {
    TreeMap<Long, String> byTag = new TreeMap<>();
    for (String k : m.keySet()) {
      byTag.put(tag(k) & 0xffffffffL, k);
    }
    int n = byTag.size();
    ByteBuffer h = ByteBuffer.allocate(4 + 4 * (n - 1) + 4 * n).order(ByteOrder.LITTLE_ENDIAN);
    h.putInt(n);
    ByteArrayOutputStream values = new ByteArrayOutputStream();
    int off = 0, i = 0;
    for (String k : byTag.values()) {
      if (i++ > 0) {
        h.putInt(off);
      }
      byte[] v = m.get(k);
      values.write(v, 0, v.length);
      off += v.length;
    }
    for (Long t : byTag.keySet()) {
      h.putInt((int) (long) t);
    }
    byte[] head = h.array(), body = values.toByteArray();
    byte[] out = new byte[head.length + body.length];
    System.arraycopy(head, 0, out, 0, head.length);
    System.arraycopy(body, 0, out, head.length, body.length);
    return out;
  }

  static Map<String, byte[]> decode(byte[] m) {
    ByteBuffer b = ByteBuffer.wrap(m).order(ByteOrder.LITTLE_ENDIAN);
    int n = b.getInt(0);
    int base = 4 + 8 * n - 4;
    Map<String, byte[]> out = new TreeMap<>();
    for (int i = 0; i < n; i++) {
      int start = i == 0 ? 0 : b.getInt(4 + 4 * (i - 1));
      int end = i + 1 < n ? b.getInt(4 + 4 * i) : m.length - base;
      byte[] t = new byte[4];
      b.position(4 + 4 * (n - 1) + 4 * i);
      b.get(t);
      String name = new String(t, StandardCharsets.US_ASCII).replace("\0", "");
      out.put(name, slice(m, base + start, base + end));
    }
    return out;
  }

  private static byte[] slice(byte[] a, int from, int to) {
    byte[] r = new byte[to - from];
    System.arraycopy(a, from, r, 0, r.length);
    return r;
  }

  private static boolean startsWith(byte[] a, byte[] p) {
    for (int i = 0; i < p.length; i++) {
      if (a[i] != p[i]) {
        return false;
      }
    }
    return true;
  }
}
