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

import java.io.File;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.net.URI;
import java.net.URISyntaxException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.EnumSet;
import java.util.List;
import java.util.Random;
import java.util.StringTokenizer;
import java.util.TreeMap;
import java.util.TreeSet;
import java.util.concurrent.Callable;

import org.apache.hadoop.conf.Configuration;
import org.apache.hadoop.fs.ChecksumException;
import org.apache.hadoop.fs.CommonPathCapabilities;
import org.apache.hadoop.fs.ContentSummary;
import org.apache.hadoop.fs.CreateFlag;
import org.apache.hadoop.fs.FSDataInputStream;
import org.apache.hadoop.fs.FSDataOutputStream;
import org.apache.hadoop.fs.FileContext;
import org.apache.hadoop.fs.FileStatus;
import org.apache.hadoop.fs.FileSystem;
import org.apache.hadoop.fs.LocatedFileStatus;
import org.apache.hadoop.fs.Options;
import org.apache.hadoop.fs.Path;
import org.apache.hadoop.fs.RawLocalFileSystem;
import org.apache.hadoop.fs.RemoteIterator;
import org.apache.hadoop.fs.permission.FsPermission;
import org.apache.hadoop.io.IntWritable;
import org.apache.hadoop.io.LongWritable;
import org.apache.hadoop.io.Text;
import org.apache.hadoop.mapreduce.Job;
import org.apache.hadoop.mapreduce.Mapper;
import org.apache.hadoop.mapreduce.Reducer;
import org.apache.hadoop.mapreduce.lib.input.FileInputFormat;
import org.apache.hadoop.mapreduce.lib.output.FileOutputFormat;

/**
 * The smoke test of the wrapper over a file system (steps 4.x to F3). Its behavior is fixed, so there are NO settings to feed it and no hook that
 * switches a rule off: the only test hooks are the directory of the fleet keys and the lifetime of the identity cache. Modes: fake (the wrapper over a
 * local directory that stands in for HDFS), mr (a MapReduce job through the wrapper, with the local runner).
 */
public class AttestedFsSmoke {
  static int checks = 0;
  static int failures = 0;
  static File ROOT;                 // the fake HDFS: its "/" is this directory
  static java.nio.file.Path[] FLEET;              // the key directories of a fleet of three nodes
  static AttestedSignatures SIG0, SIG1, OUTSIDER;

  static void check(String name, boolean ok) {
    checks++;
    if (!ok) {
      failures++;
    }
    System.out.println((ok ? "PASS  " : "FAIL  ") + name);
  }

  static void eq(String name, Object expected, Object actual) {
    boolean ok = expected == null ? actual == null : expected.equals(actual);
    check(name + (ok ? "" : "   expected=" + expected + " actual=" + actual), ok);
  }

  /** A local directory that stands in for HDFS: hdfs:// paths map into ROOT. */
  public static class FakeHdfs extends RawLocalFileSystem {
    private URI myUri;

    @Override
    public void initialize(URI uri, Configuration conf) throws IOException {
      super.initialize(uri, conf);
      if (uri.getAuthority() != null) {
        myUri = URI.create("hdfs://" + uri.getAuthority());
      }
    }

    @Override
    public URI getUri() {
      return myUri != null ? myUri : URI.create("hdfs://fake:9000");
    }

    @Override
    public String getScheme() {
      return "hdfs";
    }

    @Override
    protected void checkPath(Path path) {
    }

    @Override
    public File pathToFile(Path path) {
      Path p = path.isAbsolute() ? path : new Path(getWorkingDirectory(), path);
      return new File(ROOT != null ? ROOT : new File(System.getProperty("fake.root", "/tmp/fakeroot")), p.toUri().getPath());   // fake.root: for the script rehearsal, where the shell and the tools start their own JVMs
    }

    @Override
    public Path getWorkingDirectory() {
      return new Path(getUri().toString() + "/user/" + System.getProperty("user.name"));
    }

    /**
     * HDFS creates a file atomically at the NameNode: of two writers that create the same file without overwrite, exactly one wins and the other gets an
     * exception. RawLocalFileSystem checks "exists" and then writes, which is not atomic, and its create overloads end in a private method that none of
     * our overrides can reach, so EVERY public overload that a caller can use claims the file first (createNewFile is atomic).
     */
    private void claim(Path f, boolean overwrite) throws IOException {
      if (!overwrite) {
        File file = pathToFile(f);
        if (file.getParentFile() != null) {
          file.getParentFile().mkdirs();
        }
        if (!file.createNewFile()) {
          throw new org.apache.hadoop.fs.FileAlreadyExistsException("File already exists: " + f);
        }
      }
    }

    @Override
    public FSDataOutputStream create(Path f, FsPermission permission, boolean overwrite, int bufferSize, short replication, long blockSize,
        org.apache.hadoop.util.Progressable progress) throws IOException {
      claim(f, overwrite);
      return super.create(f, permission, true, bufferSize, replication, blockSize, progress);
    }

    @Override
    public FSDataOutputStream create(Path f, boolean overwrite, int bufferSize, short replication, long blockSize,
        org.apache.hadoop.util.Progressable progress) throws IOException {
      claim(f, overwrite);
      return super.create(f, true, bufferSize, replication, blockSize, progress);
    }

    private FileStatus statusOf(File f, Path qualified) {
      boolean dir = f.isDirectory();
      return new FileStatus(f.length(), dir, 1, 1L << 20, f.lastModified(), f.lastModified(), new FsPermission((short) (dir ? 0755 : 0644)),
          System.getProperty("user.name"), "supergroup", qualified);
    }

    @Override
    public FileStatus getFileStatus(Path p) throws IOException {
      File f = pathToFile(p);
      if (!f.exists()) {
        throw new FileNotFoundException("File " + p + " does not exist");
      }
      return statusOf(f, makeQualified(p));
    }

    @Override
    public FileStatus[] listStatus(Path p) throws IOException {
      File f = pathToFile(p);
      if (!f.exists()) {
        throw new FileNotFoundException("File " + p + " does not exist");
      }
      if (f.isFile()) {
        return new FileStatus[] {statusOf(f, makeQualified(p))};
      }
      File[] kids = f.listFiles();
      Arrays.sort(kids);
      FileStatus[] out = new FileStatus[kids.length];
      for (int i = 0; i < kids.length; i++) {
        out[i] = statusOf(kids[i], new Path(makeQualified(p), kids[i].getName()));
      }
      return out;
    }
  }

  public static class FakeWrapper extends AttestedHdfsFileSystem {
    @Override
    protected FileSystem createInner() {
      return new FakeHdfs();
    }
  }

  public static class FakeAdapter extends AttestedHdfs {
    public FakeAdapter(URI uri, Configuration conf) throws IOException, URISyntaxException {
      super(uri, new FakeWrapper(), conf);
    }
  }

  public static class LoopWrapper extends AttestedHdfsFileSystem {
    @Override
    protected FileSystem createInner() {
      return new FakeWrapper();
    }
  }

  public static void main(String[] args) throws Exception {
    String mode = args.length > 0 ? args[0] : "fake";
    setup();
    switch (mode) {
    case "fake":
      runFake();
      break;
    case "mr":
      runMr();
      break;
    default:
      System.err.println("unknown mode " + mode);
      System.exit(2);
    }
    System.out.println();
    System.out.println((failures == 0 ? "ALL-PASS" : "SOME-FAILED") + " (" + (checks - failures) + " of " + checks + " checks passed) mode=" + mode);
    System.exit(failures == 0 ? 0 : 1);
  }

  /** A private fake HDFS, and the keys of a fleet of three nodes; this JVM is node 0. */
  static void setup() throws Exception {
    ROOT = Files.createTempDirectory("attested-root").toFile();
    FLEET = TestFleet.fleet(3);
    FleetKeys.reset();
    FleetKeys.useDirForTesting(FLEET[0]);
    SIG0 = new AttestedSignatures(FleetKeys.load(FLEET[0], true));
    SIG1 = new AttestedSignatures(FleetKeys.load(FLEET[1], true));
    OUTSIDER = new AttestedSignatures(FleetKeys.load(TestFleet.outsider(), true));
    AttestedFolders.ttlNanos = 0;   // the attacks change files behind the wrapper's back, so nothing is remembered
  }

