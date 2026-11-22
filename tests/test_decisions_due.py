"""Tests for `decisions.py due`: the rows due for a recheck, without the
ones a later row with a recheck of its own names in its Decision cell,
and the session line."""

from __future__ import annotations

import time

from conftest import ROOT, log, row, run_script

# The fixture of tests/decisions-due.test.sh, for the same cases here.
BASH_FIXTURE = """\
# Decisions

Meta: date · authority · evidence · reversibility · recheck YYYY-MM-DD.

| ID | Decision | Reason | Chosen against | Meta |
| --- | --- | --- | --- | --- |
| D1 | Old row, written before Meta | why | none |
| D2 | Blank Meta | why | none |  |
| D3 | Past | why | none | 2026-01-01 · agent · research normal HIGH (docs/research/a.md) · two-way · recheck 2026-06-01 |
| D4 | Due today | why | none | 2026-01-01 · instruction · none · one-way · recheck 2026-11-16 |
| D5 | Future | why | none | 2026-01-01 · agent · assumed · two-way · recheck 2026-11-17 |
| D6 | Says recheck 2020-01-01 in the decision only | why | none | 2026-01-01 · agent · none · two-way |
| D7 | A cell with an escaped \\| pipe | why | none | 2026-01-01 · agent · none · two-way · recheck 2026-02-01 |
| D8 | A report named recheck | why | none | 2026-01-01 · agent · research deep LOW (docs/research/recheck-limits.md) · two-way |

| Other table | Meta is not here | recheck 2020-01-01 |
| --- | --- | --- |
| x | y | recheck 2020-01-01 |
"""

D4_LINE = ("| D4 | Due today | why | none | 2026-01-01 · instruction · none"
           " · one-way · recheck 2026-11-16 |")


def recheck(date: str) -> str:
    return f"2026-11-16 · agent · none · two-way · recheck {date}"


def write(tmp_path, text, name="decisions.md"):
    path = tmp_path / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(text.encode("utf-8"))
    return path


def due(run, path, today):
    return run(path.parent, "due", "--file", str(path), "--today", today)


def printed_ids(out):
    return [line.split("|")[1].strip() for line in out.splitlines()]


# --- the cases of the bash test


def test_due_rows_are_printed_whole(run, tmp_path):
    status, out, err = due(run, write(tmp_path, BASH_FIXTURE), "2026-11-16")
    assert status == 0
    assert err == ""
    assert printed_ids(out) == ["D3", "D4", "D7"]
    assert D4_LINE in out.splitlines()


def test_nothing_due_prints_nothing(run, tmp_path):
    status, out, err = due(run, write(tmp_path, BASH_FIXTURE), "2026-01-31")
    assert (status, out, err) == (0, "", "")


def test_meta_is_found_by_its_header(run, tmp_path):
    text = ("| ID | Meta | Decision |\n| --- | --- | --- |\n"
            "| D1 | 2026-01-01 · agent · none · two-way · recheck 2026-02-01"
            " | moved column |\n")
    status, out, _ = due(run, write(tmp_path, text), "2026-11-16")
    assert status == 0
    assert "moved column" in out


def test_crlf_gives_the_same_rows_without_carriage_returns(tmp_path):
    path = write(tmp_path, BASH_FIXTURE.replace("\n", "\r\n"))
    done = run_script(tmp_path, "due", "--file", str(path),
                      "--today", "2026-11-16")
    assert done.returncode == 0
    assert b"\r" not in done.stdout
    assert done.stdout.decode("utf-8").count("\n") == 3
    assert "· recheck 2026-11-16 |\n" in done.stdout.decode("utf-8")


def test_the_default_file_and_date(run, tmp_path):
    write(tmp_path, log(
        row("D1", "Long past", meta=recheck("2000-01-02")),
        row("D2", "Far future", meta=recheck("2999-12-31")),
    ), name="docs/decisions.md")
    status, out, _ = run(tmp_path, "due")
    assert status == 0
    assert printed_ids(out) == ["D1"]


