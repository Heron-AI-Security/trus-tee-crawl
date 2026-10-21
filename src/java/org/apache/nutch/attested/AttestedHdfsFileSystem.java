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
import java.io.UncheckedIOException;
import java.net.URI;
import java.util.Arrays;
import java.util.EnumSet;
import java.util.List;
import java.util.Locale;
import java.util.NoSuchElementException;
import java.util.concurrent.CompletableFuture;

import org.apache.hadoop.conf.Configuration;
import org.apache.hadoop.fs.ChecksumException;
import org.apache.hadoop.fs.CommonPathCapabilities;
import org.apache.hadoop.fs.CreateFlag;
import org.apache.hadoop.fs.FSDataInputStream;
import org.apache.hadoop.fs.FSDataOutputStream;
import org.apache.hadoop.fs.FSDataOutputStreamBuilder;
import org.apache.hadoop.fs.FileStatus;
import org.apache.hadoop.fs.FileSystem;
import org.apache.hadoop.fs.FileUtil;
import org.apache.hadoop.fs.FilterFileSystem;
import org.apache.hadoop.fs.FutureDataInputStreamBuilder;
import org.apache.hadoop.fs.LocatedFileStatus;
import org.apache.hadoop.fs.Options.ChecksumOpt;
import org.apache.hadoop.fs.Options.HandleOpt;
import org.apache.hadoop.fs.Options.Rename;
import org.apache.hadoop.fs.Path;
import org.apache.hadoop.fs.PathFilter;
import org.apache.hadoop.fs.PathHandle;
import org.apache.hadoop.fs.RemoteIterator;
import org.apache.hadoop.fs.impl.FutureDataInputStreamBuilderImpl;
import org.apache.hadoop.fs.impl.OpenFileParameters;
import org.apache.hadoop.fs.permission.FsPermission;
import org.apache.hadoop.hdfs.DistributedFileSystem;
import org.apache.hadoop.util.Progressable;

/**
 * The wrapper that stands in for HDFS: Hadoop is told, through <code>fs.hdfs.impl</code>, to use this class for every <code>hdfs://</code>
 * address, and paths stay exactly as they are. Its behavior is FIXED (step F3.1): it has no settings, no modes and no switches, so that a job
 * cannot weaken it and every JVM (a client, an ApplicationMaster, a container) behaves the same.
 *
 * <ul>
 * <li>Every file it creates is hashed in chunks and gets a signed record next to it (see {@link Records}), bound to its folder and its name.</li>
 * <li>Every read is checked against the record: the signature must be a fleet key's ({@link FleetKeys}), the folder chain must be right, and
 * every chunk must match its hash. A file without a record cannot be read.</li>
 * <li>Records and folder identities follow renames, go with deletes, and are hidden from listings.</li>
 * <li>Append, concat, truncate, path handles and local staging are refused, and every way of copying a file to local disk goes through the
 * verifying read.</li>
 * </ul>
 *
 * <p>The real HDFS client is constructed directly in {@link #createInner()}. It must never be looked up by scheme: the lookup would find this
 * wrapper again and loop, and the class refuses to start if the inner file system is another wrapper. {@link AttestedHdfs} is the adapter for
 * <code>FileContext</code>.</p>
 */
public class AttestedHdfsFileSystem extends FilterFileSystem {

  public static final String SCHEME = "hdfs";
  static final int DEFAULT_PORT = 8020;
  /** The size of one hashed chunk in bytes. Fixed. */
  static final int CHUNK_SIZE = 16384;

  private AttestedSignatures signatures;
  private AttestedFolders folders;

  public AttestedHdfsFileSystem() {
    super();
  }

  /** The real HDFS client, constructed directly. Tests replace it with a fake in a subclass; production code does not. */
  protected FileSystem createInner() {
    return new DistributedFileSystem();
  }

