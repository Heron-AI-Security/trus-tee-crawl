package org.commoncrawl.util;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/**
 * Training Custody: the bookkeeping behind "every URL of the fetch list gets
 * exactly one outcome" (step P5.6 part B of the verifier plan). It has no
 * Hadoop or Nutch type, so that it can be tested alone.
 *
 * A fetch thread that takes a URL from its queue calls {@link #begun}. When an
 * outcome is written for the URL, {@link #claim} is called first. A thread that
 * never finishes (the fetcher's time limit, a hung thread) leaves its URL in
 * the in-flight set, and {@link #sweep} at the end of the task returns those
 * URLs, so that each of them gets a "not fetched, timeout" outcome. A thread
 * that finishes after the sweep finds its URL swept: {@link #claim} says no, so
 * the URL never gets a second outcome.
 */
final class TcFetchLedger {

  private final Object lock = new Object();
  private final Set<String> inFlight = new HashSet<>();
  private final Set<String> swept = new HashSet<>();
  private boolean closed;

  /**
   * http.content.limit: a negative value means unlimited, as everywhere in
   * Nutch. The test "length >= limit" alone treats every page as truncated when
   * the limit is -1, and a truncated page gets no receipt.
   */
  static boolean limitReached(int length, int limit) {
    return limit >= 0 && length >= limit;
  }

  /** A fetch thread took this URL from its queue. */
  void begun(String url) {
    synchronized (lock) {
      if (!closed) {
        inFlight.add(url);
      }
    }
  }

  /**
   * An outcome is about to be written for this URL. Returns false when the URL
   * already got its outcome at shutdown (a late write): the caller must not
   * write a second one.
   */
  boolean claim(String url) {
    synchronized (lock) {
      if (swept.contains(url)) {
        return false;
      }
      inFlight.remove(url);
      return true;
    }
  }

  /**
   * The end of the task: the URLs that started and never finished, sorted, each
   * owed one outcome. Calling it again returns an empty list.
   */
  List<String> sweep() {
    synchronized (lock) {
      closed = true;
      List<String> urls = new ArrayList<>(inFlight);
      Collections.sort(urls);
      swept.addAll(urls);
      inFlight.clear();
      return urls;
    }
  }

  int inFlightCount() {
    synchronized (lock) {
      return inFlight.size();
    }
  }
}
