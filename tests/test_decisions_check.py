"""Tests for `decisions.py check`: old rows stay as they were, and a new
instruction row quotes the owner."""

from __future__ import annotations

from conftest import HEADER, log, row, run_script

D55_SHAPE = (
    "| D55 | Lint runs with `npx lizard . || true` until step 3 | why | — |\n"
)


def check(run, repo, base, *extra):
    return run(repo.path, "check", "--base", base, *extra)


def problem_lines(err):
    return [line for line in err.splitlines() if line]


# --- old rows


def test_an_unchanged_log_passes(run, repo):
    base = repo.commit(log(row("D1"), row("D2")))
    repo.commit(log(row("D1"), row("D2")), name="other.txt")
    status, out, err = check(run, repo, base)
    assert (status, out, err) == (0, "", "")


def test_a_new_row_passes(run, repo):
    base = repo.commit(log(row("D1")))
    repo.commit(log(row("D1"), row("D2")))
    assert check(run, repo, base)[0] == 0


def test_one_changed_character_fails_and_names_the_row(run, repo):
    base = repo.commit(log(row("D1"), row("D2", "Use pytest"), row("D3")))
    repo.commit(log(row("D1"), row("D2", "Use pytesT"), row("D3")))
    status, _, err = check(run, repo, base)
    assert status == 1
    lines = problem_lines(err)
    assert len(lines) == 1
    assert "D2" in lines[0]


def test_a_changed_trailing_space_fails(run, repo):
    base = repo.commit(log(row("D1")))
    repo.commit(log(row("D1").replace("|\n", "| \n")))
    assert check(run, repo, base)[0] == 1


def test_a_deleted_row_fails_and_names_it(run, repo):
    base = repo.commit(log(row("D1"), row("D2"), row("D3")))
    repo.commit(log(row("D1"), row("D3")))
    status, _, err = check(run, repo, base)
    assert status == 1
    assert len(problem_lines(err)) == 1
    assert "D2" in err


def test_every_problem_gets_its_own_line(run, repo):
    base = repo.commit(log(row("D1"), row("D2"), row("D3")))
    repo.commit(log(row("D1", "changed"), row("D3", "changed")))
    status, _, err = check(run, repo, base)
    assert status == 1
    lines = problem_lines(err)
    assert len(lines) == 3
    for rid in ("D1", "D2", "D3"):
        assert sum(rid in line for line in lines) == 1


def test_a_reordered_log_passes(run, repo):
    base = repo.commit(log(row("D1"), row("D2"), row("D3")))
    repo.commit(log(row("D3"), row("D1"), row("D2")))
    assert check(run, repo, base)[0] == 0


def test_the_working_tree_does_not_count(run, repo):
    base = repo.commit(log(row("D1"), row("D2")))
    repo.write(log(row("D1")))
    assert check(run, repo, base)[0] == 0


def test_a_changed_head_commit_fails_even_if_the_tree_is_restored(run, repo):
    base = repo.commit(log(row("D1"), row("D2")))
    repo.commit(log(row("D1")))
    repo.write(log(row("D1"), row("D2")))
    assert check(run, repo, base)[0] == 1


def test_a_row_with_more_cells_than_the_header_is_read(run, repo):
    base = repo.commit(log(row("D1"), D55_SHAPE))
    repo.commit(log(row("D1"), D55_SHAPE, row("D56")))
    assert check(run, repo, base)[0] == 0
    repo.commit(log(row("D1"), D55_SHAPE.replace("step 3", "step 4")))
    status, _, err = check(run, repo, base)
    assert status == 1
    assert "D55" in err


def test_a_row_written_before_meta_is_read(run, repo):
    old = "| D1 | Old | why | none |\n"
    base = repo.commit(log(old))
    repo.commit(log(old.replace("Old", "Older")))
    status, _, err = check(run, repo, base)
    assert status == 1
    assert "D1" in err


def test_an_escaped_pipe_is_part_of_the_cell(tool):
    tables = tool.parse_log(HEADER + "| D1 | a \\| b | why | none | m |\n")
    (only,) = tables[0].rows
    assert only.id == "D1"
    assert only.cells[1] == "a \\| b"


def test_a_crlf_change_counts_as_a_change(run, repo):
    base = repo.commit(log(row("D1")))
    repo.commit(log(row("D1")).replace("\n", "\r\n"))
    status, _, err = check(run, repo, base)
    assert status == 1
    assert "D1" in err


def test_another_file_can_be_named(run, repo):
    base = repo.commit(log(row("D1")), name="notes/log.md")
    repo.commit(log(), name="notes/log.md")
    assert check(run, repo, base, "--file", "notes/log.md")[0] == 1
    assert check(run, repo, base)[0] == 2


