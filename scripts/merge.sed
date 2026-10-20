# merge.sed - tag-transform stage of XNU's config-merge pipeline.
#
# Verbatim extraction of the inline `sed -n -e ...` program from Apple's
# XNU 1228 source tree, bsd/conf/tools/doconf/doconf.csh (lines ~196-217).
# Upstream keeps this program inline inside the csh script; this file lets
# CI run the same pipeline without shell-quoting hell:
#
#   echo +SYS | cat MASTER ... - MASTER ... | sed -n -f merge.sed \
#       | awk -F# -f merge.awk > config.SYS_ID
#
# What it does: everything before the first "+CONFIG" marker line is
# consumed to build a lookup table (tag -> +/-); after the marker, each
# line is tagged with '#' plus its inclusion state so merge.awk can emit
# only the lines belonging to the requested configuration.

/^+/{
	s;[-+];#&;gp
	t loop
: loop
n
/^#/b loop
/^$/b loop
s;^\([^#]*\).*#[ 	]*<\(.*\)>[ 	]*$;\2#\1;
t not
s;\([^#]*\).*;#\1;
t not
: not
s;[ 	]*$;;
s;^\!\(.*\);\1#\!;
p
t loop
b loop
}
/^[^#]/d
s;  ; ;g
s;^# *\([^ ]*\)[ ]*=[ ]*\[\(.*\)\].*;\1#\2;p
