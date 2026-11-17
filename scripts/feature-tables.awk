# feature-tables.awk: reads one feature file (templates/feature.md) and
# prints one tab-separated record per thing found, with its line number:
#
#   T <line> <Level column> <Test column>   an item table header (0 when
#                                           the column is missing)
#   I <line> <ID> <Rev> <Level> <Test>      an item row; cells trimmed, as
#                                           written
#   X <line> <message>                      a row that cannot be read
#   W <line> <value>                        a Walkthrough: line, trimmed
#   L <line> <value>                        a Locked tests: line, trimmed
#   K <line> <text>                         a line that looks like a Locked
#                                           tests: line (any case, any
#                                           Markdown decoration) but does
#                                           not start with exactly that;
#                                           text trimmed
#
# A table is a header row and a delimiter row with the same number of
# cells, as in GitHub Markdown; the outer pipes are optional. Its rows are
# the lines after it that hold a "|", up to the first line that does not.
# "\|" in a cell is not a column break. An item table is one whose first
# two header cells are ID and Rev. A line that looks like an item row
# (its first cell is F<n>-<n>) anywhere else is an X: in another table,
# in pipe lines that are not a table, or right after a table without its
# pipes.
# The same text is in hooks/check-walkthrough, between its BEGIN and END
# feature-tables.awk lines; tests/check-walkthrough.test.sh checks that
# the two match.
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
# cells(row): splits a row into cell[1..n] and returns n
function cells(row,    n, i, part) {
  split("", cell)
  gsub(/\\\|/, "\001", row)
  sub(/^[ \t]*\|/, "", row)
  sub(/\|[ \t]*$/, "", row)
  n = split(row, part, "|")
  for (i = 1; i <= n; i++) {
    gsub(/\001/, "|", part[i])
    gsub(/\t/, " ", part[i])
    cell[i] = trim(part[i])
  }
  return n
}
function delimiter(n,    i) {
  for (i = 1; i <= n; i++) if (cell[i] !~ /^:?-+:?$/) return 0
  return n > 0
}
function piped(s) { gsub(/\\\|/, "", s); return index(s, "|") > 0 }
function itemlike(s) { return s ~ /^F[0-9]+-[0-9]+$/ }
# loose(nr, text): a pipe line outside any table
function loose(nr, text) {
  cells(text)
  if (itemlike(cell[1]))
    printf "X\t%d\t\"%s\" looks like an item row, but it is not in an item table (a header with ID and Rev first, then a delimiter row)\n", nr, cell[1]
}
FNR == 1 { intable = 0; pending = 0 }
{ sub(/\r$/, "") }
/^Walkthrough:/ { v = $0; sub(/^Walkthrough:/, "", v); printf "W\t%d\t%s\n", FNR, trim(v) }
/^Locked tests:/ { v = $0; sub(/^Locked tests:/, "", v); printf "L\t%d\t%s\n", FNR, trim(v) }
!/^Locked tests:/ && tolower($0) ~ /^[ \t>*+-]*([0-9]+[.)][ \t]*)?[*_`~ \t]*locked[ \t_-]*tests?[*_`~ \t]*:/ { printf "K\t%d\t%s\n", FNR, trim($0) }
intable && $0 ~ /^[ \t]*$/ { intable = 0; next }
intable && piped($0) {
  n = cells($0)
  if (!items) {
    if (itemlike(cell[1]))
      printf "X\t%d\t\"%s\" looks like an item row, but its table is not an item table (ID and Rev must be its first two columns)\n", FNR, cell[1]
    next
  }
  lv = (level && level <= n) ? cell[level] : ""
  ts = (testcol && testcol <= n) ? cell[testcol] : ""
  printf "I\t%d\t%s\t%s\t%s\t%s\n", FNR, cell[1], cell[2], lv, ts
  next
}
intable {
  intable = 0
  if (match(trim($0), /^F[0-9]+-[0-9]+/) && substr(trim($0), RLENGTH + 1, 1) !~ /[A-Za-z0-9-]/)
    printf "X\t%d\t\"%s\" right after a table is a row of it without pipes: write it with its pipes\n", FNR, trim($0)
}
!intable && piped($0) {
  n = cells($0)
  if (pending && delimiter(n) && n == headn) {
    pending = 0
    intable = 1
    cells(header)
    items = cell[1] == "ID" && cell[2] == "Rev"
    level = 0
    testcol = 0
    named = 0
    for (i = 1; i <= headn; i++) {
      if (i > 2 && cell[i] == "Level" && !level) level = i
      if (i > 2 && cell[i] == "Test" && !testcol) testcol = i
      if (cell[i] == "Item") named = 1
    }
    if (items) printf "T\t%d\t%d\t%d\n", headnr, level, testcol
    else if (named) printf "X\t%d\ta feature table with an Item column needs ID and Rev as its first columns\n", headnr
    next
  }
  if (pending) loose(headnr, header)
  pending = 1
  header = $0
  headnr = FNR
  headn = cells($0)
  next
}
{ if (pending) loose(headnr, header); pending = 0 }
END { if (pending) loose(headnr, header) }
