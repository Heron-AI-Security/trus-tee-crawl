/*
 * Licensed to the Apache Software Foundation (ASF) under one or more
 * contributor license agreements.  See the NOTICE file distributed with
 * this work for additional information regarding copyright ownership.
 * The ASF licenses this file to You under the Apache License, Version 2.0
 * (the "License"); you may not use this file except in compliance with
 * the License.  You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package org.apache.nutch.attested;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.Random;

import org.apache.hadoop.fs.ChecksumException;
import org.apache.hadoop.fs.FSDataInputStream;
import org.apache.hadoop.fs.FSDataOutputStream;
import org.apache.hadoop.fs.FSInputStream;

/** The unit test of the record format and the flat hash list (steps F3.2 and F3.3). No cluster. */
public class RecordsTest {
  static int pass, fail;

  static void chk(String what, boolean ok) {
    if (ok) { pass++; System.out.println("  pass: " + what); } else { fail++; System.out.println("  FAIL: " + what); }
  }

  interface Thrower { void run() throws Exception; }

  static boolean refuses(Thrower t, String text) {
    try { t.run(); return false; } catch (Exception e) { return e.getMessage() != null && e.getMessage().contains(text); }
  }

  static boolean damagedOnly(Thrower t) {
    try { t.run(); return false; } catch (IOException e) { return e.getMessage() != null && e.getMessage().startsWith("record is damaged"); } catch (Throwable e) { return false; }
  }

  /** A seekable stream over bytes, to read through the verifying stream without a file system. */
  static final class BytesIn extends FSInputStream {
    private final byte[] a;
    private int pos;
    BytesIn(byte[] a) { this.a = a; }
    @Override public void seek(long p) { pos = (int) p; }
    @Override public long getPos() { return pos; }
    @Override public boolean seekToNewSource(long t) { return false; }
    @Override public int read() { return pos < a.length ? a[pos++] & 0xff : -1; }
    @Override public int read(byte[] b, int off, int len) { if (pos >= a.length) return -1; int n = Math.min(len, a.length - pos); System.arraycopy(a, pos, b, off, n); pos += n; return n; }
  }

  static byte[] data(int n, int seed) { byte[] b = new byte[n]; for (int i = 0; i < n; i++) b[i] = (byte) (i * 31 + (i >> 8) * 7 + (i >> 14) * 13 + seed); return b; }

  /** The hashes that the wrapper's output stream makes for these bytes. */
  static byte[][] hashesOf(byte[] content, int chunk) throws Exception {
    final byte[][][] got = new byte[1][][];
    try (HashingOutputStream h = new HashingOutputStream(new FSDataOutputStream(new ByteArrayOutputStream(), null), "/x", chunk, (p, len, c, hs) -> got[0] = hs)) {
      h.write(content, 0, content.length);
    }
    return got[0];
  }

