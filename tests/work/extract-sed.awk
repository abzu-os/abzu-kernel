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
