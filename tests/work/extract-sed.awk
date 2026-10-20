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