  @Override
  public void initialize(URI name, Configuration conf) throws IOException {
    if (name.getScheme() == null || !SCHEME.equalsIgnoreCase(name.getScheme())) {
      throw new IOException("This wrapper only serves hdfs:// addresses, got: " + name);
    }
    this.signatures = new AttestedSignatures(FleetKeys.current());
    FileSystem inner = createInner();
    if (inner == null || inner instanceof AttestedHdfsFileSystem) {
      throw new IOException("The wrapped file system must be the real HDFS client, constructed directly. Looking it up by scheme would find "
          + "this wrapper again and loop.");
    }
    this.fs = inner;
    this.folders = new AttestedFolders(inner, signatures);
    super.initialize(name, conf);
  }

  @Override
  public String getScheme() {
    return SCHEME;
  }

  @Override
  protected int getDefaultPort() {
    return DEFAULT_PORT;
  }

  private Path q(Path p) {
    try {
      return makeQualified(p);
    } catch (RuntimeException e) {
      return p;
    }
  }

  // ------------------------------------------------ records next to files

  /** Wraps a new output stream so that its bytes are hashed and a record is written at close. */
  private FSDataOutputStream hashed(Path f, FSDataOutputStream stream) {
    return new FSDataOutputStream(new HashingOutputStream(stream, q(f).toUri().getPath(), CHUNK_SIZE, this::writeSidecar), null);
  }

  private boolean isPlainFile(Path f) throws IOException {
    try {
      return fs.getFileStatus(f).isFile();
    } catch (FileNotFoundException e) {
      return false;
    }
  }

  private boolean isDir(Path f) throws IOException {
    try {
      return fs.getFileStatus(f).isDirectory();
    } catch (FileNotFoundException e) {
      return false;
    }
  }

  /** The id of the folder a file lives in: the fixed zero id for the root, else the folder's identity (made if it has none). */
  private byte[] folderIdOf(Path parent) throws IOException {
    return AttestedFolders.isRoot(parent) ? Records.ROOT_ID : folders.ensure(parent).folderId;
  }

  /** Stores a finished record next to its file, with the real HDFS client. */
  private void writeSidecar(String filePath, long length, int chunk, byte[][] hashes) throws IOException {
    Path file = new Path(filePath);
    byte[] bytes = signatures.encodeFile(chunk, length, hashes, folderIdOf(file.getParent()), file.getName());
    try (FSDataOutputStream out = fs.create(AttestedSidecar.pathFor(file), true)) {
      out.write(bytes);
    }
  }

  /** The file changed or went away, so its record no longer describes it: remove the record. */
  private void dropSidecar(Path f) throws IOException {
    Path sc = AttestedSidecar.pathFor(f);
    if (fs.exists(sc)) {
      fs.delete(sc, false);
    }
  }

  /** After a file was renamed: clear any old record at the new name (the moved record is written by afterFileMove). */
  private void clearSidecar(Path dst) throws IOException {
    Path to = AttestedSidecar.pathFor(dst);
    if (fs.exists(to)) {
      fs.delete(to, false);
    }
  }

  private ChecksumException refused(Path f, String why) {
    return new ChecksumException("Attested verification failed for " + f + ": " + why, 0);
  }

  /** Wraps a freshly opened stream so that every chunk read is checked against the file's record. A file without a record cannot be read. */
  private FSDataInputStream verified(Path f, FSDataInputStream raw) throws IOException {
    if (AttestedSidecar.isCompanion(f)) {
      return raw;
    }
    Records.FileRecord rec;
    try {
      rec = AttestedSidecar.read(fs, AttestedSidecar.pathFor(f));
    } catch (FileNotFoundException e) {
      raw.close();
      throw new IOException("Attested verification failed for " + f + ": the file has no record");
    } catch (IOException e) {
      raw.close();
      throw refused(f, e.getMessage());
    }
    try {
      signatures.checkFile(rec);
      checkBinding(f, rec);
    } catch (IOException e) {
      raw.close();
      throw refused(f, e.getMessage());
    }
    long len = fs.getFileStatus(f).getLen();
    if (rec.length != len) {
      raw.close();
      throw refused(f, "length is " + len + " in storage but " + rec.length + " in its record");
    }
    return new FSDataInputStream(new VerifyingInputStream(raw, rec, q(f)));
  }

  // ------------------------------------------------------------- folder binding