  static Configuration fakeConf() {
    Configuration conf = new Configuration(false);
    conf.set("fs.defaultFS", "hdfs://fake:9000");
    conf.set("fs.hdfs.impl", FakeWrapper.class.getName());
    conf.set("fs.AbstractFileSystem.hdfs.impl", FakeAdapter.class.getName());
    return conf;
  }

  static FileSystem wrapper(Configuration conf) throws IOException {
    return FileSystem.newInstance(URI.create("hdfs://fake:9000"), conf);
  }

  static void runFake() throws Exception {
    Configuration conf = fakeConf();
    Path base = new Path("hdfs://fake:9000/work");
    FakeHdfs plain = new FakeHdfs();
    plain.initialize(URI.create("hdfs://fake:9000"), new Configuration(false));
    boolean loopRefused = false;
    try {
      new LoopWrapper().initialize(URI.create("hdfs://fake:9000"), conf);
    } catch (IOException e) {
      loopRefused = e.getMessage().contains("loop");
    }
    check("a wrapper over another wrapper refuses to start (no loop)", loopRefused);
    boolean noKeys = false;
    FleetKeys.useDirForTesting(TestFleet.dir(null, null));
    try {
      new FakeWrapper().initialize(URI.create("hdfs://fake:9000"), conf);
    } catch (IOException e) {
      noKeys = true;
    }
    FleetKeys.useDirForTesting(FLEET[0]);
    check("a JVM without fleet keys cannot start the wrapper at all (no unsigned mode exists)", noKeys);
    exercise(conf, base, plain);
    verifyChecks(conf, base, plain);
    trustChecks(conf, base, plain);
    outsiderWriterChecks(conf, base, plain);
    bindingChecks(conf, base, plain);
    rootChecks(conf, base, plain);
    refusalChecks(conf, base, plain);
    copyToLocalChecks(conf, base, plain);
    containerChecks(conf, base, plain);
    cacheChecks(conf, base, plain);
    racingWriters(conf, base);
    fileContext(conf, new Path("hdfs://fake:9000/fc"));
  }

  // ------------------------------------------------------------------ helpers

  static byte[] data(int n, long seed) {
    byte[] d = new byte[n];
    new Random(seed).nextBytes(d);
    return d;
  }

  static byte[] readAll(FileSystem fs, Path p) throws IOException {
    try (FSDataInputStream in = fs.open(p)) {
      java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream();
      byte[] buf = new byte[8192];
      int n;
      while ((n = in.read(buf)) > 0) {
        out.write(buf, 0, n);
      }
      return out.toByteArray();
    }
  }

  static void put(FileSystem f, Path p, byte[] d) throws IOException {
    try (FSDataOutputStream o = f.create(p, true)) {
      o.write(d);
    }
  }

  static String lastError;

  static byte[] tryRead(FileSystem fs, Path p) {
    lastError = null;
    try {
      return readAll(fs, p);
    } catch (IOException e) {
      lastError = e.toString();
      return null;
    }
  }

  static Path sc(Path p) {
    return AttestedSidecar.pathFor(p);
  }

  static Path idf(Path dir) {
    return new Path(dir, Records.FOLDER_FILE);
  }

  static String sha(byte[] b) {
    return Records.hex(Records.sha256(b));
  }

  static byte[][] refHashes(byte[] content, int chunk) {
    int n = (int) Records.chunksFor(content.length, chunk);
    byte[][] h = new byte[n][];
    for (int i = 0; i < n; i++) {
      h[i] = Records.sha256(Arrays.copyOfRange(content, i * chunk, Math.min(content.length, (i + 1) * chunk)));
    }
    return h;
  }

  static Records.FileRecord recordOf(FileSystem plain, Path f) throws IOException {
    return Records.decodeFile(readAll(plain, sc(f)));
  }

  static Records.FolderRecord identityOf(FileSystem plain, Path dir) throws IOException {
    return Records.decodeFolder(readAll(plain, idf(dir)));
  }

  static boolean throwsChecksum(Callable<Object> call) {
    try {
      call.call();
      return false;
    } catch (ChecksumException e) {
      return true;
    } catch (Exception e) {
      return false;
    }
  }

  static boolean throwsIo(Callable<Object> call) {
    try {
      call.call();
      return false;
    } catch (IOException e) {
      return true;
    } catch (Exception e) {
      return false;
    }
  }

  static boolean throwsUnsupported(Callable<Object> call) {
    try {
      call.call();
      return false;
    } catch (UnsupportedOperationException e) {
      return e.getMessage() != null && e.getMessage().startsWith("attested:");
    } catch (Exception e) {
      return false;
    }
  }

  static int countOf(RemoteIterator<? extends FileStatus> it) throws IOException {
    int n = 0;
    while (it.hasNext()) {
      it.next();
      n++;
    }
    return n;
  }

  static void deleteTree(File f) {
    File[] kids = f.listFiles();
    if (kids != null) {
      for (File k : kids) {
        deleteTree(k);
      }
    }
    f.delete();
  }

  // ------------------------------------------------------------------ 1. the plain operations

