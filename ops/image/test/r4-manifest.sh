#!/usr/bin/env bash
# Step R4.0, READ-ONLY, on a booted VM of an image: the GROUND TRUTH of what the image measures. For every line of the measured list (NAME PATH [SKIPS]) it writes the manifest
# that the measurement hashes (the same treehash.sh, so the digest is the very value that tc-measure would extend), and it records the packages, the boot files and the kernel.
# It writes only into OUTDIR (default /tmp/r4-out) and changes nothing else.
#   sudo bash r4-manifest.sh [OUTDIR]
# Settings (environment; the defaults are the real ones): R4_LIST (/etc/tc/measured-paths.txt), R4_TREEHASH (/usr/local/lib/tc/treehash.sh), R4_PKGS (1: also the package list and the files that
# packages own, which the comparison needs to tell packages from our own files; 0 skips them), R4_ROOT (a prefix for every listed path: the rehearsal only).
set -uo pipefail
export LC_ALL=C
OUT="${1:-/tmp/r4-out}"; ROOT="${R4_ROOT:-}"; LIST="${R4_LIST:-/etc/tc/measured-paths.txt}"; TH="${R4_TREEHASH:-/usr/local/lib/tc/treehash.sh}"; PKGS="${R4_PKGS:-1}"
die() { echo "R4-MANIFEST-FAILED: $*" >&2; exit 1; }
[ -r "$LIST" ] || die "no measured list at $LIST"; [ -r "$TH" ] || die "no treehash at $TH"
rm -rf "$OUT"; mkdir -p "$OUT/manifests" || die "cannot create $OUT"
: > "$OUT/events.tsv"; n=0; entries=0
while IFS=$'\t' read -r name path skips; do
  case "$name" in ''|'#'*) continue ;; esac
  t="$ROOT$path"
  if [ -d "$t" ]; then
    # shellcheck disable=SC2086
    line="$(MANIFEST="$OUT/manifests/$name.manifest" bash "$TH" "$t" ${skips:-})" || die "treehash failed on $t"
    digest="$(awk '/^TREE-DIGEST/ {print $2}' <<<"$line")"; cnt="$(wc -l < "$OUT/manifests/$name.manifest")"; kind=dir
  elif [ -f "$t" ]; then
    digest="$(sha384sum "$t" | cut -d' ' -f1)"; cnt=1; kind=file
    printf 'F %s %s %s\n' "$(stat -c %a "$t")" "$digest" "$path" > "$OUT/manifests/$name.manifest"
  else die "the listed path does not exist: $t"; fi
  [ "${#digest}" -eq 96 ] || die "no 96-character digest for $name (got '$digest')"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$digest" "$cnt" "$kind" "$path" "${skips:-}" >> "$OUT/events.tsv"
  n=$((n+1)); entries=$((entries+cnt)); echo "   $name: $kind, $cnt entries, ${digest:0:16}..."
done < "$LIST"
[ "$n" -ge 1 ] || die "the list measured nothing"
cp "$LIST" "$OUT/measured-paths.txt"
[ -f "$ROOT/etc/tc/source.txt" ] && cp "$ROOT/etc/tc/source.txt" "$OUT/source.txt"   # the commit that the image records (step R4.2)
# size and time of every file of every folder event: not part of the digest, but they say WHY two builds differ (the same size and another hash is a timestamp or an ordering)
: > "$OUT/files-meta.tsv"
while IFS=$'\t' read -r name digest cnt kind path skips; do
  [ "$kind" = dir ] || continue
  grep '^F ' "$OUT/manifests/$name.manifest" | awk -v p="${path%/}" '{ sub(/^F [0-7]+ [0-9a-f]+ \.\//, ""); print p "/" $0 }' | while IFS= read -r f; do
    t="$ROOT$f"; printf '%s\t%s\t%s\n' "$f" "$(stat -c %s "$t" 2>/dev/null || echo -)" "$(stat -c %Y "$t" 2>/dev/null || echo -)"
  done >> "$OUT/files-meta.tsv"
done < "$OUT/events.tsv"
{ echo "# uname -r"; uname -r; echo "# /etc/os-release"; cat "$ROOT/etc/os-release" 2>/dev/null; echo "# /proc/cmdline"; cat /proc/cmdline 2>/dev/null; } > "$OUT/os.txt"
: > "$OUT/boot-files.sha256"; for f in "$ROOT"/boot/vmlinuz-* "$ROOT"/boot/initrd.img-tc "$ROOT"/boot/efi/EFI/ubuntu/grub.cfg; do [ -f "$f" ] && sha256sum "$f" >> "$OUT/boot-files.sha256"; done
if [ "$PKGS" = 1 ]; then
  dpkg-query -W -f='${Package}\t${Version}\t${Architecture}\n' 2>/dev/null | sort > "$OUT/packages.tsv" || die "dpkg-query failed"
  cat "$ROOT"/var/lib/dpkg/info/*.list 2>/dev/null | sort -u > "$OUT/dpkg-files.txt"
  echo "   packages: $(wc -l < "$OUT/packages.tsv"), files that packages own: $(wc -l < "$OUT/dpkg-files.txt")"
fi
( cd "$OUT" && find . -type f ! -name SHA256SUMS | sort | xargs sha256sum > SHA256SUMS ) || die "could not write SHA256SUMS"
echo; echo "R4-MANIFEST-OK events=$n entries=$entries out=$OUT"
