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

import java.io.EOFException;
import java.io.IOException;

import org.apache.hadoop.fs.FSDataInputStream;
import org.apache.hadoop.fs.FileSystem;
import org.apache.hadoop.fs.Path;

/** The file record kept next to a file: .NAME.attested (see Records). The folder identity file is a companion too and is hidden from listings. */
final class AttestedSidecar {

  private AttestedSidecar() {
  }

  static boolean isCompanion(Path p) {
    return isSidecar(p) || Records.isFolderFileName(p.getName());
  }

  static boolean isSidecar(Path p) {
    String n = p.getName();
    return n.length() > Records.SUFFIX.length() + 1 && n.startsWith(".") && n.endsWith(Records.SUFFIX);
  }

  static Path pathFor(Path file) {
    String n = "." + file.getName() + Records.SUFFIX;
    Path parent = file.getParent();
    return parent == null ? new Path("/" + n) : new Path(parent, n);
  }

  /** Reads and decodes a record; a record that is too long, too short or malformed fails cleanly with "record is damaged". */
  static Records.FileRecord read(FileSystem fs, Path sidecar) throws IOException {
    long size = fs.getFileStatus(sidecar).getLen();
    if (Records.fileRecordTooLong(size)) {
      throw new IOException("record is damaged (impossible sizes)");
    }
    byte[] all = new byte[(int) size];
    try (FSDataInputStream raw = fs.open(sidecar)) {
      raw.readFully(0, all);
    } catch (EOFException e) {
      throw new IOException("record is damaged (too short)");
    }
    return Records.decodeFile(all);
  }
}
