package org.commoncrawl.util;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.lang.invoke.MethodHandles;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.cert.CertPathBuilder;
import java.security.cert.CertStore;
import java.security.cert.Certificate;
import java.security.cert.CertificateFactory;
import java.security.cert.CollectionCertStoreParameters;
import java.security.cert.PKIXBuilderParameters;
import java.security.cert.TrustAnchor;
import java.security.cert.X509CertSelector;
import java.security.cert.X509Certificate;
import java.util.ArrayList;
import java.util.Base64;
import java.util.Collection;
import java.util.Collections;
import java.util.Enumeration;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import java.util.UUID;

import org.apache.hadoop.conf.Configuration;
import org.apache.hadoop.fs.FSDataOutputStream;
import org.apache.hadoop.fs.FileSystem;
import org.apache.hadoop.mapreduce.TaskInputOutputContext;
import org.apache.hadoop.mapreduce.lib.output.FileOutputFormat;
import org.apache.nutch.metadata.Metadata;
import org.apache.nutch.protocol.Content;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Training Custody SourceReceipt emitter (research spike).
 *
 * Runs in the fetcher JVM at the hand-off to the WARC writer. It re-validates
 * the server certificate chain and hostname that the protocol plugin recorded
 * from the connection that produced this response (CC-Bot itself crawls with
 * a trust-all manager), and emits a canonical SourceReceipt over
 * A = content.getContent(), the exact bytes that become the WARC payload.
 *
 * Fails closed: any missing fact or failed check means no receipt, never a
 * weaker one. No TLS secrets are touched.
 */
public class CustodyReceipt {

  private static final Logger LOG = LoggerFactory
      .getLogger(MethodHandles.lookup().lookupClass());

  public static final String TLS_HOST = "_tc_tls_socket_hostname_";
  public static final String TLS_PROTOCOL = "_tc_tls_negotiated_protocol_";
  public static final String TLS_CIPHER = "_tc_tls_negotiated_cipher_";
  public static final String TLS_CHAIN = "_tc_tls_peer_certificate_der_";
  public static final String TLS_SNI_FALLBACK = "_tc_tls_sni_fallback_used_";
  public static final String RECORD_ID = "_tc_warc_record_identifier_";
  public static final String OUTCOME_VERSION = "tc-fetch-outcome/1";
  /** Receipt and evidence carried to the WARC writer (tc.receipts.warc). */
  public static final String WARC_RECEIPT = "_tc_source_receipt_json_";
  public static final String WARC_EVIDENCE = "_tc_handshake_evidence_json_";

  /**
   * The terminal outcome of one fetch. Every fetch the fetcher finishes gets
   * exactly one outcome line, so a missing receipt is a recorded refusal with
   * a reason, not a silent omission.
   */
  public enum Status {
    ACCEPTED, NOT_HTTPS, HTTP_STATUS, NO_TLS_FACTS, SNI_FALLBACK, NO_CONTENT,
    TRUNCATED, CERTIFICATE_INVALID, HOSTNAME_MISMATCH, EMITTER_ERROR,
    NOT_FETCHED, NOT_ATTEMPTED
  }

  /** An outcome: the status, a reason, and the receipt's id when accepted. */
  public static final class Outcome {
    public final Status status;
    public final String detail;
    public final String documentId;

    Outcome(Status status, String detail, String documentId) {
      this.status = status;
      this.detail = detail;
      this.documentId = documentId;
    }
  }

  /**
   * v2: the receipt is issued whatever the certificate's state, and
   * server.validation records it (chain valid / expired / not yet valid /
   * untrusted; hostname match / mismatch). Downstream filters decide; a
   * consumer treats a receipt that is not "authenticated" as an
   * unauthenticated source.
   */
  public static final String VERSION = "tc-source-receipt/2";

  /** Local mode only (tc.receipts.dir); null in task mode. */
  private final Path outDir;
  private final Configuration conf;
  /** Task mode: per-attempt output files, opened on the first receipt. */
  private TaskSink sink;
  private final Set<TrustAnchor> anchors;
  private final byte[] policyBytes;
  private final String nonce;
  private final String binding;
  private final int contentLimit;
  private final String codeHash;
  private final boolean toWarc;
  /** tc.receipts.require.authenticated: refuse instead of recording (v1 behaviour). */
  private final boolean requireAuthenticated;