  static void exercise(Configuration conf, Path base, FileSystem plain) throws Exception {
    FileSystem fs = wrapper(conf);
    check("fs.hdfs.impl puts the wrapper behind hdfs:// (paths unchanged)", fs instanceof AttestedHdfsFileSystem);
    Path dir = new Path(base, "plain");
    Path a = new Path(dir, "a");
    Path ab = new Path(a, "b");
    check("mkdirs a/b", fs.mkdirs(ab));
    check("getFileStatus: a folder, with the hdfs scheme, leading back to the wrapper", fs.getFileStatus(ab).isDirectory() && "hdfs".equals(fs.getFileStatus(ab).getPath().toUri().getScheme())
        && fs.getFileStatus(ab).getPath().getFileSystem(conf) instanceof AttestedHdfsFileSystem);
    Path f1 = new Path(a, "f1");
    byte[] small = "hello attested".getBytes(StandardCharsets.UTF_8);
    put(fs, f1, small);
    check("exists after create, with the right length, and it reads back", fs.exists(f1) && fs.getFileStatus(f1).getLen() == small.length && Arrays.equals(small, readAll(fs, f1)));
    check("the independent plain client sees the same file", plain.exists(f1) && Arrays.equals(small, readAll(plain, f1)));
    byte[] big = new byte[3 * 1024 * 1024 + 17];
    new Random(42).nextBytes(big);
    Path f2 = new Path(ab, "big.bin");
    try (FSDataOutputStream out = fs.create(f2, true, 4096)) {
      out.write(big);
    }
    eq("sha-256 of a 3 MB file read back", sha(big), sha(readAll(fs, f2)));
    check("the record of the small file holds the independent chunk hashes", Arrays.deepEquals(refHashes(small, 16384), recordOf(plain, f1).hashes));
    check("the record of the 3 MB file holds the independent chunk hashes (flat list)", Arrays.deepEquals(refHashes(big, 16384), recordOf(plain, f2).hashes));
    try (FSDataInputStream in = fs.openFile(f1).build().get()) {
      byte[] buf = new byte[small.length];
      in.readFully(buf);
      check("openFile builder reads the file", Arrays.equals(small, buf));
    }
    TreeSet<String> names = new TreeSet<>();
    for (FileStatus s : fs.listStatus(a)) {
      names.add(s.getPath().getName());
    }
    eq("listStatus(a) shows b and f1, and no record or identity file", new TreeSet<>(Arrays.asList("b", "f1")), names);
    eq("listFiles(recursive) finds both files and no record", 2, countOf(fs.listFiles(dir, true)));
    FileStatus[] globbed = fs.globStatus(new Path(a, "*"));
    eq("globStatus(a/*) count", 2, globbed == null ? -1 : globbed.length);
    ContentSummary cs = fs.getContentSummary(dir);
    check("the plain client sees the records and identity files that the wrapper hides", plain.exists(sc(f1)) && plain.exists(idf(a)) && plain.exists(idf(ab)));
    try (FSDataInputStream in = fs.open(f2)) {
      in.seek(20000);
      byte[] b1 = new byte[10];
      in.readFully(b1);
      byte[] b2 = new byte[5000];
      in.readFully(1000000, b2);
      in.seek(big.length - 3);
      byte[] b3 = new byte[8];
      int n = in.read(b3);
      check("seek, positioned read and a read at the end are right", Arrays.equals(b1, Arrays.copyOfRange(big, 20000, 20010)) && Arrays.equals(b2, Arrays.copyOfRange(big, 1000000, 1005000)) && n == 3 && in.read() == -1);
    }
    Path f3 = new Path(ab, "renamed");
    check("rename a file: old name gone, new name present, and it reads", fs.rename(f1, f3) && !fs.exists(f1) && fs.exists(f3) && Arrays.equals(small, readAll(fs, f3)));
    Path ab2 = new Path(a, "b2");
    check("rename a folder: the files inside move with it and still read", fs.rename(ab, ab2) && Arrays.equals(big, readAll(fs, new Path(ab2, "big.bin"))) && Arrays.equals(small, readAll(fs, new Path(ab2, "renamed"))));
    boolean notEmptyRefused;
    try {
      notEmptyRefused = !fs.delete(a, false);
    } catch (IOException e) {
      notEmptyRefused = true;
    }
    check("delete(non-empty folder, recursive=false) is refused", notEmptyRefused);
    Path f4 = new Path(ab2, "renamed");
    check("delete a file removes its record too", plain.exists(sc(f4)) && fs.delete(f4, false) && !plain.exists(sc(f4)));
    Path emptyDir = new Path(dir, "emptydir");
    fs.mkdirs(emptyDir);
    check("an empty folder holds nothing but its own identity file in the plain HDFS (the cause of the contract tests' two differences)", plain.exists(idf(emptyDir)) && plain.listStatus(emptyDir).length == 1);
    check("delete(empty folder, recursive=false) works, as the contract of delete says: the folder and its identity are gone", fs.delete(emptyDir, false) && !plain.exists(emptyDir));
    Path fullDir = new Path(dir, "fulldir");
    put(fs, new Path(fullDir, "kept.bin"), data(100, 5));
    boolean refusedFull;
    try {
      refusedFull = !fs.delete(fullDir, false);
    } catch (IOException e) {
      refusedFull = true;
    }
    check("delete(folder with a file in it, recursive=false) is still refused, and the file and its identity are untouched", refusedFull && Arrays.equals(data(100, 5), readAll(fs, new Path(fullDir, "kept.bin"))) && plain.exists(idf(fullDir)));
    Path mk = new Path(dir, "mkrm");
    check("mkdirs and then delete of the new folder (the contract's testMkDirRmDir) works, and a missing path is answered with false", fs.mkdirs(mk) && fs.delete(mk, false) && !fs.exists(mk) && !fs.delete(mk, false));
    check("delete recursive removes the folder, its identities and its records", fs.delete(dir, true) && !plain.exists(dir));
  }

  // ------------------------------------------------------------------ 2. what changed behind the wrapper's back

  static void verifyChecks(Configuration conf, Path base, FileSystem plain) throws Exception {
    FileSystem fs = wrapper(conf);
    Path dir = new Path(base, "verify");
    fs.mkdirs(dir);
    int[] sizes = {0, 1, 16383, 16384, 16385, 40000, 100000};
    boolean rec = true, same = true, builder = true, len = true;
    for (int s : sizes) {
      Path f = new Path(dir, "s" + s);
      byte[] d = data(s, s);
      put(fs, f, d);
      rec &= plain.exists(sc(f)) && Arrays.deepEquals(refHashes(d, 16384), recordOf(plain, f).hashes);
      same &= Arrays.equals(d, readAll(fs, f));
      try (FSDataInputStream in = fs.openFile(f).build().get()) {
        byte[] b = new byte[s];
        in.readFully(b);
        builder &= Arrays.equals(b, d);
      }
      len &= fs.getFileStatus(f).getLen() == s;
    }
    check("every size (0, 1, one under, at and one over a chunk, 40000, 100000): a record with the right hashes", rec);
    check("every size: reads return the bytes that were written", same);
    check("every size: the builder form of open verifies and reads too", builder);
    check("every size: the length reported by the wrapper is the real length", len);
    Path f = new Path(dir, "tamper");
    byte[] d = data(100000, 5);
    put(fs, f, d);
    byte[] changed = d.clone();
    changed[3 * 16384 + 5] ^= 1;
    put(plain, f, changed);
    try (FSDataInputStream in = fs.open(f)) {
      byte[] first = new byte[3 * 16384];
      in.readFully(first);
      check("changed byte in chunk 3: the three chunks before it still read", Arrays.equals(first, Arrays.copyOf(d, 3 * 16384)));
    }
    check("changed byte: reading the changed chunk fails at chunk 3", throwsChecksum(() -> {
      try (FSDataInputStream in = fs.open(f)) {
        in.seek(3 * 16384 + 100);
        in.read();
      }
      return null;
    }) && tryRead(fs, f) == null && lastError.contains("chunk 3"));
    put(plain, f, d);
    check("the original bytes put back: the file verifies again", Arrays.equals(d, readAll(fs, f)));
    for (int flip : new int[] {0, 16384, 99999}) {
      byte[] c = d.clone();
      c[flip] ^= 0x80;
      put(plain, f, c);
      check("one bit flipped at byte " + flip + ": the read fails at chunk " + flip / 16384, tryRead(fs, f) == null && lastError.contains("chunk " + flip / 16384));
    }
    put(plain, f, Arrays.copyOf(d, 70000));
    check("shortened file: the open fails and says why (also with the builder)", throwsChecksum(() -> fs.open(f)) && throwsIo(() -> {
      org.apache.hadoop.util.functional.FutureIO.awaitFuture(fs.openFile(f).build()).close();
      return null;
    }));
    put(plain, f, Arrays.copyOf(d, 100001));
    check("lengthened file: the open fails and says why", tryRead(fs, f) == null && lastError.contains("length is 100001"));
    put(plain, f, d);
    byte[] good = readAll(plain, sc(f));
    boolean allDamaged = true;
    for (int cut : new int[] {0, 5, 40, good.length / 2, good.length - 1}) {
      put(plain, sc(f), Arrays.copyOf(good, cut));
      allDamaged &= tryRead(fs, f) == null && lastError.contains("record is damaged");
    }
    byte[] garbage = data(good.length, 9);
    put(plain, sc(f), garbage);
    allDamaged &= tryRead(fs, f) == null;
    byte[] extra = Arrays.copyOf(good, good.length + 1);
    put(plain, sc(f), extra);
    allDamaged &= tryRead(fs, f) == null && lastError.contains("trailing");
    check("a damaged record (cut at five places, garbage, one byte too many) fails the open, cleanly", allDamaged);
    put(plain, sc(f), good);
    check("the original record put back: the file verifies again", Arrays.equals(d, readAll(fs, f)));
    plain.delete(sc(f), false);
    check("a missing record: the open is refused (there is no policy that allows it)", tryRead(fs, f) == null && lastError.contains("no record"));
    put(plain, sc(f), good);
    Path g = new Path(dir, "other");
    put(fs, g, data(100000, 6));
    byte[] otherRecord = readAll(plain, sc(g));
    put(plain, sc(f), otherRecord);
    check("the record of another file (same size) put next to this one: the read fails (its name is another)", tryRead(fs, f) == null);
    put(plain, sc(f), good);
    put(fs, f, data(500, 7));
    check("writing over a file replaces its record: the new content verifies", Arrays.equals(data(500, 7), readAll(fs, f)) && recordOf(plain, f).length == 500);
    Path cp = new Path(dir, "copy");
    org.apache.hadoop.fs.FileUtil.copy(fs, f, fs, cp, false, true, conf);
    check("a copy made through the wrapper has its own record and verifies", Arrays.equals(data(500, 7), readAll(fs, cp)) && plain.exists(sc(cp)));
    Path b = new Path(dir, "built");
    try (FSDataOutputStream o = fs.createFile(b).build()) {
      o.write(data(2000, 8));
    }
    check("builder create: a record, and it verifies", Arrays.equals(data(2000, 8), readAll(fs, b)) && plain.exists(sc(b)));
    check("a rename keeps catching a changed file", fs.rename(b, new Path(dir, "built2")) && tryChange(plain, fs, new Path(dir, "built2")));
    try (FSDataInputStream in = fs.open(f)) {
      byte[] buf = new byte[100];
      in.readFully(buf);
      in.unbuffer();
      byte[] more = new byte[100];
      in.readFully(more);
      check("unbuffer in the middle of a read: the reading goes on with the right bytes", Arrays.equals(more, Arrays.copyOfRange(data(500, 7), 100, 200)));
    }
    fs.delete(dir, true);
  }

