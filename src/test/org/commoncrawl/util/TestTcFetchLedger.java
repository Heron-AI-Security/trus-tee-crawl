package org.commoncrawl.util;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

import org.junit.jupiter.api.Test;

/** Tests of the custody bookkeeping: the content limit and the one-outcome-per-URL rule. */
public class TestTcFetchLedger {

  @Test
  public void testNegativeContentLimitIsUnlimited() {
    // the bug: with http.content.limit=-1 every page counted as truncated, and a truncated page gets no receipt
    assertFalse(TcFetchLedger.limitReached(0, -1));
    assertFalse(TcFetchLedger.limitReached(5_000_000, -1));
    assertFalse(TcFetchLedger.limitReached(Integer.MAX_VALUE, -1));
    assertFalse(TcFetchLedger.limitReached(10, Integer.MIN_VALUE));
  }

  @Test
  public void testContentLimitStillTruncates() {
    int limit = 1024 * 1024;
    assertFalse(TcFetchLedger.limitReached(limit - 1, limit));
    assertTrue(TcFetchLedger.limitReached(limit, limit));
    assertTrue(TcFetchLedger.limitReached(limit + 1, limit));
    assertTrue(TcFetchLedger.limitReached(0, 0));
  }

  @Test
  public void testFinishedUrlIsNotSwept() {
    TcFetchLedger l = new TcFetchLedger();
    l.begun("https://a.example/");
    assertEquals(1, l.inFlightCount());
    assertTrue(l.claim("https://a.example/"));
    assertEquals(0, l.inFlightCount());
    assertTrue(l.sweep().isEmpty());
  }

  @Test
  public void testUnfinishedUrlsAreSweptSorted() {
    TcFetchLedger l = new TcFetchLedger();
    for (String u : new String[] {"https://b.example/", "https://a.example/", "https://c.example/"}) {
      l.begun(u);
    }
    assertTrue(l.claim("https://b.example/"));
    assertEquals(Arrays.asList("https://a.example/", "https://c.example/"), l.sweep());
    assertTrue(l.sweep().isEmpty());
  }

  @Test
  public void testLateWriteAfterTheSweepIsRefused() {
    TcFetchLedger l = new TcFetchLedger();
    l.begun("https://slow.example/");
    assertEquals(Collections.singletonList("https://slow.example/"), l.sweep());
    // the thread finishes after close(): its URL already has the shutdown outcome
    assertFalse(l.claim("https://slow.example/"));
  }

  @Test
  public void testUrlThatWasNeverBegunCanStillGetItsOutcome() {
    // notAttempted: dropped from a queue before any thread took it
    TcFetchLedger l = new TcFetchLedger();
    assertTrue(l.claim("https://dropped.example/"));
    l.sweep();
    assertTrue(l.claim("https://dropped-later.example/"));
  }

  @Test
  public void testBeginAfterTheSweepIsIgnored() {
    TcFetchLedger l = new TcFetchLedger();
    l.sweep();
    l.begun("https://late.example/");
    assertEquals(0, l.inFlightCount());
    assertTrue(l.sweep().isEmpty());
  }

  @Test
  public void testExactlyOneOutcomePerUrlWhenThreadsRaceTheSweep() throws Exception {
    for (int round = 0; round < 40; round++) {
      final TcFetchLedger l = new TcFetchLedger();
      final int n = 400;
      final List<String> urls = new ArrayList<>();
      for (int i = 0; i < n; i++) {
        String u = "https://h" + (i % 7) + ".example/p" + i;
        urls.add(u);
        l.begun(u);
      }
      final Map<String, Boolean> claimed = new ConcurrentHashMap<>();
      List<Thread> threads = new ArrayList<>();
      for (int t = 0; t < 8; t++) {
        final int off = t;
        Thread th = new Thread(() -> {
          for (int i = off; i < n; i += 8) {
            claimed.put(urls.get(i), l.claim(urls.get(i)));
          }
        });
        threads.add(th);
      }
      for (Thread th : threads) {
        th.start();
      }
      for (int spin = 0; spin < round * 50; spin++) {
        Thread.yield();
      }
      List<String> swept = l.sweep();
      for (Thread th : threads) {
        th.join();
      }
      for (String u : urls) {
        int outcomes = (claimed.get(u) ? 1 : 0) + (swept.contains(u) ? 1 : 0);
        assertEquals(1, outcomes, "exactly one outcome for " + u);
      }
    }
  }
}