def test_malformed_dates_exit_1_and_still_print_the_due_rows(run, tmp_path):
    text = ("| ID | Decision | Reason | Chosen against | Meta |\n"
            "| --- | --- | --- | --- | --- |\n"
            + row("D1", "Month 13", meta=recheck("2026-13-01"))
            + row("D2", "A word", meta=recheck("soon"))
            + row("D3", "Short", meta=recheck("2026-1-5"))
            + row("D4", "No date", meta="2026-01-01 · agent · recheck")
            + row("D5", "Due and fine", meta=recheck("2026-02-01")))
    status, out, err = due(run, write(tmp_path, text, "malformed.md"),
                           "2026-11-16")
    assert status == 1
    for line_no in (3, 4, 5, 6):
        assert f"malformed.md:{line_no}:" in err
    assert printed_ids(out) == ["D5"]


def test_an_impossible_calendar_date_is_malformed(run, tmp_path):
    text = log(row("D1", meta=recheck("2026-02-30")))
    status, out, err = due(run, write(tmp_path, text), "2026-11-16")
    assert status == 1
    assert "2026-02-30" in err
    assert out == ""


def test_a_missing_file_exits_2_and_names_it(run, tmp_path):
    path = tmp_path / "no-such.md"
    status, _, err = due(run, path, "2026-11-16")
    assert status == 2
    assert str(path) in err


def test_no_default_file_exits_2(run, tmp_path):
    status, _, err = run(tmp_path, "due")
    assert status == 2
    assert "docs/decisions.md" in err


def test_bad_dates_for_today_are_refused(run, tmp_path):
    path = write(tmp_path, BASH_FIXTURE)
    for bad in ("2026-11-31x", "2026-1-16", "16.11.2026", "2026-13-01",
                "2026-11-32", "2026-02-30", "20261116", ""):
        assert due(run, path, bad)[0] == 2, bad


def test_the_template_reads_and_its_recheck_comes_due(run):
    template = ROOT / "templates" / "decisions.md"
    assert due(run, template, "2026-11-16") == (0, "", "")
    status, out, err = due(run, template, "2999-12-31")
    assert (status, err) == (0, "")
    assert "recheck" in out


# --- the skip rule


def test_a_row_a_later_decision_names_is_skipped(run, tmp_path):
    text = log(
        row("D93", "Entire: a one-month trial", meta=recheck("2026-12-16")),
        row("D99", "Something else"),
        row("D134", "The trial waits. D93's other terms stand. D93's "
            "`recheck 2026-12-16` no longer applies.",
            meta=recheck("2027-02-18")),
    )
    assert due(run, write(tmp_path, text), "2027-01-01") == (0, "", "")


def test_a_later_row_without_a_recheck_of_its_own_does_not_skip(run, tmp_path):
    text = log(
        row("D134", "The trial waits", meta=recheck("2027-02-18")),
        row("D135", "Entire's hooks stay local. Applies D134."),
    )
    status, out, _ = due(run, write(tmp_path, text), "2027-03-01")
    assert (status, printed_ids(out)) == (0, ["D134"])


def test_a_confirming_row_replaces_the_recheck(run, tmp_path):
    text = log(
        row("D100", "Deferred", meta=recheck("2026-11-16")),
        row("D116", "Confirms D100: deferred", meta=recheck("2027-02-16")),
    )
    status, out, _ = due(run, write(tmp_path, text), "2027-03-01")
    assert status == 0
    assert printed_ids(out) == ["D116"]


def test_a_mention_in_the_reason_cell_does_not_skip(run, tmp_path):
    text = log(
        row("D1", meta=recheck("2026-11-16")),
        row("D2", "Unrelated", reason="See D1", meta=recheck("2999-12-31")),
    )
    status, out, _ = due(run, write(tmp_path, text), "2026-11-16")
    assert printed_ids(out) == ["D1"]