  public static void main(String[] args) throws Exception {
    Path[] fleet = TestFleet.fleet(2);
    FleetKeys.reset();
    FleetKeys key = FleetKeys.load(fleet[0], true);
    AttestedSignatures sig = new AttestedSignatures(key);
    int chunk = 16384;
    byte[] content = data(50000, 1);
    byte[][] hashes = hashesOf(content, chunk);
    byte[] folder = Records.sha256("a folder".getBytes());

    System.out.println("== 1. the flat hash list (F3.3)");
    chk("50000 bytes in chunks of 16384 make 4 hashes, and each is the plain SHA-256 of its chunk (no tree, no prefix)",
        hashes.length == 4 && Arrays.equals(hashes[0], Records.sha256(Arrays.copyOfRange(content, 0, 16384))) && Arrays.equals(hashes[3], Records.sha256(Arrays.copyOfRange(content, 49152, 50000))));
    chk("chunk counts: 0 bytes make 0, 1 byte 1, 16384 bytes 1, 16385 bytes 2", Records.chunksFor(0, chunk) == 0 && Records.chunksFor(1, chunk) == 1 && Records.chunksFor(16384, chunk) == 1 && Records.chunksFor(16385, chunk) == 2 && hashesOf(new byte[0], chunk).length == 0 && hashesOf(new byte[16384], chunk).length == 1 && hashesOf(new byte[16385], chunk).length == 2);
    chk("the chunks of the test data differ from each other, so that swaps and replacements are visible", !Arrays.equals(hashes[0], hashes[1]) && !Arrays.equals(hashes[1], hashes[2]));
    chk("writing byte by byte or in odd pieces gives the same hashes", Arrays.deepEquals(hashes, hashesOf(content, chunk)) && Arrays.deepEquals(hashes, byByte(content, chunk)));
    chk("the list hash is the SHA-256 of the concatenated chunk hashes", Arrays.equals(Records.listHash(hashes), Records.sha256(hashes[0], hashes[1], hashes[2], hashes[3])));

    System.out.println("== 2. the file record (F3.2)");
    byte[] rec = sig.encodeFile(chunk, content.length, hashes, folder, "part-0000.bin");
    Records.FileRecord d = Records.decodeFile(rec);
    chk("a record starts with ATTEST04, and decodes to what was put in",
        new String(rec, 0, 8).equals("ATTEST04") && d.chunkSize == chunk && d.length == content.length && Arrays.equals(d.folderId, folder) && d.name.equals("part-0000.bin") && Arrays.deepEquals(d.hashes, hashes) && d.keyId.equals(key.signingKeyId()));
    chk("its size is 8+4+8+1+keyid+32+2+name+4+32 per chunk+2+signature", rec.length == 8 + 4 + 8 + 1 + d.keyId.length() + 32 + 2 + 13 + 4 + 32 * 4 + 2 + d.signature.length);
    sig.checkFile(d);
    chk("a record signed with a fleet key verifies, also on the other node of the fleet", true);
    new AttestedSignatures(FleetKeys.load(fleet[1], true)).checkFile(d);
    chk("the same record verifies on the second node (the list is the same)", true);
    chk("a record for an empty file has no hashes and still verifies", verifies(sig, sig.encodeFile(chunk, 0, new byte[0][], Records.ROOT_ID, "empty")));
    System.out.println("== 3. a truncated, oversized or malformed record fails cleanly");
    boolean allTruncations = true;
    for (int n = 0; n < rec.length; n++) { final int k = n; if (!damagedOnly(() -> Records.decodeFile(Arrays.copyOf(rec, k)))) { allTruncations = false; System.out.println("   not clean at length " + n); break; } }
    chk("every one of the " + rec.length + " shorter prefixes of a record is refused with 'record is damaged' and nothing else", allTruncations);
    chk("one extra byte at the end is refused (trailing bytes)", damagedOnly(() -> Records.decodeFile(Arrays.copyOf(rec, rec.length + 1))));
    byte[] big = rec.clone(); int countAt = 8 + 4 + 8 + 1 + d.keyId.length() + 32 + 2 + 13; big[countAt] = 0x7f;
    chk("a chunk count that does not match the length is refused", damagedOnly(() -> Records.decodeFile(big)));
    byte[] zeroChunk = rec.clone(); zeroChunk[8] = zeroChunk[9] = zeroChunk[10] = zeroChunk[11] = 0;
    chk("a chunk size of 0 is refused", damagedOnly(() -> Records.decodeFile(zeroChunk)));
    byte[] negLen = rec.clone(); negLen[12] = (byte) 0x80;
    chk("a negative length is refused", damagedOnly(() -> Records.decodeFile(negLen)));
    byte[] badMagic = rec.clone(); badMagic[7] = '3';
    chk("another magic (an old format) is refused: wrong header", refuses(() -> Records.decodeFile(badMagic), "wrong header"));
    byte[] badId = rec.clone(); badId[8 + 4 + 8 + 1] = ' ';
    chk("a key id with a character that is not allowed is refused", damagedOnly(() -> Records.decodeFile(badId)));
    chk("a size above the largest possible record is refused before anything is allocated, and the largest itself is about 1 GiB", Records.fileRecordTooLong(Records.MAX_FILE_RECORD + 1) && !Records.fileRecordTooLong(Records.MAX_FILE_RECORD) && Records.MAX_FILE_RECORD < (1L << 30) + 4096 && damagedOnly(() -> Records.decodeFile(null)));
    Random rnd = new Random(7); boolean garbageOk = true;
    for (int i = 0; i < 300 && garbageOk; i++) { byte[] g = new byte[rnd.nextInt(300)]; rnd.nextBytes(g); if (i % 3 == 0 && g.length > 8) System.arraycopy(Records.FILE_MAGIC, 0, g, 0, 8); final byte[] gg = g; garbageOk = damagedOnly(() -> Records.decodeFile(gg)); }
    chk("300 random byte strings (a third with the right magic) are refused cleanly, never with another kind of exception", garbageOk);
    System.out.println("== 4. what the signature binds");
    chk("a record moved to another folder id does not verify", refuses(() -> sig.checkFile(Records.decodeFile(Records.encodeFile(chunk, content.length, hashes, Records.ROOT_ID, "part-0000.bin", d.keyId, d.signature))), "does not verify"));
    chk("a record renamed to another file name does not verify", refuses(() -> sig.checkFile(Records.decodeFile(Records.encodeFile(chunk, content.length, hashes, folder, "other.bin", d.keyId, d.signature))), "does not verify"));
    chk("a record with another length does not verify", refuses(() -> sig.checkFile(Records.decodeFile(Records.encodeFile(chunk, content.length - 1, hashes, folder, "part-0000.bin", d.keyId, d.signature))), "does not verify"));
    byte[][] other = hashes.clone(); other[2] = Records.sha256("x".getBytes());
    chk("a record with one chunk hash replaced does not verify (the signature covers the whole list)", refuses(() -> sig.checkFile(Records.decodeFile(Records.encodeFile(chunk, content.length, other, folder, "part-0000.bin", d.keyId, d.signature))), "does not verify"));
    byte[][] swapped = hashes.clone(); swapped[0] = hashes[1]; swapped[1] = hashes[0];
    chk("two chunk hashes swapped do not verify (the order is covered too)", refuses(() -> sig.checkFile(Records.decodeFile(Records.encodeFile(chunk, content.length, swapped, folder, "part-0000.bin", d.keyId, d.signature))), "does not verify"));
    byte[] fs1 = Records.fileStatement(d.keyId, folder, "a", chunk, 10, Records.sha256()); 
    chk("the statement changes with every bound field", !Arrays.equals(fs1, Records.fileStatement(d.keyId + "x", folder, "a", chunk, 10, Records.sha256())) && !Arrays.equals(fs1, Records.fileStatement(d.keyId, Records.ROOT_ID, "a", chunk, 10, Records.sha256())) && !Arrays.equals(fs1, Records.fileStatement(d.keyId, folder, "b", chunk, 10, Records.sha256())) && !Arrays.equals(fs1, Records.fileStatement(d.keyId, folder, "a", chunk + 1, 10, Records.sha256())) && !Arrays.equals(fs1, Records.fileStatement(d.keyId, folder, "a", chunk, 11, Records.sha256())) && !Arrays.equals(fs1, Records.fileStatement(d.keyId, folder, "a", chunk, 10, Records.sha256(new byte[1]))));
    FleetKeys.reset(); Path out = TestFleet.outsider(); AttestedSignatures rogue = new AttestedSignatures(FleetKeys.load(out, true));
    byte[] recR = rogue.encodeFile(chunk, content.length, hashes, folder, "part-0000.bin");
    chk("a record signed by a valid key that is not in fleet.tsv is refused: not trusted here", refuses(() -> sig.checkFile(Records.decodeFile(recR)), "not trusted here"));
    System.out.println("== 5. the folder identity, and the fixed root");
    chk("the root id is 32 bytes of zeros", Records.ROOT_ID.length == 32 && Arrays.equals(Records.ROOT_ID, new byte[32]));
    byte[] fid = Records.sha256("f".getBytes());
    byte[] fr = sig.encodeFolder(fid, "seg1", Records.ROOT_ID);
    Records.FolderRecord fd = Records.decodeFolder(fr);
    sig.checkFolder(fd);
    chk("a folder identity starts with ATTEST05, decodes to what was put in, names the root as parent, and verifies", new String(fr, 0, 8).equals("ATTEST05") && Arrays.equals(fd.folderId, fid) && fd.name.equals("seg1") && Arrays.equals(fd.parentId, Records.ROOT_ID));
    boolean folderTrunc = true;
    for (int n = 0; n < fr.length; n++) { final int k = n; if (!damagedOnly(() -> Records.decodeFolder(Arrays.copyOf(fr, k)))) { folderTrunc = false; break; } }
    chk("every shorter prefix of a folder identity is refused cleanly, and so is a trailing byte", folderTrunc && damagedOnly(() -> Records.decodeFolder(Arrays.copyOf(fr, fr.length + 1))));
    chk("a folder identity re-pointed at another parent does not verify", refuses(() -> sig.checkFolder(Records.decodeFolder(Records.encodeFolder(fid, "seg1", Records.sha256("p".getBytes()), fd.keyId, fd.signature))), "does not verify"));
    chk("a folder identity renamed does not verify", refuses(() -> sig.checkFolder(Records.decodeFolder(Records.encodeFolder(fid, "seg2", Records.ROOT_ID, fd.keyId, fd.signature))), "does not verify"));
    System.out.println("== 6. a read that is checked chunk by chunk (F3.3)");
    Records.FileRecord good = Records.decodeFile(rec);
    try (FSDataInputStream in = new FSDataInputStream(new VerifyingInputStream(new FSDataInputStream(new BytesIn(content)), good, new org.apache.hadoop.fs.Path("/f")))) {
      byte[] all = new byte[content.length]; in.readFully(all);
      chk("an untouched file reads back byte for byte", Arrays.equals(all, content));
    }
    byte[] flip = content.clone(); flip[3 * chunk + 5] ^= 1;
    chk("one bit flipped in chunk 3 fails at chunk 3 ... ", readFails(flip, good, "chunk 3"));
    boolean earlyOk;
    try (FSDataInputStream in = new FSDataInputStream(new VerifyingInputStream(new FSDataInputStream(new BytesIn(flip)), good, new org.apache.hadoop.fs.Path("/f")))) {
      byte[] first = new byte[3 * chunk]; in.readFully(first); earlyOk = Arrays.equals(first, Arrays.copyOf(content, 3 * chunk));
    }
    chk("... while the three chunks before it still read fine", earlyOk);
    chk("one bit flipped in chunk 0 fails at chunk 0", readFails(flipAt(content, 0), good, "chunk 0"));
    chk("a file that is shorter than its record says fails: the file ends before the length in its record", readFails(Arrays.copyOf(content, 40000), good, "chunk 2"));
    System.out.println(); System.out.println("pass: " + pass + "   fail: " + fail);
    System.out.println(fail == 0 ? "RECORDS-TEST-PASS" : "RECORDS-TEST-FAIL");
    System.exit(fail == 0 ? 0 : 1);
  }

