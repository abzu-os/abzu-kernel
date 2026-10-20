# merge.awk - tag-resolution/emission stage. Verbatim port of doconf.csh's inline awk,
# plus defensive skips for empty tag tokens so malformed table entries can't poison f[].
part == 0 && $1 != "" {
	m[$1]=m[$1] " " $2;
	next;
}
part == 0 && $1 == "" {
	for (i=NF;i>1;i--){
		s=substr($i,2);
		c[++na]=substr($i,1,1);
		a[na]=s;
	}
	while (na > 0){
		s=a[na];
		d=c[na--];
		if (s == "") continue;
		if (m[s] == "") {
			f[s]=d;
		} else {
			nx=split(m[s],x," ");
			for (j=nx;j>0;j--) {
				z=x[j];
				if (z == "") continue;
				a[++na]=z;
				c[na]=d;
			}
		}
	}
	part=1;
	next;
}
part != 0 {
	if ($1 != "") {
		n=split($1,x,",");
		ok=0;
		for (i=1;i<=n;i++) {
			if (f[x[i]] == "+") {
				ok=1;
			}
		}
		if (NF > 2 && ok == 0 || NF <= 2 && ok != 0) {
			print $2;
		}
	} else {
		print $2;
	}
}