def test_an_earlier_row_naming_it_does_not_skip(run, tmp_path):
    text = log(
        row("D1", "Before D2", meta=recheck("2999-12-31")),
        row("D2", meta=recheck("2026-11-16")),
    )
    status, out, _ = due(run, write(tmp_path, text), "2026-11-16")
    assert printed_ids(out) == ["D2"]


def test_a_longer_id_is_not_a_mention(run, tmp_path):
    text = log(
        row("D1", meta=recheck("2026-11-16")),
        row("D2", "Refines D10 and D1x", meta=recheck("2999-12-31")),
    )
    status, out, _ = due(run, write(tmp_path, text), "2026-11-16")
    assert printed_ids(out) == ["D1"]


def test_recheck_text_outside_meta_does_not_count(run, tmp_path):
    text = log(row("D1", "D0's `recheck 2026-12-16` no longer applies"))
    assert due(run, write(tmp_path, text), "2027-01-01") == (0, "", "")


def test_a_named_row_with_a_malformed_date_is_not_reported(run, tmp_path):
    text = log(
        row("D1", meta=recheck("soon")),
        row("D2", "Sets D1's recheck to 2027-01-01", meta=recheck("2027-01-01")),
    )
    assert due(run, write(tmp_path, text), "2026-11-16") == (0, "", "")


# --- the session line


def test_session_without_a_file_prints_nothing(run, tmp_path):
    assert run(tmp_path, "due", "--session") == (0, "", "")


def test_session_with_nothing_due_prints_nothing(run, tmp_path):
    write(tmp_path, log(row("D1", meta=recheck("2999-12-31"))),
          name="docs/decisions.md")
    assert run(tmp_path, "due", "--session") == (0, "", "")


def test_session_prints_a_heading_and_the_due_rows(run, tmp_path):
    long = "Entire: a one-month trial on one private solo repository " * 4
    write(tmp_path, log(
        row("D1", long, meta=recheck("2000-01-02")),
        row("D2", "Not due", meta=recheck("2999-12-31")),
        row("D3", "Withdrawn", meta=recheck("2000-01-02")),
        row("D4", "Replaces D3", meta=recheck("2999-12-31")),
    ), name="docs/decisions.md")
    status, out, err = run(tmp_path, "due", "--session")
    assert (status, err) == (0, "")
    lines = out.splitlines()
    assert len(lines) == 2
    assert "recheck" in lines[0]
    assert "D1" in lines[1]
    assert "2000-01-02" in lines[1]
    assert "Entire: a one-month trial" in lines[1]
    assert len(lines[1]) < 160


def test_session_exits_0_on_a_malformed_date(run, tmp_path):
    write(tmp_path, log(row("D1", meta=recheck("soon"))),
          name="docs/decisions.md")
    status, out, _ = run(tmp_path, "due", "--session")
    assert status == 0
    assert "D1" in out


def test_session_exits_0_on_an_unreadable_file(run, tmp_path):
    path = tmp_path / "docs" / "decisions.md"
    path.parent.mkdir()
    path.write_bytes(b"| ID | Meta |\n| --- | --- |\n| D1 | \xff\xfe |\n")
    assert run(tmp_path, "due", "--session")[0] == 0


def test_session_as_a_program_is_quick_and_exits_0(tmp_path):
    write(tmp_path, log(row("D1", "Päätös", meta=recheck("2000-01-02"))),
          name="docs/decisions.md")
    started = time.monotonic()
    done = run_script(tmp_path, "due", "--session")
    assert time.monotonic() - started < 5
    assert done.returncode == 0
    assert "Päätös" in done.stdout.decode("utf-8")
    assert b"\r" not in done.stdout


def test_the_live_log_skips_only_rechecks_a_later_row_moved(run):
    # D134 moved D93's recheck and D116 D100's; D137 ("Amends D116") and
    # D135 ("Applies D134") set none of their own.
    status, out, err = due(run, ROOT / "docs" / "decisions.md", "2027-03-01")
    assert (status, err) == (0, "")
    ids = printed_ids(out)
    assert "D93" not in ids
    assert "D100" not in ids
    assert "D116" in ids
    assert "D134" in ids
