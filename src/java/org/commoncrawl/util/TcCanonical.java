package org.commoncrawl.util;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;

/**
 * Training Custody canonical JSON, byte-identical to custody/canonical.py
 * (canonicalization tc-canonical-json/1).
 *
 * The subset: objects with ASCII string keys (sorted), strings, integers in
 * [-(2^53-1), 2^53-1], booleans, null, lists. Strings use json.dumps
 * (ensure_ascii=False) escapes and are emitted as UTF-8. Anything outside the
 * subset is refused, never encoded some other way: floats, other number types,
 * integers outside the range, non-ASCII or non-string keys, and strings with
 * unpaired UTF-16 surrogates (which have no UTF-8 encoding). For accepted
 * values the output equals RFC 8785 (JCS).
 *
 * No dependencies, so the differential test (verify/test_canonical.py) can
 * compile and run this class on its own.
 */
public final class TcCanonical {

  public static final String VERSION = "tc-canonical-json/1";
  static final long MAX_SAFE = (1L << 53) - 1;

  private TcCanonical() {
  }

  /** The one byte representation of v, as UTF-8. */
  public static byte[] encode(Object v) {
    return encodeString(v).getBytes(StandardCharsets.UTF_8);
  }

  public static String encodeString(Object v) {
    StringBuilder sb = new StringBuilder();
    write(sb, v);
    return sb.toString();
  }

  @SuppressWarnings("unchecked")
  private static void write(StringBuilder sb, Object v) {
    if (v == null) {
      sb.append("null");
    } else if (v instanceof Boolean) {
      sb.append(((Boolean) v) ? "true" : "false");
    } else if (v instanceof Long || v instanceof Integer) {
      long n = ((Number) v).longValue();
      if (n > MAX_SAFE || n < -MAX_SAFE) {
        throw new IllegalArgumentException("integer outside +-(2^53-1)");
      }
      sb.append(n);
    } else if (v instanceof String) {
      writeString(sb, (String) v);
    } else if (v instanceof Map) {
      Map<Object, Object> m = (Map<Object, Object>) v;
      Map<String, Object> sorted = new TreeMap<>();
      for (Map.Entry<Object, Object> e : m.entrySet()) {
        if (!(e.getKey() instanceof String)) {
          throw new IllegalArgumentException("keys must be strings");
        }
        String k = (String) e.getKey();
        for (int i = 0; i < k.length(); i++) {
          if (k.charAt(i) > 0x7f) {
            throw new IllegalArgumentException("non-ASCII key");
          }
        }
        sorted.put(k, e.getValue());
      }
      sb.append('{');
      boolean first = true;
      for (Map.Entry<String, Object> e : sorted.entrySet()) {
        if (!first) {
          sb.append(',');
        }
        first = false;
        writeString(sb, e.getKey());
        sb.append(':');
        write(sb, e.getValue());
      }
      sb.append('}');
    } else if (v instanceof List) {
      sb.append('[');
      boolean first = true;
      for (Object o : (List<Object>) v) {
        if (!first) {
          sb.append(',');
        }
        first = false;
        write(sb, o);
      }
      sb.append(']');
    } else {
      throw new IllegalArgumentException("not canonical-encodable: "
          + v.getClass().getName());
    }
  }

  private static void writeString(StringBuilder sb, String s) {
    sb.append('"');
    for (int i = 0; i < s.length(); i++) {
      char c = s.charAt(i);
      if (Character.isHighSurrogate(c)) {
        if (i + 1 >= s.length() || !Character.isLowSurrogate(s.charAt(i + 1))) {
          throw new IllegalArgumentException("unpaired surrogate");
        }
        sb.append(c).append(s.charAt(++i));
        continue;
      }
      if (Character.isLowSurrogate(c)) {
        throw new IllegalArgumentException("unpaired surrogate");
      }
      switch (c) {
      case '"': sb.append("\\\""); break;
      case '\\': sb.append("\\\\"); break;
      case '\n': sb.append("\\n"); break;
      case '\r': sb.append("\\r"); break;
      case '\t': sb.append("\\t"); break;
      case '\b': sb.append("\\b"); break;
      case '\f': sb.append("\\f"); break;
      default:
        if (c < 0x20) {
          sb.append(String.format("\\u%04x", (int) c));
        } else {
          sb.append(c);
        }
      }
    }
    sb.append('"');
  }

  /**
   * Differential test driver. Reads one value per line in a tagged form that
   * can express what JSON text cannot (unpaired surrogates, out-of-range
   * integers) and prints the hex of the canonical bytes, or ERR if refused:
   *
   *   n | t | f | i<decimal>; | d<decimal>; | s<count>:<4 hex per UTF-16 unit>
   *   | l<count>:<items> | m<count>:<key value pairs, keys tagged as s>
   */
  public static void main(String[] args) throws Exception {
    BufferedReader in = new BufferedReader(
        new InputStreamReader(System.in, StandardCharsets.US_ASCII));
    StringBuilder out = new StringBuilder();
    for (String line; (line = in.readLine()) != null;) {
      int[] pos = { 0 };
      Object v = parse(line, pos);
      try {
        byte[] b = encode(v);
        for (byte x : b) {
          out.append(Character.forDigit((x >> 4) & 0xf, 16))
              .append(Character.forDigit(x & 0xf, 16));
        }
      } catch (IllegalArgumentException e) {
        out.append("ERR");
      }
      out.append('\n');
    }
    System.out.print(out);
  }

  private static Object parse(String s, int[] p) {
    char t = s.charAt(p[0]++);
    switch (t) {
    case 'n': return null;
    case 't': return Boolean.TRUE;
    case 'f': return Boolean.FALSE;
    case 'i': {
      BigInteger n = new BigInteger(until(s, p, ';'));
      return n.bitLength() < 64 ? (Object) Long.valueOf(n.longValue()) : n;
    }
    case 'd': return Double.valueOf(until(s, p, ';'));
    case 's': {
      int count = Integer.parseInt(until(s, p, ':'));
      char[] cs = new char[count];
      for (int i = 0; i < count; i++) {
        cs[i] = (char) Integer.parseInt(s.substring(p[0], p[0] + 4), 16);
        p[0] += 4;
      }
      return new String(cs);
    }
    case 'l': {
      int count = Integer.parseInt(until(s, p, ':'));
      List<Object> l = new ArrayList<>();
      for (int i = 0; i < count; i++) {
        l.add(parse(s, p));
      }
      return l;
    }
    case 'm': {
      int count = Integer.parseInt(until(s, p, ':'));
      Map<Object, Object> m = new java.util.LinkedHashMap<>();
      for (int i = 0; i < count; i++) {
        Object k = parse(s, p);
        m.put(k, parse(s, p));
      }
      return m;
    }
    default:
      throw new IllegalArgumentException("bad tag " + t);
    }
  }

  private static String until(String s, int[] p, char end) {
    int e = s.indexOf(end, p[0]);
    String r = s.substring(p[0], e);
    p[0] = e + 1;
    return r;
  }
}