  static boolean tryChange(FileSystem plain, FileSystem fs, Path f) throws IOException {
    byte[] d = readAll(fs, f);
    byte[] c = d.clone();
    c[10] ^= 1;
    put(plain, f, c);
    boolean refused = tryRead(fs, f) == null;
    put(plain, f, d);
    return refused;
  }

  // ------------------------------------------------------------------ 3. who may sign

  static void trustChecks(Configuration conf, Path base, FileSystem plain) throws Exception {
    FileSystem fs = wrapper(conf);
    Path dir = new Path(base, "trust");
    fs.mkdirs(dir);
    Path f = new Path(dir, "f");
    byte[] d = data(45000, 31);
    put(fs, f, d);
    byte[] genuine = readAll(plain, sc(f));
    Records.FileRecord g = Records.decodeFile(genuine);
    check("the record names this node's FLEET- key", g.keyId.equals(FleetKeys.current().signingKeyId()) && g.keyId.startsWith("FLEET-"));
    check("the folder identity is signed with the same key", identityOf(plain, dir).keyId.equals(g.keyId));
    byte[] fromNode1 = SIG1.encodeFile(g.chunkSize, g.length, g.hashes, g.folderId, g.name);
    put(plain, sc(f), fromNode1);
    check("a record signed by ANOTHER NODE of the fleet is accepted (it is in fleet.tsv)", Arrays.equals(d, readAll(fs, f)));
    byte[] fromOutsider = OUTSIDER.encodeFile(g.chunkSize, g.length, g.hashes, g.folderId, g.name);
    put(plain, sc(f), fromOutsider);
    check("attack: the record re-signed by a valid P-256 key that is NOT in fleet.tsv (right folder, name, content): the read FAILS, not trusted here", tryRead(fs, f) == null && lastError.contains("not trusted here"));
    byte[] flipped = genuine.clone();
    flipped[flipped.length - 4] ^= 1;
    put(plain, sc(f), flipped);
    check("attack: one bit of the signature flipped: the read FAILS, the signature does not verify", tryRead(fs, f) == null && lastError.contains("does not verify"));
    byte[][] other = g.hashes.clone();
    other[1] = Records.sha256("x".getBytes());
    put(plain, sc(f), Records.encodeFile(g.chunkSize, g.length, other, g.folderId, g.name, g.keyId, g.signature));
    check("attack: one chunk hash replaced, the old signature kept: the read FAILS", tryRead(fs, f) == null && lastError.contains("does not verify"));
    byte[] unsigned = Arrays.copyOf(genuine, genuine.length);
    put(plain, sc(f), unsigned);
    put(plain, f, d);
    put(plain, sc(f), genuine);
    check("undone: the file reads again", Arrays.equals(d, readAll(fs, f)));
    put(plain, f, data(45000, 32));
    put(plain, sc(f), OUTSIDER.encodeFile(g.chunkSize, 45000, refHashes(data(45000, 32), 16384), g.folderId, g.name));
    check("attack: a file AND its record rewritten together by an outsider's key: the read FAILS (a signature is what stops this)", tryRead(fs, f) == null && lastError.contains("not trusted here"));
    put(plain, f, d);
    put(plain, sc(f), genuine);
    fs.delete(dir, true);
  }

  /** An outsider (a valid key in no real fleet.tsv) as the WRITER: what it can and cannot do, and what the fleet then does with its files. */
  static void outsiderWriterChecks(Configuration conf, Path base, FileSystem plain) throws Exception {
    FileSystem fs = wrapper(conf);
    Path fleetDir = new Path(base, "ofleet");
    fs.mkdirs(fleetDir);
    Path ownTop = new Path("hdfs://fake:9000/outsider-top");
    String denied = null;
    boolean ownOk;
    FleetKeys.useDirForTesting(TestFleet.outsider());
    try {
      FileSystem fo = wrapper(conf);
      try {
        put(fo, new Path(fleetDir, "x"), data(10, 1));
      } catch (IOException e) {
        denied = e.getMessage();
      }
      put(fo, new Path(ownTop, "evil.bin"), data(5000, 2));
      ownOk = Arrays.equals(data(5000, 2), readAll(fo, new Path(ownTop, "evil.bin")));
    } finally {
      FleetKeys.useDirForTesting(FLEET[0]);
    }
    check("an outsider cannot write into a folder that the fleet made: the folder's identity is signed by a fleet key that it does not trust", denied != null && denied.contains("not trusted here"));
    check("an outsider can make its own new top-level folder (its parent is the root) and write there, and it reads back under its own wrapper", ownOk);
    check("the fleet's wrapper refuses to read the outsider's file: not trusted here", tryRead(fs, new Path(ownTop, "evil.bin")) == null && lastError.contains("not trusted here"));
    check("... and refuses to write into the outsider's folder too", throwsIo(() -> {
      put(fs, new Path(ownTop, "mine.bin"), data(10, 3));
      return null;
    }));
    fs.delete(fleetDir, true);
    plain.delete(ownTop, true);
  }

  // ------------------------------------------------------------------ 4. files and folders move only through the wrapper

