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
import java.security.KeyPair;
import java.util.Arrays;

/** The unit test of FleetKeys (step F2): no cluster needed. */
public class FleetKeysTest {
  static int pass, fail;

  static void chk(String what, boolean ok) {
    if (ok) { pass++; System.out.println("  pass: " + what); } else { fail++; System.out.println("  FAIL: " + what); }
  }

  interface Thrower { void run() throws Exception; }

  static boolean refuses(Thrower t, String text) {
    try { t.run(); return false; } catch (Exception e) { return e.getMessage() != null && e.getMessage().contains(text); }
  }

  static byte[] run(String... cmd) throws Exception {
    Process p = new ProcessBuilder(cmd).redirectErrorStream(false).start();
    byte[] out = p.getInputStream().readAllBytes();
    if (p.waitFor() != 0) { throw new IOException("failed: " + String.join(" ", cmd)); }
    return out;
  }

  static byte[] record(AttestedSignatures s, String name) throws IOException {
    byte[][] hashes = {Records.sha256(name.getBytes())};
    return s.encodeFile(16384, 10, hashes, Records.ROOT_ID, name);
  }

  public static void main(String[] args) throws Exception {
    KeyPair a = TestFleet.pair(), b = TestFleet.pair(), outsider = TestFleet.pair();
    String H = TestFleet.HEADER;
    String fleet = H + TestFleet.row("m", "master", "10.10.0.1", a) + TestFleet.row("w", "worker", "10.10.0.2", b);
    System.out.println("== 1. a node of a two-node fleet");
    FleetKeys ka = FleetKeys.load(TestFleet.dir(a, fleet), true);
    FleetKeys kb = FleetKeys.load(TestFleet.dir(b, fleet), true);
    chk("the node's key id starts with FLEET- and is 38 characters", ka.signingKeyId().startsWith("FLEET-") && ka.signingKeyId().length() == 38 && Records.validKeyId(ka.signingKeyId()));
    chk("the two nodes have different key ids, and each trusts both keys", !ka.signingKeyId().equals(kb.signingKeyId()) && ka.publicKey(kb.signingKeyId()) != null && kb.publicKey(ka.signingKeyId()) != null && ka.publicKey(ka.signingKeyId()) != null);
    AttestedSignatures sa = new AttestedSignatures(ka), sb = new AttestedSignatures(kb);
    sb.checkFile(Records.decodeFile(record(sa, "f")));
    chk("a record that node m signed is accepted by node w (the list is the same on both)", true);
    System.out.println("== 2. what a node refuses");
    FleetKeys rogue = FleetKeys.load(TestFleet.dir(outsider, H + TestFleet.row("evil", "master", "10.10.0.9", outsider)), true);
    byte[] recR = record(new AttestedSignatures(rogue), "f");
    chk("a record signed by a VALID P-256 key that is not in fleet.tsv is refused: not trusted here", refuses(() -> sa.checkFile(Records.decodeFile(recR)), "not trusted here"));
    byte[] ok = record(sa, "f"); byte[] flipped = ok.clone(); flipped[flipped.length - 4] ^= 1;
    chk("a record with one bit of its signature flipped is refused: does not verify", refuses(() -> sa.checkFile(Records.decodeFile(flipped)), "does not verify"));
    System.out.println("== 3. a directory that is wrong is refused, in words");
    chk("this node's key is not in fleet.tsv: refused", refuses(() -> FleetKeys.load(TestFleet.dir(outsider, fleet), true), "is not in fleet.tsv"));
    chk("fleet.tsv is missing: refused", refuses(() -> FleetKeys.load(TestFleet.dir(a, null), true), "fleet.tsv"));
    chk("fleet.tsv holds no key: refused", refuses(() -> FleetKeys.load(TestFleet.dir(a, H), true), "holds no key"));
    chk("a line with 5 fields: refused", refuses(() -> FleetKeys.load(TestFleet.dir(a, H + "m\tmaster\t10.10.0.1\t10.128.0.2:51820\t" + TestFleet.b64(a.getPublic().getEncoded()) + "\n"), true), "6 fields"));
    chk("a public key that is not base64: refused", refuses(() -> FleetKeys.load(TestFleet.dir(a, H + "m\tmaster\t10.10.0.1\t10.128.0.2:51820\t!!!\tQUJD\n"), true), "could not be read"));
    chk("a public key that is not an EC key: refused", refuses(() -> FleetKeys.load(TestFleet.dir(a, H + "m\tmaster\t10.10.0.1\t10.128.0.2:51820\tQUJDREVGRw==\tQUJD\n"), true), "could not be read"));
    Path mismatch = TestFleet.dir(a, fleet); Files.write(mismatch.resolve("sign.key"), TestFleet.pem(b).getBytes(StandardCharsets.US_ASCII));
    chk("sign.key that does not match the public key listed for this node: refused", refuses(() -> FleetKeys.load(mismatch, true), "does not match"));
    Path nokey = TestFleet.dir(a, fleet); Files.delete(nokey.resolve("sign.key"));
    chk("signing on but no sign.key: refused", refuses(() -> FleetKeys.load(nokey, true), "sign.key"));
    FleetKeys readOnly = FleetKeys.load(nokey, false);
    chk("a reader that does not sign needs no private key: it verifies, and says it cannot sign", readOnly.signingKeyId() == null && refuses(() -> readOnly.sign(new byte[1]), "no signing key"));
    chk("the wrapper's signature layer refuses keys that cannot sign (the wrapper always signs)", refuses(() -> new AttestedSignatures(readOnly), "no signing key"));
    System.out.println("== 4. once per JVM, and the fixed place");
    Path once = TestFleet.dir(a, fleet);
    FleetKeys first = FleetKeys.load(once, true);
    Files.write(once.resolve("fleet.tsv"), (H + TestFleet.row("evil", "master", "10.10.0.9", outsider)).getBytes(StandardCharsets.US_ASCII));
    chk("the same directory gives the same object, and a later change of fleet.tsv is not seen (nothing can change the list in a run)", FleetKeys.load(once, true) == first && first.publicKey(kb.signingKeyId()) != null);
    FleetKeys.reset();
    chk("only reset() (for tests) makes it read again", refuses(() -> FleetKeys.load(once, true), "is not in fleet.tsv"));
    FleetKeys.useDirForTesting(null); FleetKeys.reset();
    chk("without the test hook the keys come from /run/tc (not there in this sandbox: refused, naming fleet.tsv)", refuses(() -> FleetKeys.current(), "fleet.tsv"));
    Path d0 = TestFleet.dir(a, fleet); FleetKeys.useDirForTesting(d0);
    chk("with the test hook, current() reads that directory", FleetKeys.current().signingKeyId().equals(ka.signingKeyId())); FleetKeys.useDirForTesting(null);
    System.out.println("== 5. the real format of openssl, as tc-fleet.sh writes it (skipped when there is no openssl)");
    boolean ssl; try { run("openssl", "version"); ssl = true; } catch (Exception e) { ssl = false; System.out.println("  note: no openssl here, skipped"); }
    if (ssl) {
      Path d = Files.createTempDirectory("fleetssl");
      Path tmp = d.resolve("sec1.pem"); Files.write(tmp, run("openssl", "ecparam", "-name", "prime256v1", "-genkey", "-noout"));
      Files.write(d.resolve("sign.key"), run("openssl", "pkcs8", "-topk8", "-nocrypt", "-in", tmp.toString()));
      Files.delete(tmp);
      String pub = TestFleet.b64(run("openssl", "ec", "-in", d.resolve("sign.key").toString(), "-pubout", "-outform", "DER"));
      Files.write(d.resolve("sign.pub"), pub.getBytes(StandardCharsets.US_ASCII));
      Files.write(d.resolve("fleet.tsv"), (H + "x\tmaster\t10.10.0.1\t10.128.0.2:51820\t" + pub + "\tQUJD\n").getBytes(StandardCharsets.US_ASCII));
      AttestedSignatures s = new AttestedSignatures(FleetKeys.load(d, true));
      s.checkFile(Records.decodeFile(record(s, "g")));
      chk("a key made by openssl (PKCS#8 PEM, P-256) and its public key load, sign, and verify", true);
      chk("the key file has the header that the fleet check searches for", new String(Files.readAllBytes(d.resolve("sign.key"))).startsWith("-----BEGIN PRIVATE KEY-----"));
    }
    System.out.println(); System.out.println("pass: " + pass + "   fail: " + fail);
    System.out.println(fail == 0 ? "FLEETKEYS-TEST-PASS" : "FLEETKEYS-TEST-FAIL");
    System.exit(fail == 0 ? 0 : 1);
  }
}