  private CustodyReceipt(Configuration conf) throws Exception {
    this.conf = conf;
    String dir = conf.get("tc.receipts.dir");
    outDir = dir == null ? null : Paths.get(dir);
    if (outDir != null) {
      Files.createDirectories(outDir);
    }
    // Default: the JDK's own CA store, the one the cluster measures.
    String pem = conf.get("tc.anchors.pem");
    anchors = pem != null ? loadAnchors(Paths.get(pem)) : loadJdkAnchors();
    policyBytes = readPolicy(conf, conf.get("tc.policy.file"));
    checkAnchorsMatchPolicy(anchors, policyBytes);
    nonce = conf.get("tc.nonce");
    binding = conf.get("tc.binding", "unattested");
    contentLimit = conf.getInt("http.content.limit", 1024 * 1024);
    codeHash = selfHash();
    toWarc = conf.getBoolean("tc.receipts.warc", true);
    requireAuthenticated = conf.getBoolean("tc.receipts.require.authenticated", false);
  }

  private static CustodyReceipt instance;
  /** First write failure of this task attempt; close() fails the task on it. */
  private static volatile String failure;
  /** Set by close(): no receipt file may be opened again in this attempt. */
  private static volatile boolean closed;

  /**
   * Whether receipts are on for this job: task mode (tc.receipts.enabled=true)
   * or local mode (tc.receipts.dir set). Protocol plugins use this too, so the
   * TLS facts are recorded exactly when a receipt will be emitted.
   */
  public static boolean enabled(Configuration conf) {
    return conf.getBoolean("tc.receipts.enabled", false)
        || conf.get("tc.receipts.dir") != null;
  }

  /**
   * Called by the fetch task before any fetcher thread starts. Sets up the
   * emitter (policy, trust anchors, key-free prerequisites) and, in task mode,
   * opens this attempt's files, so that a configuration problem fails the task
   * at once instead of surfacing later inside a fetcher thread, where Nutch
   * would catch it.
   */
  public static synchronized void start(Configuration conf,
      TaskInputOutputContext<?, ?, ?, ?> context) throws IOException {
    CustodyReceipt tc = get(conf);
    if (tc == null) {
      return;
    }
    failure = null;
    closed = false;
    if (tc.outDir == null) {
      tc.sinkFor(context);
    }
  }

  /**
   * Null when receipts are not configured. Task mode: tc.receipts.enabled=true;
   * local mode: tc.receipts.dir set.
   */
  public static synchronized CustodyReceipt get(Configuration conf) {
    if (!enabled(conf)) {
      return null;
    }
    if (instance == null) {
      try {
        instance = new CustodyReceipt(conf);
        LOG.info("Training Custody receipts -> {} ({} trust anchors)",
            instance.outDir == null ? "task work output path" : instance.outDir,
            instance.anchors.size());
      } catch (Exception e) {
        throw new RuntimeException("custody receipt setup failed", e);
      }
    }
    return instance;
  }

  /**
   * Emit a receipt for this fetch if every check passes. Always strips the
   * TLS capture keys from the content metadata so they never reach the WARC
   * headers. Returns the outcome; its documentId is null when refused.
   */
  public Outcome emit(String url, Content content, int httpStatus) {
    return emit(url, content, httpStatus, null);
  }

  /**
   * As above; in task mode the receipt goes to this task attempt's work output
   * path, so it is committed with the task and discarded with a failed attempt.
   */
  public Outcome emit(String url, Content content, int httpStatus,
      TaskInputOutputContext<?, ?, ?, ?> context) {
    Metadata md = content.getMetadata();
    String[] chainB64 = md.getValues(TLS_CHAIN);
    String socketHost = md.get(TLS_HOST);
    String protocol = md.get(TLS_PROTOCOL);
    String cipher = md.get(TLS_CIPHER);
    String sniFallback = md.get(TLS_SNI_FALLBACK);
    for (String k : new String[] { TLS_CHAIN, TLS_HOST, TLS_PROTOCOL,
        TLS_CIPHER, TLS_SNI_FALLBACK }) {
      md.remove(k);
    }
    try {
      Outcome refusal = check(url, content, httpStatus, chainB64, socketHost,
          sniFallback);
      if (refusal == null) {
        List<X509Certificate> chain = decode(chainB64);
        String host = new java.net.URL(url).getHost().toLowerCase(Locale.ROOT);
        Validation v = validate(chain, host);
        refusal = requireAuthenticated ? v.refusal() : null;
        if (refusal == null) {
          return issue(url, content, httpStatus, context, v, chainB64, chain,
              host, socketHost, protocol, cipher);
        }
      }
      return refuse(url, refusal, context);
    } catch (Exception e) {
      return refuse(url, new Outcome(Status.EMITTER_ERROR, e.toString(), null),
          context);
    }
  }

