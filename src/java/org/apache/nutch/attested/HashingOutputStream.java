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

import java.io.IOException;
import java.io.OutputStream;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.List;

import org.apache.hadoop.fs.FSDataOutputStream;
import org.apache.hadoop.fs.StreamCapabilities;
import org.apache.hadoop.fs.Syncable;
import org.apache.hadoop.fs.statistics.IOStatistics;
import org.apache.hadoop.fs.statistics.IOStatisticsSource;

/** Passes every byte on to the real stream and hashes it in chunks (SHA-256 of each chunk, a flat list); at close the record is written. */
final class HashingOutputStream extends OutputStream implements Syncable, StreamCapabilities, IOStatisticsSource {

  /** Receives the finished list of chunk hashes at close. */
  interface SidecarSink {
    void write(String path, long length, int chunkSize, byte[][] hashes) throws IOException;
  }

  private final FSDataOutputStream inner;
  private final String path;
  private final int chunkSize;
  private final SidecarSink sink;
  private final MessageDigest md;
  private final List<byte[]> hashes = new ArrayList<>();
  private long length;
  private int inChunk;
  private boolean closed;

  HashingOutputStream(FSDataOutputStream inner, String path, int chunkSize, SidecarSink sink) {
    this.inner = inner;
    this.path = path;
    this.chunkSize = chunkSize;
    this.sink = sink;
    try {
      this.md = MessageDigest.getInstance("SHA-256");
    } catch (NoSuchAlgorithmException e) {
      throw new IllegalStateException(e);
    }
  }

  private void update(byte[] b, int off, int len) {
    while (len > 0) {
      int n = Math.min(len, chunkSize - inChunk);
      md.update(b, off, n);
      inChunk += n;
      length += n;
      off += n;
      len -= n;
      if (inChunk == chunkSize) {
        hashes.add(md.digest());
        inChunk = 0;
      }
    }
  }

  @Override
  public void write(int b) throws IOException {
    inner.write(b);
    update(new byte[] {(byte) b}, 0, 1);
  }

  @Override
  public void write(byte[] b, int off, int len) throws IOException {
    inner.write(b, off, len);
    update(b, off, len);
  }

  @Override
  public void flush() throws IOException {
    inner.flush();
  }

  public void sync() throws IOException {
    inner.hflush();
  }

  @Override
  public void hflush() throws IOException {
    inner.hflush();
  }

  @Override
  public void hsync() throws IOException {
    inner.hsync();
  }

  @Override
  public boolean hasCapability(String capability) {
    return inner.hasCapability(capability);
  }

  @Override
  public IOStatistics getIOStatistics() {
    return inner.getIOStatistics();
  }

  @Override
  public void close() throws IOException {
    if (closed) {
      return;
    }
    closed = true;
    inner.close();
    if (inChunk > 0) {
      hashes.add(md.digest());
      inChunk = 0;
    }
    sink.write(path, length, chunkSize, hashes.toArray(new byte[0][]));
  }
}
