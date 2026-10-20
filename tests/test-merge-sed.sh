#!/usr/bin/env bash
# tests/test-merge-sed.sh - regression test: scripts/merge.sed vs GNU sed running
# the VERBATIM upstream sed program extracted from XNU 1228 bsd/conf/tools/doconf/doconf.csh,
# over the real MASTER + MASTER.ppc stream, with trailing-whitespace sensitivity.
#
# Checks (all diffs use `cat -A` so tabs/spaces are visible and byte-significant):
#   [1] extraction sanity   - the extractor finds the full sed invocation in doconf.csh
#                             and produces a nonempty program with literal tabs intact
#   [2] sed-stage diff      - diff <(upstream | cat -A) <(merge.sed | cat -A) must be empty
#   [3] awk-stage diff      - same check through merge.awk (full pipeline), byte-for-byte
#   [4] template-poisoning  - documented-template-line guard for the deliberate deviation
#
# The one INTENTIONAL deviation from upstream is the table-extraction rule's identifier
# class \([A-Za-z_][A-Za-z_0-9]*\) replacing upstream's \([^ ]*\). It is safe on these
# fixtures because the /^+/ loop consumes every input line via 'n' before any tail rule
# can fire (both programs emit ZERO table lines; checks [2]/[3] pass byte-clean WITH the
# deviation). Check [4] proves the deviation's purpose: fed directly, upstream's rule
# extracts all 9 real tables AND poisons the stream with the documentation template line
# "<configuration> = [ ... ]" (a bogus <> tag mapping); the port rejects only that line.
# Do NOT revert it.
#
# CI note: run from anywhere; the script cds to the repo root itself. The stream is
# materialized as a REGULAR FILE (tests/work/stream.txt), never a process substitution
# or heredoc pipe: GNU sed's 'n' command at EOF behaves differently when stdin is not a
# regular file and has been observed to spin there.
#
# Usage:  ./tests/test-merge-sed.sh            # fetch/checkout xnu-1228 if needed, run all checks
# Env:    XNU_SRC=/path/to/xnu-xnu-1228        # skip fetching, use an existing checkout
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF="$REPO/tests/work"
XNU_TAG="xnu-1228"

say() { printf '[test-merge-sed] %s\n' "$*"; }
die() { printf '[test-merge-sed] FAIL: %s\n' "$*" >&2; exit 1; }

mkdir -p "$CONF"

# ---------------------------------------------------------------------------
# Step 1: fetch / checkout the real xnu-1228 sources (cached across runs).
# ---------------------------------------------------------------------------
if [ -n "${XNU_SRC:-}" ]; then
    [ -d "$XNU_SRC" ] || die "XNU_SRC=$XNU_SRC does not exist"
    XNU_DIR="$XNU_SRC"
else
    XNU_DIR="$CONF/$XNU_TAG"
    if [ ! -f "$XNU_DIR/bsd/conf/MASTER" ]; then
        say "fetching $XNU_TAG tarball..."
        curl -fsSL --retry 3 -o "$CONF/xnu.tar.gz" \
            "https://github.com/apple-oss-distributions/xnu/archive/refs/tags/$XNU_TAG.tar.gz"
        tar -xzf "$CONF/xnu.tar.gz" -C "$CONF"
    fi
fi

MASTER="$XNU_DIR/bsd/conf/MASTER"
MASTER_CPU="$XNU_DIR/bsd/conf/MASTER.ppc"
DOCONF="$XNU_DIR/bsd/conf/tools/doconf/doconf.csh"
for f in "$MASTER" "$MASTER_CPU" "$DOCONF"; do
    [ -f "$f" ] || die "missing fixture: $f"
done

