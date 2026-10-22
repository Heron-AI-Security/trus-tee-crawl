/*
 * Test vectors for the record formats ATTEST04 (a file record) and ATTEST05 (a folder identity), made with the wrapper's own code (Records, FleetKeys.idOf)
 * and a FIXED key pair that is for these vectors only. A second implementation, written only from the specification (docs/milestone-5-signed-records.md
 * section 16.3), is ops/attested/testvectors_check.py: it must give every vector the verdict that the vector says. ECDSA signatures are not deterministic,
 * so the committed file is the reference; to make a new one run this class with the output path.
 */
package org.apache.nutch.attested;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.security.KeyFactory;
import java.security.PrivateKey;
import java.security.Signature;
import java.security.spec.PKCS8EncodedKeySpec;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Base64;
import java.util.List;

public class TestVectors {
  static final String PRIVATE_PKCS8 = "MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgYzffwgWj//Rmp89fH4KJ3HH2bijnxDBW123fvN69CRWhRANCAAQNaq+JTyz0tzs3JLxREovfdkcBvCykrB1EuPc7dp+3EuwRaox4Yzvc0+SF6Jod3sDA8bE1BCL5LXpkjvYPJp7r";
  static final String PUBLIC_X509 = "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEDWqviU8s9Lc7NyS8URKL33ZHAbwspKwdRLj3O3aftxLsEWqMeGM73NPkheiaHd7AwPGxNQQi+S16ZI72Dyae6w==";
  static final int CHUNK = 16384;
  static final List<String> out = new ArrayList<>();
  static PrivateKey key;
  static String keyId;

  static String hex(byte[] b) {
    return Records.hex(b);
  }

  static String js(String s) {
    StringBuilder b = new StringBuilder("\"");
    for (char c : s.toCharArray()) {
      if (c == '"' || c == '\\') {
        b.append('\\').append(c);
      } else if (c < 32 || c > 126) {
        b.append(String.format("\\u%04x", (int) c));
      } else {
        b.append(c);
      }
    }
    return b.append('"').toString();
  }

  static byte[] content(int length) {
    byte[] d = new byte[length];
    for (int i = 0; i < length; i++) {
      d[i] = (byte) (i % 251);
    }
    return d;
  }

  static byte[] id(String label) throws IOException {
    return Records.sha256(label.getBytes(StandardCharsets.US_ASCII));
  }

  static byte[] sign(byte[] statement) throws Exception {
    Signature s = Signature.getInstance("SHA256withECDSA");
    s.initSign(key);
    s.update(statement);
    return s.sign();
  }

  static byte[][] hashes(byte[] data) throws IOException {
    int n = (int) Records.chunksFor(data.length, CHUNK);
    byte[][] h = new byte[n][];
    for (int i = 0; i < n; i++) {
      int from = i * CHUNK, to = Math.min(data.length, from + CHUNK);
      h[i] = Records.sha256(Arrays.copyOfRange(data, from, to));
    }
    return h;
  }

  /** the file is described by a rule, so that the vectors stay small: byte i is i mod 251; one byte may be changed and one byte appended */
  static void file(String name, String why, byte[] record, int length, int flipAt, int extra, byte[] folderId, String fileName, byte[] statement, String failure) {
    out.add("    {\"name\": " + js(name) + ", \"kind\": \"file\", \"why\": " + js(why) + ", \"record_hex\": \"" + hex(record) + "\", \"file\": {\"pattern\": \"byte i is i mod 251\", \"length\": " + length
        + ", \"flip_byte_at\": " + flipAt + ", \"extra_bytes\": " + extra + "}, \"expected_folder_id_hex\": \"" + hex(folderId) + "\", \"expected_name\": " + js(fileName) + ", \"statement_hex\": \"" + hex(statement)
        + "\", \"valid\": " + failure.isEmpty() + ", \"failure\": " + js(failure) + "}");
  }

  static void folder(String name, String why, byte[] record, byte[] folderId, String folderName, byte[] parentId, byte[] statement, String failure) {
    out.add("    {\"name\": " + js(name) + ", \"kind\": \"folder\", \"why\": " + js(why) + ", \"record_hex\": \"" + hex(record) + "\", \"expected_folder_id_hex\": \"" + hex(folderId)
        + "\", \"expected_name\": " + js(folderName) + ", \"expected_parent_id_hex\": \"" + hex(parentId) + "\", \"statement_hex\": \"" + hex(statement)
        + "\", \"valid\": " + failure.isEmpty() + ", \"failure\": " + js(failure) + "}");
  }

  static byte[] statementOf;

  static byte[] fileRecord(byte[] data, byte[] folderId, String name) throws Exception {
    byte[][] h = hashes(data);
    statementOf = Records.fileStatement(keyId, folderId, name, CHUNK, data.length, Records.listHash(h));
    return Records.encodeFile(CHUNK, data.length, h, folderId, name, keyId, sign(statementOf));
  }

  static byte[] flip(byte[] b, int at) {
    byte[] c = b.clone();
    c[at] ^= 1;
    return c;
  }