  /**
   * Record the outcome of a fetch that produced no content for the emitter
   * (failed, denied by robots.txt, gone...). Redirects with content go
   * through emit() and are refused there for their HTTP status.
   */
  public void notFetched(String url, String detail,
      TaskInputOutputContext<?, ?, ?, ?> context) {
    refuse(url, new Outcome(Status.NOT_FETCHED, detail, null), context);
  }

  private Outcome refuse(String url, Outcome refusal,
      TaskInputOutputContext<?, ?, ?, ?> context) {
    LOG.info("custody REFUSED {}: {} {}", url, refusal.status, refusal.detail);
    try {
      writeOutcome(url, refusal, null, context);
    } catch (Exception e) {
      // not thrown: Nutch's fetcher threads catch and continue; close()
      // fails the task instead
      markFailed("writing outcome for " + url, e);
    }
    return refusal;
  }

  /**
   * Record a URL that was on the fetch list but never fetched: dropped by the
   * fetcher's time limit, throughput threshold or task timeout, by too many
   * exceptions on its host, or by URL filters. Without this a dropped URL and
   * a deleted one would look the same.
   */
  public static void notAttempted(String url, String reason) {
    CustodyReceipt tc = instance;
    if (tc != null) {
      tc.refuse(url, new Outcome(Status.NOT_ATTEMPTED, reason, null), null);
    }
  }

  static void markFailed(String what, Throwable e) {
    LOG.error("custody write FAILED ({}): the task will fail at close", what, e);
    if (failure == null) {
      failure = what + ": " + e;
    }
  }

  private void writeOutcome(String url, Outcome o, byte[] receipt,
      TaskInputOutputContext<?, ?, ?, ?> context) throws Exception {
    Map<String, Object> m = new TreeMap<>();
    m.put("version", OUTCOME_VERSION);
    m.put("source_url", url);
    m.put("status", o.status.name());
    m.put("detail", o.detail);
    m.put("document_id", o.documentId);
    m.put("receipt_sha256", receipt == null ? null : sha256(receipt));
    m.put("nonce", nonce);
    byte[] line = canonical(m).getBytes(StandardCharsets.UTF_8);
    if (outDir == null) {
      sinkFor(context).writeOutcome(line);
    } else {
      synchronized (this) {
        Files.write(outDir.resolve("outcomes.jsonl"), (new String(line,
            StandardCharsets.UTF_8) + "\n").getBytes(StandardCharsets.UTF_8),
            java.nio.file.StandardOpenOption.CREATE,
            java.nio.file.StandardOpenOption.APPEND);
      }
    }
  }

