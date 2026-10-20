#!/usr/bin/env bash
# tests/test-merge-sed.sh - regression test: scripts/merge.sed vs GNU sed running
# the VERBATIM upstream sed program extracted from XNU 1228 bsd/conf/tools/doconf/doconf.csh,
# over the real MASTER + MASTER.ppc stream, with trailing-whitespace sensitivity.
# All diffs use `cat -A` so tabs/spaces are visible and byte-significant.
#   [1] extraction sanity  [2] sed-stage diff  [3] awk-stage diff  [4] template-poison guard
# The stream is materialized as a REGULAR FILE (never process substitution: sed's 'n'
# at EOF has been observed to spin when stdin is not a regular file).
# Env: XNU_SRC=/path/to/xnu-xnu-1228 to skip fetching.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF="$REPO/tests/work"; XNU_TAG="xnu-1228"
say(){ printf '[test-merge-sed] %s\n' "$*"; }
die(){ printf '[test-merge-sed] FAIL: %s\n' "$*" >&2; exit 1; }
mkdir -p "$CONF"

if [ -n "${XNU_SRC:-}" ]; then
    [ -d "$XNU_SRC" ] || die "XNU_SRC=$XNU_SRC does not exist"; XNU_DIR="$XNU_SRC"
else
    XNU_DIR="$CONF/$XNU_TAG"
    if [ ! -f "$XNU_DIR/bsd/conf/MASTER" ]; then
        say "fetching $XNU_TAG tarball..."
        curl -fsSL --retry 3 -o "$CONF/xnu.tar.gz" \
            "https://github.com/apple-oss-distributions/xnu/archive/refs/tags/$XNU_TAG.tar.gz"
        tar -xzf "$CONF/xnu.tar.gz" -C "$CONF"
    fi
fi
MASTER="$XNU_DIR/bsd/conf/MASTER"; MASTER_CPU="$XNU_DIR/bsd/conf/MASTER.ppc"
DOCONF="$XNU_DIR/bsd/conf/tools/doconf/doconf.csh"
for f in "$MASTER" "$MASTER_CPU" "$DOCONF"; do [ -f "$f" ] || die "missing fixture: $f"; done

