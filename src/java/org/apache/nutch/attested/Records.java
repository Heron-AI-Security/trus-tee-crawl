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

import java.io.ByteArrayOutputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.Arrays;

/**
 * The two record formats of the wrapper (step F3.2), the only ones.
 *
 * <p><b>File record</b> (ATTEST04), kept next to its file as .NAME.attested, big-endian, no padding, no trailing bytes:
 * magic "ATTEST04" (8) | chunk size (int, at least 1) | length (long, at least 0) | key id length (1 byte, 1 to 64) | key id (ASCII) |
 * folder id (32) | name length (2 bytes, 1 to 1024) | name (UTF-8) | chunk count (int, equal to ceil(length / chunk size)) |
 * chunk hashes (32 each: SHA-256 of the chunk's bytes, a flat list, step F3.3) | signature length (2 bytes, 1 to 128) | signature (ECDSA P-256, SHA-256, DER).
 * The signature is over the statement: UTF "tc-attest-file-v1", UTF key id, folder id, int name length, name, int chunk size, long length,
 * and the SHA-256 of the concatenated chunk hashes.</p>
 *
 * <p><b>Folder identity</b> (ATTEST05), kept in the folder as _attested-folder: magic "ATTEST05" (8) | folder id (32) | name length (2) | name |
 * parent id (32) | key id length (1) | key id | signature length (2) | signature. The statement is UTF "tc-attest-folder-v1", UTF key id,
 * folder id, int name length, name, parent id. The root "/" has the fixed all-zero id and no identity file (step F3.4): a folder directly
 * under the root has the parent id of zeros, and a file directly under the root is bound to the folder id of zeros.</p>
 */
final class Records {
  static final byte[] FILE_MAGIC = "ATTEST04".getBytes(StandardCharsets.US_ASCII);
  static final byte[] FOLDER_MAGIC = "ATTEST05".getBytes(StandardCharsets.US_ASCII);
  static final int HASH = 32;
  static final int FOLDER_ID = 32;
  static final int MAX_KEY_ID = 64;
  static final int MAX_NAME = 1024;
  static final int MAX_SIGNATURE = 128;
  static final long MAX_CHUNKS = 1L << 25;   // 512 GiB of data at 16 KiB per chunk; a record of about 1 GiB at most
  static final long MAX_FILE_RECORD = 8 + 4 + 8 + 1 + MAX_KEY_ID + FOLDER_ID + 2 + MAX_NAME + 4 + MAX_CHUNKS * HASH + 2 + MAX_SIGNATURE;
  static final long MAX_FOLDER_RECORD = 8 + FOLDER_ID + 2 + MAX_NAME + FOLDER_ID + 1 + MAX_KEY_ID + 2 + MAX_SIGNATURE;
  /** The id of the root folder: fixed, never stored. */
  static final byte[] ROOT_ID = new byte[FOLDER_ID];
  static final String FOLDER_FILE = "_attested-folder";
  static final String SUFFIX = ".attested";

  private Records() {
  }

  /** A decoded file record. */
  static final class FileRecord {
    final int chunkSize;
    final long length;
    final String keyId;
    final byte[] folderId;
    final String name;
    final byte[][] hashes;
    final byte[] signature;

    FileRecord(int chunkSize, long length, String keyId, byte[] folderId, String name, byte[][] hashes, byte[] signature) {
      this.chunkSize = chunkSize;
      this.length = length;
      this.keyId = keyId;
      this.folderId = folderId;
      this.name = name;
      this.hashes = hashes;
      this.signature = signature;
    }

    byte[] listHash() {
      return Records.listHash(hashes);
    }
  }

  /** A decoded folder identity. */
  static final class FolderRecord {
    final byte[] folderId;
    final String name;
    final byte[] parentId;
    final String keyId;
    final byte[] signature;

    FolderRecord(byte[] folderId, String name, byte[] parentId, String keyId, byte[] signature) {
      this.folderId = folderId;
      this.name = name;
      this.parentId = parentId;
      this.keyId = keyId;
      this.signature = signature;
    }
  }

  static String hex(byte[] b) {
    StringBuilder sb = new StringBuilder();
    for (byte x : b) {
      sb.append(String.format("%02x", x));
    }
    return sb.toString();
  }

  /** True when a file record of this many bytes cannot be valid: refused before anything is allocated. */
  static boolean fileRecordTooLong(long size) {
    return size > MAX_FILE_RECORD;
  }

  static long chunksFor(long length, long chunkSize) {
    return length == 0 ? 0 : (length - 1) / chunkSize + 1;
  }

