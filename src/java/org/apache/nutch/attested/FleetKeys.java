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
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.security.GeneralSecurityException;
import java.security.KeyFactory;
import java.security.MessageDigest;
import java.security.PrivateKey;
import java.security.PublicKey;
import java.security.Signature;
import java.security.spec.PKCS8EncodedKeySpec;
import java.security.spec.X509EncodedKeySpec;
import java.util.Base64;
import java.util.HashMap;
import java.util.Map;

/**
 * The keys of a node of the fixed fleet (step F2). The directory (normally /run/tc, a memory file system) holds three files that
 * tc-fleet.sh wrote at boot: sign.key (this node's private key, PKCS#8 PEM, P-256), sign.pub (its public key, base64 of the X.509 form)
 * and fleet.tsv (the list that every node measured; the signing public key of every node is its fifth field). A record is trusted only
 * when it was signed by a key in fleet.tsv; a key that is valid but not in the list is refused. There is no quote handling here: the
 * consumer's verifier checks the quotes, and nothing in the cluster can change the list. The files are read once per JVM and directory.
 */
final class FleetKeys implements AttestedKeys {
  static final String PREFIX = "FLEET-";
  private static final Map<String, FleetKeys> LOADED = new HashMap<>();

  private final String id;
  private final PrivateKey priv;
  private final Map<String, PublicKey> trusted;

  private FleetKeys(String id, PrivateKey priv, Map<String, PublicKey> trusted) {
    this.id = id;
    this.priv = priv;
    this.trusted = trusted;
  }

  /** The keys of this directory, read once per JVM; needPrivate is true when this JVM signs (the private key must then exist). */
  static synchronized FleetKeys load(Path dir, boolean needPrivate) throws IOException {
    String k = dir.toAbsolutePath().normalize() + "|" + needPrivate;
    FleetKeys f = LOADED.get(k);
    if (f == null) {
      f = read(dir, needPrivate);
      LOADED.put(k, f);
    }
    return f;
  }

  /** Where the keys of a fleet node are: tc-fleet.sh writes them at boot into /run/tc (memory). Fixed; only the unit tests change it. */
  private static final Path FLEET_DIR = Paths.get("/run/tc");
  private static volatile Path dirForTesting;

  /** The keys of this node: always the fleet directory, signing included. */
  static FleetKeys current() throws IOException {
    Path d = dirForTesting;
    return load(d != null ? d : FLEET_DIR, true);
  }

  /** Points the keys at another directory (for tests only; null puts it back). */
  static void useDirForTesting(Path dir) {
    dirForTesting = dir;
  }

  /** Forgets what was loaded (for tests only). */
  static synchronized void reset() {
    LOADED.clear();
  }

  static String idOf(byte[] publicEncoded) throws GeneralSecurityException {
    byte[] h = MessageDigest.getInstance("SHA-256").digest(publicEncoded);
    StringBuilder sb = new StringBuilder(PREFIX);
    for (int i = 0; i < 16; i++) {
      sb.append(String.format("%02x", h[i]));
    }
    return sb.toString();
  }

  private static FleetKeys read(Path dir, boolean needPrivate) throws IOException {
    try {
      KeyFactory kf = KeyFactory.getInstance("EC");
      Map<String, PublicKey> trusted = new HashMap<>();
      for (String line : Files.readAllLines(dir.resolve("fleet.tsv"), StandardCharsets.UTF_8)) {
        if (line.isEmpty() || line.startsWith("#")) {
          continue;
        }
        String[] f = line.split("\t", -1);
        if (f.length != 6) {
          throw new IOException("a line of fleet.tsv does not have 6 fields");
        }
        byte[] enc = Base64.getDecoder().decode(f[4]);
        trusted.put(idOf(enc), kf.generatePublic(new X509EncodedKeySpec(enc)));
      }
      if (trusted.isEmpty()) {
        throw new IOException("fleet.tsv holds no key");
      }
      Path keyFile = dir.resolve("sign.key");
      if (!needPrivate && !Files.isReadable(keyFile)) {
        return new FleetKeys(null, null, trusted);
      }
      String id = idOf(Base64.getDecoder().decode(new String(Files.readAllBytes(dir.resolve("sign.pub")), StandardCharsets.UTF_8).trim()));
      if (!trusted.containsKey(id)) {
        throw new IOException("this node's signing key (" + id + ") is not in fleet.tsv");
      }
      String pem = new String(Files.readAllBytes(keyFile), StandardCharsets.UTF_8).replaceAll("-----[A-Z ]+-----", "").replaceAll("\\s", "");
      PrivateKey priv = kf.generatePrivate(new PKCS8EncodedKeySpec(Base64.getDecoder().decode(pem)));
      Signature s = Signature.getInstance("SHA256withECDSA");
      s.initSign(priv);
      s.update(new byte[] {1});
      byte[] sig = s.sign();
      s.initVerify(trusted.get(id));
      s.update(new byte[] {1});
      if (!s.verify(sig)) {
        throw new IOException("sign.key does not match the public key listed in fleet.tsv");
      }
      return new FleetKeys(id, priv, trusted);
    } catch (GeneralSecurityException | IllegalArgumentException e) {
      throw new IOException("the fleet keys could not be read: " + e.getMessage(), e);
    }
  }

  @Override
  public String signingKeyId() {
    return id;
  }

  @Override
  public byte[] sign(byte[] statement) throws IOException {
    if (priv == null) {
      throw new IOException("this JVM has no signing key");
    }
    try {
      Signature s = Signature.getInstance("SHA256withECDSA");
      s.initSign(priv);
      s.update(statement);
      return s.sign();
    } catch (GeneralSecurityException e) {
      throw new IOException("signing failed: " + e.getMessage(), e);
    }
  }

  @Override
  public PublicKey publicKey(String keyId) {
    return trusted.get(keyId);
  }
}