  public static void main(String[] a) throws Exception {
    key = KeyFactory.getInstance("EC").generatePrivate(new PKCS8EncodedKeySpec(Base64.getDecoder().decode(PRIVATE_PKCS8)));
    keyId = FleetKeys.idOf(Base64.getDecoder().decode(PUBLIC_X509));
    byte[] root = new byte[32];
    byte[] f1 = id("tc-vector-folder-1"), f2 = id("tc-vector-folder-2"), other = id("tc-vector-folder-other");

    byte[] d3 = content(40000);
    byte[] r3 = fileRecord(d3, f1, "data.bin");
    byte[] s3 = statementOf;
    file("file-three-chunks", "40000 bytes, chunks of 16384, 16384 and 7232", r3, 40000, -1, 0, f1, "data.bin", s3, "");
    byte[] d0 = content(0);
    byte[] r0 = fileRecord(d0, f1, "empty.bin");
    file("file-empty", "length 0, no chunks", r0, 0, -1, 0, f1, "empty.bin", statementOf, "");
    byte[] d1 = content(CHUNK);
    byte[] r1 = fileRecord(d1, f1, "full.bin");
    file("file-one-full-chunk", "exactly one chunk", r1, CHUNK, -1, 0, f1, "full.bin", statementOf, "");
    byte[] du = content(100);
    String uni = "d\u00e4t\u00e4-\u00df.bin";
    byte[] ru = fileRecord(du, f1, uni);
    file("file-unicode-name", "a file name with non-ASCII characters (UTF-8 in the statement, the length is in bytes)", ru, 100, -1, 0, f1, uni, statementOf, "");

    byte[] fst = Records.folderStatement(keyId, f1, "crawl", root);
    byte[] fr1 = Records.encodeFolder(f1, "crawl", root, keyId, sign(fst));
    folder("folder-under-root", "a folder directly under the root (parent id all zeros)", fr1, f1, "crawl", root, fst, "");
    byte[] fst2 = Records.folderStatement(keyId, f2, "segments", f1);
    byte[] fr2 = Records.encodeFolder(f2, "segments", f1, keyId, sign(fst2));
    folder("folder-nested", "a folder inside the first one", fr2, f2, "segments", f1, fst2, "");

    file("file-signature-flipped", "the last byte of the signature changed", flip(r3, r3.length - 1), 40000, -1, 0, f1, "data.bin", s3, "signature");
    file("file-truncated", "the record without its last byte", Arrays.copyOf(r3, r3.length - 1), 40000, -1, 0, f1, "data.bin", s3, "decode");
    file("file-trailing-byte", "the record with one byte after the signature", Arrays.copyOf(r3, r3.length + 1), 40000, -1, 0, f1, "data.bin", s3, "decode");
    byte[] bad = r3.clone();
    bad[7] = '5';
    file("file-bad-magic", "the magic ATTEST05 on a file record", bad, 40000, -1, 0, f1, "data.bin", s3, "decode");
    file("file-data-changed", "a valid record, but one byte of the second chunk of the file changed", r3, 40000, 20000, 0, f1, "data.bin", s3, "chunk-hash");
    file("file-length-changed", "a valid record, but the file has one more byte", r3, 40000, -1, 1, f1, "data.bin", s3, "length");
    file("file-wrong-folder", "a valid record that belongs to another folder than the one the file is in", r3, 40000, -1, 0, other, "data.bin", s3, "binding-folder");
    file("file-wrong-name", "a valid record for another file name than the file's", r3, 40000, -1, 0, f1, "other.bin", s3, "binding-name");
    folder("folder-signature-flipped", "the last byte of the signature changed", flip(fr1, fr1.length - 1), f1, "crawl", root, fst, "signature");
    folder("folder-truncated", "the identity without its last byte", Arrays.copyOf(fr1, fr1.length - 1), f1, "crawl", root, fst, "decode");
    folder("folder-wrong-parent", "a valid identity whose parent is not the folder above", fr2, f2, "segments", other, fst2, "binding-parent");
    folder("folder-wrong-name", "a valid identity for another folder name than the folder's", fr1, f1, "other", root, fst, "binding-name");

    StringBuilder b = new StringBuilder();
    b.append("{\n  \"format\": \"ATTEST04 and ATTEST05 test vectors, version 1\",\n");
    b.append("  \"specification\": \"docs/milestone-5-signed-records.md section 16.3\",\n");
    b.append("  \"key\": {\"id\": ").append(js(keyId)).append(", \"public_x509_b64\": ").append(js(PUBLIC_X509)).append(", \"private_pkcs8_b64\": ").append(js(PRIVATE_PKCS8))
        .append(", \"note\": \"a fixed key pair for these vectors only; ECDSA P-256 with SHA-256, DER signatures\"},\n");
    b.append("  \"chunk_size\": ").append(CHUNK).append(",\n");
    b.append("  \"order_of_checks\": [\"decode\", \"signature\", \"binding-folder\", \"binding-name\", \"binding-parent\", \"length\", \"chunk-hash\"],\n");
    b.append("  \"vectors\": [\n").append(String.join(",\n", out)).append("\n  ]\n}\n");
    Files.write(Paths.get(a[0]), b.toString().getBytes(StandardCharsets.UTF_8));
    System.out.println("wrote " + out.size() + " vectors to " + a[0]);
  }
}
