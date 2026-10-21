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
import java.nio.file.Paths;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.spec.ECGenParameterSpec;
import java.util.Base64;

import org.apache.hadoop.conf.Configuration;
import org.apache.hadoop.fs.FSDataOutputStream;
import org.apache.hadoop.fs.FileSystem;

/**
 * A TEST tool for the cluster check of step F2 (never installed): writes a file through the wrapper AS AN OUTSIDER, with a valid P-256 key that is in
 * no real fleet.tsv. The key directory of the wrapper is fixed, so this class (compiled on the node, in the wrapper's package, to reach the test hook)
 * points the keys at a one-node fleet of its own. The file's record is then genuine but signed by an unlisted key, and the fleet's wrapper must refuse it.
 * Usage: java -cp ... org.apache.nutch.attested.OutsiderWrite TARGET LOCALFILE
 */
public final class OutsiderWrite {
  private OutsiderWrite() {
  }

  public static void main(String[] args) throws Exception {
    if (args.length != 2) {
      System.err.println("usage: OutsiderWrite TARGET LOCALFILE");
      System.exit(2);
    }
    KeyPairGenerator g = KeyPairGenerator.getInstance("EC");
    g.initialize(new ECGenParameterSpec("secp256r1"));
    KeyPair kp = g.generateKeyPair();
    String pub = Base64.getEncoder().encodeToString(kp.getPublic().getEncoded());
    Path dir = Files.createTempDirectory("outsider");
    Files.write(dir.resolve("sign.pub"), pub.getBytes(StandardCharsets.US_ASCII));
    Files.write(dir.resolve("sign.key"), ("-----BEGIN PRIVATE KEY-----\n" + Base64.getMimeEncoder(64, "\n".getBytes(StandardCharsets.US_ASCII)).encodeToString(kp.getPrivate().getEncoded())
        + "\n-----END PRIVATE KEY-----\n").getBytes(StandardCharsets.US_ASCII));
    Files.write(dir.resolve("fleet.tsv"), ("# tc-fleet v1\noutsider\tmaster\t10.10.0.9\t10.0.0.9:51820\t" + pub + "\tQUJD\n").getBytes(StandardCharsets.US_ASCII));
    FleetKeys.useDirForTesting(dir);
    org.apache.hadoop.fs.Path target = new org.apache.hadoop.fs.Path(args[0]);
    FileSystem fs = target.getFileSystem(new Configuration());
    if (!(fs instanceof AttestedHdfsFileSystem)) {
      System.err.println("OUTSIDER-STOP: the file system is " + fs.getClass().getName() + ", not the wrapper");
      System.exit(1);
    }
    try (FSDataOutputStream out = fs.create(target, true)) {
      out.write(Files.readAllBytes(Paths.get(args[1])));
    }
    System.out.println("OUTSIDER-WROTE " + args[0] + " signed by " + FleetKeys.current().signingKeyId());
  }
}
