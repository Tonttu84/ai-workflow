#!/usr/bin/env python3
"""Checks a decision log (docs/decisions.md) and lists its due rechecks.

Usage:
  decisions.py check --base <ref> [--file docs/decisions.md]
  decisions.py due [--file docs/decisions.md] [--today YYYY-MM-DD] [--session]

check reads the file at <ref> and at HEAD from git objects, not from the
working tree. It fails when a row that exists at <ref> is changed or
missing at HEAD (rows are found by their ID and compared byte for byte;
new rows and a new order are fine), and when a new row with the Meta
field "instruction" quotes no owner: no cell holds Owner, an optional
"(where)", then ': "' and some words in straight quotes. A file missing
at <ref> makes every row new.
  Exit status: 0 passed, 1 problems (one line each on stderr, naming the
  row), 2 it could not run (not a git repository, unknown ref, no such
  file at HEAD, a table it cannot read, a duplicate or empty ID).

due prints, whole, every row whose Meta has "recheck YYYY-MM-DD" on or
before today, unless a later row cleared it: the later row's Decision
cell names its ID and that row has a recheck of its own (it took the
recheck over), or the Decision cell says "Rechecked <ID>" (the recheck
was done). A row that only names the ID ("Applies D5") clears nothing.
  Exit status: 0 whether or not anything is due, 1 a recheck date is
  malformed (each is named on stderr; due rows are still printed),
  2 bad arguments or no such file.
With --session (for a Claude Code SessionStart hook) it prints a heading
and one short line per due row, nothing when nothing is due or there is
no such file, and always exits 0.

Python 3.10 or later, standard library only.
"""

from __future__ import annotations

import argparse
import datetime
import os
import posixpath
import re
import subprocess
import sys
from dataclasses import dataclass
from typing import Optional

PROG = "decisions.py"
DEFAULT_FILE = "docs/decisions.md"
GIT_TIMEOUT = 60
SESSION_WIDTH = 100

TABLE_LINE = re.compile(r"[ \t]*\|")
SEPARATOR = re.compile(r"[ \t]*\|[ \t:|-]*")
CELL_BREAK = re.compile(r"(?<!\\)\|")
DATE = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}")
OWNER_QUOTE = re.compile(r'(?<!\w)Owner(?:[ \t]*\([^)]*\))?: "[ \t]*[^\s"][^"]*"')
NEVER_REWRITE = "never rewrite an old row; add a new row that names it"


class CannotRun(Exception):
    """The tool could not look: exit status 2."""


# --- the log, parsed once into typed values


def strip_cr(line: str) -> str:
    return line[:-1] if line.endswith("\r") else line


@dataclass(frozen=True)
class Row:
    """A table row, with the raw line it came from (without its \\n).

    id and decision are None when the table has no such column, and ""
    when the row is too short to reach it. meta holds the Meta cell's
    fields, split on the middle dot; it is None when the table has no
    Meta column or the row is too short, () when the cell is blank."""

    line_no: int
    raw: str
    cells: tuple
    id: Optional[str]
    decision: Optional[str]
    meta: Optional[tuple]

    @property
    def text(self) -> str:
        return strip_cr(self.raw)


@dataclass(frozen=True)
class Table:
    line_no: int
    header: tuple
    has_separator: bool
    rows: tuple


def split_cells(line: str) -> tuple:
    """The cells of a table row; an escaped \\| stays inside its cell."""
    inner = re.sub(r"^[ \t]*\|", "", line)
    inner = re.sub(r"\|[ \t]*$", "", inner)
    return tuple(part.strip(" \t") for part in CELL_BREAK.split(inner))


def cell_at(cells: tuple, header: tuple, name: str) -> Optional[str]:
    if name not in header:
        return None
    index = header.index(name)
    return cells[index] if index < len(cells) else ""


def meta_of(cells: tuple, header: tuple) -> Optional[tuple]:
    if "Meta" not in header or header.index("Meta") >= len(cells):
        return None
    cell = cells[header.index("Meta")]
    return tuple(field.strip() for field in cell.split("·")) if cell else ()


