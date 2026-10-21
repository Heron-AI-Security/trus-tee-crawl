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

import java.io.FileNotFoundException;
import java.io.IOException;
import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.apache.hadoop.fs.FSDataInputStream;
import org.apache.hadoop.fs.FSDataOutputStream;
import org.apache.hadoop.fs.FileSystem;
import org.apache.hadoop.fs.Path;

/**
 * The signed identity of every folder (steps 5.1.2 and F3.4). A folder has a random 32-byte id, and its identity file (_attested-folder) is signed
 * and names the folder, its name, and its parent's id. The root "/" has the fixed all-zero id and no file: a folder directly under the root has the
 * parent id of zeros. A file's record is bound to its folder's id and its name, and the chain of identities up to the root is checked, so a
 * file cannot be moved or copied to another place, or a folder be put under another parent, without being noticed. Read through a cache of a few
 * seconds.
 */
final class AttestedFolders {
  private static final int MAX_DEPTH = 256;
  private static final int PARTIAL_RETRIES = 40;
  private static final int CACHE_MAX = 4096;
  /** How long an identity that was read stays valid (nanoseconds); only the tests change it. */
  static volatile long ttlNanos = 10L * 1000 * 1000 * 1000;

  private static final class Entry {
    final Records.FolderRecord decoded;
    final long at;
    byte[] chainId;
    long chainAt;

    Entry(Records.FolderRecord decoded, long at) {
      this.decoded = decoded;
      this.at = at;
    }
  }

  private final FileSystem fs;
  private final AttestedSignatures sigs;
  private final SecureRandom random = new SecureRandom();
  private final Map<String, Entry> cache = new LinkedHashMap<String, Entry>(256, 0.75f, true) {
    private static final long serialVersionUID = 1L;

    @Override
    protected boolean removeEldestEntry(Map.Entry<String, Entry> eldest) {
      return size() > CACHE_MAX;
    }
  };

  AttestedFolders(FileSystem fs, AttestedSignatures sigs) {
    this.fs = fs;
    this.sigs = sigs;
  }

  static boolean isRoot(Path p) {
    return p == null || p.getName().isEmpty();
  }

  private static String key(Path dir) {
    return dir.toUri().getPath();
  }

  Path identityPath(Path dir) {
    return new Path(dir, Records.FOLDER_FILE);
  }

  void forgetTree(Path dir) {
    String prefix = key(dir);
    synchronized (cache) {
      cache.keySet().removeIf(k -> k.equals(prefix) || k.startsWith(prefix + "/"));
    }
  }

  private void forget(Path dir) {
    synchronized (cache) {
      cache.remove(key(dir));
    }
  }

  private byte[] readBytes(Path idPath) throws IOException {
    for (int i = 0;; i++) {
      long size;
      try {
        size = fs.getFileStatus(idPath).getLen();
      } catch (FileNotFoundException e) {
        return null;
      }
      if (size > Records.MAX_FOLDER_RECORD) {
        throw new IOException("folder identity is damaged (too long): " + idPath);
      }
      if (size > 0) {
        byte[] all = new byte[(int) size];
        try (FSDataInputStream in = fs.open(idPath)) {
          in.readFully(0, all);
        } catch (FileNotFoundException e) {
          return null;
        } catch (java.io.EOFException e) {
          all = null;
        }
        if (all != null) {
          return all;
        }
      }
      // a file that is empty or short may be one that another task is still writing: wait a little
      if (i >= PARTIAL_RETRIES) {
        throw new IOException("folder identity is damaged (empty or too short): " + idPath);
      }
      try {
        Thread.sleep(50);
      } catch (InterruptedException e) {
        Thread.currentThread().interrupt();
        throw new IOException("interrupted while waiting for the identity of " + idPath);
      }
    }
  }

  /** The verified identity of a folder, or null when it has none (and for the root, which has no file). */
  Records.FolderRecord read(Path dir) throws IOException {
    if (isRoot(dir)) {
      return null;
    }
    long now = System.nanoTime();
    long ttl = ttlNanos;
    synchronized (cache) {
      Entry e = cache.get(key(dir));
      if (e != null && ttl > 0 && now - e.at < ttl) {
        return e.decoded;
      }
    }
    byte[] bytes = readBytes(identityPath(dir));
    if (bytes == null) {
      return null;
    }
    Records.FolderRecord d = Records.decodeFolder(bytes);
    sigs.checkFolder(d);
    synchronized (cache) {
      cache.put(key(dir), new Entry(d, now));
    }
    return d;
  }

  /** The identity of a folder, made (with those of the folders above it that have none) when it does not exist. Not for the root. */
  Records.FolderRecord ensure(Path dir) throws IOException {
    if (isRoot(dir)) {
      throw new IOException("the root has no identity file; its id is fixed");
    }
    Records.FolderRecord d = read(dir);
    if (d != null) {
      return d;
    }
    List<Path> unidentified = new ArrayList<>();
    unidentified.add(dir);
    Records.FolderRecord above = null;
    for (Path cur = dir.getParent(); !isRoot(cur); cur = cur.getParent()) {
      if (unidentified.size() > MAX_DEPTH) {
        throw new IOException("the folder chain of " + dir + " is too deep");
      }
      above = read(cur);
      if (above != null) {
        break;
      }
      unidentified.add(cur);
    }
    byte[] parentId = above == null ? Records.ROOT_ID : above.folderId;
    Records.FolderRecord made = above;
    for (int i = unidentified.size() - 1; i >= 0; i--) {   // from the folder just below the identified ancestor (or the root) down to dir
      made = create(unidentified.get(i), parentId);
      parentId = made.folderId;
    }
    return made;
  }