  /** The folder identity file's name is the wrapper's own: nobody creates, renames or deletes it through the wrapper. */
  private void denyReserved(Path p) throws IOException {
    if (p != null && Records.isFolderFileName(p.getName())) {
      throw new IOException("attested: the name " + Records.FOLDER_FILE + " is reserved for the folder identity and cannot be created, renamed or deleted: " + p);
    }
  }

  /** Before a file is created: its folder (and any missing parent) has an identity. */
  private void prepareParent(Path f, boolean makeParents) throws IOException {
    Path parent = q(f).getParent();
    if (AttestedFolders.isRoot(parent)) {
      return;
    }
    if (makeParents) {
      folders.ensureTree(parent);
    } else if (fs.exists(parent)) {
      folders.ensure(parent);
    }
  }

  /** The record is bound to a folder and a name: both must be the ones this file has now, all the way up to the root. */
  private void checkBinding(Path f, Records.FileRecord d) throws IOException {
    Path parent = f.getParent();
    byte[] id = AttestedFolders.isRoot(parent) ? Records.ROOT_ID : folders.verifyChain(parent);
    if (!Arrays.equals(id, d.folderId)) {
      throw new IOException("the record belongs to another folder than the one this file is in");
    }
    if (!f.getName().equals(d.name)) {
      throw new IOException("the record is for a file named '" + d.name + "', not '" + f.getName() + "'");
    }
  }

  /**
   * Before a file is renamed: the old record, its signature and its binding are checked (a forged record must never be signed again), and the
   * new folder gets its identity. Returns the old record, or null when the file has none (then nothing is moved).
   */
  private Records.FileRecord beforeFileMove(Path src, Path target) throws IOException {
    Records.FileRecord rec;
    try {
      rec = AttestedSidecar.read(fs, AttestedSidecar.pathFor(src));
    } catch (FileNotFoundException e) {
      return null;
    }
    try {
      signatures.checkFile(rec);
      checkBinding(src, rec);
      Path np = target.getParent();
      if (!AttestedFolders.isRoot(np) && fs.exists(np)) {
        folders.ensure(np);
      }
    } catch (IOException e) {
      throw new IOException("Attested rename refused for " + src + ": " + e.getMessage());
    }
    return rec;
  }

  /** After a file was renamed: a new record for the new folder and name, from the old one, with no data read. */
  private void afterFileMove(Path src, Path target, Records.FileRecord moved) throws IOException {
    clearSidecar(target);
    if (moved != null) {
      byte[] bytes = signatures.encodeFile(moved.chunkSize, moved.length, moved.hashes, folderIdOf(q(target).getParent()), target.getName());
      try (FSDataOutputStream out = fs.create(AttestedSidecar.pathFor(target), true)) {
        out.write(bytes);
      }
    }
    dropSidecar(src);
  }

  /** Before a folder with an identity is renamed: its chain is checked, and the new parent has its identity. Null when it has none. */
  private Records.FolderRecord beforeDirMove(Path src, Path target) throws IOException {
    try {
      Records.FolderRecord old = folders.read(src);
      if (old == null) {
        return null;
      }
      folders.verifyChain(src);
      Path np = target.getParent();
      if (!AttestedFolders.isRoot(np) && fs.exists(np)) {
        folders.ensure(np);
      }
      return old;
    } catch (IOException e) {
      throw new IOException("Attested rename refused for the folder " + src + ": " + e.getMessage());
    }
  }

  /** After a folder was renamed: only its own identity file is signed again; the files and folders inside are untouched. */
  private void afterDirMove(Path src, Path target, Records.FolderRecord old) throws IOException {
    folders.forgetTree(src);
    folders.forgetTree(target);
    if (old != null) {
      folders.resign(q(target), old);
    }
  }

  // ------------------------------------------------------------- listings

  private static FileStatus[] withoutSidecars(FileStatus[] all) {
    int keep = 0;
    for (FileStatus s : all) {
      if (!AttestedSidecar.isCompanion(s.getPath())) {
        keep++;
      }
    }
    if (keep == all.length) {
      return all;
    }
    FileStatus[] out = new FileStatus[keep];
    int i = 0;
    for (FileStatus s : all) {
      if (!AttestedSidecar.isCompanion(s.getPath())) {
        out[i++] = s;
      }
    }
    return out;
  }