  static void bindingChecks(Configuration conf, Path base, FileSystem plain) throws Exception {
    FileSystem fs = wrapper(conf);
    Path top = new Path(base, "bind");
    Path seg = new Path(top, "seg1");
    fs.mkdirs(seg);
    Records.FolderRecord topId = identityOf(plain, top), segId = identityOf(plain, seg);
    check("making a folder through the wrapper gives it a signed identity file, and the child's names its parent's id and its own name",
        topId.name.equals("bind") && segId.name.equals("seg1") && Arrays.equals(segId.parentId, topId.folderId));
    check("identity files are hidden from listings made through the wrapper, and visible to the plain client", fs.listStatus(top).length == 1 && plain.listStatus(top).length == 2);
    byte[] before = readAll(plain, idf(top));
    fs.mkdirs(top);
    check("making a folder that exists does not change its identity", Arrays.equals(before, readAll(plain, idf(top))));
    Path f = new Path(seg, "a.bin");
    byte[] d = data(45000, 1);
    put(fs, f, d);
    Records.FileRecord r = recordOf(plain, f);
    check("the record of a file names the folder's id and the file's name", Arrays.equals(r.folderId, segId.folderId) && r.name.equals("a.bin"));
    Path deep = new Path(top, "x/y/z/f.bin");
    put(fs, deep, data(100, 2));
    check("creating a file in folders that do not exist makes each folder with an identity (the parent id chain)",
        Arrays.equals(identityOf(plain, new Path(top, "x/y")).parentId, identityOf(plain, new Path(top, "x")).folderId) && Arrays.equals(identityOf(plain, new Path(top, "x")).parentId, topId.folderId)
        && Arrays.equals(recordOf(plain, deep).folderId, identityOf(plain, new Path(top, "x/y/z")).folderId));
    Path seg2 = new Path(top, "seg2");
    fs.mkdirs(seg2);
    Path moved = new Path(seg2, "moved.bin");
    check("renaming a file into another folder works, and the file reads", fs.rename(f, moved) && Arrays.equals(d, readAll(fs, moved)));
    Records.FileRecord mr = recordOf(plain, moved);
    check("the new record names the new folder's id and the file's new name, with the same hashes, and the old record is gone",
        Arrays.equals(mr.folderId, identityOf(plain, seg2).folderId) && mr.name.equals("moved.bin") && Arrays.deepEquals(mr.hashes, r.hashes) && !plain.exists(sc(f)));
    Path back = new Path(seg, "back.bin");
    fs.rename(moved, back);
    Path renamed = new Path(seg, "renamed.bin");
    check("renaming a file inside its folder signs a new record for the new name", fs.rename(back, renamed) && recordOf(plain, renamed).name.equals("renamed.bin") && Arrays.equals(d, readAll(fs, renamed)));
    byte[] idBefore = readAll(plain, idf(seg));
    byte[] recInside = readAll(plain, sc(renamed));
    Path seg3 = new Path(top, "seg3");
    check("renaming a folder works, and the files inside still read", fs.rename(seg, seg3) && Arrays.equals(d, readAll(fs, new Path(seg3, "renamed.bin"))));
    Records.FolderRecord after = identityOf(plain, seg3);
    check("a folder rename signs only the folder's own identity: same id, new name, the records inside byte for byte unchanged",
        Arrays.equals(after.folderId, segId.folderId) && after.name.equals("seg3") && Arrays.equals(recInside, readAll(plain, sc(new Path(seg3, "renamed.bin")))) && !Arrays.equals(idBefore, readAll(plain, idf(seg3))));
    Path newParent = new Path(top, "parent2");
    fs.mkdirs(newParent);
    Path under = new Path(newParent, "seg3");
    check("renaming a folder under another parent re-signs it with the new parent's id, and its files read", fs.rename(seg3, under) && Arrays.equals(identityOf(plain, under).parentId, identityOf(plain, newParent).folderId) && Arrays.equals(d, readAll(fs, new Path(under, "renamed.bin"))));
    Path intoFolder = new Path(top, "file2.bin");
    put(fs, intoFolder, data(70, 3));
    check("renaming a file onto a folder moves it into the folder, with a record for the new place", fs.rename(intoFolder, newParent) && Arrays.equals(data(70, 3), readAll(fs, new Path(newParent, "file2.bin"))) && recordOf(plain, new Path(newParent, "file2.bin")).name.equals("file2.bin"));
    fs.delete(top, true);

    Path root = new Path(base, "attacks");
    Path fa = new Path(root, "a"), fb = new Path(root, "b");
    fs.mkdirs(fa);
    fs.mkdirs(fb);
    byte[] da = data(20000, 11), db = data(20000, 12);
    put(fs, new Path(fa, "same.bin"), da);
    put(fs, new Path(fb, "same.bin"), db);
    check("two honest same-named files in two folders both read", Arrays.equals(da, readAll(fs, new Path(fa, "same.bin"))) && Arrays.equals(db, readAll(fs, new Path(fb, "same.bin"))));
    byte[] ra = readAll(plain, sc(new Path(fa, "same.bin"))), rb = readAll(plain, sc(new Path(fb, "same.bin")));
    put(plain, new Path(fa, "same.bin"), db);
    put(plain, sc(new Path(fa, "same.bin")), rb);
    put(plain, new Path(fb, "same.bin"), da);
    put(plain, sc(new Path(fb, "same.bin")), ra);
    check("attack: swapping two same-named files (with their records) between folders: both reads fail", tryRead(fs, new Path(fa, "same.bin")) == null && tryRead(fs, new Path(fb, "same.bin")) == null);
    put(plain, new Path(fa, "same.bin"), da);
    put(plain, sc(new Path(fa, "same.bin")), ra);
    put(plain, new Path(fb, "same.bin"), db);
    put(plain, sc(new Path(fb, "same.bin")), rb);
    check("undone: both read again", Arrays.equals(da, readAll(fs, new Path(fa, "same.bin"))) && Arrays.equals(db, readAll(fs, new Path(fb, "same.bin"))));
    plain.rename(new Path(fa, "same.bin"), new Path(fb, "stolen.bin"));
    plain.rename(sc(new Path(fa, "same.bin")), sc(new Path(fb, "stolen.bin")));
    check("attack: a signed file and its record moved into another folder, under another name, behind the back: the read FAILS", tryRead(fs, new Path(fb, "stolen.bin")) == null);
    plain.rename(new Path(fb, "stolen.bin"), new Path(fa, "same.bin"));
    plain.rename(sc(new Path(fb, "stolen.bin")), sc(new Path(fa, "same.bin")));
    plain.rename(new Path(fa, "same.bin"), new Path(fa, "other.bin"));
    plain.rename(sc(new Path(fa, "same.bin")), sc(new Path(fa, "other.bin")));
    check("attack: renaming a signed file and its record behind the back, in the same folder: the read FAILS (the name is bound)", tryRead(fs, new Path(fa, "other.bin")) == null);
    plain.rename(new Path(fa, "other.bin"), new Path(fa, "same.bin"));
    plain.rename(sc(new Path(fa, "other.bin")), sc(new Path(fa, "same.bin")));
    Path copyDir = new Path(root, "copy-of-a");
    org.apache.hadoop.fs.FileUtil.copy(plain, fa, plain, copyDir, false, true, conf);
    check("attack: copying a whole folder elsewhere (with identity and records): its files FAIL the read (the identity belongs to the other folder name)", tryRead(fs, new Path(copyDir, "same.bin")) == null);
    put(plain, new Path(fa, "unsigned.bin"), data(100, 13));
    check("attack: adding an unsigned file with no record: the read FAILS", tryRead(fs, new Path(fa, "unsigned.bin")) == null && lastError.contains("no record"));
    plain.delete(new Path(fa, "unsigned.bin"), false);
    byte[] idA = readAll(plain, idf(fa)), idB = readAll(plain, idf(fb));
    put(plain, idf(fa), idB);
    check("attack: putting the identity of another folder into this folder: the read FAILS", tryRead(fs, new Path(fa, "same.bin")) == null);
    put(plain, idf(fa), idA);
    check("restored, it reads again", Arrays.equals(da, readAll(fs, new Path(fa, "same.bin"))));
    plain.delete(idf(fa), false);
    check("attack: deleting the identity file behind the back: the read FAILS (the folder has no identity)", tryRead(fs, new Path(fa, "same.bin")) == null && lastError.contains("no identity"));
    Records.FolderRecord ida = Records.decodeFolder(idA);
    put(plain, idf(fa), OUTSIDER.encodeFolder(ida.folderId, ida.name, ida.parentId));
    check("attack: an identity signed with an outsider's key: the read FAILS", tryRead(fs, new Path(fa, "same.bin")) == null && lastError.contains("not trusted here"));
    put(plain, idf(fa), idA);
    check("restored again, it reads", Arrays.equals(da, readAll(fs, new Path(fa, "same.bin"))));
    plain.rename(fa, new Path(root, "a-renamed"));
    check("attack: renaming a folder behind the back: the read FAILS (the identity names another folder name)", tryRead(fs, new Path(root, "a-renamed/same.bin")) == null);
    check("the wrapper does not sign a folder that was moved behind its back: its rename is refused", throwsIo(() -> fs.rename(new Path(root, "a-renamed"), new Path(root, "a-final"))));
    plain.rename(new Path(root, "a-renamed"), fa);
    byte[] forged = OUTSIDER.encodeFile(Records.decodeFile(ra).chunkSize, 20000, refHashes(da, 16384), identityOf(plain, fa).folderId, "same.bin");
    put(plain, sc(new Path(fa, "same.bin")), forged);
    check("a forged record is not signed again by a rename (the old record is checked first): the rename is refused", throwsIo(() -> fs.rename(new Path(fa, "same.bin"), new Path(fa, "new.bin"))));
    put(plain, sc(new Path(fa, "same.bin")), ra);
    Path foreign = new Path(root, "fa-copy-under-b/a");
    fs.mkdirs(foreign.getParent());
    org.apache.hadoop.fs.FileUtil.copy(plain, fa, plain, foreign, false, true, conf);
    check("attack: copying a folder under another parent with the same name: the read FAILS (its identity points to another parent)", tryRead(fs, new Path(foreign, "same.bin")) == null && lastError.contains("another parent"));
    check("the identity file's name cannot be created, renamed to or deleted through the wrapper", throwsIo(() -> {
      fs.create(idf(fb)).close();
      return null;
    }) && throwsIo(() -> fs.rename(new Path(fb, "same.bin"), idf(fb))) && throwsIo(() -> fs.delete(idf(fb), false)));
    Path adopt = new Path(root, "made-by-plain/inner");
    plain.mkdirs(adopt);
    put(fs, new Path(adopt, "w.bin"), data(100, 14));
    check("writing into folders that the plain client made adopts them: each gets an identity, the chain is closed up to the root, and the file reads",
        Arrays.equals(data(100, 14), readAll(fs, new Path(adopt, "w.bin"))) && Arrays.equals(identityOf(plain, adopt).parentId, identityOf(plain, adopt.getParent()).folderId));
    check("deleting a file leaves its folder's identity; deleting a folder removes it with its identity and records", fs.delete(new Path(adopt, "w.bin"), false) && plain.exists(idf(adopt)) && fs.delete(adopt.getParent(), true) && !plain.exists(adopt.getParent()));
    fs.delete(root, true);
  }

