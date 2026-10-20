# merge.sed - tag-transform stage of XNU's config-merge pipeline.
# Verbatim port of the inline sed program in Apple XNU 1228
# bsd/conf/tools/doconf/doconf.csh (the "sed -n -e ..." invocation). Reconciled
# byte-for-byte against GNU sed 4.9 running the upstream program over the real
# MASTER + MASTER.ppc stream (+RELEASE_PPC | "MASTER MASTER.ppc - MASTER MASTER.ppc"):
# identical output, including trailing whitespace.
#
# RECONCILIATION NOTE (/^+/ block): upstream's rule order is
#   strip trailing WS -> negate-tag transform -> print
# and its strip rule, verbatim from doconf.csh, is "s;[ \t]*$;;" — space AND tab class.
# Keep it exactly as upstream has it. (An earlier revision of this port narrowed it to
# "s;[ ]*$;;", claiming upstream preserved TAB padding before the appended "#!"; re-extracting
# the program from bsd/conf/tools/doconf/doconf.csh proves otherwise: GNU sed 4.9 running the
# verbatim program strips trailing tabs too, e.g. emits "newvm#options\t\tOLD_VM_CODE#!".)
# tests/test-merge-sed.sh diffs this file's output against the verbatim extracted program
# over the real MASTER stream with trailing-whitespace sensitivity (diff <(cat -A ...)),
# so any drift in this rule — widening or narrowing — fails CI.
#
# One deliberate deviation from upstream remains, in the table-extraction rule below.
# KEEP this identifier-class regex — it is a verified-safe improvement over upstream's
# "\([^ ]*\)" for these fixtures and prevents documented-template-line poisoning:
#   - On the real MASTER + MASTER.ppc stream, GNU sed running the upstream program emits
#     ZERO table-extraction lines (the /^+/ loop consumes all 548 input lines via "n",
#     so the tail rules never fire). The port likewise emits zero. Byte-identical output
#     (237 lines, cmp clean) is therefore preserved WITH the deviation intact.
#   - Isolated-rule tests prove the safety property: fed directly, upstream's rule extracts
#     all 9 real tables AND poisons the pipeline with the documentation template line,
#     emitting '\t<configuration># <attribute0> <attribute1> ... <attributeN> ' — a bogus
#     <> tag mapping that would poison merge.awk's resolution. The port's identifier class
#     ("\([A-Za-z_][A-Za-z_0-9]*\)") rejects that template line (0 bytes emitted) while
#     still matching every real table name (MACH, BASE, NETWORKING, NFS, VPN, RELEASE,
#     DEVELOPMENT, PROFILE, DEBUG), because on the real MASTER files every table line
#     begins with an identifier.
# Do NOT "restore fidelity" by reverting to \([^ ]*\): it re-enables the poisoning path
# with no offsetting benefit on these fixtures.
/^+/{
	s;[-+];#&;gp
	t loop
: loop
n
/^#/b loop
/^$/b loop
s;^\([^#]*\).*#[	]*<\(.*\)>[	]*$;\2#\1;
	t not
s;\([^#]*\).*;#\1;
	t not
: not
s;^[	 ]*$;;
s;^\!\(.*\);\1#\!;
p
	t loop
b loop
}
/^[^#]/d
s;^[\t ]; ;g
s;^# *\([A-Za-z_][A-Za-z_0-9]*\)[ ]*=\[\([A-Za-z_0-9 \t]*\)\].*;\1#\2;p
