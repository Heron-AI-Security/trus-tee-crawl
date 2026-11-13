#!/usr/bin/env bash
# Phase 4: the VM reports on itself, because a locked image has no login. Every TC_REPORT_INTERVAL seconds it writes a report of what an outsider may check
# (login absent, firewall loaded, units, listeners, the fleet event, the crawl) and publishes it as the guest attribute tc/report; the first report and every tenth
# one also go to the console (the serial port), which can be read without logging in. It reports failures too: it does not depend on the fleet unit.
# Hooks for the rehearsal only: TC_RUN, TC_META, TC_REPORT_INTERVAL, TC_REPORT_ONCE, TC_MODE_FILE.
set -uo pipefail
RUN="${TC_RUN:-/run/tc}"; META="${TC_META:-http://169.254.169.254/computeMetadata/v1}"; INTERVAL="${TC_REPORT_INTERVAL:-30}"; ONCE="${TC_REPORT_ONCE:-0}"; MODEF="${TC_MODE_FILE:-/etc/tc/image-mode}"; CLOG="${TC_CRAWL_LOG:-/var/log/hadoop/tc-crawl.log}"; HLOGS="${TC_HADOOP_LOGS:-/var/log/hadoop}"
md() { curl -sf -m 5 -H 'Metadata-Flavor: Google' "$META/$1" 2>/dev/null || true; }
yn() { "$@" >/dev/null 2>&1 && echo yes || echo no; }
tree_state() { case ",$(findmnt -no OPTIONS -T "$1" 2>/dev/null | head -1)," in ,,) echo unknown;; *,ro,*) echo ro;; *) echo rw;; esac; }   # ro only if the mount that holds this path is read-only; unknown if the mount table cannot be read
n=0
report() {
  mkdir -p "$RUN"; local f="$RUN/report.txt"
  {
    echo "report_time=$(date -u +%FT%TZ)"; echo "name=$(md instance/name)"; echo "image=$(md instance/image | sed 's#.*/##')"; echo "mode=$(cat "$MODEF" 2>/dev/null || echo unknown)"; echo "kernel=$(uname -r)"; echo "hostname=$(hostname)"
    echo "openssh_server_installed=$(yn dpkg -s openssh-server)"; echo "guest_agent_installed=$(yn dpkg -s google-guest-agent)"; echo "oslogin_installed=$(yn dpkg -s google-compute-engine-oslogin)"
    echo "port22_listening=$(ss -ltnH 2>/dev/null | awk '$4 ~ /:22$/' | wc -l)"
    echo "serial_getty=$(systemctl is-enabled serial-getty@ttyS0.service 2>&1 | head -1)"
    for d in usr etc opt boot root; do echo "tree_$d=$(tree_state "/$d")"; done   # work item, change 1: a locked image must say ro for all five
    echo "input_policy=$(nft list chain inet tc input 2>/dev/null | grep -o 'policy [a-z]*' | head -1)"
    echo "nft_rules_sha=$(nft list ruleset 2>/dev/null | sha256sum | cut -c1-16)"
    echo "failed_units=$(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}' | tr '\n' ',')"   # --plain: without it the first column of a failed unit is a bullet
    for u in tc-measure tc-fleet tc-namenode tc-datanode tc-resourcemanager tc-nodemanager tc-crawl; do echo "unit_$u=$(systemctl is-active $u.service 2>&1 | head -1)/$(systemctl show $u.service -p Result --value 2>/dev/null)"; done
    echo "crawl_marker=$(head -c 160 /var/lib/tc-crawl/done 2>/dev/null | tr '\n' ' ')"
    # a locked VM has no login, so the reason of a failure must be in the report: the last line of the crawl log, and the last ERROR or FATAL line of the Hadoop logs (the last 200 KB of each)
    echo "crawl_last=$(tail -n 1 "$CLOG" 2>/dev/null | tr -d '\r' | tr '\t' ' ' | cut -c1-200)"
    echo "hadoop_last_error=$(for f in "$HLOGS"/*.log; do [ -f "$f" ] && tail -c 200000 "$f"; done 2>/dev/null | grep -aE ' (ERROR|FATAL) ' | tail -n 1 | tr -d '\r' | tr '\t' ' ' | cut -c1-220)"
    echo "fleet_done=$(cat "$RUN/fleet-done" 2>/dev/null)"; echo "fleet_event=$(awk -F'\t' '$1=="fleet" {print $2}' "$RUN/rtmr3-events.tsv" 2>/dev/null)"
    echo "wg_peers=$(wg show wg0 peers 2>/dev/null | wc -l)"; echo "listeners=$(ss -ltnH 2>/dev/null | awk '{print $4}' | sort | tr '\n' ' ')"
  } > "$f"
  curl -sf -m 10 -X PUT -H 'Metadata-Flavor: Google' --data-binary @"$f" "$META/instance/guest-attributes/tc/report" >/dev/null 2>&1 || echo "note: could not publish the report as a guest attribute"
  if [ $((n % 10)) -eq 0 ]; then echo "TC-REPORT-BEGIN"; cat "$f"; echo "TC-REPORT-END"; fi
  n=$((n+1))
}
while true; do report; [ "$ONCE" = 1 ] && exit 0; sleep "$INTERVAL"; done