  private Outcome issue(String url, Content content, int httpStatus,
      TaskInputOutputContext<?, ?, ?, ?> context, Validation validation, String[] chainB64,
      List<X509Certificate> chain, String host, String socketHost,
      String protocol, String cipher) throws Exception {
    Metadata md = content.getMetadata();
    {

      byte[] a = content.getContent();
      String uuid = UUID.randomUUID().toString();
      String documentId = "urn:uuid:" + uuid;

      List<Object> chainHashes = new ArrayList<>();
      for (String b64 : chainB64) {
        chainHashes.add(sha256(Base64.getDecoder().decode(b64)));
      }
      Map<String, Object> server = new TreeMap<>();
      server.put("profile", "jsse-handshake/1");
      server.put("hostname", host);
      if (!host.equalsIgnoreCase(socketHost)) {
        server.put("connection_host", socketHost.toLowerCase(Locale.ROOT));
      }
      server.put("leaf_sha256", chainHashes.get(0));
      server.put("chain_sha256", chainHashes);
      // Validity period of every certificate, in chain order (epoch seconds).
      // The emitter's own PKIX check uses the VM clock, which the host
      // controls; recording the periods lets a verifier check them against a
      // trusted time window instead.
      List<Object> validity = new ArrayList<>();
      for (X509Certificate c : chain) {
        Map<String, Object> v = new TreeMap<>();
        v.put("not_before", Long.valueOf(c.getNotBefore().getTime() / 1000));
        v.put("not_after", Long.valueOf(c.getNotAfter().getTime() / 1000));
        validity.add(v);
      }
      server.put("chain_validity", validity);
      server.put("protocol", protocol);
      server.put("cipher_suite", cipher);
      server.put("chain_valid", Boolean.valueOf(validation.chainValid()));
      server.put("hostname_matches", Boolean.valueOf(validation.hostnameMatches));
      server.put("validation", validation.toMap());
      // JSSE completes a handshake only after verifying CertificateVerify
      // and the server Finished, whatever the TrustManager decides.
      server.put("finished_verified", Boolean.TRUE);
      // no handshake evidence in this build (see source-receipt-keyfree.patch)
      byte[] evidence = null;

      Map<String, Object> bindingObj = new TreeMap<>();
      bindingObj.put("type", binding);

      Map<String, Object> sr = new TreeMap<>();
      sr.put("version", VERSION);
      sr.put("document_id", documentId);
      sr.put("source_url", url);
      sr.put("raw_content_hash", sha256(a));
      sr.put("raw_content_length", Long.valueOf(a.length));
      sr.put("collection_policy_hash", sha256(policyBytes));
      sr.put("server", server);
      sr.put("http_status", Long.valueOf(httpStatus));
      sr.put("code_hash", codeHash);
      sr.put("nonce", nonce);
      sr.put("binding", bindingObj);

      byte[] receipt = canonical(sr).getBytes(StandardCharsets.UTF_8);
      try {
        if (outDir == null) {
          sinkFor(context).write(receipt, evidence,
              evidence == null ? null : sha256(evidence));
        } else {
          Files.write(outDir.resolve(uuid + ".source.json"), receipt);
          Files.write(outDir.resolve(uuid + ".raw"), a);
          if (evidence != null) {
            Files.write(outDir.resolve(uuid + ".handshake.json"), evidence);
          }
        }
      } catch (IOException e) {
        markFailed("writing receipt for " + url, e);
        throw e;
      }
      md.set(RECORD_ID, documentId);
      if (toWarc) {
        // the exact bytes, so the WARC carries this receipt, not a re-derived one
        md.set(WARC_RECEIPT, new String(receipt, StandardCharsets.UTF_8));
        if (evidence != null) {
          md.set(WARC_EVIDENCE, new String(evidence, StandardCharsets.UTF_8));
        }
      }
      String detail = validation.authenticated() ? ""
          : "unauthenticated source: " + validation.summary();
      if (evidence == null) {
        detail = (detail.isEmpty() ? "" : detail + "; ") + "no key-free handshake evidence";
      }
      Outcome ok = new Outcome(Status.ACCEPTED, detail, documentId);
      try {
        writeOutcome(url, ok, receipt, context);
      } catch (Exception e) {
        // the receipt is written; record the failure rather than also
        // writing a refusal for the same fetch
        markFailed("writing outcome for " + url, e);
      }
      LOG.info("custody receipt {} for {} H(A)={} ({} B)", documentId, url,
          sha256(a), a.length);
      return ok;
    }
  }

  private static Outcome no(Status s, String detail) {
    return new Outcome(s, detail, null);
  }

  private Outcome check(String url, Content content, int httpStatus,
      String[] chainB64, String socketHost, String sniFallback)
      throws IOException {
    if (!url.startsWith("https://")) {
      return no(Status.NOT_HTTPS, "not https");
    }
    if (httpStatus != 200) {
      return no(Status.HTTP_STATUS, "HTTP status " + httpStatus);
    }
    if (chainB64 == null || chainB64.length == 0 || socketHost == null) {
      return no(Status.NO_TLS_FACTS, "no TLS facts recorded for this response");
    }
    if (!"false".equals(sniFallback)) {
      return no(Status.SNI_FALLBACK, "SNI fallback used");
    }
    // A connection opened for another host is accepted (HTTP/2 connection
    // coalescing, RFC 9113 9.1.1): what matters is that the certificate the
    // server presented is valid for THIS URL's host, which validate() checks
    // independently of the client. The connection host is recorded.
    if (content.getContent() == null) {
      return no(Status.NO_CONTENT, "no content");
    }
    if (content.getContent().length >= contentLimit) {
      return no(Status.TRUNCATED,
          "content reached http.content.limit; possibly truncated");
    }
    if ("true".equals(content.getMetadata().get(
        org.apache.nutch.net.protocols.Response.TRUNCATED_CONTENT))) {
      // protocol-okhttp also truncates on time or disconnect, below the limit
      return no(Status.TRUNCATED, "content marked truncated by the protocol plugin");
    }
    return null;
  }