  // ------------------------------------------------------------------ 5. the root has a fixed id (F3.4)

  static void rootChecks(Configuration conf, Path base, FileSystem plain) throws Exception {
    FileSystem fs = wrapper(conf);
    Path atRoot = new Path("hdfs://fake:9000/rootfile.bin");
    byte[] d = data(33000, 41);
    put(fs, atRoot, d);
    Records.FileRecord r = recordOf(plain, atRoot);
    check("a file directly under the root is bound: its record names the fixed all-zero root id, and it reads", Arrays.equals(r.folderId, new byte[32]) && Arrays.equals(d, readAll(fs, atRoot)));
    check("the root has no identity file", !plain.exists(new Path("hdfs://fake:9000/" + Records.FOLDER_FILE)));
    Path topFolder = new Path("hdfs://fake:9000/topfolder");
    fs.mkdirs(topFolder);
    check("a folder directly under the root names the all-zero parent id", Arrays.equals(identityOf(plain, topFolder).parentId, new byte[32]));
    put(plain, atRoot, data(33000, 42));
    check("a changed file under the root fails at its chunk", tryRead(fs, atRoot) == null && lastError.contains("chunk"));
    put(plain, atRoot, d);
    Path other = new Path("hdfs://fake:9000/topfolder/rootfile.bin");
    plain.rename(atRoot, other);
    plain.rename(sc(atRoot), sc(other));
    check("attack: a file of the root moved into a folder with its record: the read FAILS (the record is for the root)", tryRead(fs, other) == null);
    plain.rename(other, atRoot);
    plain.rename(sc(other), sc(atRoot));
    Path nest = new Path("hdfs://fake:9000/nest/inner/deeper");
    fs.mkdirs(nest);
    Path nf = new Path(nest, "n.bin");
    put(fs, nf, data(10, 43));
    check("the nested-rename case: moving the outer folder keeps the inner chain valid, and the file reads", fs.rename(new Path("hdfs://fake:9000/nest"), new Path("hdfs://fake:9000/topfolder/nest")) && Arrays.equals(data(10, 43), readAll(fs, new Path("hdfs://fake:9000/topfolder/nest/inner/deeper/n.bin"))));
    Path nid = new Path("hdfs://fake:9000/topfolder/nest");
    check("... and the moved folder now has the topfolder as its parent", Arrays.equals(identityOf(plain, nid).parentId, identityOf(plain, topFolder).folderId));
    check("moving a top folder into the root's other place (rename to the root level) gives it the all-zero parent id again", fs.rename(nid, new Path("hdfs://fake:9000/nest2")) && Arrays.equals(identityOf(plain, new Path("hdfs://fake:9000/nest2")).parentId, new byte[32]) && Arrays.equals(data(10, 43), readAll(fs, new Path("hdfs://fake:9000/nest2/inner/deeper/n.bin"))));
    fs.delete(new Path("hdfs://fake:9000/nest2"), true);
    fs.delete(topFolder, true);
    fs.delete(atRoot, false);
  }

  // ------------------------------------------------------------------ 6. what is refused

  static void refusalChecks(Configuration conf, Path base, FileSystem plain) throws Exception {
    FileSystem fs = wrapper(conf);
    Path dir = new Path(base, "refusals");
    fs.mkdirs(dir);
    Path f = new Path(dir, "f"), g = new Path(dir, "g");
    byte[] d = data(3000, 21);
    put(fs, f, d);
    put(fs, g, data(100, 22));
    check("append is refused, also the builder form", throwsIo(() -> fs.append(f)) && throwsIo(() -> fs.appendFile(f).build()));
    check("concat is refused", throwsUnsupported(() -> {
      fs.concat(f, new Path[] {g});
      return null;
    }));
    check("truncate is refused, also through FileContext", throwsUnsupported(() -> fs.truncate(f, 10)) && throwsUnsupported(() -> FileContext.getFileContext(conf).truncate(f, 10)));
    check("after the refused calls the file is unchanged and still has its record", plain.exists(sc(f)) && Arrays.equals(d, readAll(fs, f)));
    check("F3.7: the capability probe says no to append, concat and truncate",
        !fs.hasPathCapability(f, CommonPathCapabilities.FS_APPEND) && !fs.hasPathCapability(f, CommonPathCapabilities.FS_CONCAT) && !fs.hasPathCapability(f, CommonPathCapabilities.FS_TRUNCATE));
    check("F3.7: and it still answers other questions (an unknown capability is false, a known one is passed on)", !fs.hasPathCapability(f, "fs.capability.no.such.thing") && fs.hasPathCapability(f, CommonPathCapabilities.FS_CHECKSUMS) == plain.hasPathCapability(f, CommonPathCapabilities.FS_CHECKSUMS));
    System.out.println("      (the plain client says append: " + plain.hasPathCapability(f, CommonPathCapabilities.FS_APPEND) + ", the wrapper says false)");
    Path nr = new Path(dir, "no-record");
    put(plain, nr, data(500, 23));
    check("a file with no record cannot be read", throwsIo(() -> readAll(fs, nr)));
    check("a status question about a file with no record is answered (it exposes no content)", fs.getFileStatus(nr).getLen() == 500);
    Path writing = new Path(dir, "being-written");
    try (FSDataOutputStream o = fs.create(writing)) {
      o.write(data(100, 25));
      o.hflush();
      check("a file that is still being written (no record yet) can be asked about", fs.getFileStatus(writing) != null);
    }
    org.apache.hadoop.fs.PathHandle handle = () -> java.nio.ByteBuffer.allocate(0);
    check("opening by path handle is refused, also its builder and making a handle", throwsUnsupported(() -> fs.open(handle, 4096)) && throwsUnsupported(() -> fs.openFile(handle)) && throwsUnsupported(() -> fs.getPathHandle(fs.getFileStatus(f))));
    check("the plain file system under the wrapper is not handed out, and there are no child file systems", throwsUnsupported(() -> ((org.apache.hadoop.fs.FilterFileSystem) fs).getRawFileSystem()) && (fs.getChildFileSystems() == null || fs.getChildFileSystems().length == 0));
    check("staging an output on the local disk is refused (start and complete)", throwsUnsupported(() -> fs.startLocalOutput(f, new Path("/tmp/attested-local-out"))) && throwsUnsupported(() -> {
      fs.completeLocalOutput(f, new Path("/tmp/attested-local-out"));
      return null;
    }));
    File local = Files.createTempDirectory("attested-local").toFile();
    Path lf = new Path(new File(local, "up.bin").toURI());
    Files.write(new File(local, "up.bin").toPath(), data(5000, 27));
    fs.copyFromLocalFile(false, true, lf, new Path(dir, "uploaded"));
    check("copyFromLocalFile goes through the wrapper: the uploaded file has a record and verifies", plain.exists(sc(new Path(dir, "uploaded"))) && Arrays.equals(data(5000, 27), readAll(fs, new Path(dir, "uploaded"))));
    deleteTree(local);
    fs.delete(dir, true);
  }