  static byte[] flipAt(byte[] c, int i) { byte[] b = c.clone(); b[i] ^= 1; return b; }

  static byte[][] byByte(byte[] c, int chunk) throws Exception {
    final byte[][][] got = new byte[1][][];
    try (HashingOutputStream h = new HashingOutputStream(new FSDataOutputStream(new ByteArrayOutputStream(), null), "/x", chunk, (p, len, cc, hs) -> got[0] = hs)) {
      for (int i = 0; i < c.length; ) { int n = Math.min(1 + (i % 7), c.length - i); if (n == 1) h.write(c[i]); else h.write(c, i, n); i += n; }
    }
    return got[0];
  }

  static boolean verifies(AttestedSignatures s, byte[] r) { try { s.checkFile(Records.decodeFile(r)); return true; } catch (Exception e) { return false; } }

  static boolean readFails(byte[] stored, Records.FileRecord rec, String where) {
    try (FSDataInputStream in = new FSDataInputStream(new VerifyingInputStream(new FSDataInputStream(new BytesIn(stored)), rec, new org.apache.hadoop.fs.Path("/f")))) {
      byte[] all = new byte[(int) rec.length]; in.readFully(all); return false;
    } catch (ChecksumException e) { return e.getMessage().contains(where); } catch (Exception e) { return false; }
  }
}
