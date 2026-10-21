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
import java.security.GeneralSecurityException;
import java.security.PublicKey;
import java.security.Signature;

/**
 * Signs and checks the records (step F3). Behavior is fixed: every record is signed with this node's fleet key, and a record is trusted
 * only when its signer is a key of fleet.tsv (see FleetKeys). There is no switch, no test key, and no unsigned legacy form.
 */
final class AttestedSignatures {

  private final AttestedKeys keys;

  AttestedSignatures(AttestedKeys keys) throws IOException {
    if (keys == null || keys.signingKeyId() == null) {
      throw new IOException("this JVM has no signing key (the fleet keys are made by tc-fleet.sh at boot)");
    }
    this.keys = keys;
  }

  String signingKeyId() {
    return keys.signingKeyId();
  }

  byte[] encodeFile(int chunkSize, long length, byte[][] hashes, byte[] folderId, String name) throws IOException {
    String id = keys.signingKeyId();
    byte[] sig = keys.sign(Records.fileStatement(id, folderId, name, chunkSize, length, Records.listHash(hashes)));
    return Records.encodeFile(chunkSize, length, hashes, folderId, name, id, sig);
  }

  byte[] encodeFolder(byte[] folderId, String name, byte[] parentId) throws IOException {
    String id = keys.signingKeyId();
    byte[] sig = keys.sign(Records.folderStatement(id, folderId, name, parentId));
    return Records.encodeFolder(folderId, name, parentId, id, sig);
  }

  /** Checks the signature of a file record; whether the folder id and the name are the right ones is the caller's job. */
  void checkFile(Records.FileRecord r) throws IOException {
    verify("record", r.keyId, Records.fileStatement(r.keyId, r.folderId, r.name, r.chunkSize, r.length, r.listHash()), r.signature);
  }

  void checkFolder(Records.FolderRecord d) throws IOException {
    verify("folder identity", d.keyId, Records.folderStatement(d.keyId, d.folderId, d.name, d.parentId), d.signature);
  }

  private void verify(String what, String keyId, byte[] statement, byte[] signature) throws IOException {
    PublicKey pub = keys.publicKey(keyId);
    if (pub == null) {
      throw new IOException("the " + what + " is signed by a key that is not trusted here (" + keyId + ")");
    }
    try {
      Signature s = Signature.getInstance("SHA256withECDSA");
      s.initVerify(pub);
      s.update(statement);
      if (!s.verify(signature)) {
        throw new IOException("the signature of the " + what + " does not verify (" + keyId + ")");
      }
    } catch (GeneralSecurityException e) {
      throw new IOException("the signature of the " + what + " does not verify (" + keyId + "): " + e.getMessage());
    }
  }
}