  // ------------------------------------------------------------------ 7. a copy to local disk is checked too (F3.5)

  static void copyToLocalChecks(Configuration conf, Path base, FileSystem plain) throws Exception {
    FileSystem fs = wrapper(conf);
    Path dir = new Path(base, "tolocal");
    fs.mkdirs(dir);
    Path f = new Path(dir, "c.bin");
    byte[] d = data(70000, 51);
    put(fs, f, d);
    File out = Files.createTempDirectory("attested-out").toFile();
    fs.copyToLocalFile(false, f, new Path(new File(out, "good.bin").toURI()));
    check("a copy of an untouched file to local disk is the file", Arrays.equals(d, Files.readAllBytes(new File(out, "good.bin").toPath())));
    byte[] changed = d.clone();
    changed[2 * 16384 + 9] ^= 1;
    put(plain, f, changed);
    check("a copy of a CHANGED file to local disk FAILS (copyToLocalFile used to read the plain HDFS and bypass the check)", throwsChecksum(() -> {
      fs.copyToLocalFile(false, f, new Path(new File(out, "bad1.bin").toURI()));
      return null;
    }));
    check("the raw-local variant fails too", throwsChecksum(() -> {
      fs.copyToLocalFile(false, f, new Path(new File(out, "bad2.bin").toURI()), true);
      return null;
    }));
    check("moveToLocalFile (copy and delete) fails too, and the source is NOT deleted", throwsChecksum(() -> {
      fs.moveToLocalFile(f, new Path(new File(out, "bad3.bin").toURI()));
      return null;
    }) && plain.exists(f));
    check("the 2-argument copyToLocalFile fails too", throwsChecksum(() -> {
      fs.copyToLocalFile(f, new Path(new File(out, "bad4.bin").toURI()));
      return null;
    }));
    put(plain, f, d);
    fs.copyToLocalFile(true, f, new Path(new File(out, "moved.bin").toURI()));
    check("with the bytes put back, copy-and-delete works: the file arrives and the source and its record are gone", Arrays.equals(d, Files.readAllBytes(new File(out, "moved.bin").toPath())) && !plain.exists(f) && !plain.exists(sc(f)));
    deleteTree(out);
    fs.delete(dir, true);
  }

  // ------------------------------------------------------------------ 8. a container sees what the client sees

  /**
   * The first fleet run failed because a MapReduce container builds its configuration from job.xml, and the wrapper then ignored its settings.
   * The wrapper has no settings now: whatever the configuration says, even a hostile job.xml, nothing is switched off.
   */
  static void containerChecks(Configuration conf, Path base, FileSystem plain) throws Exception {
    Path dir = new Path(base, "container");
    wrapper(conf).mkdirs(dir);
    Path f = new Path(dir, "f");
    byte[] d = data(40000, 61);
    put(wrapper(conf), f, d);
    java.nio.file.Path tmp = Files.createTempDirectory("attested-job");
    File jobXml = new File(tmp.toFile(), "job.xml");
    StringBuilder x = new StringBuilder("<configuration>");
    for (String k : new String[] {"attested.verify.reads", "attested.verify.missing", "attested.hash.enabled", "attested.signature.required", "attested.signature.enabled",
        "attested.signature.allow.test.keys", "attested.folder.binding.enabled", "attested.folder.binding.required", "attested.metadata.check", "attested.keys.provider"}) {
      x.append("<property><name>").append(k).append("</name><value>").append(k.endsWith("missing") || k.endsWith("provider") ? "allow" : "false").append("</value></property>");
    }
    Files.write(jobXml.toPath(), x.append("</configuration>").toString().getBytes(StandardCharsets.UTF_8));
    Configuration job = new Configuration(conf);
    job.addResource(new Path(jobXml.toURI()));
    FileSystem fsJob = wrapper(job);
    check("a configuration that comes from a job.xml with every old setting turned off reads a good file", Arrays.equals(d, readAll(fsJob, f)));
    byte[] changed = d.clone();
    changed[30000] ^= 1;
    put(plain, f, changed);
    check("... and still refuses a changed file (verification cannot be switched off)", throwsChecksum(() -> readAll(fsJob, f)));
    put(plain, f, d);
    Path nr = new Path(dir, "nr");
    put(plain, nr, data(100, 62));
    check("... and still refuses a file without a record (missing=allow does nothing)", throwsIo(() -> readAll(fsJob, nr)));
    byte[] genuine = readAll(plain, sc(f));
    Records.FileRecord g = Records.decodeFile(genuine);
    put(plain, sc(f), OUTSIDER.encodeFile(g.chunkSize, g.length, g.hashes, g.folderId, g.name));
    check("... and still refuses a record of an outsider's key (the keys cannot be changed by a job)", tryRead(fsJob, f) == null && lastError.contains("not trusted here"));
    put(plain, sc(f), genuine);
    Configuration empty = new Configuration(false);
    empty.set("fs.hdfs.impl", FakeWrapper.class.getName());
    check("a completely empty configuration behaves the same (a container needs nothing but fs.hdfs.impl)", Arrays.equals(d, readAll(FileSystem.newInstance(URI.create("hdfs://fake:9000"), empty), f)));
    deleteTree(tmp.toFile());
    wrapper(conf).delete(dir, true);
  }

  // ------------------------------------------------------------------ 9. the identity cache, and writers that race

  static void cacheChecks(Configuration conf, Path base, FileSystem plain) throws Exception {
    AttestedFolders.ttlNanos = 10L * 1000 * 1000 * 1000;
    try {
      FileSystem fs = wrapper(conf);
      Path dir = new Path(base, "cached/a");
      Path f = new Path(dir, "f");
      byte[] d = data(30000, 71);
      put(fs, f, d);
      Path g = new Path(dir, "g");
      check("with the identity cache on (10 s), creating, reading, renaming a file and renaming a folder all work",
          Arrays.equals(d, readAll(fs, f)) && fs.rename(f, g) && Arrays.equals(d, readAll(fs, g)) && fs.rename(dir, new Path(base, "cached/b")) && Arrays.equals(d, readAll(fs, new Path(base, "cached/b/g"))));
      fs.delete(new Path(base, "cached"), true);
    } finally {
      AttestedFolders.ttlNanos = 0;
    }
  }

  static void racingWriters(Configuration conf, Path base) throws Exception {
    final int writers = 8, rounds = 5;
    boolean all = true;
    int failed = 0;
    for (int r = 0; r < rounds; r++) {
      final Path dir = new Path(base, "race" + r + "/new/folders/deeper");
      final List<Throwable> errors = new ArrayList<>();
      List<Thread> ts = new ArrayList<>();
      final java.util.concurrent.CountDownLatch go = new java.util.concurrent.CountDownLatch(1);
      for (int i = 0; i < writers; i++) {
        final int n = i;
        Thread t = new Thread(() -> {
          try {
            FileSystem fs = wrapper(conf);
            go.await();
            put(fs, new Path(dir, "w" + n), data(5000, 80 + n));
          } catch (Throwable e) {
            synchronized (errors) {
              errors.add(e);
            }
          }
        });
        ts.add(t);
        t.start();
      }
      go.countDown();
      for (Thread t : ts) {
        t.join();
      }
      FileSystem fs = wrapper(conf);
      boolean ok = errors.isEmpty();
      for (int i = 0; i < writers && ok; i++) {
        try {
          ok &= Arrays.equals(data(5000, 80 + i), readAll(fs, new Path(dir, "w" + i)));
        } catch (IOException e) {
          ok = false;
          errors.add(e);
        }
      }
      if (!ok) {
        failed++;
        System.out.println("      round " + r + ": " + (errors.isEmpty() ? "a file does not read" : errors.get(0)));
      }
      all &= ok;
      fs.delete(new Path(base, "race" + r), true);
    }
    check(writers + " writers racing for the same new folders, " + rounds + " rounds on fresh trees: no error, one identity wins in each folder, every file reads (" + failed + " rounds failed)", all);
  }

