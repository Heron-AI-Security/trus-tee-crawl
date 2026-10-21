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

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.spec.ECGenParameterSpec;
import java.util.Base64;

/** Helpers of the unit tests and of the smoke test: the files of a fleet node, made from Java key pairs. */
final class TestFleet {
  static final String HEADER = "# tc-fleet v1\n";

  private TestFleet() {
  }

  static KeyPair pair() throws Exception {
    KeyPairGenerator g = KeyPairGenerator.getInstance("EC");
    g.initialize(new ECGenParameterSpec("secp256r1"));
    return g.generateKeyPair();
  }

  static String b64(byte[] b) {
    return Base64.getEncoder().encodeToString(b);
  }

  static String pem(KeyPair kp) {
    return "-----BEGIN PRIVATE KEY-----\n" + Base64.getMimeEncoder(64, "\n".getBytes()).encodeToString(kp.getPrivate().getEncoded()) + "\n-----END PRIVATE KEY-----\n";
  }

  static String row(String name, String role, String ip, KeyPair kp) {
    return name + "\t" + role + "\t" + ip + "\t10.128.0.2:51820\t" + b64(kp.getPublic().getEncoded()) + "\tQUJD\n";
  }

  /** A node's directory: its own key pair (when given) and a fleet.tsv with the given rows (when given). */
  static Path dir(KeyPair own, String fleet) throws Exception {
    Path d = Files.createTempDirectory("fleetkeys");
    if (own != null) {
      Files.write(d.resolve("sign.key"), pem(own).getBytes(StandardCharsets.US_ASCII));
      Files.write(d.resolve("sign.pub"), b64(own.getPublic().getEncoded()).getBytes(StandardCharsets.US_ASCII));
    }
    if (fleet != null) {
      Files.write(d.resolve("fleet.tsv"), fleet.getBytes(StandardCharsets.US_ASCII));
    }
    return d;
  }

  /** The directories of n nodes of one fleet (node 0 is the master): each has its own key and the same fleet.tsv. */
  static Path[] fleet(int n) throws Exception {
    KeyPair[] k = new KeyPair[n];
    StringBuilder rows = new StringBuilder(HEADER);
    for (int i = 0; i < n; i++) {
      k[i] = pair();
      rows.append(row("node" + i, i == 0 ? "master" : "worker", "10.10.0." + (i + 1), k[i]));
    }
    Path[] d = new Path[n];
    for (int i = 0; i < n; i++) {
      d[i] = dir(k[i], rows.toString());
    }
    return d;
  }

  /** The directory of an OUTSIDER: a valid key of its own, in a one-node fleet that is not the real one. */
  static Path outsider() throws Exception {
    KeyPair o = pair();
    return dir(o, HEADER + row("outsider", "master", "10.10.0.9", o));
  }
}