def test_an_absolute_file_path_is_read(run, repo):
    base = repo.commit(log(row("D1")))
    repo.commit(log())
    path = str(repo.path / "docs" / "decisions.md")
    assert check(run, repo, base, "--file", path)[0] == 1


def test_it_runs_from_a_subdirectory(run, repo):
    base = repo.commit(log(row("D1")))
    repo.commit(log())
    status, _, _ = run(repo.path / "docs", "check", "--base", base,
                       "--file", "decisions.md")
    assert status == 1


# --- it cannot run: exit 2, never a pass


def test_a_duplicate_id_exits_2(run, repo):
    base = repo.commit(log(row("D1")))
    repo.commit(log(row("D1"), row("D2"), row("D2", "again")))
    status, _, err = check(run, repo, base)
    assert status == 2
    assert "D2" in err


def test_a_duplicate_id_at_the_base_exits_2(run, repo):
    base = repo.commit(log(row("D1"), row("D1", "again")))
    repo.commit(log(row("D1")))
    assert check(run, repo, base)[0] == 2


def test_an_empty_id_exits_2(run, repo):
    base = repo.commit(log(row("D1")))
    repo.commit(log(row("D1"), row("")))
    assert check(run, repo, base)[0] == 2


def test_an_unknown_base_exits_2(run, repo):
    repo.commit(log(row("D1")))
    status, _, err = check(run, repo, "no-such-ref")
    assert status == 2
    assert "no-such-ref" in err


def test_a_file_missing_at_head_exits_2(run, repo):
    base = repo.commit(log(row("D1")))
    repo.git("rm", "-q", "docs/decisions.md")
    repo.git("commit", "-q", "-m", "remove")
    status, _, err = check(run, repo, base)
    assert status == 2
    assert "docs/decisions.md" in err


def test_a_file_only_in_the_working_tree_exits_2(run, repo):
    base = repo.commit("readme\n", name="README.md")
    repo.write(log(row("D1")))
    assert check(run, repo, base)[0] == 2


def test_outside_a_git_repository_exits_2(run, tmp_path):
    plain = tmp_path / "plain"
    (plain / "docs").mkdir(parents=True)
    (plain / "docs" / "decisions.md").write_text(log(row("D1")))
    status, _, err = run(plain, "check", "--base", "main")
    assert status == 2
    assert err


def test_a_log_without_a_table_exits_2(run, repo):
    base = repo.commit(log(row("D1")))
    repo.commit("# Decisions\n\nNo table here.\n")
    assert check(run, repo, base)[0] == 2


def test_a_table_without_its_separator_row_exits_2(run, repo):
    base = repo.commit(log(row("D1")))
    head = log(row("D1")).replace("| --- | --- | --- | --- | --- |\n", "")
    repo.commit(head)
    assert check(run, repo, base)[0] == 2


def test_a_missing_base_argument_exits_2(run, repo):
    repo.commit(log(row("D1")))
    assert run(repo.path, "check")[0] == 2


# --- a file missing at the base: every row is new


def test_a_file_missing_at_the_base_passes_with_all_rows_new(run, repo):
    base = repo.commit("readme\n", name="README.md")
    repo.commit(log(row("D1"), row("D2")))
    assert check(run, repo, base)[0] == 0


def test_a_file_missing_at_the_base_still_needs_quotes(run, repo):
    base = repo.commit("readme\n", name="README.md")
    repo.commit(log(row("D1", meta="2026-11-22 · instruction · none · two-way")))
    status, _, err = check(run, repo, base)
    assert status == 1
    assert "D1" in err


# --- the quote rule for new instruction rows

INSTRUCTION = "2026-11-22 · instruction · none · two-way"


def new_row_status(run, repo, new):
    base = repo.commit(log(row("D1")))
    repo.commit(log(row("D1"), new))
    return check(run, repo, base)


def test_a_quoted_instruction_passes(run, repo):
    new = row("D2", reason='Owner: "Yes".', meta=INSTRUCTION)
    assert new_row_status(run, repo, new)[0] == 0


def test_a_quote_with_its_origin_passes(run, repo):
    new = row("D2", reason='Owner (in the review session): "Yes, quote '
              'required".', meta=INSTRUCTION)
    assert new_row_status(run, repo, new)[0] == 0


def test_a_quote_with_its_question_passes(run, repo):
    new = row("D2", reason='Owner: "Yes", answering "Must a new row quote '
              'you?". *Why.*', meta=INSTRUCTION)
    assert new_row_status(run, repo, new)[0] == 0