UPSTREAM_SED="$CONF/upstream.sed"; EXTRACT_AWK="$CONF/extract-sed.awk"
cat > "$EXTRACT_AWK" << 'AWK_EOF'
# Extracts the sed program from doconf.csh's multi-line `sed -n \` invocation.
# Byte-faithful: trim ONLY indent up to "-e ", drop trailing continuation (" \"),
# remove exactly ONE pair of surrounding quotes. Backslash unescaping is done in
# CORRECT awk order: first collapse escaped-slash "\/" -> "/", then "\\" -> "\".
BEGIN { q = "'" }
/^[ \t]*sed[ \t]+-n[ \t]+\\[ \t]*$/ { insed = 1; next }
insed {
    line = $0
    if (line !~ /^[ \t]*-e[ \t]/) { insed = 0; next }
    sub(/^[ \t]*-e[ \t]+/, "", line)
    sub(/[ \t]*\\[ \t]*$/, "", line)
    gsub(/\\\//, "/", line)        # csh escaped slash "\/" -> "/"   (FIXED: was /\\\\\//)
    gsub(/\\\\/, "\\", line)       # escaped backslash "\\" -> "\"   (FIXED: was /\\\\\\/ ...)
    if (substr(line, 1, 1) == "\"" && substr(line, length(line), 1) == "\"")
        line = substr(line, 2, length(line) - 2)
    else if (substr(line, 1, 1) == q && substr(line, length(line), 1) == q)
        line = substr(line, 2, length(line) - 2)
    print line > OUT
}
AWK_EOF
rm -f "$UPSTREAM_SED"
awk -v OUT="$UPSTREAM_SED" -f "$EXTRACT_AWK" "$DOCONF"
[ -s "$UPSTREAM_SED" ] || die "extraction produced empty program"
grep -qF 's;^\!\(.*\);\1#\!;' "$UPSTREAM_SED" \
    || die "extracted program lost the negate-tag rule"
TABRULES=$(grep -cP '\[\t' "$UPSTREAM_SED" || true)
[ "${TABRULES:-0}" -ge 2 ] \
    || die "extracted program lost literal TAB bytes inside char classes ($TABRULES, want >=2)"
say "extracted $(wc -l < "$UPSTREAM_SED") rules, $TABRULES with literal-TAB classes"

STREAM="$CONF/stream.txt"
{ echo +RELEASE_PPC; cat "$MASTER" "$MASTER_CPU" /dev/null "$MASTER" "$MASTER_CPU"; } > "$STREAM"
say "stream: $(wc -l < "$STREAM") lines"

OUT_UP="$CONF/out.upstream.txt"; OUT_PORT="$CONF/out.merge.sed.txt"
timeout 60 sed -n -f "$UPSTREAM_SED" "$STREAM" > "$OUT_UP"
timeout 60 sed -n -f "$REPO/scripts/merge.sed" "$STREAM" > "$OUT_PORT"
if ! diff <(cat -A "$OUT_UP") <(cat -A "$OUT_PORT") > "$CONF/sedstage.diff"; then
    head -20 "$CONF/sedstage.diff" >&2
    die "FAIL [2]: sed-stage trailing-whitespace drift (see $CONF/sedstage.diff)"
fi
say "PASS [2]: sed-stage byte-identical ($(wc -l < "$OUT_UP") lines)"

UPSTREAM_AWK="$CONF/upstream.awk"; EXTRACT_AWK2="$CONF/extract-awk.awk"
cat > "$EXTRACT_AWK2" << 'AWK_EOF'
BEGIN { q = "'" }
awkgrab {
    if ($0 == q "\\") { awkgrab = 0; next }
    sub(/[ \t]*\\[ \t]*$/, "")
    print > OUT
}
index($0, "awk '-F#'") {
    line = $0
    sub(/^.*-F#'/, "", line)
    sub(/[ \t]*\\[ \t]*$/, "", line)
    print line > OUT
    awkgrab = 1
}
AWK_EOF
rm -f "$UPSTREAM_AWK"
awk -v OUT="$UPSTREAM_AWK" -f "$EXTRACT_AWK2" "$DOCONF"
[ -s "$UPSTREAM_AWK" ] || die "could not extract upstream awk program"

FIN_UP="$CONF/final.upstream.txt"; FIN_PORT="$CONF/final.merge.sed.txt"
timeout 60 sh -c "sed -n -f '$UPSTREAM_SED' '$STREAM' | awk -F# -f '$UPSTREAM_AWK'" > "$FIN_UP"
timeout 60 sh -c "sed -n -f '$REPO/scripts/merge.sed' '$STREAM' | awk -F# -f '$REPO/scripts/merge.awk'" > "$FIN_PORT"
if ! diff <(cat -A "$FIN_UP") <(cat -A "$FIN_PORT") > "$CONF/awkstage.diff"; then
    head -20 "$CONF/awkstage.diff" >&2
    die "FAIL [3]: pipeline divergence through merge.awk"
fi
say "PASS [3]: final merged config byte-identical ($(wc -l < "$FIN_UP") lines)"

TAIL_UP="$CONF/tail-upstream.sed"; TAIL_PORT="$CONF/tail-port.sed"
grep '^s;\^# ' "$UPSTREAM_SED" > "$TAIL_UP"
grep '^s;\^# ' "$REPO/scripts/merge.sed" > "$TAIL_PORT"
TPL="$CONF/template.txt"
printf '%s\n' \
    '# BASE = [ machdep cpu_at macos ]' \
    '# MACH = [ base ]' \
    '# NETWORKING = [ bsdnet nfsclient ]' \
    '# <configuration> = [ <attribute0> <attribute1> ... <attributeN> ]' \
    > "$TPL"
U_OUT=$(sed -n -f "$TAIL_UP" "$TPL"); P_OUT=$(sed -n -f "$TAIL_PORT" "$TPL")
[ "$(printf '%s\n' "$U_OUT" | grep -c '#')" -eq 4 ] || die "unexpected upstream tail behavior"
printf '%s\n' "$P_OUT" | grep -qF '<' && die "FAIL [4]: identifier-class deviation reverted"
[ "$(printf '%s\n' "$P_OUT" | grep -c '#')" -eq 3 ] || die "FAIL [4]: port dropped real tables"
say "PASS [4]: port rejects documented-template line, keeps real tables"
say "ALL CHECKS PASSED"