  static boolean validKeyId(String id) {
    if (id == null || id.isEmpty() || id.length() > MAX_KEY_ID) {
      return false;
    }
    for (int i = 0; i < id.length(); i++) {
      char c = id.charAt(i);
      if (!(c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c == '-' || c == '_' || c == '.')) {
        return false;
      }
    }
    return true;
  }

  static boolean isFolderFileName(String name) {
    return FOLDER_FILE.equals(name);
  }

  static byte[] sha256(byte[]... parts) {
    try {
      MessageDigest md = MessageDigest.getInstance("SHA-256");
      for (byte[] p : parts) {
        md.update(p);
      }
      return md.digest();
    } catch (NoSuchAlgorithmException e) {
      throw new IllegalStateException(e);
    }
  }

  /** SHA-256 over the concatenated chunk hashes: what the signature covers of the content. */
  static byte[] listHash(byte[][] hashes) {
    return sha256(hashes);
  }

  private static byte[] utf8(String name) throws IOException {
    byte[] n = name == null ? new byte[0] : name.getBytes(StandardCharsets.UTF_8);
    if (n.length < 1 || n.length > MAX_NAME) {
      throw new IOException("a file or folder name must be 1 to " + MAX_NAME + " bytes");
    }
    return n;
  }

  private static void needId(byte[] id, String what) throws IOException {
    if (id == null || id.length != FOLDER_ID) {
      throw new IOException(what + " must be " + FOLDER_ID + " bytes");
    }
  }

  static byte[] fileStatement(String keyId, byte[] folderId, String name, int chunkSize, long length, byte[] listHash) throws IOException {
    if (!validKeyId(keyId) || chunkSize < 1 || length < 0 || listHash == null || listHash.length != HASH) {
      throw new IOException("bad values for a file statement");
    }
    needId(folderId, "the folder id");
    byte[] n = utf8(name);
    ByteArrayOutputStream b = new ByteArrayOutputStream();
    try (DataOutputStream o = new DataOutputStream(b)) {
      o.writeUTF("tc-attest-file-v1");
      o.writeUTF(keyId);
      o.write(folderId);
      o.writeInt(n.length);
      o.write(n);
      o.writeInt(chunkSize);
      o.writeLong(length);
      o.write(listHash);
    }
    return b.toByteArray();
  }

  static byte[] folderStatement(String keyId, byte[] folderId, String name, byte[] parentId) throws IOException {
    if (!validKeyId(keyId)) {
      throw new IOException("bad key id for a folder statement");
    }
    needId(folderId, "the folder id");
    needId(parentId, "the parent id");
    byte[] n = utf8(name);
    ByteArrayOutputStream b = new ByteArrayOutputStream();
    try (DataOutputStream o = new DataOutputStream(b)) {
      o.writeUTF("tc-attest-folder-v1");
      o.writeUTF(keyId);
      o.write(folderId);
      o.writeInt(n.length);
      o.write(n);
      o.write(parentId);
    }
    return b.toByteArray();
  }

  static byte[] encodeFile(int chunkSize, long length, byte[][] hashes, byte[] folderId, String name, String keyId, byte[] signature)
      throws IOException {
    if (!validKeyId(keyId) || chunkSize < 1 || length < 0 || signature == null || signature.length < 1 || signature.length > MAX_SIGNATURE
        || hashes == null || hashes.length != chunksFor(length, chunkSize) || hashes.length > MAX_CHUNKS) {
      throw new IOException("bad values for a file record");
    }
    needId(folderId, "the folder id");
    byte[] n = utf8(name);
    byte[] id = keyId.getBytes(StandardCharsets.US_ASCII);
    ByteArrayOutputStream b = new ByteArrayOutputStream(8 + 4 + 8 + 1 + id.length + FOLDER_ID + 2 + n.length + 4 + hashes.length * HASH + 2 + signature.length);
    try (DataOutputStream o = new DataOutputStream(b)) {
      o.write(FILE_MAGIC);
      o.writeInt(chunkSize);
      o.writeLong(length);
      o.writeByte(id.length);
      o.write(id);
      o.write(folderId);
      o.writeShort(n.length);
      o.write(n);
      o.writeInt(hashes.length);
      for (byte[] h : hashes) {
        if (h == null || h.length != HASH) {
          throw new IOException("a chunk hash must be " + HASH + " bytes");
        }
        o.write(h);
      }
      o.writeShort(signature.length);
      o.write(signature);
    }
    return b.toByteArray();
  }