def make_row(line_no: int, raw: str, header: tuple) -> Row:
    cells = split_cells(strip_cr(raw))
    return Row(
        line_no=line_no,
        raw=raw,
        cells=cells,
        id=cell_at(cells, header, "ID"),
        decision=cell_at(cells, header, "Decision"),
        meta=meta_of(cells, header),
    )


def is_separator(raw: str) -> bool:
    return SEPARATOR.fullmatch(strip_cr(raw)) is not None


def make_table(block: list) -> Table:
    """A table from its (line number, raw line) pairs, header first."""
    first_no, first = block[0]
    header = split_cells(strip_cr(first))
    rest = block[1:]
    has_separator = bool(rest) and is_separator(rest[0][1])
    rows = tuple(make_row(no, raw, header) for no, raw in rest
                 if not is_separator(raw))
    return Table(first_no, header, has_separator, rows)


def split_lines(text: str) -> list:
    """The lines, split on \\n alone, so a row keeps every other byte."""
    lines = text.split("\n")
    return lines[:-1] if lines and lines[-1] == "" else lines


def parse_log(text: str) -> tuple:
    """Every table in the text, in order: a table is a run of lines that
    start with a pipe, its first line the header."""
    tables, block = [], []
    for line_no, raw in enumerate(split_lines(text), start=1):
        if TABLE_LINE.match(raw):
            block.append((line_no, raw))
        elif block:
            tables.append(make_table(block))
            block = []
    if block:
        tables.append(make_table(block))
    return tuple(tables)


def all_rows(tables) -> list:
    return [r for table in tables for r in table.rows]


def decode(data: bytes, name: str) -> str:
    try:
        return data.decode("utf-8-sig")
    except UnicodeDecodeError as error:
        raise CannotRun(f"{name} is not UTF-8 text: {error}") from None


# --- check: the rows by ID, compared with the base


def id_tables(text: str, where: str) -> list:
    """The tables with an ID column; refuses a log it cannot read."""
    tables = [t for t in parse_log(text) if "ID" in t.header]
    if not tables:
        raise CannotRun(f"{where}: no table with an ID column")
    for table in tables:
        if not table.has_separator:
            raise CannotRun(f"{where}:{table.line_no}: no separator row "
                            "under the table's header")
    return tables


def rows_by_id(text: str, where: str) -> dict:
    rows = {}
    for r in all_rows(id_tables(text, where)):
        if not r.id:
            raise CannotRun(f"{where}:{r.line_no}: a row without an ID")
        if r.id in rows:
            raise CannotRun(f"{where}:{r.line_no}: duplicate ID {r.id} "
                            f"(also on line {rows[r.id].line_no})")
        rows[r.id] = r
    return rows


def is_instruction(r: Row) -> bool:
    return r.meta is not None and "instruction" in r.meta


def quotes_owner(r: Row) -> bool:
    return any(OWNER_QUOTE.search(cell) for cell in r.cells)


def rewritten(base: dict, head: dict, base_ref: str) -> list:
    problems = []
    for rid, old in base.items():
        new = head.get(rid)
        if new is None:
            problems.append(f"{rid}: removed (line {old.line_no} at "
                            f"{base_ref}); {NEVER_REWRITE}")
        elif new.raw != old.raw:
            problems.append(f"{rid}: changed since {base_ref} (line "
                            f"{new.line_no}); {NEVER_REWRITE}")
    return problems


def unquoted(base: dict, head: dict) -> list:
    return [f"{rid}: a new instruction row that quotes no owner (line "
            f'{r.line_no}); hold their words as Owner: "<words>"'
            for rid, r in head.items()
            if rid not in base and is_instruction(r) and not quotes_owner(r)]


def check_rows(base: dict, head: dict, base_ref: str) -> list:
    """The problems, one line each: old rows rewritten or removed, then
    new instruction rows without the owner's words."""
    return rewritten(base, head, base_ref) + unquoted(base, head)


# --- check: reading git objects