  private Records.FolderRecord create(Path dir, byte[] parentId) throws IOException {
    Records.FolderRecord existing = read(dir);
    if (existing != null) {
      return existing;
    }
    byte[] id = new byte[Records.FOLDER_ID];
    random.nextBytes(id);
    byte[] bytes = sigs.encodeFolder(id, dir.getName(), parentId);
    Path idPath = identityPath(dir);
    try {
      try (FSDataOutputStream out = fs.create(idPath, false)) {
        out.write(bytes);
      }
    } catch (IOException e) {
      // Another writer was first. The real HDFS tells the loser either "file exists" or, while the winner is still writing, "already being
      // created by another client" (a different exception), so any failure to create is followed by a look at what is there now: the
      // winner's identity is read and used (read waits a little for a file that is still being written). If there is none, the failure is real.
      forget(dir);
      Records.FolderRecord winner = read(dir);
      if (winner == null) {
        throw e;
      }
      return winner;
    }
    Records.FolderRecord made = Records.decodeFolder(bytes);
    synchronized (cache) {
      cache.put(key(dir), new Entry(made, System.nanoTime()));
    }
    return made;
  }

  /** The folders on the way to dir that do not exist yet (outermost first): they get an identity once they are made. */
  List<Path> missingAncestors(Path dir) throws IOException {
    List<Path> missing = new ArrayList<>();
    Path cur = dir;
    while (!isRoot(cur) && !fs.exists(cur)) {
      missing.add(0, cur);
      cur = cur.getParent();
    }
    return missing;
  }

  void adopt(List<Path> folders) throws IOException {
    for (Path p : folders) {
      ensure(p);
    }
  }

  private Records.FolderRecord cached(Path dir) {
    long now = System.nanoTime();
    long ttl = ttlNanos;
    synchronized (cache) {
      Entry e = cache.get(key(dir));
      return e != null && ttl > 0 && now - e.at < ttl ? e.decoded : null;
    }
  }

  /** Makes sure that dir exists, with an identity for it and every folder above it. */
  void ensureTree(Path dir) throws IOException {
    if (isRoot(dir) || cached(dir) != null) {
      return;
    }
    List<Path> missing = missingAncestors(dir);
    if (!missing.isEmpty()) {
      fs.mkdirs(dir);
    }
    if (missing.isEmpty()) {
      ensure(dir);
    } else {
      adopt(missing);
    }
  }

  /**
   * Checks the whole chain of identities from dir up to the root: every folder names itself rightly and points at its parent's id (the
   * root's id for a folder at the top). Returns dir's id.
   */
  byte[] verifyChain(Path dir) throws IOException {
    long now = System.nanoTime();
    long ttl = ttlNanos;
    synchronized (cache) {
      Entry e = cache.get(key(dir));
      if (e != null && e.chainId != null && ttl > 0 && now - e.chainAt < ttl) {
        return e.chainId;
      }
    }
    Records.FolderRecord first = read(dir);
    if (first == null) {
      throw new IOException("the folder " + dir + " has no identity");
    }
    Path cur = dir;
    Records.FolderRecord d = first;
    for (int depth = 0;; depth++) {
      if (depth > MAX_DEPTH) {
        throw new IOException("the folder chain of " + dir + " is too deep or loops");
      }
      if (!d.name.equals(cur.getName())) {
        throw new IOException("the identity in " + cur + " is for a folder named '" + d.name + "', not '" + cur.getName() + "'");
      }
      Path parent = cur.getParent();
      if (isRoot(parent)) {
        if (!Arrays.equals(d.parentId, Records.ROOT_ID)) {
          throw new IOException("the folder " + cur + " claims a parent folder but is at the top");
        }
        break;
      }
      Records.FolderRecord pd = read(parent);
      if (pd == null) {
        throw new IOException("the parent folder " + parent + " has no identity");
      }
      if (!Arrays.equals(d.parentId, pd.folderId)) {
        throw new IOException("the identity in " + cur + " points to another parent folder than " + parent);
      }
      cur = parent;
      d = pd;
    }
    synchronized (cache) {
      Entry e = cache.get(key(dir));
      if (e != null) {
        e.chainId = first.folderId;
        e.chainAt = now;
      }
    }
    return first.folderId;
  }

  /** After a folder was renamed or moved: only its own identity file is signed again (new name, new parent); what is inside is untouched. */
  void resign(Path newDir, Records.FolderRecord old) throws IOException {
    Path idPath = identityPath(newDir);
    Path parent = newDir.getParent();
    byte[] parentId = isRoot(parent) ? Records.ROOT_ID : ensure(parent).folderId;
    byte[] bytes = sigs.encodeFolder(old.folderId, newDir.getName(), parentId);
    forgetTree(newDir);
    fs.delete(idPath, false);
    try (FSDataOutputStream out = fs.create(idPath, false)) {
      out.write(bytes);
    }
  }
}