  static byte[] encodeFolder(byte[] folderId, String name, byte[] parentId, String keyId, byte[] signature) throws IOException {
    if (!validKeyId(keyId) || signature == null || signature.length < 1 || signature.length > MAX_SIGNATURE) {
      throw new IOException("bad values for a folder identity");
    }
    needId(folderId, "the folder id");
    needId(parentId, "the parent id");
    byte[] n = utf8(name);
    byte[] id = keyId.getBytes(StandardCharsets.US_ASCII);
    ByteArrayOutputStream b = new ByteArrayOutputStream();
    try (DataOutputStream o = new DataOutputStream(b)) {
      o.write(FOLDER_MAGIC);
      o.write(folderId);
      o.writeShort(n.length);
      o.write(n);
      o.write(parentId);
      o.writeByte(id.length);
      o.write(id);
      o.writeShort(signature.length);
      o.write(signature);
    }
    return b.toByteArray();
  }

  /** A strict reader: every overrun is a damaged record, and nothing is allocated before its size is checked. */
  private static final class Reader {
    private final byte[] a;
    private int pos;

    Reader(byte[] a) {
      this.a = a;
    }

    long remaining() {
      return a.length - pos;
    }

    byte[] bytes(int n) throws IOException {
      if (n < 0 || n > remaining()) {
        throw damaged("too short");
      }
      byte[] out = Arrays.copyOfRange(a, pos, pos + n);
      pos += n;
      return out;
    }

    int u8() throws IOException {
      return bytes(1)[0] & 0xff;
    }

    int u16() throws IOException {
      byte[] b = bytes(2);
      return (b[0] & 0xff) << 8 | (b[1] & 0xff);
    }

    int i32() throws IOException {
      return ByteBuffer.wrap(bytes(4)).getInt();
    }

    long i64() throws IOException {
      return ByteBuffer.wrap(bytes(8)).getLong();
    }
  }

  private static IOException damaged(String why) {
    return new IOException("record is damaged (" + why + ")");
  }

  private static String text(byte[] b) throws IOException {
    try {
      return StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT)
          .decode(ByteBuffer.wrap(b)).toString();
    } catch (CharacterCodingException e) {
      throw damaged("a name is not UTF-8");
    }
  }

  private static String keyId(Reader r) throws IOException {
    int len = r.u8();
    if (len < 1 || len > MAX_KEY_ID) {
      throw damaged("impossible sizes");
    }
    String id = new String(r.bytes(len), StandardCharsets.US_ASCII);
    if (!validKeyId(id)) {
      throw damaged("the key id has characters that are not allowed");
    }
    return id;
  }

  private static String name(Reader r) throws IOException {
    int len = r.u16();
    if (len < 1 || len > MAX_NAME) {
      throw damaged("impossible sizes");
    }
    return text(r.bytes(len));
  }

  static FileRecord decodeFile(byte[] all) throws IOException {
    if (all == null || fileRecordTooLong(all.length)) {
      throw damaged("impossible sizes");
    }
    Reader r = new Reader(all);
    if (!Arrays.equals(r.bytes(FILE_MAGIC.length), FILE_MAGIC)) {
      throw damaged("wrong header");
    }
    int chunk = r.i32();
    long length = r.i64();
    if (chunk < 1 || length < 0) {
      throw damaged("impossible sizes");
    }
    String keyId = keyId(r);
    byte[] folderId = r.bytes(FOLDER_ID);
    String name = name(r);
    int count = r.i32();
    if (count < 0 || count > MAX_CHUNKS || count != chunksFor(length, chunk)) {
      throw damaged("impossible sizes");
    }
    if ((long) count * HASH + 2 > r.remaining()) {
      throw damaged("too short");
    }
    byte[][] hashes = new byte[count][];
    for (int i = 0; i < count; i++) {
      hashes[i] = r.bytes(HASH);
    }
    int sigLen = r.u16();
    if (sigLen < 1 || sigLen > MAX_SIGNATURE) {
      throw damaged("impossible sizes");
    }
    byte[] sig = r.bytes(sigLen);
    if (r.remaining() != 0) {
      throw damaged("trailing bytes");
    }
    return new FileRecord(chunk, length, keyId, folderId, name, hashes, sig);
  }

  static FolderRecord decodeFolder(byte[] all) throws IOException {
    if (all == null || all.length > MAX_FOLDER_RECORD) {
      throw damaged("impossible sizes");
    }
    Reader r = new Reader(all);
    if (!Arrays.equals(r.bytes(FOLDER_MAGIC.length), FOLDER_MAGIC)) {
      throw damaged("wrong header");
    }
    byte[] folderId = r.bytes(FOLDER_ID);
    String name = name(r);
    byte[] parentId = r.bytes(FOLDER_ID);
    String keyId = keyId(r);
    int sigLen = r.u16();
    if (sigLen < 1 || sigLen > MAX_SIGNATURE) {
      throw damaged("impossible sizes");
    }
    byte[] sig = r.bytes(sigLen);
    if (r.remaining() != 0) {
      throw damaged("trailing bytes");
    }
    return new FolderRecord(folderId, name, parentId, keyId, sig);
  }
}