  /** The emitter's view of the server certificate, recorded in the receipt. */
  static final class Validation {
    /** "valid", "expired", "not_yet_valid" or "untrusted". */
    final String chain;
    final boolean hostnameMatches;
    final String detail;

    Validation(String chain, boolean hostnameMatches, String detail) {
      this.chain = chain;
      this.hostnameMatches = hostnameMatches;
      this.detail = detail;
    }

    boolean chainValid() {
      return "valid".equals(chain);
    }

    boolean authenticated() {
      return chainValid() && hostnameMatches;
    }

    String summary() {
      return "chain " + chain + ", hostname " + (hostnameMatches ? "match" : "mismatch");
    }

    Map<String, Object> toMap() {
      Map<String, Object> m = new TreeMap<>();
      m.put("authenticated", Boolean.valueOf(authenticated()));
      m.put("chain", chain);
      m.put("hostname", hostnameMatches ? "match" : "mismatch");
      m.put("detail", detail);
      return m;
    }

    /** The v1 refusal, for tc.receipts.require.authenticated=true. */
    Outcome refusal() {
      if (!chainValid()) {
        return no(Status.CERTIFICATE_INVALID, "certificate path: " + chain + " " + detail);
      }
      if (!hostnameMatches) {
        return no(Status.HOSTNAME_MISMATCH, detail);
      }
      return null;
    }
  }

  /**
   * PKIX under the pinned anchors at the VM's current time; if that fails,
   * again at a time inside every certificate's validity period, to tell an
   * expired (or not yet valid) chain from one that no anchor vouches for.
   * The VM clock comes from the host, so "expired" is the emitter's view; the
   * verifier re-checks the recorded periods against trusted time.
   */
  private Validation validate(List<X509Certificate> chain, String host)
      throws Exception {
    String chainState = "valid";
    String detail = "";
    try {
      buildPath(chain, null);
    } catch (Exception e) {
      detail = String.valueOf(e.getMessage());
      chainState = "untrusted";
      long lo = Long.MIN_VALUE, hi = Long.MAX_VALUE;
      for (X509Certificate c : chain) {
        lo = Math.max(lo, c.getNotBefore().getTime());
        hi = Math.min(hi, c.getNotAfter().getTime());
      }
      if (lo <= hi) {
        try {
          buildPath(chain, new java.util.Date(lo));
          chainState = System.currentTimeMillis() < lo ? "not_yet_valid" : "expired";
        } catch (Exception e2) {
          // no anchor vouches for this chain at any time
        }
      }
    }
    boolean hostOk = matchesHostname(chain.get(0), host);
    if (!hostOk) {
      detail = (detail.isEmpty() ? "" : detail + "; ") + "hostname " + host
          + " not in subjectAltName";
    }
    return new Validation(chainState, hostOk, detail);
  }

  private void buildPath(List<X509Certificate> chain, java.util.Date at)
      throws Exception {
    X509CertSelector target = new X509CertSelector();
    target.setCertificate(chain.get(0));
    PKIXBuilderParameters params = new PKIXBuilderParameters(anchors, target);
    params.setRevocationEnabled(false);
    if (at != null) {
      params.setDate(at);
    }
    params.addCertStore(CertStore.getInstance("Collection",
        new CollectionCertStoreParameters(chain)));
    CertPathBuilder.getInstance("PKIX").build(params);
  }

  /** Mirrors task2 pki.matches_hostname: DNS SANs only, leftmost wildcard. */
  static boolean matchesHostname(X509Certificate leaf, String hostname)
      throws Exception {
    String h = hostname.toLowerCase(Locale.ROOT);
    if (h.endsWith(".")) {
      h = h.substring(0, h.length() - 1);
    }
    Collection<List<?>> sans = leaf.getSubjectAlternativeNames();
    if (sans == null) {
      return false;
    }
    for (List<?> san : sans) {
      if (((Integer) san.get(0)) != 2) {
        continue;
      }
      String c = ((String) san.get(1)).toLowerCase(Locale.ROOT);
      if (c.equals(h)) {
        return true;
      }
      int dot = h.indexOf('.');
      if (c.startsWith("*.") && dot > 0 && h.substring(dot + 1).equals(c.substring(2))) {
        return true;
      }
    }
    return false;
  }