def git(*args: str) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(["git", *args], capture_output=True,
                              stdin=subprocess.DEVNULL, timeout=GIT_TIMEOUT)
    except FileNotFoundError:
        raise CannotRun("git is not on PATH") from None
    except subprocess.TimeoutExpired:
        raise CannotRun(f"git {args[0]} took over {GIT_TIMEOUT} s") from None


def git_out(failure: str, *args: str) -> bytes:
    done = git(*args)
    if done.returncode != 0:
        detail = done.stderr.decode("utf-8", "replace").strip()
        raise CannotRun(f"{failure}: {detail}" if detail else failure)
    return done.stdout


def repo_path(file: str) -> str:
    """The file's path from the top of the repository, with slashes."""
    prefix = git_out("not a git repository", "rev-parse", "--show-prefix")
    if os.path.isabs(file):
        top = git_out("no working tree", "rev-parse", "--show-toplevel")
        top = os.path.realpath(top.decode("utf-8").strip())
        try:
            path = os.path.relpath(os.path.realpath(file), top)
        except ValueError:
            raise CannotRun(f"{file} is outside the repository") from None
    else:
        path = os.path.join(prefix.decode("utf-8").strip(), file)
    path = posixpath.normpath(path.replace(os.sep, "/"))
    if path in (".", "..") or path.startswith("../"):
        raise CannotRun(f"{file} is outside the repository")
    return path


def commit_of(ref: str) -> str:
    if ref.startswith("-"):
        raise CannotRun(f"not a commit: {ref}")
    done = git("rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}")
    if done.returncode != 0:
        raise CannotRun(f"not a commit: {ref}")
    return done.stdout.decode("ascii").strip()


def read_blob(commit: str, path: str) -> Optional[bytes]:
    """The file's bytes at the commit, or None when it has no such file."""
    listing = git_out(f"cannot list {commit}", "ls-tree", "-z", "--full-tree",
                      commit, "--", path)
    if not listing:
        return None
    entry = listing.split(b"\0")[0]
    kind, sha = entry.split(b"\t")[0].split(b" ")[1:3]
    if kind != b"blob":
        raise CannotRun(f"{path} at {commit[:12]} is not a file")
    return git_out(f"cannot read {path}", "cat-file", "blob", sha.decode())


def run_check(base_ref: str, file: str) -> int:
    path = repo_path(file)
    head_commit, base_commit = commit_of("HEAD"), commit_of(base_ref)
    head_data = read_blob(head_commit, path)
    if head_data is None:
        raise CannotRun(f"no such file at HEAD: {file}")
    head = rows_by_id(decode(head_data, file), f"{file} at HEAD")
    base_data = read_blob(base_commit, path)
    base = {} if base_data is None else rows_by_id(
        decode(base_data, file), f"{file} at {base_ref}")
    problems = check_rows(base, head, base_ref)
    for problem in problems:
        print(f"{PROG}: {file}: {problem}", file=sys.stderr)
    return 1 if problems else 0


# --- due: rechecks that no later row has named


@dataclass(frozen=True)
class Recheck:
    row: Row
    text: str
    date: Optional[datetime.date]


def parse_date(text: str) -> Optional[datetime.date]:
    if not DATE.fullmatch(text):
        return None
    try:
        return datetime.date.fromisoformat(text)
    except ValueError:
        return None


def recheck_text(r: Row) -> Optional[str]:
    """What follows the first Meta field that starts with the word recheck."""
    for field in r.meta or ():
        word, _, rest = field.partition(" ")
        if word == "recheck":
            return rest.strip()
    return None


def clears(later: Row, rid: str) -> bool:
    """The later row clears rid's recheck: its Decision cell says
    "Rechecked <rid>", or names rid and the row has a recheck of its own,
    which takes the recheck over. Only naming it ("Applies D5") clears
    nothing, and the phrase is matched as written, capital R."""
    escaped = re.escape(rid)
    decision = later.decision or ""
    if re.search(rf"(?<!\w)Rechecked {escaped}(?!\w)", decision):
        return True
    return (recheck_text(later) is not None
            and re.search(rf"(?<!\w){escaped}(?!\w)", decision) is not None)


