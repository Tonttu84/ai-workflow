# junit-cases.awk: reads one JUnit XML report (Vitest, Playwright, pytest
# and cargo-nextest write them) and prints tab-separated records:
#
#   C <status> <name>   per <testcase>: status pass, skip or fail (a
#                       <failure> or <error> in it), and its name
#                       attribute with the XML entities decoded
#   O <count>           failures and errors outside every testcase: a
#                       <failure> or <error> element there, or the largest
#                       errors= plus failures= of a <testsuite(s)> tag,
#                       whichever is more (a suite that failed to load)
#   E <message>         instead of everything else, when the report is
#                       empty, not JUnit, or not complete (the runner did
#                       not finish writing it)
#
# Comments, CDATA sections and processing instructions are skipped, and
# a ">" inside a quoted attribute does not end a tag. Used by
# check-test-count.sh and check-trace-links.sh.
function problem(msg) { if (!err) printf "E\t%s\n", msg; err = 1 }
# join(a, lo, hi): a[lo] a[lo + 1] ... a[hi], joined half by half, so the
# copying stays O(n log n) in an awk that copies on every concatenation
function join(a, lo, hi,    mid) {
  if (lo > hi) return ""
  if (lo == hi) return a[lo]
  mid = int((lo + hi) / 2)
  return join(a, lo, mid) join(a, mid + 1, hi)
}
# strip(s, start, re, end): s without every start...end section (re is
# start as a regular expression); a start inside a section is part of
# it. Linear: one split, then one search per piece.
function strip(s, start, re, end,    n, i, j, piece) {
  n = split(s, piece, re)
  for (i = 2; i <= n; i++) {
    # Every piece after the first begins inside a section.
    if ((j = index(piece[i], end)) > 0) piece[i] = substr(piece[i], j + length(end))
    else if (i < n) piece[i] = "" # the section goes on past the next start
    else { problem("an unclosed " start " section: the runner did not finish writing it"); n = i - 1 }
  }
  return join(piece, 1, n)
}
# tag_end(s): where the tag that s starts with ends, quotes respected
function tag_end(s,    i, n, c, q) {
  n = length(s)
  q = ""
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (q != "") { if (c == q) q = "" }
    else if (c == "\"" || c == "'") q = c
    else if (c == ">") return i
  }
  return 0
}
# attr(tag, key): the value of the attribute in the tag text, decoded
function attr(tag, key,    v) {
  if (!match(tag, "[ \t\n]" key "[ \t\n]*=[ \t\n]*(\"[^\"]*\"|'[^']*')")) return ""
  v = substr(tag, RSTART, RLENGTH)
  sub(/^[^=]*=[ \t\n]*/, "", v)
  v = substr(v, 2, length(v) - 2)
  gsub(/&lt;/, "<", v)
  gsub(/&gt;/, ">", v)
  gsub(/&quot;/, "\"", v)
  gsub(/&apos;/, "'", v)
  gsub(/&#10;|&#xA;|&#xa;/, " ", v)
  gsub(/[\t\n]/, " ", v)
  gsub(/&amp;/, "\\&", v)
  return v
}
# suite_counts(s): the largest errors= plus failures= of the testsuite and
# testsuites tags in s
function suite_counts(s,    i, k, e, tag, n, best, part) {
  best = 0
  k = split(s, part, "<testsuite")
  for (i = 2; i <= k; i++) {
    e = tag_end(part[i])
    if (e == 0) continue
    tag = substr(part[i], 1, e)
    n = attr(tag, "errors") + attr(tag, "failures")
    if (n > best) best = n
  }
  return best
}
{ sub(/\r$/, ""); line[++lines] = $0 "\n" }
END {
  s = join(line, 1, lines)
  s = strip(s, "<![CDATA[", "<![[]CDATA[[]", "]]>")
  s = strip(s, "<!--", "<!--", "-->")
  s = strip(s, "<?", "<[?]", "?>")
  sub(/^[ \t\n]+/, "", s)
  sub(/[ \t\n]+$/, "", s)
  if (s == "") problem("is empty")
  else if (s !~ /^<testsuites?[ \t\n\/>]/) problem("has no <testsuites> or <testsuite> root: not a JUnit report")
  else {
    root = s ~ /^<testsuites[ \t\n\/>]/ ? "testsuites" : "testsuite"
    closed = substr(s, length(s) - length(root) - 2) == "</" root ">"
    empty = tag_end(s) == length(s) && substr(s, length(s) - 1) == "/>" # <testsuites/>
    if (!closed && !empty) problem("is not closed: the runner did not finish writing it")
  }
  if (err) exit
  n = split(s, part, "<testcase")
  out[++o] = part[1] # what is outside every testcase
  for (i = 2; i <= n; i++) {
    p = part[i]
    if (substr(p, 1, 1) !~ /[ \t\n\/>]/) { out[++o] = "<testcase" p; continue } # a longer tag name
    e = tag_end(p)
    if (e == 0) { problem("a <testcase> tag is not closed"); exit }
    tag = substr(p, 1, e)
    name = attr(tag, "name")
    if (substr(p, e - 1, 1) == "/") { cases[++m] = "pass\t" name; out[++o] = substr(p, e + 1); continue } # <testcase .../>
    k = index(p, "</testcase>")
    if (k == 0) { problem("a <testcase> is never closed"); exit }
    body = substr(p, e + 1, k - e - 1)
    out[++o] = substr(p, k + length("</testcase>"))
    if (body ~ /<skipped[ \t\n\/>]/) cases[++m] = "skip\t" name
    else if (body ~ /<(failure|error)[ \t\n\/>]/) cases[++m] = "fail\t" name
    else cases[++m] = "pass\t" name
  }
  for (i = 1; i <= m; i++) printf "C\t%s\n", cases[i]
  outside = join(out, 1, o)
  loose = gsub(/<(failure|error)[ \t\n\/>]/, "&", outside)
  attrs = suite_counts(outside)
  printf "O\t%d\n", (loose > attrs) ? loose : attrs
}