  private static List<X509Certificate> decode(String[] chainB64)
      throws Exception {
    CertificateFactory cf = CertificateFactory.getInstance("X.509");
    List<X509Certificate> out = new ArrayList<>();
    for (String b64 : chainB64) {
      out.add((X509Certificate) cf.generateCertificate(
          new ByteArrayInputStream(Base64.getDecoder().decode(b64))));
    }
    return out;
  }

  private synchronized TaskSink sinkFor(TaskInputOutputContext<?, ?, ?, ?> context)
      throws IOException {
    if (closed) {
      throw new IOException("receipt files already closed for this attempt");
    }
    if (sink == null) {
      if (context == null) {
        throw new IOException("task mode needs the task context");
      }
      sink = new TaskSink(conf, context);
    }
    return sink;
  }

  /**
   * Close this attempt's receipt files. Called by the fetch task before it
   * returns, so the files are complete when the task commits.
   */
  public static synchronized void close() {
    if (instance == null) {
      return;
    }
    synchronized (instance) {
      closed = true;
      if (instance.sink != null) {
        try {
          instance.sink.close();
        } catch (IOException e) {
          markFailed("closing receipt files", e);
        } finally {
          instance.sink = null;
        }
      }
    }
    if (failure != null) {
      // fail the attempt: its receipts or outcomes are incomplete
      throw new IllegalStateException("custody receipt writes failed: " + failure);
    }
  }

  /**
   * One file of receipts and one of handshake evidence per task attempt, in
   * the attempt's work output path. Canonical JSON has no newlines, so each
   * line is exactly one canonical document. Evidence is written once per TLS
   * connection: fetches over a reused connection share it.
   */
  private static final class TaskSink {
    private final FileSystem fs;
    private final org.apache.hadoop.fs.Path dir;
    private final String attempt;
    private final FSDataOutputStream receipts;
    private FSDataOutputStream handshakes;
    private final FSDataOutputStream outcomes;
    private final Set<String> evidenceSeen = new HashSet<>();

    TaskSink(Configuration conf, TaskInputOutputContext<?, ?, ?, ?> context)
        throws IOException {
      org.apache.hadoop.fs.Path work;
      try {
        work = FileOutputFormat.getWorkOutputPath(context);
      } catch (InterruptedException e) {
        Thread.currentThread().interrupt();
        throw new IOException("interrupted while locating the task output path", e);
      }
      if (work == null) {
        throw new IOException("no work output path for this task");
      }
      dir = new org.apache.hadoop.fs.Path(work, "tc_receipts");
      fs = dir.getFileSystem(conf);
      attempt = context.getTaskAttemptID().toString();
      receipts = fs.create(
          new org.apache.hadoop.fs.Path(dir, "receipts-" + attempt + ".jsonl"), false);
      outcomes = fs.create(
          new org.apache.hadoop.fs.Path(dir, "outcomes-" + attempt + ".jsonl"), false);
      LOG.info("Training Custody receipts -> {}", dir);
    }

    synchronized void write(byte[] receipt, byte[] evidence, String evidenceHash)
        throws IOException {
      // evidence first, so a receipt never names evidence that was not written
      if (evidence != null && evidenceSeen.add(evidenceHash)) {
        if (handshakes == null) {
          handshakes = fs.create(new org.apache.hadoop.fs.Path(dir,
              "handshakes-" + attempt + ".jsonl"), false);
        }
        handshakes.write(evidence);
        handshakes.write('\n');
      }
      receipts.write(receipt);
      receipts.write('\n');
    }

    synchronized void writeOutcome(byte[] line) throws IOException {
      outcomes.write(line);
      outcomes.write('\n');
    }

    synchronized void close() throws IOException {
      receipts.close();
      outcomes.close();
      if (handshakes != null) {
        handshakes.close();
      }
    }
  }

  /** The JDK's CA store, ${java.home}/lib/security/cacerts. */
  private static Set<TrustAnchor> loadJdkAnchors() throws Exception {
    java.io.File f = new java.io.File(System.getProperty("java.home"),
        "lib/security/cacerts");
    java.security.KeyStore ks = java.security.KeyStore.getInstance(f,
        "changeit".toCharArray());
    Set<TrustAnchor> out = new HashSet<>();
    for (Enumeration<String> e = ks.aliases(); e.hasMoreElements();) {
      Certificate c = ks.getCertificate(e.nextElement());
      if (c instanceof X509Certificate) {
        out.add(new TrustAnchor((X509Certificate) c, null));
      }
    }
    if (out.isEmpty()) {
      throw new IllegalStateException("no trust anchors in " + f);
    }
    return out;
  }