  private <T extends FileStatus> RemoteIterator<T> hidden(final RemoteIterator<T> it, final PathFilter filter) {
    return new RemoteIterator<T>() {
      private T next;

      private void advance() throws IOException {
        while (next == null && it.hasNext()) {
          T s = it.next();
          if (!AttestedSidecar.isCompanion(s.getPath()) && (filter == null || filter.accept(s.getPath()))) {
            next = s;
          }
        }
      }

      @Override
      public boolean hasNext() throws IOException {
        advance();
        return next != null;
      }

      @Override
      public T next() throws IOException {
        advance();
        if (next == null) {
          throw new NoSuchElementException();
        }
        T r = next;
        next = null;
        return r;
      }
    };
  }

  @Override
  public FileStatus[] listStatus(Path f) throws IOException {
    return withoutSidecars(super.listStatus(f));
  }

  @Override
  public RemoteIterator<FileStatus> listStatusIterator(Path f) throws IOException {
    return hidden(super.listStatusIterator(f), null);
  }

  @Override
  public RemoteIterator<LocatedFileStatus> listLocatedStatus(Path f) throws IOException {
    return hidden(super.listLocatedStatus(f), null);
  }

  @Override
  protected RemoteIterator<LocatedFileStatus> listLocatedStatus(Path f, PathFilter filter) throws IOException {
    return hidden(super.listLocatedStatus(f), filter);
  }

  // ------------------------------------------------------------- reads

  @Override
  public FSDataInputStream open(Path f, int bufferSize) throws IOException {
    return verified(f, super.open(f, bufferSize));
  }

  @Override
  public FutureDataInputStreamBuilder openFile(Path path) throws IOException, UnsupportedOperationException {
    return new FutureDataInputStreamBuilderImpl(this, path) {
      @Override
      public CompletableFuture<FSDataInputStream> build() throws IllegalArgumentException, UnsupportedOperationException, IOException {
        OpenFileParameters params = new OpenFileParameters()
            .withMandatoryKeys(getMandatoryKeys())
            .withOptionalKeys(getOptionalKeys())
            .withOptions(getOptions())
            .withBufferSize(getBufferSize())
            .withStatus(getStatus());
        return AttestedHdfsFileSystem.this.openFileWithOptions(getPath(), params);
      }
    };
  }

  @Override
  protected CompletableFuture<FSDataInputStream> openFileWithOptions(Path path, OpenFileParameters parameters) throws IOException {
    return super.openFileWithOptions(path, parameters).thenApply(raw -> {
      try {
        return verified(path, raw);
      } catch (IOException e) {
        throw new UncheckedIOException(e);
      }
    });
  }

  /** Step F3.5: a copy to local disk reads through THIS file system, so that every chunk is verified (the inherited copy reads the plain HDFS). */
  @Override
  public void copyToLocalFile(boolean delSrc, Path src, Path dst) throws IOException {
    copyToLocalFile(delSrc, src, dst, false);
  }

  @Override
  public void copyToLocalFile(boolean delSrc, Path src, Path dst, boolean useRawLocalFileSystem) throws IOException {
    Configuration conf = getConf();
    FileSystem local = useRawLocalFileSystem ? FileSystem.getLocal(conf).getRawFileSystem() : FileSystem.getLocal(conf);
    FileUtil.copy(this, src, local, dst, delSrc, true, conf);
  }

  /** Step F3.7: append, concat and truncate are refused, and the capability probe says so. */
  @Override
  public boolean hasPathCapability(Path path, String capability) throws IOException {
    switch (capability.toLowerCase(Locale.ENGLISH)) {
    case CommonPathCapabilities.FS_APPEND:
    case CommonPathCapabilities.FS_CONCAT:
    case CommonPathCapabilities.FS_TRUNCATE:
      return false;
    default:
      return super.hasPathCapability(path, capability);
    }
  }

  // ------------------------------------------------------ data changes