  // ------------------------------------------------------------------ 10. FileContext

  static void fileContext(Configuration conf, Path dir) throws Exception {
    FileContext fc = FileContext.getFileContext(dir.toUri(), conf);
    check("fs.AbstractFileSystem.hdfs.impl puts the adapter behind FileContext", fc.getDefaultFileSystem() instanceof AttestedHdfs);
    Path d = new Path(dir, "sub");
    fc.mkdir(d, FsPermission.getDirDefault(), true);
    Path f = new Path(d, "file");
    byte[] body = "via FileContext".getBytes(StandardCharsets.UTF_8);
    try (FSDataOutputStream out = fc.create(f, EnumSet.of(CreateFlag.CREATE, CreateFlag.OVERWRITE))) {
      out.write(body);
    }
    FakeHdfs plain = new FakeHdfs();
    plain.initialize(URI.create("hdfs://fake:9000"), new Configuration(false));
    check("FileContext: the file created through it has a record with the right hashes", Arrays.deepEquals(refHashes(body, 16384), recordOf(plain, f).hashes));
    Path g = new Path(d, "renamed");
    fc.rename(f, g, Options.Rename.NONE);
    check("FileContext: rename worked, and the record went with it", !fc.util().exists(f) && fc.util().exists(g) && recordOf(plain, g).name.equals("renamed"));
    try (FSDataInputStream in = fc.open(g)) {
      byte[] buf = new byte[body.length];
      in.readFully(buf);
      eq("FileContext: read back", "via FileContext", new String(buf, StandardCharsets.UTF_8));
    }
    byte[] changed = body.clone();
    changed[2] ^= 1;
    put(plain, g, changed);
    check("FileContext: a changed file fails the read", throwsIo(() -> {
      try (FSDataInputStream in = fc.open(g)) {
        in.read(new byte[body.length]);
      }
      return null;
    }));
    check("FileContext: delete recursive", fc.delete(dir, true));
  }

  // ------------------------------------------------------------------ MapReduce through the wrapper

  public static class TokMapper extends Mapper<LongWritable, Text, Text, IntWritable> {
    private final static IntWritable ONE = new IntWritable(1);
    private final Text word = new Text();

    @Override
    protected void map(LongWritable key, Text value, Context context) throws IOException, InterruptedException {
      StringTokenizer t = new StringTokenizer(value.toString());
      while (t.hasMoreTokens()) {
        word.set(t.nextToken());
        context.write(word, ONE);
      }
    }
  }

  public static class SumReducer extends Reducer<Text, IntWritable, Text, IntWritable> {
    @Override
    protected void reduce(Text key, Iterable<IntWritable> values, Context context) throws IOException, InterruptedException {
      int sum = 0;
      for (IntWritable v : values) {
        sum += v.get();
      }
      context.write(key, new IntWritable(sum));
    }
  }

  static boolean runWordCount(Configuration conf, Path in, Path out) throws Exception {
    Job job = Job.getInstance(conf, "attested-wordcount");
    job.setJarByClass(AttestedFsSmoke.class);
    job.setMapperClass(TokMapper.class);
    job.setCombinerClass(SumReducer.class);
    job.setReducerClass(SumReducer.class);
    job.setOutputKeyClass(Text.class);
    job.setOutputValueClass(IntWritable.class);
    FileInputFormat.addInputPath(job, in);
    FileOutputFormat.setOutputPath(job, out);
    try {
      return job.waitForCompletion(false);
    } catch (IOException e) {
      return false;
    }
  }

  static void runMr() throws Exception {
    java.nio.file.Path tmp = Files.createTempDirectory("attested-mr");
    Configuration conf = fakeConf();
    conf.set("mapreduce.framework.name", "local");
    conf.set("hadoop.tmp.dir", tmp + "/hadoop-tmp");
    conf.set("mapreduce.jobtracker.staging.root.dir", "/mr-staging");
    Path in = new Path("hdfs://fake:9000/mr/in");
    Path out = new Path("hdfs://fake:9000/mr/out");
    FileSystem fs = in.getFileSystem(conf);
    FakeHdfs plain = new FakeHdfs();
    plain.initialize(URI.create("hdfs://fake:9000"), new Configuration(false));
    check("the job's file system is the wrapper", fs instanceof AttestedHdfsFileSystem);
    fs.mkdirs(in);
    String[] lines = {"to be or not to be", "that is the question", "to be is to do"};
    TreeMap<String, Integer> expected = new TreeMap<>();
    for (int i = 0; i < 2; i++) {
      try (FSDataOutputStream o = fs.create(new Path(in, "part" + i + ".txt"))) {
        for (String l : lines) {
          o.write((l + "\n").getBytes(StandardCharsets.UTF_8));
          for (String w : l.split(" ")) {
            expected.merge(w, 1, Integer::sum);
          }
        }
      }
    }
    check("a MapReduce job reading and writing hdfs:// through the wrapper completes (the local runner: client, AppMaster logic and tasks in one JVM)", runWordCount(conf, in, out));
    check("_SUCCESS marker exists, and no _temporary folder is left behind", fs.exists(new Path(out, "_SUCCESS")) && !fs.exists(new Path(out, "_temporary")));
    TreeMap<String, Integer> got = new TreeMap<>();
    for (FileStatus s : fs.listStatus(out)) {
      if (s.getPath().getName().startsWith("part-")) {
        for (String line : new String(readAll(fs, s.getPath()), StandardCharsets.UTF_8).split("\n")) {
          if (!line.isEmpty()) {
            String[] kv = line.split("\t");
            got.put(kv[0], Integer.parseInt(kv[1]));
          }
        }
      }
    }
    eq("word counts equal the expected counts", expected, got);
    int files = 0, bound = 0;
    for (Path dir : new Path[] {in, out}) {
      byte[] fid = identityOf(plain, dir).folderId;
      for (FileStatus s : plain.listStatus(dir)) {
        String n = s.getPath().getName();
        if (s.isDirectory() || AttestedSidecar.isCompanion(s.getPath()) || n.startsWith(".")) {
          continue;
        }
        files++;
        Records.FileRecord r = recordOf(plain, s.getPath());
        if (Arrays.equals(r.folderId, fid) && r.name.equals(n)) {
          bound++;
        }
      }
    }
    check("every file of the job's input and output (" + files + ", with _SUCCESS) has a record bound to its folder and name, after the committer's folders and renames", files >= 4 && files == bound);
    check("the committer's _temporary folder and its identity are gone with the commit", !plain.exists(new Path(out, "_temporary")));
    Path victim = new Path(in, "part0.txt");
    byte[] orig = readAll(plain, victim);
    byte[] changed = orig.clone();
    changed[3] ^= 0x20;
    put(plain, victim, changed);
    check("a job reading a changed input file fails", !runWordCount(conf, in, new Path("hdfs://fake:9000/mr/out2")));
    put(plain, victim, orig);
    check("with the original bytes put back the same job completes again", runWordCount(conf, in, new Path("hdfs://fake:9000/mr/out3")));
    byte[] genuine = readAll(plain, sc(victim));
    Records.FileRecord g = Records.decodeFile(genuine);
    put(plain, sc(victim), OUTSIDER.encodeFile(g.chunkSize, g.length, g.hashes, g.folderId, g.name));
    check("a job reading a file whose record is signed by an outsider's valid key fails (the F2 pass condition, in the job's own JVM)", !runWordCount(conf, in, new Path("hdfs://fake:9000/mr/out4")));
    put(plain, sc(victim), genuine);
    deleteTree(tmp.toFile());
  }
}