def cleared_later(rows: list, index: int) -> bool:
    rid = rows[index].id
    return bool(rid) and any(clears(later, rid) for later in rows[index + 1:])


def rechecks(tables) -> list:
    rows = all_rows(tables)
    found = []
    for index, r in enumerate(rows):
        text = recheck_text(r)
        if text is not None and not cleared_later(rows, index):
            found.append(Recheck(r, text, parse_date(text)))
    return found


def due_and_malformed(text: str, today: datetime.date) -> tuple:
    found = rechecks(parse_log(text))
    due = [c for c in found if c.date is not None and c.date <= today]
    return due, [c for c in found if c.date is None]


def read_file(file: str) -> str:
    try:
        with open(file, "rb") as handle:
            return decode(handle.read(), file)
    except (FileNotFoundError, IsADirectoryError, NotADirectoryError):
        raise CannotRun(f"no such file: {file}") from None
    except OSError as error:
        raise CannotRun(f"cannot read {file}: {error.strerror}") from None


def run_due(file: str, today: datetime.date) -> int:
    due, malformed = due_and_malformed(read_file(file), today)
    for c in malformed:
        print(f'{PROG}: {file}:{c.row.line_no}: malformed recheck date: '
              f'"{c.text}"', file=sys.stderr)
    for c in due:
        print(c.row.text)
    return 1 if malformed else 0


# --- due --session: a short note for the start of a session


def shorten(text: str, width: int) -> str:
    text = " ".join(text.split())
    return text if len(text) <= width else text[:width - 3].rstrip() + "..."


def session_lines(file: str, due: list, malformed: list) -> list:
    if not due and not malformed:
        return []
    lines = [f"Decisions due for a recheck in {file} (a new row clears one "
             "when its Decision says \"Rechecked <ID>\", or names the ID "
             "and has its own recheck):"]
    for c in due:
        label = c.row.id or f"line {c.row.line_no}"
        lines.append(f"- {label} (recheck {c.text}): "
                     f"{shorten(c.row.decision or '', SESSION_WIDTH)}")
    for c in malformed:
        label = c.row.id or f"line {c.row.line_no}"
        lines.append(f'- {label}: malformed recheck date "{c.text}"')
    return lines


def run_session(file: str, today: datetime.date) -> int:
    """Never fails: a session must start whatever the log holds."""
    if not os.path.isfile(file):
        return 0
    try:
        due, malformed = due_and_malformed(read_file(file), today)
        lines = session_lines(file, due, malformed)
    except Exception as error:  # noqa: BLE001 - the hook must exit 0
        lines = [f"{PROG}: could not list the rechecks in {file}: {error}"]
    for line in lines:
        print(line)
    return 0


# --- arguments


def today_arg(text: str) -> datetime.date:
    date = parse_date(text)
    if date is None:
        raise argparse.ArgumentTypeError(
            f"today must be a date like 2026-11-16, not '{text}'")
    return date


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog=PROG, description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    check = commands.add_parser("check", help="no old row rewritten, "
                                "new instruction rows quote the owner")
    check.add_argument("--base", required=True, metavar="REF")
    check.add_argument("--file", default=DEFAULT_FILE)
    due = commands.add_parser("due", help="the rows due for a recheck")
    due.add_argument("--file", default=DEFAULT_FILE)
    due.add_argument("--today", type=today_arg, metavar="YYYY-MM-DD")
    due.add_argument("--session", action="store_true",
                     help="a short note for a SessionStart hook; exits 0")
    return parser


def dispatch(args: argparse.Namespace) -> int:
    if args.command == "check":
        return run_check(args.base, args.file)
    today = args.today or datetime.date.today()
    if args.session:
        return run_session(args.file, today)
    return run_due(args.file, today)


def main(argv: Optional[list] = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return dispatch(args)
    except CannotRun as error:
        print(f"{PROG}: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    # UTF-8 and \n on every platform: Windows would write cp1252 and CRLF.
    for stream in (sys.stdout, sys.stderr):
        stream.reconfigure(encoding="utf-8", newline="\n")
    sys.exit(main())
