# merge.sed - tag-transform stage of XNU's config-merge pipeline.
# Port of the inline sed program in Apple XNU 1228 bsd/conf/tools/doconf/doconf.csh.
# FIX vs. naive port: the table-extraction rule requires an identifier name so the
# documentation template line "<configuration> = [ <attribute0> ... ]" in MASTER can
# never inject a bogus empty/<> tag mapping that poisons merge.awk's resolution.
/^+/{
	s;[-+];#&;gp
	t loop
: loop
n
/^#/b loop
/^$/b loop
s;^\([^#]*\).*#[ \t]*<\(.*\)>[ \t]*$;\2#\1;
	t not
s;\([^#]*\).*;#\1;
	t not
: not
s;[ \t]*$;;
s;^\!\(.*\);\1#\!;
p
	t loop
b loop
}
/^[^#]/d
s;  ; ;g
s;^# *\([A-Za-z_][A-Za-z_0-9]*\)[ ]*=[ ]*\[\([A-Za-z_0-9 \t]*\)\].*;\1#\2;p