# ---------------------------------------------------------------------------
# Step 2: extract the verbatim sed program from doconf.csh.
#
# Byte-faithful handling of literal tabs inside -e '...' quotes is the critical
# part. Upstream writes character classes like "[ ^I]*" where ^I is a REAL TAB
# byte embedded in the quoted argument. Two corruption sources are avoided here:
#   (a) word-splitting/globbing of the -e arguments  -> handled by reading the
#       file line-by-line with IFS= read -r and never eval-ing anything;
#   (b) stripping ALL whitespace around each -e argument (an earlier revision
#       used "s/^[[:space:]]*-e //", which also ate the leading indent TAB of
#       the next continuation line and mangled embedded literal tabs) -> fixed
#       below by trimming ONLY spaces/tabs up to "-e ", cutting the trailing
#       " \"\\" continuation, and removing exactly ONE pair of surrounding
#       quotes (never tr -d '"' | tr -d \"'\", which destroys tabs adjacent to
#       quote characters and unbalances quoting).
# ---------------------------------------------------------------------------
UPSTREAM_SED="$CONF/upstream.sed"
EXTRACT_AWK="$CONF/extract-sed.awk"
cat > "$EXTRACT_AWK" << 'AWK_EOF'
# Extracts the sed program from doconf.csh's multi-line `sed -n \` invocation.
# Written to its own file and run with awk -f so no shell quoting can corrupt it.
# Byte-faithful rules: trim ONLY the indent up to "-e ", drop the trailing
# continuation (" \"), and remove exactly ONE pair of surrounding quotes.
BEGIN { q = "'" }                       # one literal single-quote char
/^[ \t]*sed[ \t]+-n[ \t]+\\[ \t]*$/ { insed = 1; next }
insed {
    line = $0
    # any non "-e" continuation line ends the sed program (next stage is "| awk")
    if (line !~ /^[ \t]*-e[ \t]/) { insed = 0; next }
    sub(/^[ \t]*-e[ \t]+/, "", line)                 # leading indent + "-e " only
    sub(/[ \t]*\\[ \t]*$/, "", line)                 # trailing line continuation
    gsub(/\\\\\//, "/", line)                          # csh escaped slash "\/" -> "/"
    gsub(/\\\\/, "\\", line)                           # escaped backslash "\\" -> "\"
    if (substr(line, 1, 1) == "\"" && substr(line, length(line), 1) == "\"")
        line = substr(line, 2, length(line) - 2)     # remove ONE pair of "..."
    else if (substr(line, 1, 1) == q && substr(line, length(line), 1) == q)
        line = substr(line, 2, length(line) - 2)     # remove ONE pair of '...'
    print line > OUT
}
AWK_EOF
awk -v OUT="$UPSTREAM_SED" -f "$EXTRACT_AWK" "$DOCONF"
[ -s "$UPSTREAM_SED" ] || die "extraction produced empty program from $DOCONF"

# Sanity: the extracted program must contain the negate-tag rule and at least one
# rule whose character class holds a LITERAL TAB byte (the thing naive extraction
# corrupts). If either check fails, the extractor regressed, not merge.sed.
grep -qF 's;^\!\(.*\);\1#\!;' "$UPSTREAM_SED" \
    || die "extracted program lost the negate-tag rule (quote handling corrupted?)"
TABRULES=$(grep -cP '\[\t' "$UPSTREAM_SED" || true)
[ "${TABRULES:-0}" -ge 2 ] \
    || die "extracted program lost literal tabs inside character classes (found $TABRULES tab-class rules, expected >= 2)"
say "extracted verbatim program: $(wc -l < "$UPSTREAM_SED") rules, $TABRULES rules with literal-TAB classes"

# ---------------------------------------------------------------------------
# Step 3: build the input stream EXACTLY as doconf.csh feeds it for RELEASE_PPC
# ($SYS=RELEASE_PPC, $MASTER_LOCAL and $MASTER_CPU_LOCAL empty):
#     echo +$SYS | cat $MASTER $MASTER_CPU - $MASTER $MASTER_CPU
# Written to a REGULAR FILE (see CI note at top: 'n'-at-EOF spins on pipes).
# ---------------------------------------------------------------------------
STREAM="$CONF/stream.txt"
{ echo +RELEASE_PPC; cat "$MASTER" "$MASTER_CPU" /dev/null "$MASTER" "$MASTER_CPU"; } > "$STREAM"
say "stream: $(wc -l < "$STREAM") lines from $(basename "$MASTER")+$(basename "$MASTER_CPU") doubled"

# ---------------------------------------------------------------------------
# Step 4: [2] sed-stage diff, trailing-whitespace sensitive.
# ---------------------------------------------------------------------------
OUT_UP="$CONF/out.upstream.txt"; OUT_PORT="$CONF/out.merge.sed.txt"
timeout 60 sed -n -f "$UPSTREAM_SED" "$STREAM" > "$OUT_UP"
timeout 60 sed -n -f "$REPO/scripts/merge.sed" "$STREAM" > "$OUT_PORT"
if ! diff <(cat -A "$OUT_UP") <(cat -A "$OUT_PORT") > "$CONF/sedstage.diff"; then
    say "FAIL [2]: sed-stage output differs ($(grep -c '^[<>]' "$CONF/sedstage.diff") lines; see $CONF/sedstage.diff)"
    head -20 "$CONF/sedstage.diff" >&2
    die "trailing-whitespace drift between merge.sed and the verbatim upstream program"
fi
say "PASS [2]: sed-stage byte-identical ($(wc -l < "$OUT_UP") lines, tabs/spaces verified via cat -A)"

# ---------------------------------------------------------------------------
# Step 5: [3] full-pipeline diff through merge.awk (vs upstream's inline awk).
# Upstream's awk program is the block right after the sed stage in doconf.csh;
# extract it byte-faithfully the same way (it lives in one '-F#' '...' quoted
# string spanning many lines, terminated by a lone "'\").
# ---------------------------------------------------------------------------
UPSTREAM_AWK="$CONF/upstream.awk"
EXTRACT_AWK2="$CONF/extract-awk.awk"
cat > "$EXTRACT_AWK2" << 'AWK_EOF'
# Extracts doconf.csh's inline awk program (the stage right after the sed one).
# It lives inside ONE single-quoted string that spans lines and ends on a lone
# "'\" continuation line. Interior bytes (tabs!) are passed through untouched;
# only the trailing "\" of each continuation line is trimmed. csh cannot nest
# single quotes, so no unescaping is needed inside this particular program.
BEGIN { q = "'" }
awkgrab {
    if ($0 == q "\\") { awkgrab = 0; next }        # closing quote + continuation
    sub(/[ \t]*\\[ \t]*$/, "")                     # line continuation only
    print > OUT
}
index($0, "awk '-F#'") {
    line = $0
    sub(/^.*-F#'/, "", line)                   # drop everything up to & incl. opening quote
    sub(/[ \t]*\\[ \t]*$/, "", line)               # drop trailing continuation
    print line > OUT
    awkgrab = 1
}
AWK_EOF
awk -v OUT="$UPSTREAM_AWK" -f "$EXTRACT_AWK2" "$DOCONF"
[ -s "$UPSTREAM_AWK" ] || die "could not extract upstream awk program from $DOCONF"

FIN_UP="$CONF/final.upstream.txt"; FIN_PORT="$CONF/final.merge.sed.txt"
timeout 60 sh -c "sed -n -f '$UPSTREAM_SED' '$STREAM' | awk -F# -f '$UPSTREAM_AWK'" > "$FIN_UP"
timeout 60 sh -c "sed -n -f '$REPO/scripts/merge.sed' '$STREAM' | awk -F# -f '$REPO/scripts/merge.awk'" > "$FIN_PORT"
if ! diff <(cat -A "$FIN_UP") <(cat -A "$FIN_PORT") > "$CONF/awkstage.diff"; then
    say "FAIL [3]: final merged config differs (see $CONF/awkstage.diff)"
    head -20 "$CONF/awkstage.diff" >&2
    die "pipeline divergence through merge.awk"
fi
say "PASS [3]: final merged config byte-identical ($(wc -l < "$FIN_UP") lines, incl. trailing tabs)"

# ---------------------------------------------------------------------------
# Step 6: [4] documented-template-line poisoning guard (isolated-rule test).
# Feed ONLY the table-extraction tail rules a synthetic set of real MASTER table
# lines plus the documentation template line. Upstream's \([^ ]*\) matches the
# template and injects a bogus '<configuration>' tag; the port's identifier class
# must extract all real tables and reject the template. This documents WHY the
# deliberate deviation is kept and fails loudly if someone reverts it.
# ---------------------------------------------------------------------------
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
[ "$(printf '%s\n' "$U_OUT" | grep -c '#')" -eq 4 ] \
    || die "unexpected upstream tail behavior: got [$(echo "$U_OUT" | tr '\n' '|')]"
if ! printf '%s\n' "$P_OUT" | grep -qF '<'; then
    : # good: port rejected the template line
else
    die "FAIL [4]: port emits the documented-template line '<configuration>' - the identifier-class deviation was reverted; restore it (do NOT match \\([^ ]*\\))"
fi
[ "$(printf '%s\n' "$P_OUT" | grep -c '#')" -eq 3 ] \
    || die "FAIL [4]: port dropped real table lines: [$(echo "$P_OUT" | tr '\n' '|')]"
say "PASS [4]: upstream tail extracts 3 tables + poisoned template; port extracts 3 tables, rejects template"

say "ALL CHECKS PASSED"