  @Override
  public FSDataOutputStream create(Path f, FsPermission permission, boolean overwrite, int bufferSize, short replication, long blockSize,
      Progressable progress) throws IOException {
    denyReserved(f);
    prepareParent(f, true);
    return hashed(f, super.create(f, permission, overwrite, bufferSize, replication, blockSize, progress));
  }

  @Override
  public FSDataOutputStream create(Path f, FsPermission permission, EnumSet<CreateFlag> flags, int bufferSize, short replication,
      long blockSize, Progressable progress, ChecksumOpt checksumOpt) throws IOException {
    denyReserved(f);
    prepareParent(f, true);
    return hashed(f, super.create(f, permission, flags, bufferSize, replication, blockSize, progress, checksumOpt));
  }

  @Override
  @SuppressWarnings("deprecation")
  public FSDataOutputStream createNonRecursive(Path f, FsPermission permission, EnumSet<CreateFlag> flags, int bufferSize,
      short replication, long blockSize, Progressable progress) throws IOException {
    denyReserved(f);
    prepareParent(f, false);
    return hashed(f, super.createNonRecursive(f, permission, flags, bufferSize, replication, blockSize, progress));
  }

  @Override
  protected FSDataOutputStream primitiveCreate(Path f, FsPermission absolutePermission, EnumSet<CreateFlag> flag, int bufferSize,
      short replication, long blockSize, Progressable progress, ChecksumOpt checksumOpt) throws IOException {
    denyReserved(f);
    prepareParent(f, true);
    return hashed(f, super.primitiveCreate(f, absolutePermission, flag, bufferSize, replication, blockSize, progress, checksumOpt));
  }

  @Override
  @SuppressWarnings("rawtypes")
  public FSDataOutputStreamBuilder createFile(Path path) {
    return createDataOutputStreamBuilder(this, path).create().overwrite(true);
  }

  @Override
  public FSDataOutputStream append(Path f, int bufferSize, Progressable progress) throws IOException {
    throw new IOException("attested: append is not supported (the added bytes would not be hashed and the record could not be kept): " + f);
  }

  @Override
  @SuppressWarnings("rawtypes")
  public FSDataOutputStreamBuilder appendFile(Path path) {
    return createDataOutputStreamBuilder(this, path).append();
  }

  @Override
  public void concat(Path f, Path[] psrcs) throws IOException {
    throw new UnsupportedOperationException("attested: concat is not supported (it would join files without a record for the result): " + f);
  }

  @Override
  public boolean truncate(Path f, long newLength) throws IOException {
    throw new UnsupportedOperationException("attested: truncate is not supported (the record would no longer describe the file): " + f);
  }

  @Override
  public FSDataInputStream open(PathHandle fd, int bufferSize) throws IOException {
    throw new UnsupportedOperationException("attested: opening by path handle is not supported (it would skip verification)");
  }

  @Override
  public FutureDataInputStreamBuilder openFile(PathHandle pathHandle) throws IOException, UnsupportedOperationException {
    throw new UnsupportedOperationException("attested: opening by path handle is not supported (it would skip verification)");
  }

  @Override
  protected CompletableFuture<FSDataInputStream> openFileWithOptions(PathHandle pathHandle, OpenFileParameters parameters) throws IOException {
    throw new UnsupportedOperationException("attested: opening by path handle is not supported (it would skip verification)");
  }

  @Override
  protected PathHandle createPathHandle(FileStatus stat, HandleOpt... opts) {
    throw new UnsupportedOperationException("attested: path handles are not supported");
  }

  @Override
  public FileSystem getRawFileSystem() {
    throw new UnsupportedOperationException("attested: the plain file system under this wrapper is not handed out");
  }

  @Override
  public FileSystem[] getChildFileSystems() {
    return null;
  }

  @Override
  public Path startLocalOutput(Path fsOutputFile, Path tmpLocalFile) throws IOException {
    throw new UnsupportedOperationException("attested: staging an output on the local disk is not supported (it would arrive without a record)");
  }

  @Override
  public void completeLocalOutput(Path fsOutputFile, Path tmpLocalFile) throws IOException {
    throw new UnsupportedOperationException("attested: staging an output on the local disk is not supported (it would arrive without a record)");
  }