def test_a_quote_in_another_cell_passes(run, repo):
    new = row("D2", decision='Owner: "Do it" applies.', meta=INSTRUCTION)
    assert new_row_status(run, repo, new)[0] == 0


def test_an_instruction_without_a_quote_fails_and_names_it(run, repo):
    new = row("D2", reason="The owner said yes.", meta=INSTRUCTION)
    status, _, err = new_row_status(run, repo, new)
    assert status == 1
    assert len(problem_lines(err)) == 1
    assert "D2" in err


def test_empty_quotes_fail(run, repo):
    new = row("D2", reason='Owner: "".', meta=INSTRUCTION)
    assert new_row_status(run, repo, new)[0] == 1


def test_blank_quotes_fail(run, repo):
    new = row("D2", reason='Owner: "   ".', meta=INSTRUCTION)
    assert new_row_status(run, repo, new)[0] == 1


def test_an_unclosed_quote_fails(run, repo):
    new = row("D2", reason='Owner: "Yes.', meta=INSTRUCTION)
    assert new_row_status(run, repo, new)[0] == 1


def test_curly_quotes_fail(run, repo):
    new = row("D2", reason="Owner: “Yes”.", meta=INSTRUCTION)
    assert new_row_status(run, repo, new)[0] == 1


def test_a_quote_not_attributed_to_the_owner_fails(run, repo):
    new = row("D2", reason='Reviewer: "Yes".', meta=INSTRUCTION)
    assert new_row_status(run, repo, new)[0] == 1


def test_instruction_in_any_meta_field_counts(run, repo):
    new = row("D2", meta="2026-11-22 · none · instruction · two-way")
    assert new_row_status(run, repo, new)[0] == 1


def test_instruction_outside_the_meta_cell_does_not_count(run, repo):
    new = row("D2", decision="An instruction for agents",
              meta="2026-11-22 · agent · none · two-way")
    assert new_row_status(run, repo, new)[0] == 0


def test_a_new_preference_without_a_quote_passes(run, repo):
    new = row("D2", meta="2026-11-22 · preference · none · two-way")
    assert new_row_status(run, repo, new)[0] == 0


def test_a_new_agent_under_row_without_a_quote_passes(run, repo):
    new = row("D2", meta="2026-11-22 · agent under D5 · none · two-way")
    assert new_row_status(run, repo, new)[0] == 0


def test_a_new_row_without_meta_passes(run, repo):
    assert new_row_status(run, repo, "| D2 | Old style | why | none |\n")[0] == 0


def test_an_old_unquoted_instruction_row_does_not_fail(run, repo):
    old = row("D1", reason="The owner said so.", meta=INSTRUCTION)
    base = repo.commit(log(old))
    repo.commit(log(old, row("D2")))
    assert check(run, repo, base)[0] == 0


# --- as a program, and on this repository's own log


def test_problems_go_to_stderr_as_utf8_lines(repo):
    base = repo.commit(log(row("D1", "Päätös")))
    repo.commit(log(row("D1", "Päätös muuttui")))
    done = run_script(repo.path, "check", "--base", base)
    assert done.returncode == 1
    assert done.stdout == b""
    assert b"\r" not in done.stderr
    assert b"D1" in done.stderr


def test_a_passing_check_as_a_program_prints_nothing(repo):
    # The log's shapes: rows before Meta, the D55 shape, Meta rows, UTF-8.
    rows = ("| D1 | Old | why | none |\n", D55_SHAPE,
            row("D58", "Päätös", reason='Owner: "Kyllä".',
                meta="2026-11-16 · instruction · none · two-way"))
    base = repo.commit(log(*rows))
    repo.commit(log(*rows, row("D59")))
    done = run_script(repo.path, "check", "--base", base)
    assert (done.returncode, done.stdout, done.stderr) == (0, b"", b"")


def commit_bytes(repo, data: bytes) -> str:
    target = repo.path / "docs" / "decisions.md"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)
    repo.git("add", "-A")
    repo.git("commit", "-q", "-m", "bytes")
    return repo.git("rev-parse", "HEAD")


def test_a_log_that_is_not_utf8_at_head_exits_2(run, repo):
    base = repo.commit(log(row("D1")))
    commit_bytes(repo, log(row("D1"), row("D2", "bad")).encode() + b"\xff\n")
    status, _, err = check(run, repo, base)
    assert status == 2
    assert "UTF-8" in err


def test_a_log_that_is_not_utf8_at_the_base_exits_2(run, repo):
    base = commit_bytes(repo, log(row("D1")).encode() + b"| D2 | \xff |\n")
    repo.commit(log(row("D1")))
    status, _, err = check(run, repo, base)
    assert status == 2
    assert "UTF-8" in err