  /**
   * Policy bytes. A plain path is read from the local disk (the measured
   * image); a path with a scheme (file://, hdfs://) through Hadoop.
   */
  private static byte[] readPolicy(Configuration conf, String location)
      throws IOException {
    if (location == null) {
      throw new IOException("tc.policy.file is not set");
    }
    if (java.net.URI.create(location).getScheme() == null) {
      // a plain path is local: the policy shipped in the measured image, so
      // it is covered by the measurement (not the cluster's default file system)
      return Files.readAllBytes(Paths.get(location));
    }
    org.apache.hadoop.fs.Path p = new org.apache.hadoop.fs.Path(location);
    FileSystem fs = p.getFileSystem(conf);
    try (InputStream in = fs.open(p)) {
      return in.readAllBytes();
    }
  }

  /**
   * The SHA-256 of the canonical JSON list of the sorted, distinct SHA-256s of
   * every anchor certificate (as make_policy.py computes it) must equal the
   * policy's trust_anchors.anchor_set_sha256. Otherwise receipts would name a
   * policy whose roots are not the ones actually used: refuse to start.
   */
  static void checkAnchorsMatchPolicy(Set<TrustAnchor> anchors, byte[] policy)
      throws Exception {
    Set<String> hashes = new HashSet<>();
    for (TrustAnchor t : anchors) {
      hashes.add(sha256(t.getTrustedCert().getEncoded()).substring("sha256:".length()));
    }
    List<String> sorted = new ArrayList<>(hashes);
    Collections.sort(sorted);
    StringBuilder list = new StringBuilder("[");
    for (int i = 0; i < sorted.size(); i++) {
      list.append(i == 0 ? "" : ",").append('"').append(sorted.get(i)).append('"');
    }
    list.append(']');
    String actual = sha256(list.toString().getBytes(StandardCharsets.UTF_8));
    java.util.regex.Matcher m = java.util.regex.Pattern
        .compile("\"anchor_set_sha256\":\"(sha256:[0-9a-f]{64})\"")
        .matcher(new String(policy, StandardCharsets.UTF_8));
    if (!m.find()) {
      throw new IllegalStateException("policy has no trust_anchors.anchor_set_sha256");
    }
    if (!m.group(1).equals(actual)) {
      throw new IllegalStateException("trust anchors (" + hashes.size()
          + ", set " + actual + ") do not match the collection policy ("
          + m.group(1) + ")");
    }
  }

  private static Set<TrustAnchor> loadAnchors(Path pem) throws Exception {
    CertificateFactory cf = CertificateFactory.getInstance("X.509");
    Set<TrustAnchor> out = new HashSet<>();
    try (InputStream in = Files.newInputStream(pem)) {
      for (Certificate c : cf.generateCertificates(in)) {
        out.add(new TrustAnchor((X509Certificate) c, null));
      }
    }
    if (out.isEmpty()) {
      throw new IllegalStateException("no trust anchors in " + pem);
    }
    return out;
  }

  /** Self-computed hash of the jar holding this class. A claim, as in the POC. */
  private static String selfHash() {
    try {
      Path p = Paths.get(CustodyReceipt.class.getProtectionDomain()
          .getCodeSource().getLocation().toURI());
      if (Files.isRegularFile(p)) {
        return sha256(Files.readAllBytes(p));
      }
    } catch (Exception e) {
      // fall through
    }
    return "sha256:unknown";
  }

  /** sha256(data), for callers that cannot handle the checked exception. */
  public static String sha256Hex(byte[] data) {
    try {
      return sha256(data);
    } catch (NoSuchAlgorithmException e) {
      throw new IllegalStateException(e);
    }
  }

  static String sha256(byte[] data) throws NoSuchAlgorithmException {
    byte[] d = MessageDigest.getInstance("SHA-256").digest(data);
    StringBuilder sb = new StringBuilder("sha256:");
    for (byte b : d) {
      sb.append(String.format("%02x", b));
    }
    return sb.toString();
  }

  /** Canonical JSON (TcCanonical, identical to custody/canonical.py). */
  static String canonical(Object v) {
    return TcCanonical.encodeString(v);
  }
}