  @Override
  public void copyFromLocalFile(boolean delSrc, Path src, Path dst) throws IOException {
    FileUtil.copy(FileSystem.getLocal(getConf()), src, this, dst, delSrc, true, getConf());
  }

  @Override
  public void copyFromLocalFile(boolean delSrc, boolean overwrite, Path[] srcs, Path dst) throws IOException {
    FileUtil.copy(FileSystem.getLocal(getConf()), srcs, this, dst, delSrc, overwrite, getConf());
  }

  @Override
  public void copyFromLocalFile(boolean delSrc, boolean overwrite, Path src, Path dst) throws IOException {
    FileUtil.copy(FileSystem.getLocal(getConf()), src, this, dst, delSrc, overwrite, getConf());
  }

  @Override
  public boolean rename(Path src, Path dst) throws IOException {
    denyReserved(src);
    denyReserved(dst);
    boolean file = isPlainFile(src);
    boolean dir = !file && isDir(src);
    Path target = dst;
    if ((file || dir) && isDir(dst)) {
      target = new Path(dst, src.getName());
    }
    Records.FileRecord moved = file ? beforeFileMove(src, target) : null;
    Records.FolderRecord oldDir = dir ? beforeDirMove(src, target) : null;
    boolean ok = super.rename(src, dst);
    if (ok && file) {
      afterFileMove(src, target, moved);
    }
    if (ok && dir) {
      afterDirMove(src, target, oldDir);
    }
    return ok;
  }

  @Override
  protected void rename(Path src, Path dst, Rename... options) throws IOException {
    denyReserved(src);
    denyReserved(dst);
    boolean file = isPlainFile(src);
    boolean dir = !file && isDir(src);
    Records.FileRecord moved = file ? beforeFileMove(src, dst) : null;
    Records.FolderRecord oldDir = dir ? beforeDirMove(src, dst) : null;
    super.rename(src, dst, options);
    if (file) {
      afterFileMove(src, dst, moved);
    }
    if (dir) {
      afterDirMove(src, dst, oldDir);
    }
  }

  /**
   * A folder holds its own identity file, which the wrapper hides. For the caller a folder with nothing else in it is EMPTY, and delete(folder, false)
   * must work (the contract of delete); the real HDFS refuses it because of the identity file. So when the identity file is all that the folder
   * holds, it is removed first. A folder with anything else in it is refused as before, and nothing is lost.
   */
  private void removeIdentityOfEmptyFolder(Path dir) throws IOException {
    FileStatus[] kids;
    try {
      kids = fs.listStatus(dir);
    } catch (FileNotFoundException e) {
      return;
    }
    if (kids.length == 1 && !kids[0].isDirectory() && Records.isFolderFileName(kids[0].getPath().getName())) {
      fs.delete(kids[0].getPath(), false);
      folders.forgetTree(dir);
    }
  }

  @Override
  public boolean delete(Path f, boolean recursive) throws IOException {
    denyReserved(f);
    boolean file = isPlainFile(f);
    if (!recursive && !file) {
      removeIdentityOfEmptyFolder(f);
    }
    boolean ok = super.delete(f, recursive);
    if (ok && file) {
      dropSidecar(f);
    }
    if (ok) {
      folders.forgetTree(f);
    }
    return ok;
  }

  @Override
  public boolean mkdirs(Path f, FsPermission permission) throws IOException {
    List<Path> fresh = folders.missingAncestors(q(f));
    boolean ok = super.mkdirs(f, permission);
    if (ok) {
      folders.adopt(fresh);
    }
    return ok;
  }

  @Override
  public boolean mkdirs(Path f) throws IOException {
    List<Path> fresh = folders.missingAncestors(q(f));
    boolean ok = super.mkdirs(f);
    if (ok) {
      folders.adopt(fresh);
    }
    return ok;
  }

  @Override
  protected boolean primitiveMkdir(Path f, FsPermission abdolutePermission) throws IOException {
    List<Path> fresh = folders.missingAncestors(q(f));
    boolean ok = super.primitiveMkdir(f, abdolutePermission);
    if (ok) {
      folders.adopt(fresh);
    }
    return ok;
  }
}
